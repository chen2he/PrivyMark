//
//  EditorView.swift
//  PrivyMark
//
//  Scan + edit screen (PRD §10.4). DAMA-style: a pinch-zoomable canvas, a
//  floating tool palette (Auto pinned, the rest scrolls), an export popover
//  with four save/share options, and a marker with a system color picker.
//
//  Canvas layout invariant: every canvas child is placed with `.position()`
//  (a flexible wrapper), so the ZStack always fills the canvas and gesture
//  coordinates and drawn coordinates share ONE space. Do not switch back to
//  fixed-size children + `.offset` — on iOS 27 the stack then sizes to the
//  image and the outer frame re-centers it, applying the centering offset
//  twice (image hugs the trailing edge, taps/strokes land offset).
//

import SwiftUI

struct EditorView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var settings: SettingsStore
    /// False when the editor is the detail column of a split view, where the
    /// grid stays on screen beside it and there is nothing to go back to.
    var showsBackButton = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Size of the space the editor was actually handed, palette included —
    /// drives whether the tool palette sits along the bottom or becomes a
    /// vertical rail. Never measure it inside the palette's inset (see `body`).
    @State private var contentSize: CGSize = .zero

    // Editing gesture state
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var touchLocation: CGPoint = .zero
    @State private var markerPoints: [CGPoint] = []
    @State private var longPressFired = false
    /// Emoji cover being dragged (position fine-tuning).
    @State private var draggingEmojiID: UUID?
    /// Region whose emoji is being changed via the system emoji keyboard.
    @State private var emojiPickTarget: EmojiPickTarget?

    // Zoom / pan. pinchSession captures the state at pinch start so the
    // image point under the fingers stays anchored while scaling.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var pinchSession: (zoom: CGFloat, pan: CGSize, anchor: CGPoint)?
    @State private var panDragOrigin: CGSize?

    // Sheets / popovers
    @State private var showExport = false
    @State private var showMetadata = false
    @State private var showRiskList = false
    @State private var showHelp = false
    @State private var showWatermarkInput = false
    // (Pro/paywall removed — the app is fully free.)
    @State private var watermarkText = ""
    @State private var sharePayload: SharePayload?
    @State private var toast: String?
    /// Text currently fanned out in the "Text Explode" picker — either a plain
    /// OCR line (long-press on unflagged text) or a detected region being
    /// refined word by word.
    @State private var explodeTarget: ExplodeTarget?

    private let appName = "PrivyMark"

    /// Where the tool palette belongs for the space we were handed.
    private var palettePlacement: PalettePlacement {
        PalettePlacement.forContent(of: contentSize, horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        NavigationStack {
            editorSurface
            // Measured OUTSIDE the palette's safe-area bar, so the size doesn't
            // depend on where the palette went. Measuring the canvas instead is
            // a feedback loop: a bottom palette makes the canvas squarer (→ rail),
            // a rail makes it taller (→ bottom), and the flip never settles —
            // the main thread spins and the app hangs on opening a photo.
            .measureContent(into: $contentSize)
            .navigationTitle("")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showMetadata) { MetadataSheet(editor: editor) }
            .sheet(isPresented: $showRiskList) { RiskListSheet(editor: editor) }
            .sheet(isPresented: $showHelp) { HelpSheet() }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(url: payload.url) {
                    if payload.deleteAfter {
                        Task {
                            do { try await editor.deleteOriginal(); flash(String(localized: "Shared · original deleted")) }
                            catch { flash(error.localizedDescription) }
                        }
                    }
                }
            }
            .sheet(item: $emojiPickTarget) { target in
                EmojiPickerSheet(
                    onPick: { editor.setEmoji($0, forRegion: target.id) },
                    onRemove: { editor.removeEmojiCover(target.id) })
            }
            .sheet(item: $explodeTarget) { target in
                TextExplodeSheet(target: target, editor: editor)
            }
            .alert("Watermark", isPresented: $showWatermarkInput) {
                TextField("Watermark text", text: $watermarkText)
                Button("Apply") { editor.setUserWatermark(watermarkText) }
                if editor.userWatermarkText != nil {
                    Button("Remove", role: .destructive) { editor.setUserWatermark(nil) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stamp your own text across the image, e.g. \"Internal use only\".")
            }
        }
    }

    // MARK: Surface (canvas + palette in the safe area)

    /// The canvas plus its chrome. The palette and the hint banners go into the
    /// SAFE AREA instead of floating over a hard-coded strip of bottom padding,
    /// so the canvas re-fits itself whenever the available space changes — a
    /// fold, a rotation, or a Split View resize on Duo.
    @ViewBuilder
    private var editorSurface: some View {
        switch palettePlacement {
        case .rail:
            // Wide-and-short: tools go to the side, matching the system bars,
            // and the banners stay horizontal along the bottom.
            canvasStack
                .hintBar { banners }
                .paletteBar(.rail) { paletteStrip(axis: .vertical) }
        case .bottom:
            canvasStack
                .paletteBar(.bottom) {
                    VStack(spacing: 8) {
                        banners
                        paletteStrip(axis: .horizontal)
                    }
                }
        }
    }

    private var canvasStack: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            if editor.hasImage {
                canvas
            } else {
                loadingView
            }
            if let toast { toastView(toast) }
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 8) {
            stegoBanner
            hintBanner
        }
    }

    // MARK: Toolbar

    /// Every item carries BOTH a title and a symbol via `Label`: the bar shows
    /// the symbol, and the system needs the title for the overflow menu and for
    /// expanded forms — which is where these items end up on Duo, whose bar runs
    /// down the side and holds far fewer of them.
    ///
    /// Items overflow from the bottom of that vertical bar upwards by default,
    /// so the priorities below say what to keep: Export (the primary action) and
    /// the risk list (it carries the scan result) stay longest, Help goes first.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsBackButton {
            // Primary navigation belongs at the top of the vertical axis, which
            // is where the system puts a leading item on Duo.
            ToolbarItem(placement: .topBarLeading) {
                Button { editor.reset() } label: { Label("Back", systemImage: "chevron.left") }
            }
            .overflowPriority(.high)
        }
        // The editing controls only make sense once the image is loaded.
        // Individual ToolbarItems + ToolbarSpacer (iOS 26+) so Liquid Glass
        // groups them as [undo·redo] [help·risk] [export] instead of one blob,
        // setting the primary Export action apart at the trailing edge.
        if editor.hasImage {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!editor.canUndo)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!editor.canRedo)
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: { Label("How to use", systemImage: "questionmark.circle") }
            }
            .overflowPriority(.low)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRiskList = true } label: { Label("Risk list", systemImage: "list.bullet.rectangle") }
            }
            .overflowPriority(.high)
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .popover(isPresented: $showExport) {
                        exportMenu.presentationCompactAdaptation(.popover)
                    }
            }
            .overflowPriority(.high)
        }
    }

    // MARK: Loading screen (immediate feedback + iCloud download progress)

    private var loadingView: some View {
        VStack(spacing: 18) {
            ZStack {
                ProgressView()
                    .controlSize(.large)
                if editor.isDownloadingFromCloud {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .offset(y: 34)
                }
            }
            if editor.isDownloadingFromCloud {
                Text("Downloading from iCloud… \(Int((editor.downloadProgress * 100).rounded()))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Loading photo…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(editor.isDownloadingFromCloud
            ? "Downloading from iCloud, \(Int(editor.downloadProgress * 100)) percent"
            : "Loading photo")
    }

    // MARK: Export popover (four options)

    private var exportMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Photo Metadata", systemImage: "doc.text.magnifyingglass",
                    subtitle: "GPS, device model, timestamps — GPS removed by default") {
                dismissPopoverThen { showMetadata = true }
            }
            Divider()
            Toggle(isOn: $editor.compress) {
                Label("Compress similar colors", systemImage: "rectangle.compress.vertical")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Toggle(isOn: $editor.scrubHiddenMarks) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Remove hidden marks", systemImage: "eye.slash")
                    Text("Clears pixel low-bits + all metadata. Can't remove robust forensic watermarks.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 28)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            menuRow("Share…", systemImage: "square.and.arrow.up") { share(deleteAfter: false) }
            if editor.hasSourceAsset {
                menuRow("Share & Delete Original", systemImage: "square.and.arrow.up.trianglebadge.exclamationmark",
                        role: .destructive) { share(deleteAfter: true) }
            }
            Divider()
            if editor.hasSourceAsset {
                menuRow("Save (Overwrite Original)", systemImage: "square.and.arrow.down.on.square") {
                    saveOverwrite()
                }
            }
            menuRow("Save a Copy", systemImage: "doc.on.doc") { saveCopy() }
        }
        // Ideal rather than fixed, so the menu can compress on the narrow outer
        // display instead of being clipped.
        .frame(idealWidth: 310, maxWidth: 340)
        .tint(.accentColor)
    }

    private func menuRow(_ title: LocalizedStringKey, systemImage: String, subtitle: LocalizedStringKey? = nil,
                         role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(role == .destructive ? Color.red : .primary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.leading, 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Dismisses the export popover, THEN runs `action` (typically presenting a
    /// sheet) after the dismissal settles. On iOS 26+, flipping a sheet's binding
    /// to `true` in the SAME runloop that hides the popover silently fails to
    /// present and leaves the binding stuck `true` — which then blocks every
    /// other sheet in the view (the "many buttons stop responding" bug). Deferring
    /// past the popover's dismissal animation makes the sheet present reliably.
    private func dismissPopoverThen(_ action: @escaping () -> Void) {
        showExport = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let base = fittedRect(in: proxy.size)
            let fz = zoomedRect(base: base)
            ZStack {
                // Flexible anchor so the ZStack always fills the canvas and
                // .position coordinates match gesture coordinates exactly.
                Color.clear
                if let preview = editor.previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .frame(width: fz.width, height: fz.height)
                        .position(x: fz.midX, y: fz.midY)
                        .accessibilityLabel("Photo preview with redactions applied")
                }
                ForEach(editor.regions) { region in
                    regionOverlay(region, fitted: fz)
                }
                // Emoji covers (faces): live overlay — crisp and cheap to drag;
                // baked into pixels only at export.
                ForEach(editor.regions.filter { $0.isSelected && $0.emoji != nil }) { region in
                    let rect = viewRect(for: region.boundingBox, fitted: fz)
                    Text(region.emoji ?? "")
                        .font(.system(size: min(rect.width, rect.height) * 1.1))
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Emoji cover, drag to move, tap to change")
                }
                if !editor.isMarkerMode, let rect = activeDragRect(fitted: fz) {
                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Color.accentColor.opacity(0.15))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                if editor.isMarkerMode, markerPoints.count > 1 {
                    Path { $0.addLines(markerPoints) }
                        .stroke(Color(rgba: editor.markerColor),
                                style: StrokeStyle(lineWidth: EditorModel.markerWidth * fz.width,
                                                   lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                }
                if editor.isScanning { scanningOverlay(in: proxy.size) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(canvasGesture(fitted: fz))
            .simultaneousGesture(longPressGesture(fitted: fz))
            .simultaneousGesture(magnifyGesture(base: base, canvasSize: proxy.size))
            .overlay(alignment: .bottomTrailing) {
                if showsColorControl { colorControl }
            }
        }
        // No reservation for the palette: it lives in the safe area now, so the
        // canvas already ends where the palette begins, on any display size.
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func regionOverlay(_ region: RiskRegion, fitted: CGRect) -> some View {
        // Selected emoji covers show the emoji itself instead of a border.
        if !(region.isSelected && region.emoji != nil) {
            let color = color(for: region.riskLevel)
            let isHighlighted = editor.highlightedRegionID == region.id
            // A refined region outlines each kept word instead of one box.
            ForEach(Array(region.coverRects.enumerated()), id: \.offset) { _, box in
                let rect = viewRect(for: box, fitted: fitted)
                Rectangle()
                    .strokeBorder(
                        region.isSelected ? color : Color.gray,
                        style: StrokeStyle(lineWidth: isHighlighted ? 4 : 2,
                                           dash: region.isSelected ? [] : [5]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func scanningOverlay(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning on device…").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .floatingGlass(in: RoundedRectangle(cornerRadius: 16))
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: Color control (marker brush + Block fill)

    /// The floating color well appears for the Marker and for the Block style —
    /// both let the user choose a fill color via the system picker (grid /
    /// spectrum / sliders + built-in screen eyedropper).
    private var showsColorControl: Bool {
        editor.isMarkerMode || editor.style == .block
    }

    private var colorControl: some View {
        ColorPicker(colorControlTitle, selection: activeColorBinding, supportsOpacity: false)
            .labelsHidden()
            .scaleEffect(1.35)
            .frame(width: 48, height: 48)
            .floatingGlass(in: Circle(), interactive: true)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .accessibilityLabel(colorControlTitle)
    }

    private var colorControlTitle: String {
        editor.isMarkerMode ? String(localized: "Brush color") : String(localized: "Block color")
    }

    /// Marker mode targets the brush color; otherwise the Block fill color.
    private var activeColorBinding: Binding<Color> {
        editor.isMarkerMode ? brushColorBinding : blockColorBinding
    }

    private var brushColorBinding: Binding<Color> {
        Binding(get: { Color(rgba: editor.markerColor) },
                set: { editor.markerColor = $0.rgba })
    }

    private var blockColorBinding: Binding<Color> {
        Binding(get: { Color(rgba: editor.blockColor) },
                set: { editor.setBlockColor($0.rgba) })
    }

    // MARK: Tool palette (Auto pinned, rest scrolls, inset from edges)

    /// The palette laid out along `axis`: a capsule under the photo in tall
    /// layouts, a rail beside it in wide-and-short ones. The ORDER is identical
    /// either way — Auto first, then the styles, then marker and watermark — so
    /// that changing pose never makes the user relearn where a tool lives.
    private func paletteStrip(axis: Axis) -> some View {
        let strip = paletteLayout(axis, spacing: 0)
        let tools = paletteLayout(axis, spacing: 2)
        return strip {
            paletteButton("Auto", systemImage: "wand.and.stars", active: false) {
                editor.applyAllSuggestions()
                flash(String(localized: "Applied \(editor.selectedRegions.count) suggestions"))
            }
            .padding(axis == .horizontal ? .leading : .top, 6)
            divider(axis: axis)
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                tools {
                    styleButton(.block, "Block", "rectangle.fill")
                    styleButton(.pixelate, "Pixelate", "squareshape.split.3x3")
                    styleButton(.blur, "Blur", "drop.fill")
                    styleButton(.hideText, "Hide Text", "character.textbox")
                    divider(axis: axis)
                    paletteButton("Marker", systemImage: "scribble.variable",
                                  active: editor.isMarkerMode) {
                        editor.isMarkerMode = true
                    }
                    paletteButton("Watermark", systemImage: "signature",
                                  active: editor.userWatermarkText != nil) {
                        watermarkText = editor.userWatermarkText ?? appName
                        showWatermarkInput = true
                    }
                }
                .padding(axis == .horizontal ? .horizontal : .vertical, 8)
            }
        }
        .padding(axis == .horizontal ? .vertical : .horizontal, 8)
        .padding(axis == .horizontal ? .trailing : .bottom, 6)
        .floatingGlass(in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(axis == .horizontal ? .horizontal : .vertical, 16)
        .padding(axis == .horizontal ? .bottom : .trailing, 12)
    }

    /// Best-effort hidden-watermark warning. Tapping opens the export sheet,
    /// where "Remove hidden marks" is already on. Honest wording: it's a
    /// possibility, and removal can't guarantee robust forensic watermarks.
    @ViewBuilder
    private var stegoBanner: some View {
        if editor.stegoFinding.isSuspicious {
            Button { showExport = true } label: {
                Label("Possible hidden watermark — will be scrubbed on export",
                      systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.caption2.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.orange, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens export options to remove hidden marks")
        }
    }

    @ViewBuilder
    private var hintBanner: some View {
        if editor.isMarkerMode {
            banner("Drag to draw. Pinch to zoom.", systemImage: "scribble.variable", color: .accentColor)
        } else if editor.style == .hideText {
            banner("Hide Text works best on a solid background.", systemImage: "info.circle", color: .secondary)
        } else if editor.style.isReversibleOnText, hasTextSelected {
            banner("Pixelate/blur on text can be reversed. Block is safest.",
                   systemImage: "exclamationmark.triangle", color: .orange)
        }
    }

    private func banner(_ text: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }

    /// `AnyLayout` rather than a branch on HStack/VStack: the buttons keep their
    /// identity when the palette swings between capsule and rail, so the change
    /// animates instead of snapping — the small adjustment the HIG asks for as
    /// the device folds.
    private func paletteLayout(_ axis: Axis, spacing: CGFloat) -> AnyLayout {
        axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
    }

    private func divider(axis: Axis) -> some View {
        Rectangle().fill(Color(.separator).opacity(0.4))
            .frame(width: axis == .horizontal ? 0.5 : 34,
                   height: axis == .horizontal ? 34 : 0.5)
            .padding(axis == .horizontal ? .horizontal : .vertical, 3)
    }

    private func styleButton(_ style: RedactionStyle, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        paletteButton(title, systemImage: symbol,
                      active: !editor.isMarkerMode && editor.style == style) {
            editor.setStyle(style)
        }
    }

    private func paletteButton(_ title: LocalizedStringKey, systemImage: String, active: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 20))
                Text(title).font(.caption2)
            }
            .frame(width: 60, height: 52)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(active ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    private var hasTextSelected: Bool {
        editor.selectedRegions.contains { $0.type != .face }
    }

    // MARK: Actions

    private func share(deleteAfter: Bool) {
        showExport = false
        Task {
            guard let export = await editor.makeExport(),
                  let url = editor.shareURL(for: export) else {
                flash(String(localized: "Couldn't prepare image")); return
            }
            sharePayload = SharePayload(url: url, deleteAfter: deleteAfter)
        }
    }

    private func saveCopy() {
        showExport = false
        Task {
            guard let export = await editor.makeExport() else { flash(String(localized: "Couldn't prepare image")); return }
            do { try await editor.saveToPhotos(export); flash(String(localized: "Saved a copy")) }
            catch { flash(error.localizedDescription) }
        }
    }

    private func saveOverwrite() {
        showExport = false
        Task {
            guard let export = await editor.makeExport() else { flash(String(localized: "Couldn't prepare image")); return }
            do { try await editor.overwriteOriginal(export); flash(String(localized: "Saved · original updated")) }
            catch { flash(error.localizedDescription) }
        }
    }

    private func flash(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .floatingGlass(in: Capsule())
            .shadow(radius: 8)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Gestures

    /// Pinch zoom anchored at the fingers: the image point under the pinch
    /// start stays fixed. Derivation: with drawn center C and scale ratio
    /// k = z'/z₀, keeping anchor A stationary requires C' = A - (A - C₀)·k.
    private func magnifyGesture(base: CGRect, canvasSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchSession == nil {
                    pinchSession = (zoom, pan,
                                    CGPoint(x: value.startAnchor.x * canvasSize.width,
                                            y: value.startAnchor.y * canvasSize.height))
                    // A second finger landed: abandon any in-progress stroke/box.
                    markerPoints = []
                    dragStart = nil
                    dragCurrent = nil
                }
                guard let s = pinchSession, base.width > 0 else { return }
                let newZoom = (s.zoom * value.magnification).clamped(to: 1...5)
                let k = newZoom / s.zoom
                let c0 = CGPoint(x: base.midX + s.pan.width, y: base.midY + s.pan.height)
                let c1 = CGPoint(x: s.anchor.x - (s.anchor.x - c0.x) * k,
                                 y: s.anchor.y - (s.anchor.y - c0.y) * k)
                zoom = newZoom
                pan = CGSize(width: c1.x - base.midX, height: c1.y - base.midY)
            }
            .onEnded { _ in
                pinchSession = nil
                if zoom <= 1.02 {
                    withAnimation(.easeOut(duration: 0.15)) { zoom = 1; pan = .zero }
                } else {
                    // Settle pan onto the clamped value used for drawing.
                    pan = clampedPan(pan, base: base)
                }
            }
    }

    private func canvasGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchLocation = value.location
                if pinchSession != nil { return } // two fingers down: pinch owns input
                // Dragging an emoji cover repositions it — takes precedence
                // over panning and box-drawing.
                if draggingEmojiID == nil, !editor.isMarkerMode,
                   distance(value.startLocation, value.location) > 4,
                   let hit = emojiRegion(at: value.startLocation, fitted: fitted) {
                    draggingEmojiID = hit.id
                    editor.beginRegionDrag(hit.id)
                }
                if let id = draggingEmojiID {
                    editor.moveRegion(id, toNormalizedCenter:
                        normalizedPoint(value.location, in: fitted))
                    return
                }
                if zoom > 1 && !editor.isMarkerMode {
                    // Pan the zoomed image.
                    if panDragOrigin == nil { panDragOrigin = pan }
                    if let origin = panDragOrigin {
                        pan = CGSize(width: origin.width + value.translation.width,
                                     height: origin.height + value.translation.height)
                    }
                } else if editor.isMarkerMode {
                    markerPoints.append(value.location)
                } else {
                    if dragStart == nil, distance(value.startLocation, value.location) > 8 {
                        dragStart = value.startLocation
                    }
                    if dragStart != nil { dragCurrent = value.location }
                }
            }
            .onEnded { value in
                let wasPanning = panDragOrigin != nil
                let wasMovingEmoji = draggingEmojiID != nil
                defer {
                    dragStart = nil; dragCurrent = nil; markerPoints = []
                    longPressFired = false; panDragOrigin = nil; draggingEmojiID = nil
                }
                if pinchSession != nil || wasPanning || wasMovingEmoji { return }
                let moved = distance(value.startLocation, value.location) > 8
                if editor.isMarkerMode {
                    commitMarker(fitted: fitted)
                    return
                }
                if longPressFired { return }
                if moved, let rect = activeDragRect(fitted: fitted), fitted.width > 0, fitted.height > 0 {
                    editor.addManualRegion(normalizedRect: normalizedRect(rect, in: fitted))
                } else if !moved {
                    tapToggle(at: value.location, fitted: fitted)
                }
            }
    }

    private func longPressGesture(fitted: CGRect) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                guard !editor.isMarkerMode, pinchSession == nil, panDragOrigin == nil,
                      draggingEmojiID == nil,
                      emojiRegion(at: touchLocation, fitted: fitted) == nil else { return }
                longPressFired = true
                // Fan the text under the finger into tappable word chips (Text
                // Explode). On a detected region that means refining it word by
                // word; elsewhere it covers plain text the detectors missed.
                let point = normalizedPoint(touchLocation, in: fitted)
                if let region = refinableRegion(at: point) {
                    explodeTarget = ExplodeTarget(region: region,
                                                  lines: editor.refinableLines(for: region))
                } else if let line = editor.line(atNormalizedPoint: point) {
                    explodeTarget = ExplodeTarget(line: line)
                }
            }
    }

    /// The smallest detected text region under a normalized point that can be
    /// refined to words — long-pressing it opens the word picker for it.
    private func refinableRegion(at point: CGPoint) -> RiskRegion? {
        editor.regions
            .filter { $0.emoji == nil && $0.boundingBox.contains(point)
                        && !editor.refinableLines(for: $0).isEmpty }
            .min { ($0.boundingBox.width * $0.boundingBox.height)
                 < ($1.boundingBox.width * $1.boundingBox.height) }
    }

    /// The selected emoji cover under a canvas point, if any.
    private func emojiRegion(at point: CGPoint, fitted: CGRect) -> RiskRegion? {
        editor.regions.first {
            $0.isSelected && $0.emoji != nil
                && viewRect(for: $0.boundingBox, fitted: fitted).contains(point)
        }
    }

    private func tapToggle(at point: CGPoint, fitted: CGRect) {
        // Tap on a selected emoji cover → change its emoji (system keyboard).
        if let emojiHit = emojiRegion(at: point, fitted: fitted) {
            emojiPickTarget = EmojiPickTarget(id: emojiHit.id)
            return
        }
        let atPoint = editor.regions.filter {
            viewRect(for: $0.boundingBox, fitted: fitted).contains(point)
        }
        func area(_ r: RiskRegion) -> CGFloat { r.boundingBox.width * r.boundingBox.height }
        // Peel coverage: if any SELECTED region covers this spot, deselect the
        // smallest one — so overlapping auto-marks can ALWAYS be cleared (tap
        // again for the next). Only when nothing is selected here does a tap
        // re-cover. Fixes "auto-marked region can't be canceled".
        if let selected = atPoint.filter(\.isSelected).min(by: { area($0) < area($1) }) {
            editor.setSelected(selected.id, false)
        } else if let hit = atPoint.min(by: { area($0) < area($1) }) {
            editor.setSelected(hit.id, true)
        }
    }

    private func commitMarker(fitted: CGRect) {
        guard !markerPoints.isEmpty, fitted.width > 0, fitted.height > 0 else { return }
        editor.addStroke(markerPoints.map { normalizedPoint($0, in: fitted) })
    }

    // MARK: Geometry

    /// Base fit-to-canvas rect at zoom 1.
    private func fittedRect(in container: CGSize) -> CGRect {
        guard let image = editor.image, container.width > 0, container.height > 0 else { return .zero }
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The base rect scaled by the current zoom and shifted by the pan, clamped.
    private func zoomedRect(base: CGRect) -> CGRect {
        guard base.width > 0 else { return base }
        let size = CGSize(width: base.width * zoom, height: base.height * zoom)
        let p = clampedPan(pan, base: base)
        let center = CGPoint(x: base.midX + p.width, y: base.midY + p.height)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Keeps the zoomed image covering the base rect (no gaps at the edges).
    private func clampedPan(_ pan: CGSize, base: CGRect) -> CGSize {
        let maxX = max(0, base.width * (zoom - 1) / 2)
        let maxY = max(0, base.height * (zoom - 1) / 2)
        return CGSize(width: pan.width.clamped(to: -maxX...maxX),
                      height: pan.height.clamped(to: -maxY...maxY))
    }

    private func activeDragRect(fitted: CGRect) -> CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
            .intersection(fitted)
    }

    private func normalizedRect(_ rect: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: (rect.minX - fitted.minX) / fitted.width,
               y: (rect.minY - fitted.minY) / fitted.height,
               width: rect.width / fitted.width, height: rect.height / fitted.height)
    }

    private func normalizedPoint(_ p: CGPoint, in fitted: CGRect) -> CGPoint {
        CGPoint(x: (p.x - fitted.minX) / fitted.width, y: (p.y - fitted.minY) / fitted.height)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func viewRect(for normalized: CGRect, fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + normalized.minX * fitted.width,
               y: fitted.minY + normalized.minY * fitted.height,
               width: normalized.width * fitted.width, height: normalized.height * fitted.height)
    }

    private func color(for level: RiskLevel) -> Color {
        switch level {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

extension View {
    /// Floating-surface background: Liquid Glass on iOS 26+ (the OS-native
    /// material that lets the photo show through and reacts to motion), falling
    /// back to `.regularMaterial` on earlier releases. `interactive` makes the
    /// glass respond to touch — used for tappable chrome like the color well.
    @ViewBuilder
    func floatingGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

extension Color {
    init(rgba: RGBAColor) {
        self = Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
    var rgba: RGBAColor {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBAColor(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}

/// In-app usage guide (the ? button) mirroring DAMA's how-to.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Redact") {
                    step("1", "Tap a text line to redact the whole line. Tap again to undo.")
                    step("2", "Long-press text to explode it into words — tap any word to cover it, or cover the whole line.")
                    step("3", "Long-press a detected risk to trim it word by word, or use the text button in the risk list.")
                    step("4", "Drag anywhere on the image to redact a custom area.")
                    step("✦", "Tap Auto to apply all detected suggestions at once.")
                    step("⌕", "Pinch to zoom; drag to pan when zoomed in.")
                }
                Section("Tools") {
                    tool("Block", "Solid, irreversible cover. Tap the color well to recolor it.", "rectangle.fill")
                    tool("Pixelate", "Mosaic (can be reversible on text).", "squareshape.split.3x3")
                    tool("Blur", "Gaussian blur (can be reversible on text).", "drop.fill")
                    tool("Hide Text", "Blends into a solid background.", "character.textbox")
                    tool("Marker", "Free-draw; pick any color or eyedrop from the image.", "scribble.variable")
                    tool("Watermark", "Stamp your own text across the image.", "signature")
                }
            }
            .navigationTitle("How to Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func step(_ n: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color.accentColor)
            Text(text)
        }
    }

    private func tool(_ name: LocalizedStringKey, _ desc: LocalizedStringKey, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// What the Text Explode sheet operates on: a plain OCR line (cover text the
/// detectors missed) or a detected region being trimmed word by word.
struct ExplodeTarget: Identifiable {
    let id: UUID
    let lines: [TextLine]
    /// nil in freeform mode — chips create standalone manual covers instead.
    let region: RiskRegion?

    init(line: TextLine) {
        self.id = line.id
        self.lines = [line]
        self.region = nil
    }

    init(region: RiskRegion, lines: [TextLine]) {
        self.id = region.id
        self.lines = lines
        self.region = region
    }
}

/// "Text Explode" (文字大爆炸): fans OCR text out as tappable word chips so a
/// redaction can stop at word boundaries instead of swallowing a whole line
/// (PRD §7.5). Long-pressing plain text covers the words picked here; opening
/// it on a detected risk trims that detection down to the words it should keep.
struct TextExplodeSheet: View {
    let target: ExplodeTarget
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss

    /// Every word across the target's lines — the universe a refinement works in.
    private var allWords: [TextWord] { target.lines.flatMap(\.words) }

    // Explicitly typed so both literals stay localizable keys rather than
    // collapsing to a plain String (which SwiftUI would render verbatim).
    private var title: LocalizedStringKey {
        target.region == nil ? "Text Explode" : "Refine to Words"
    }

    private var hint: LocalizedStringKey {
        target.region == nil
            ? "Tap words to cover them. Your picks are redacted on the photo."
            : "Tap a word to cover or reveal it. Only the highlighted words stay redacted."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(hint)
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(target.lines) { line in
                        FlowLayout(spacing: 8) {
                            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                                chip(word)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let region = target.region {
                        Button {
                            editor.resetRefinement(forRegion: region.id)
                        } label: { Label("Whole Match", systemImage: "text.redaction") }
                    } else if let line = target.lines.first {
                        Button {
                            editor.coverWholeLine(line)
                            dismiss()
                        } label: { Label("Whole Line", systemImage: "text.redaction") }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func isCovered(_ word: TextWord) -> Bool {
        guard let region = target.region else { return editor.isWordCovered(word) }
        return editor.isWordCovered(word, inRegion: region.id, allWords: allWords)
    }

    private func toggle(_ word: TextWord) {
        guard let region = target.region else {
            editor.toggleWordCover(word)
            return
        }
        editor.toggleRefinedWord(word, inRegion: region.id, allWords: allWords)
    }

    @ViewBuilder
    private func chip(_ word: TextWord) -> some View {
        let covered = isCovered(word)
        Text(word.text)
            .font(.body)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(covered ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(covered ? Color.white : Color.primary)
            .contentShape(Capsule())
            .onTapGesture { toggle(word) }
            .accessibilityLabel(word.text)
            .accessibilityValue(covered ? "Covered" : "Not covered")
            .accessibilityAddTraits(.isButton)
    }
}

/// Minimal wrapping layout for the Text Explode chips (iOS 16+ `Layout`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : max(0, x - spacing)
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Identifiable share payload for `.sheet(item:)`.
struct SharePayload: Identifiable {
    let url: URL
    var deleteAfter: Bool = false
    var id: String { url.absoluteString }
}

/// Region whose emoji cover is being changed.
struct EmojiPickTarget: Identifiable {
    let id: UUID
}

/// Small sheet that summons the SYSTEM emoji keyboard to pick a cover emoji,
/// or removes the emoji cover entirely.
struct EmojiPickerSheet: View {
    var onPick: (String) -> Void
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color(.tertiarySystemFill)).frame(width: 36, height: 5)
                .padding(.top, 8)
            Text("Face Cover")
                .font(.headline)
            Text("Pick an emoji from the keyboard, or remove the cover.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            EmojiKeyboardField { emoji in
                onPick(emoji)
                dismiss()
            }
            .frame(width: 120, height: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            Button(role: .destructive) {
                onRemove()
                dismiss()
            } label: {
                Label("Remove Cover", systemImage: "eye.slash")
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(220)])
    }
}

/// UITextField that forces the system EMOJI keyboard and reports the first
/// emoji typed. (iOS has no standalone emoji-picker API; the emoji keyboard
/// is the system picker.)
struct EmojiKeyboardField: UIViewRepresentable {
    var onEmoji: (String) -> Void

    final class EmojiTextField: UITextField {
        // A distinct context + emoji input mode summons the emoji keyboard.
        override var textInputContextIdentifier: String? { "" }
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
                ?? super.textInputMode
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let onEmoji: (String) -> Void
        init(onEmoji: @escaping (String) -> Void) { self.onEmoji = onEmoji }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            guard let first = string.first(where: \.isEmoji) else { return false }
            onEmoji(String(first))
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEmoji: onEmoji) }

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.textAlignment = .center
        field.placeholder = "😀"
        field.tintColor = .clear
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ uiView: EmojiTextField, context: Context) {}
}

extension Character {
    /// True for emoji with emoji presentation (filters plain text/digits).
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && unicodeScalars.count > 1)
            || scalar.value >= 0x1F000
    }
}

/// UIActivityViewController wrapper; `onFinish` runs after the sheet dismisses.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onFinish?() }
        return vc
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
