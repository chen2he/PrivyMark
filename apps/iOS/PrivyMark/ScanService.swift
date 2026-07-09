//
//  ScanService.swift
//  PrivyMark
//
//  First detection layer per PRD §9.2: Vision face detection + OCR,
//  feeding OCR lines through TextRuleMatcher. 100% on-device.
//

import Foundation
import CoreGraphics
import Vision
import NaturalLanguage
import DataDetection

nonisolated enum ScanService {

    /// OCR languages covering launch regions (PRD §4.1 / §8.5): North America,
    /// Europe, Latin America, and Mainland China (Simplified + Traditional).
    static let recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant",
                                       "es-ES", "pt-BR", "fr-FR", "de-DE", "it-IT"]

    /// Suggested risk regions, a per-word index for long-press redaction, and
    /// per-line grouping that powers the "Text Explode" chip picker.
    struct ScanResult: Sendable {
        let regions: [RiskRegion]
        let words: [TextWord]
        let lines: [TextLine]
    }

    /// Scans an upright CGImage and returns suggested regions + OCR word boxes.
    /// Bounding boxes are normalized with a top-left origin.
    ///
    /// Face detection and OCR run in SEPARATE handlers on purpose: if one fails
    /// (e.g. the Simulator can't build a face-detection inference context) the
    /// other still produces results. PRD §8.3: a detection failure must never
    /// block the rest of the flow, so this never throws for per-request errors.
    /// - Parameter useAI: when true (and iOS 26+ with an available on-device
    ///   model), layer in the Foundation Models semantic pass. Off = Vision +
    ///   rules only.
    static func scan(_ image: CGImage, useAI: Bool = true) async -> ScanResult {
        // Base pass (every OS version): the sync Vision face/barcode/OCR + rule
        // pipeline, off the main thread. This is the floor and the fallback.
        let base = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: performScan(image))
            }
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            return await augment(base, image: image, useAI: useAI)
        }
        return base
    }

    /// iOS 26+ augmentation, layered over the base result:
    /// 1. Vision's document data detector natively finds phone / email / URL /
    ///    postal-address / shipment-tracking in 26 languages with boxes — it
    ///    OWNS those data types (the rule-based ones are dropped).
    /// 2. On-device Foundation Models add a semantic pass for names / IDs /
    ///    sensitive context the rules miss (only when `useAI` and the model is
    ///    available). Each returned span is located back onto a box via `locate`.
    /// Any sub-step that's unavailable or fails is simply skipped (PRD §8.3).
    @available(iOS 26.0, macOS 26.0, *)
    private static func augment(_ base: ScanResult, image: CGImage, useAI: Bool) async -> ScanResult {
        var regions = base.regions
        var changed = false

        if let dataRegions = await detectDocumentData(image) {
            let owned: Set<RiskType> = [.email, .phone, .url, .address]
            regions = regions.filter { !owned.contains($0.type) }
            regions.append(contentsOf: dataRegions)
            changed = true
        }

        if useAI {
            let transcript = base.lines.map(\.text).joined(separator: "\n")
            if let hits = await SemanticScanner.detect(transcript: transcript) {
                for hit in hits {
                    guard let box = locate(hit.text, in: base.lines) else { continue }
                    regions.append(RiskRegion(
                        type: hit.type, boundingBox: box, confidence: 1,
                        detectedText: hit.text, riskLevel: hit.level))
                    changed = true
                }
            }
        }

        guard changed else { return base }
        regions = deduplicated(regions)
        regions.sort(by: riskSort)
        return ScanResult(regions: regions, words: base.words, lines: base.lines)
    }

    /// Maps a text span (from the semantic model) back onto a box using the OCR
    /// word boxes. Grows a consecutive-word window within each line while it
    /// stays a prefix of the target, returning the union of the matched words'
    /// boxes; falls back to the whole line, then nil. Pure/testable — no model.
    static func locate(_ entity: String, in lines: [TextLine]) -> CGRect? {
        let target = matchKey(entity)
        guard target.count >= 2 else { return nil }
        for line in lines {
            let words = line.words
            for start in words.indices {
                var joined = ""
                var end = start
                while end < words.count {
                    let next = joined + matchKey(words[end].text)
                    if next == target {
                        return union(words[start...end].map(\.boundingBox))
                    }
                    if !target.hasPrefix(next) { break }   // window diverged from target
                    joined = next
                    end += 1
                }
            }
            if matchKey(line.text).contains(target) { return line.boundingBox }
        }
        return nil
    }

    /// Fuzzy match key: lowercased, alphanumerics only (so "+1 (555) 123-4567"
    /// and "john.doe@x.com" line up with however OCR split the words).
    private static func matchKey(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func union(_ rects: [CGRect]) -> CGRect? {
        guard var u = rects.first else { return nil }
        for r in rects.dropFirst() { u = u.union(r) }
        return u
    }

    private static func performScan(_ image: CGImage) -> ScanResult {
        var regions: [RiskRegion] = []
        var words: [TextWord] = []
        var lines: [TextLine] = []

        // Faces — high risk, selected by default. Tolerate failure.
        let faceRequest = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([faceRequest])
            for face in faceRequest.results ?? [] {
                let box = flip(face.boundingBox).insetBy(fraction: -0.08)
                regions.append(RiskRegion(
                    type: .face,
                    boundingBox: clamp(box),
                    confidence: face.confidence,
                    riskLevel: .high,
                    emoji: "😀")) // faces default to an emoji cover (PRD §7.4)
            }
        } catch {
            // Face detection unavailable — user can still frame faces manually.
        }

        // QR codes / barcodes — payloads often hold links, IDs, payment info.
        // Own handler so a failure can't cancel face/OCR (and vice-versa).
        let barcodeRequest = VNDetectBarcodesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([barcodeRequest])
            for code in barcodeRequest.results ?? [] {
                let box = flip(code.boundingBox).insetBy(fraction: -0.04)
                regions.append(RiskRegion(
                    type: .code,
                    boundingBox: clamp(box),
                    confidence: code.confidence,
                    detectedText: code.payloadStringValue,
                    riskLevel: .high))
            }
        } catch {
            // Barcode detection unavailable — user can still box it manually.
        }

        // OCR lines → rule matching. Tolerate failure independently.
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = recognitionLanguages
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([textRequest])
        } catch {
            // OCR unavailable — return whatever faces were found (possibly none).
            return ScanResult(regions: regions, words: words, lines: lines)
        }

        let observations = textRequest.results ?? []
        let allLines = observations.compactMap { $0.topCandidates(1).first?.string }
        let sceneHint = TextRuleMatcher.containsContextKeywords(allLines)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string

            // Detected sensitive patterns → suggested regions.
            for match in TextRuleMatcher.matches(in: line, sceneHint: sceneHint) {
                let visionBox: CGRect
                if match.coversWholeLine {
                    visionBox = observation.boundingBox
                } else if let rect = try? candidate.boundingBox(for: match.range) {
                    visionBox = rect.boundingBox
                } else {
                    visionBox = observation.boundingBox
                }
                let padded = padTextBox(flip(visionBox))
                regions.append(RiskRegion(
                    type: match.type,
                    boundingBox: clamp(padded),
                    confidence: candidate.confidence,
                    detectedText: String(line[match.range]),
                    riskLevel: match.level))
            }

            // Person names via on-device NER. Unlike face/barcode, NaturalLanguage
            // is CPU-based and runs on the Simulator too. Best-effort → medium risk.
            for range in personNameRanges(in: line) {
                let text = String(line[range])
                guard text.count >= 2, let box = try? candidate.boundingBox(for: range) else { continue }
                regions.append(RiskRegion(
                    type: .name,
                    boundingBox: clamp(padTextBox(flip(box.boundingBox))),
                    confidence: candidate.confidence,
                    detectedText: text,
                    riskLevel: .medium))
            }

            // Per-word boxes for long-press redaction (handles CJK via .byWords),
            // grouped into a TextLine for the "Text Explode" chip picker.
            var lineWords: [TextWord] = []
            line.enumerateSubstrings(in: line.startIndex..<line.endIndex,
                                     options: [.byWords, .localized]) { sub, range, _, _ in
                guard let sub, !sub.trimmingCharacters(in: .whitespaces).isEmpty,
                      let box = try? candidate.boundingBox(for: range) else { return }
                lineWords.append(TextWord(
                    boundingBox: clamp(padTextBox(flip(box.boundingBox))), text: sub))
            }
            words.append(contentsOf: lineWords)
            if !lineWords.isEmpty {
                lines.append(TextLine(
                    boundingBox: clamp(padTextBox(flip(observation.boundingBox))),
                    text: line,
                    words: lineWords))
            }
        }

        // Form fields whose label and value land on SEPARATE OCR lines — either
        // vertical ("Card Holder" above "MANSIR USMAN") or Vision's horizontal
        // split at a Chinese colon ("收件人：" + "李娜"). The same-line rules can't
        // see these, so pair a label line with a spatially-adjacent value line to
        // recover bare names and bare CVVs.
        for label in lines where TextRuleMatcher.isNameLabelLine(label.text) {
            if let v = adjacentValue(to: label, in: lines, where: TextRuleMatcher.looksLikeName) {
                regions.append(RiskRegion(type: .name, boundingBox: v.boundingBox,
                    confidence: 1, detectedText: v.text, riskLevel: .medium))
            }
        }
        for label in lines where TextRuleMatcher.isCVVLabel(label.text) {
            if let v = adjacentValue(to: label, in: lines, where: TextRuleMatcher.looksLikeCVV) {
                regions.append(RiskRegion(type: .payment, boundingBox: v.boundingBox,
                    confidence: 1, detectedText: v.text, riskLevel: .high))
            }
        }

        regions.sort(by: riskSort)
        return ScanResult(regions: regions, words: words, lines: lines)
    }

    /// The value line spatially adjacent to a field label — same row to its
    /// right (Vision's horizontal `label：value` split) or the line just below
    /// (vertical forms). Nearest by vertical distance wins; `matches` filters
    /// candidate value lines. Boxes are normalized top-left.
    static func adjacentValue(to label: TextLine, in lines: [TextLine],
                              where matches: (String) -> Bool) -> TextLine? {
        let lb = label.boundingBox
        return lines.filter { $0.boundingBox != lb && matches($0.text) }
            .filter { cand in
                let cb = cand.boundingBox
                let sameRowRight = abs(cb.midY - lb.midY) < lb.height * 0.9 && cb.midX > lb.minX
                let justBelow = cb.minY >= lb.minY && cb.minY - lb.maxY < lb.height * 1.6
                    && cb.maxX > lb.minX && cb.minX < lb.maxX + lb.width
                return sameRowRight || justBelow
            }
            .min { abs($0.boundingBox.midY - lb.midY) < abs($1.boundingBox.midY - lb.midY) }
    }

    /// Sort order for the risk list: higher risk first, then top-to-bottom.
    private static func riskSort(_ lhs: RiskRegion, _ rhs: RiskRegion) -> Bool {
        if lhs.riskLevel != rhs.riskLevel { return lhs.riskLevel > rhs.riskLevel }
        return lhs.boundingBox.minY < rhs.boundingBox.minY
    }

    /// Drops same-type regions whose boxes essentially coincide — e.g. a shipment
    /// tracking number found by BOTH the Vision data detector and our keyword rule.
    /// Keeps the first occurrence.
    private static func deduplicated(_ regions: [RiskRegion]) -> [RiskRegion] {
        var result: [RiskRegion] = []
        for region in regions {
            let duplicate = result.contains {
                $0.type == region.type && iou($0.boundingBox, region.boundingBox) > 0.6
            }
            if !duplicate { result.append(region) }
        }
        return result
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }

    // MARK: - iOS 26+ document data detection

    /// Native data detection via `RecognizeDocumentsRequest` (iOS 26+). Returns
    /// suggested regions for phone / email / URL / postal address / tracking,
    /// or nil if the request is unavailable or fails — the caller then keeps the
    /// rule-based results (PRD §8.3 resilience).
    @available(iOS 26.0, macOS 26.0, *)
    private static func detectDocumentData(_ image: CGImage) async -> [RiskRegion]? {
        var request = RecognizeDocumentsRequest()
        request.barcodeDetectionOptions.enabled = false      // our own barcode path handles QR
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        do {
            let observations = try await request.perform(on: image)
            var out: [RiskRegion] = []
            for observation in observations {
                appendData(from: observation.document.text, into: &out)
                for paragraph in observation.document.paragraphs {
                    appendData(from: paragraph, into: &out)
                }
            }
            return out
        } catch {
            return nil   // detector unavailable — fall back to the rule-based regions
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func appendData(
        from text: DocumentObservation.Container.Text, into out: inout [RiskRegion]
    ) {
        for data in text.detectedData {
            let type: RiskType
            let level: RiskLevel
            let detected: String?
            switch data.match.details {
            case .phoneNumber(let p):           type = .phone;       level = .high;   detected = p.phoneNumber
            case .emailAddress(let e):          type = .email;       level = .high;   detected = e.emailAddress
            case .link(let l):                  type = .url;         level = .medium; detected = l.url.absoluteString
            case .postalAddress(let a):         type = .address;     level = .medium; detected = a.fullAddress
            case .shipmentTrackingNumber(let s): type = .orderNumber; level = .medium; detected = s.trackingNumber
            default: continue   // date / money / flight / measurement / UPI — not PII we redact
            }
            // Vision boxes are normalized bottom-left; reuse our TL conversion + padding.
            let box = clamp(padTextBox(flip(data.boundingRegion.boundingBox.cgRect)))
            guard box.width > 0, box.height > 0 else { continue }
            out.append(RiskRegion(
                type: type, boundingBox: box, confidence: 1,
                detectedText: detected, riskLevel: level))
        }
    }

    /// Person-name spans in one OCR line via NaturalLanguage NER (`.joinNames`
    /// keeps "John Smith" as a single span). Runs on-device incl. Simulator.
    private static func personNameRanges(in line: String) -> [Range<String.Index>] {
        guard line.contains(where: \.isLetter) else { return [] }
        var ranges: [Range<String.Index>] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = line
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]
        tagger.enumerateTags(in: line.startIndex..<line.endIndex,
                             unit: .word, scheme: .nameType, options: options) { tag, range in
            if tag == .personalName { ranges.append(range) }
            return true
        }
        return ranges
    }

    // MARK: - Geometry helpers

    /// Vision boxes are normalized with a bottom-left origin; convert to top-left.
    private static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.minY - rect.height,
               width: rect.width, height: rect.height)
    }

    /// Small padding so redaction fully covers glyph ascenders/descenders.
    private static func padTextBox(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -rect.height * 0.18, dy: -rect.height * 0.18)
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

nonisolated extension CGRect {
    /// Insets by a fraction of the rect's own size (negative = expand).
    func insetBy(fraction: CGFloat) -> CGRect {
        insetBy(dx: width * fraction, dy: height * fraction)
    }
}
