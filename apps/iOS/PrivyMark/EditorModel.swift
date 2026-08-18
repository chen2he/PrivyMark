//
//  EditorModel.swift
//  PrivyMark
//
//  Editor state: scan results, selection, manual regions, style,
//  undo/redo, metadata choices, preview rendering, and export.
//

import Foundation
import Combine
import SwiftUI
import Photos
import UIKit

@MainActor
final class EditorModel: ObservableObject {

    // MARK: State

    @Published private(set) var image: CGImage?
    @Published private(set) var regions: [RiskRegion] = []
    @Published private(set) var words: [TextWord] = []
    /// OCR lines (word groups) for the "Text Explode" long-press picker.
    @Published private(set) var lines: [TextLine] = []
    @Published private(set) var strokes: [Stroke] = []
    @Published var style: RedactionStyle = .block
    /// Marker (freehand) mode: canvas drags paint strokes instead of boxes.
    @Published var isMarkerMode = false
    /// Current marker brush color (persists across images).
    @Published var markerColor: RGBAColor = .black
    /// Fill color for the Block style (system color picker, like the marker).
    @Published var blockColor: RGBAColor = .black
    /// The library asset this image came from (for overwrite / delete-original);
    /// nil for the sample, a Files import, or the Share Extension inbox.
    var sourceAsset: PHAsset?
    /// User's own watermark text (e.g. "Internal use only"); nil = off.
    @Published var userWatermarkText: String?
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var isScanning = false
    @Published private(set) var scanFailed = false
    /// True from the moment a photo is tapped until its data is ready — drives
    /// an immediate loading screen so an iCloud download never looks like a
    /// no-op tap.
    @Published private(set) var isPreparing = false
    @Published private(set) var isDownloadingFromCloud = false
    @Published private(set) var downloadProgress: Double = 0
    @Published var metadata = ImageMetadata.read(from: Data())
    @Published var keptMetadata: Set<MetadataCategory> = []
    @Published var highlightedRegionID: UUID?
    /// Export option (DAMA-style compress toggle).
    @Published var compress = false
    /// Best-effort hidden-watermark / steganography finding for this image.
    @Published private(set) var stegoFinding: StegoFinding = .clean
    /// Export option: scrub pixel LSBs + strip ALL metadata to remove the
    /// removable class of hidden marks (PRD §7.8).
    @Published var scrubHiddenMarks = false

    /// The editor owns the screen while preparing, scanning, or showing an image.
    var isActive: Bool { isPreparing || isScanning || image != nil }

    /// Marker stroke width as a fraction of image width.
    static let markerWidth: CGFloat = 0.035

    /// Default redaction tool from Settings (PRD §10.4 "自动模式默认工具").
    var defaultStyle: RedactionStyle = .block
    /// Settings toggle: layer in the on-device Foundation Models semantic pass
    /// (iOS 26+, Apple-Intelligence devices). Gracefully ignored elsewhere.
    var useAIDetection: Bool = true

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var renderTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// Bounded working image for Vision (normalized boxes are resolution-free).
    private var scanImage: CGImage?
    /// Downscaled base used for live preview rendering.
    private var previewBase: CGImage?

    /// Size caps that keep decode/scan/render off the "freeze a large photo" path.
    private static let maxExportDimension: CGFloat = 4096
    private static let scanDimension: CGFloat = 2400
    private static let previewDimension: CGFloat = 1600

    private struct Snapshot {
        let regions: [RiskRegion]
        let strokes: [Stroke]
        let style: RedactionStyle
        let userWatermarkText: String?
    }

    private struct Prepared {
        let export: CGImage
        let scan: CGImage
        let preview: CGImage
        let metadata: ImageMetadata
        let stego: StegoFinding
    }

    var hasImage: Bool { image != nil }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedRegions: [RiskRegion] { regions.filter(\.isSelected) }

    var groupedRegions: [(type: RiskType, regions: [RiskRegion])] {
        RiskType.allCases.compactMap { type in
            let matching = regions.filter { $0.type == type }
            return matching.isEmpty ? nil : (type, matching)
        }
    }

    // MARK: Load & scan

    /// Enters the editor in a loading state the instant a photo is tapped, so
    /// an iCloud download shows a screen immediately instead of looking dead.
    func beginLoading() {
        reset()
        isPreparing = true
    }

    /// Reports iCloud download progress (0…1) during `requestImageData`.
    func updateDownloadProgress(_ progress: Double) {
        guard isPreparing else { return }
        // A local photo never reports progress; only flag "downloading" once
        // PhotoKit actually streams (progress < 1 while still preparing).
        if progress < 1 { isDownloadingFromCloud = true }
        downloadProgress = progress
    }

    /// The photo data couldn't be fetched (e.g. offline + iCloud-only).
    func failLoading() {
        reset()
        scanFailed = true
    }

    /// Loads image data (from the library grid, sample, or Share Extension inbox).
    /// All heavy work — decode, orientation bake, downscales, metadata read —
    /// runs OFF the main thread so a large photo can never stall the UI. The
    /// image is size-capped (§ maxExportDimension) to bound memory. Scanning
    /// happens on a smaller image; redaction boxes are normalized, so placement
    /// is identical at any resolution.
    func load(data: Data) {
        reset()
        isScanning = true // isActive stays true → no flicker back to the grid
        loadTask = Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.prepare(data: data)
            }.value
            guard !Task.isCancelled else { return }
            guard let prepared else {
                self.isScanning = false
                self.scanFailed = true
                return
            }
            self.image = prepared.export
            self.scanImage = prepared.scan
            self.previewBase = prepared.preview
            self.metadata = prepared.metadata
            self.stegoFinding = prepared.stego
            // When a hidden mark is detected, default the removal ON so it's
            // scrubbed "together" on export (the user can still turn it off).
            self.scrubHiddenMarks = prepared.stego.isSuspicious
            self.keptMetadata = Set(MetadataCategory.allCases.filter {
                $0.keptByDefault && prepared.metadata.present.keys.contains($0)
            })
            // Show the image immediately while the scan runs.
            self.previewImage = UIImage(cgImage: prepared.preview)

            // ScanService is resilient (PRD §8.3): partial detector failures
            // still return whatever was found and never abort the flow.
            let result = await ScanService.scan(prepared.scan, useAI: useAIDetection)
            guard !Task.isCancelled else { return }
            self.regions = result.regions
            self.words = result.words
            self.lines = result.lines
            self.isScanning = false
            self.renderPreview()
        }
    }

    func reset() {
        loadTask?.cancel()
        renderTask?.cancel()
        image = nil
        scanImage = nil
        previewBase = nil
        regions = []
        words = []
        lines = []
        strokes = []
        userWatermarkText = nil
        isMarkerMode = false
        sourceAsset = nil
        previewImage = nil
        undoStack = []
        redoStack = []
        scanFailed = false
        isScanning = false
        isPreparing = false
        isDownloadingFromCloud = false
        downloadProgress = 0
        highlightedRegionID = nil
        stegoFinding = .clean
        scrubHiddenMarks = false
        style = defaultStyle
    }

    /// Decodes, bakes orientation, and produces the three working images plus
    /// metadata. Pure/off-main; safe to call from a detached task.
    private nonisolated static func prepare(data: Data) -> Prepared? {
        guard let uiImage = UIImage(data: data),
              let upright = uiImage.uprightCGImage() else { return nil }
        let export = downscale(upright, maxDimension: maxExportDimension)
        let scan = downscale(export, maxDimension: scanDimension)
        let preview = downscale(export, maxDimension: previewDimension)
        let metadata = ImageMetadata.read(from: data)
        // LSB analysis needs the un-rescaled pixels; `export` == original for a
        // typical (upright, ≤4096px) screenshot. Rotated/huge images are
        // re-rendered, which already destroys any LSB signal → reads as clean.
        let stego = SteganographyAnalyzer.analyze(export)
        return Prepared(export: export, scan: scan, preview: preview,
                        metadata: metadata, stego: stego)
    }

    // MARK: Mutations (all undoable)

    func toggle(_ region: RiskRegion) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }) else { return }
        pushUndo()
        regions[index].isSelected.toggle()
        renderPreview()
    }

    /// Sets a region's selection explicitly. Used by tap-to-peel so overlapping
    /// auto-marks can always be cleared: tapping a covered spot deselects the
    /// topmost region there instead of re-toggling the same one. No-op if the
    /// region is already in that state.
    func setSelected(_ id: UUID, _ selected: Bool) {
        guard let index = regions.firstIndex(where: { $0.id == id }),
              regions[index].isSelected != selected else { return }
        pushUndo()
        regions[index].isSelected = selected
        renderPreview()
    }

    func setAll(ofType type: RiskType, selected: Bool) {
        pushUndo()
        for index in regions.indices where regions[index].type == type {
            regions[index].isSelected = selected
        }
        renderPreview()
    }

    /// PRD §7.3: "一键应用建议" — selects every suggested region.
    func applyAllSuggestions() {
        pushUndo()
        for index in regions.indices where regions[index].origin == .automatic {
            regions[index].isSelected = true
        }
        renderPreview()
    }

    func addManualRegion(normalizedRect rect: CGRect) {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard clamped.width > 0.005, clamped.height > 0.005 else { return }
        pushUndo()
        regions.append(RiskRegion(
            type: .otherText,
            boundingBox: clamped,
            confidence: 1,
            riskLevel: .medium,
            isSelected: true,
            origin: .manual))
        renderPreview()
    }

    func removeManualRegion(_ region: RiskRegion) {
        guard region.origin == .manual else { return }
        pushUndo()
        regions.removeAll { $0.id == region.id }
        renderPreview()
    }

    /// Selecting a fill style also exits marker mode.
    func setStyle(_ newStyle: RedactionStyle) {
        isMarkerMode = false
        guard newStyle != style else { return }
        pushUndo()
        style = newStyle
        renderPreview()
    }

    /// Sets the Block fill color (system color picker) and refreshes the preview.
    /// A tool setting like `markerColor` — not part of the undo snapshot.
    func setBlockColor(_ color: RGBAColor) {
        guard color != blockColor else { return }
        blockColor = color
        renderPreview()
    }

    // MARK: Text Explode (文字大爆炸)

    /// PRD §7.5: the OCR line under a normalized point (smallest match). A
    /// long-press here fans the line's words out as tappable chips so the user
    /// can cover plain text the risk detectors didn't flag.
    func line(atNormalizedPoint point: CGPoint) -> TextLine? {
        lines.filter { $0.boundingBox.contains(point) }
            .min { ($0.boundingBox.width * $0.boundingBox.height)
                 < ($1.boundingBox.width * $1.boundingBox.height) }
    }

    /// Whether a specific OCR word currently has a manual cover.
    func isWordCovered(_ word: TextWord) -> Bool {
        regions.contains { $0.origin == .manual && $0.boundingBox == word.boundingBox }
    }

    /// Toggles a cover over a single OCR word (from the Text Explode picker).
    func toggleWordCover(_ word: TextWord) {
        if let existing = regions.first(where: {
            $0.origin == .manual && $0.boundingBox == word.boundingBox
        }) {
            removeManualRegion(existing)
            return
        }
        pushUndo()
        regions.append(RiskRegion(
            type: .otherText, boundingBox: word.boundingBox, confidence: 1,
            detectedText: word.text, riskLevel: .medium, isSelected: true, origin: .manual))
        renderPreview()
    }

    // MARK: Refine a detection to words

    /// The OCR lines a detected region sits on, in reading order — the chips
    /// shown when refining that detection word by word. Empty when nothing
    /// textual underlies the region (faces, barcodes), which is the signal to
    /// hide the Refine affordance entirely.
    func refinableLines(for region: RiskRegion) -> [TextLine] {
        lines
            .filter { line in
                line.boundingBox.intersects(region.boundingBox)
                    && line.words.contains { Self.overlapFraction($0.boundingBox, region.boundingBox) > 0.3 }
            }
            .sorted { lhs, rhs in
                // Reading order; same visual row (within half a line height) reads left→right.
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > lhs.boundingBox.height / 2 {
                    return lhs.boundingBox.midY < rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
    }

    /// Whether `word` is currently redacted as part of `regionID`. Before the
    /// first edit the region has no explicit word list, so the answer is derived
    /// from which words its detected box already swallows.
    func isWordCovered(_ word: TextWord, inRegion regionID: UUID, allWords: [TextWord]) -> Bool {
        guard let region = regions.first(where: { $0.id == regionID }), region.isSelected else { return false }
        return Self.currentWordBoxes(of: region, in: allWords).contains(word.boundingBox)
    }

    /// Toggles one word inside a detected region. Deselecting the last word
    /// switches the whole detection off rather than leaving an empty cover.
    func toggleRefinedWord(_ word: TextWord, inRegion regionID: UUID, allWords: [TextWord]) {
        guard let index = regions.firstIndex(where: { $0.id == regionID }) else { return }
        pushUndo()
        var boxes = regions[index].isSelected
            ? Self.currentWordBoxes(of: regions[index], in: allWords)
            : []
        if let hit = boxes.firstIndex(of: word.boundingBox) {
            boxes.remove(at: hit)
        } else {
            boxes.append(word.boundingBox)
        }
        if boxes.isEmpty {
            regions[index].wordBoxes = nil
            regions[index].isSelected = false
        } else {
            regions[index].wordBoxes = boxes
            regions[index].isSelected = true
        }
        renderPreview()
    }

    /// Drops a word-level refinement: the region covers its detected box again.
    func resetRefinement(forRegion regionID: UUID) {
        guard let index = regions.firstIndex(where: { $0.id == regionID }) else { return }
        pushUndo()
        regions[index].wordBoxes = nil
        regions[index].isSelected = true
        renderPreview()
    }

    /// The word boxes a region currently redacts: its explicit refinement, or —
    /// before any refinement — the words its detected box mostly swallows.
    private static func currentWordBoxes(of region: RiskRegion, in words: [TextWord]) -> [CGRect] {
        if let boxes = region.wordBoxes { return boxes }
        return words
            .filter { overlapFraction($0.boundingBox, region.boundingBox) >= 0.5 }
            .map(\.boundingBox)
    }

    /// How much of `box` lies inside `other`, as a fraction of `box`'s own area.
    private static func overlapFraction(_ box: CGRect, _ other: CGRect) -> CGFloat {
        let area = box.width * box.height
        guard area > 0 else { return 0 }
        let hit = box.intersection(other)
        guard !hit.isNull else { return 0 }
        return (hit.width * hit.height) / area
    }

    /// Covers an entire OCR line at once ("cover whole line" in Text Explode).
    func coverWholeLine(_ line: TextLine) {
        guard !regions.contains(where: {
            $0.origin == .manual && $0.boundingBox == line.boundingBox
        }) else { return }
        pushUndo()
        regions.append(RiskRegion(
            type: .otherText, boundingBox: line.boundingBox, confidence: 1,
            detectedText: line.text, riskLevel: .medium, isSelected: true, origin: .manual))
        renderPreview()
    }

    /// Commits a freehand marker stroke (normalized, top-left points).
    func addStroke(_ normalizedPoints: [CGPoint]) {
        guard !normalizedPoints.isEmpty else { return }
        pushUndo()
        strokes.append(Stroke(points: normalizedPoints, width: Self.markerWidth, color: markerColor))
        renderPreview()
    }

    /// Sets or clears the user's own watermark text (PRD §7.4 水印工具).
    func setUserWatermark(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        pushUndo()
        userWatermarkText = (trimmed?.isEmpty == false) ? trimmed : nil
        renderPreview()
    }

    // MARK: Emoji covers (faces)

    /// Changes the emoji covering a region (from the system emoji keyboard).
    func setEmoji(_ emoji: String, forRegion id: UUID) {
        guard let index = regions.firstIndex(where: { $0.id == id }),
              regions[index].emoji != nil else { return }
        pushUndo()
        regions[index].emoji = emoji
        // Emoji covers draw as a live overlay, not in the bitmap — no re-render.
    }

    /// Removes a face's emoji cover — the face shows through, the detection box
    /// stays (a dashed hint) so it can be re-enabled from the risk list.
    func removeEmojiCover(_ id: UUID) {
        guard let index = regions.firstIndex(where: { $0.id == id }),
              regions[index].emoji != nil else { return }
        pushUndo()
        regions[index].isSelected = false
        renderPreview()
    }

    /// Starts an emoji drag: one undo entry for the whole gesture.
    func beginRegionDrag(_ id: UUID) {
        guard regions.contains(where: { $0.id == id }) else { return }
        pushUndo()
    }

    /// Live update while dragging an emoji cover; keeps the box inside the image.
    func moveRegion(_ id: UUID, toNormalizedCenter center: CGPoint) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        let size = regions[index].boundingBox.size
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        let x = center.x.clamped(to: half.width...(1 - half.width))
        let y = center.y.clamped(to: half.height...(1 - half.height))
        regions[index].boundingBox.origin = CGPoint(x: x - half.width, y: y - half.height)
    }

    // MARK: Undo / redo

    private func snapshot() -> Snapshot {
        Snapshot(regions: regions, strokes: strokes, style: style,
                 userWatermarkText: userWatermarkText)
    }

    private func apply(_ s: Snapshot) {
        regions = s.regions
        strokes = s.strokes
        style = s.style
        userWatermarkText = s.userWatermarkText
    }

    private func pushUndo() {
        undoStack.append(snapshot())
        redoStack.removeAll()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        apply(s)
        renderPreview()
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        apply(s)
        renderPreview()
    }

    // MARK: Preview rendering

    /// Selected regions covered by the fill style (emoji faces excluded —
    /// those draw as a live canvas overlay and bake only at export).
    var styleRects: [CGRect] {
        selectedRegions.filter { $0.emoji == nil }.flatMap(\.coverRects)
    }

    /// Selected emoji covers (faces), for the canvas overlay and export bake.
    var emojiStamps: [EmojiStamp] {
        selectedRegions.compactMap { region in
            region.emoji.map { EmojiStamp(rect: region.boundingBox, emoji: $0) }
        }
    }

    /// Re-renders the redacted preview from the downscaled base. The preview
    /// shows the user watermark and marker strokes (WYSIWYG) but not the
    /// free-tier badge (export-only) or emoji covers (live overlay, for
    /// smooth dragging).
    private func renderPreview() {
        guard let base = previewBase else { return }
        let rects = styleRects
        let currentStyle = style
        let strokes = self.strokes
        let userWM = userWatermarkText
        let blockColor = self.blockColor
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) {
            let rendered = RedactionRenderer.render(
                image: base, regions: rects, style: currentStyle,
                strokes: strokes, userWatermark: userWM, blockColor: blockColor)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.previewImage = UIImage(cgImage: rendered)
            }
        }
    }

    // MARK: Export

    struct ExportResult {
        let data: Data
        let fileExtension: String
    }

    /// Renders the full-resolution flattened export with metadata choices applied.
    func makeExport() async -> ExportResult? {
        guard let image else { return nil }
        let rects = styleRects
        let stamps = emojiStamps
        let currentStyle = style
        let meta = metadata
        let kept = keptMetadata
        let compress = compress
        let strokes = self.strokes
        let userWM = userWatermarkText
        let blockColor = self.blockColor
        let scrub = scrubHiddenMarks
        return await Task.detached(priority: .userInitiated) { () -> ExportResult? in
            var rendered = RedactionRenderer.render(
                image: image, regions: rects, style: currentStyle,
                strokes: strokes, userWatermark: userWM,
                emojiStamps: stamps, blockColor: blockColor)
            // Remove hidden marks: clear pixel LSBs and strip ALL metadata.
            let keeping = scrub ? Set<MetadataCategory>() : kept
            if scrub { rendered = SteganographyAnalyzer.scrub(rendered) }
            guard let data = meta.encode(image: rendered, keeping: keeping, compress: compress)
            else { return nil }
            let ext = compress ? "jpg" : meta.exportFileExtension
            return ExportResult(data: data, fileExtension: ext)
        }.value
    }

    /// "Save a copy" — creates a NEW asset, original untouched (PRD §7.6).
    func saveToPhotos(_ export: ExportResult) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: export.data, options: nil)
        }
    }

    /// True only when the image came from a library asset we can overwrite/delete.
    var hasSourceAsset: Bool { sourceAsset != nil }

    /// "Save (overwrite original)" — saves the redacted image as a new asset,
    /// then deletes the original so it's genuinely replaced. (Photos can't do a
    /// true in-place overwrite — content edits stay revertible — and delete+save
    /// is robust across formats.) If the delete is declined, the redacted copy
    /// still remains. Falls back to save-as-new when there's no source asset.
    func overwriteOriginal(_ export: ExportResult) async throws {
        try await saveToPhotos(export)
        try await deleteOriginal()
    }

    /// Deletes the source asset (Photos shows a system confirmation).
    func deleteOriginal() async throws {
        guard let asset = sourceAsset else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    /// Writes the export to a temp file for the system share sheet.
    func shareURL(for export: ExportResult) -> URL? {
        let stamp = Date().formatted(.iso8601.year().month().day()
            .timeSeparator(.omitted).dateTimeSeparator(.standard).time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivyMark_\(stamp)")
            .appendingPathExtension(export.fileExtension)
        do {
            try export.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    enum ExportError: LocalizedError {
        case photoAccessDenied
        case editUnavailable

        var errorDescription: String? {
            switch self {
            case .photoAccessDenied:
                return String(localized: "Allow PrivyMark to access Photos in Settings to save your redacted image.")
            case .editUnavailable:
                return String(localized: "This photo can't be edited in place. Try \"Save a Copy\".")
            }
        }
    }

    // MARK: Helpers

    private nonisolated static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longest = max(width, height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage ?? image
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension UIImage {
    /// Returns a CGImage with orientation baked in (always .up).
    func uprightCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
