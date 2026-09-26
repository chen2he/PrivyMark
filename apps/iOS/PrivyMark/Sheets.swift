//
//  Sheets.swift
//  PrivyMark
//
//  Metadata options (PRD §7.6) and the risk list (PRD §7.3).
//

import SwiftUI

// MARK: - Metadata

struct MetadataSheet: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MetadataList(editor: editor)
                .navigationTitle("Photo Metadata")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// The metadata screen itself — shown as a sheet from the More menu and
/// pushed from both the Detected Risks list and the export sheet, so it is
/// reachable from the "what did you find" surface and the "what am I about to
/// send" surface alike (App Review 2.3).
struct MetadataList: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        List {
            if editor.metadata.isEmpty {
                ContentUnavailableView(
                    "No Metadata in This File",
                    systemImage: "checkmark.shield",
                    description: Text("This image carries no GPS, capture or device data. Screenshots and images saved by other apps usually have none; a photo taken with the Camera app normally does."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(MetadataCategory.allCases) { category in
                        if let summary = editor.metadata.present[category] {
                            Toggle(isOn: binding(for: category)) {
                                HStack(spacing: 12) {
                                    IconTile(systemName: category.symbolName, color: category.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.displayName)
                                            .foregroundStyle(Theme.ink)
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .accessibilityLabel("Keep \(category.displayName) in exported image")
                        }
                    }
                } header: {
                    Text("Keep in exported image")
                } footer: {
                    Text("Location is removed by default. Anything switched off is stripped from the exported copy; the original photo is never changed.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Remove All Metadata", role: .destructive) {
                        withAnimation { editor.keptMetadata = [] }
                    }
                    .disabled(editor.keptMetadata.isEmpty)
                }
                .listRowBackground(Theme.card)
            }
        }
        .paperBackground()
    }

    private func binding(for category: MetadataCategory) -> Binding<Bool> {
        Binding(
            get: { editor.keptMetadata.contains(category) },
            set: { keep in
                if keep { editor.keptMetadata.insert(category) }
                else { editor.keptMetadata.remove(category) }
            })
    }
}

extension MetadataCategory {
    var symbolName: String {
        switch self {
        case .location: return "location.fill"
        case .captureInfo: return "camera.aperture"
        case .deviceInfo: return "iphone"
        case .other: return "doc.text"
        }
    }

    var tint: Color {
        switch self {
        case .location: return .blue
        case .captureInfo: return .orange
        case .deviceInfo: return .gray
        case .other: return .purple
        }
    }
}

// MARK: - Risk list

struct RiskListSheet: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    /// Detection being trimmed word by word in the Text Explode picker.
    @State private var refineTarget: ExplodeTarget?

    private var automatic: [RiskRegion] { editor.regions.filter { $0.origin == .automatic } }
    private var coveredCount: Int { automatic.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            List {
                if !automatic.isEmpty {
                    Section {
                        summary
                    }
                    .listRowBackground(Theme.card)
                }

                // Metadata is a risk the scan found too, so it belongs in this
                // list — not only behind the export sheet (App Review 2.3).
                Section {
                    NavigationLink {
                        MetadataList(editor: editor)
                            .navigationTitle("Photo Metadata")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemName: "doc.text.magnifyingglass", color: .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Photo Metadata")
                                    .foregroundStyle(Theme.ink)
                                Text(metadataSummary)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text("In the file itself")
                }
                .listRowBackground(Theme.card)

                if editor.regions.isEmpty {
                    ContentUnavailableView(
                        "No Risks Detected",
                        systemImage: "checkmark.shield",
                        description: Text("Drag on the image to add a redaction box manually."))
                        .listRowBackground(Color.clear)
                }
                ForEach(editor.groupedRegions, id: \.type) { group in
                    Section {
                        ForEach(group.regions) { region in
                            row(region)
                        }
                    } header: {
                        groupHeader(group.type, regions: group.regions)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .paperBackground()
            .navigationTitle("Detected Risks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $refineTarget) { target in
                TextExplodeSheet(target: target, editor: editor)
            }
            .sensoryFeedback(.selection, trigger: editor.selectedRegions.count)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var summary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.inkFaint, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: automatic.isEmpty ? 0 : CGFloat(coveredCount) / CGFloat(automatic.count))
                    .stroke(Theme.brand, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: coveredCount == automatic.count ? "checkmark" : "exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(coveredCount == automatic.count ? Theme.brand : .orange)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 42, height: 42)
            .animation(.snappy, value: coveredCount)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(automatic.count) found · \(coveredCount) covered")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                Text("Review each one before you share.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            if coveredCount < automatic.count {
                Button("Cover All") {
                    withAnimation(.snappy) { editor.applyAllSuggestions() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func groupHeader(_ type: RiskType, regions: [RiskRegion]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: type.symbolName)
                .foregroundStyle(Theme.brand)
            Text("\(type.displayName) (\(regions.count))")
            Spacer()
            let allOn = regions.allSatisfy(\.isSelected)
            Button(allOn ? "None" : "All") {
                withAnimation(.snappy) { editor.setAll(ofType: type, selected: !allOn) }
            }
            .font(.caption.weight(.semibold))
            .textCase(nil)
        }
    }

    /// One line naming what the file actually carries, so the entry point reads
    /// as a finding rather than a settings link.
    private var metadataSummary: String {
        let present = MetadataCategory.allCases.filter { editor.metadata.present[$0] != nil }
        guard !present.isEmpty else { return String(localized: "No GPS, capture or device data") }
        return present.map(\.displayName).joined(separator: ", ")
    }

    private func row(_ region: RiskRegion) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title(for: region))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                levelChip(region.riskLevel)
            }
            .contentShape(Rectangle())
            // Flash it on the photo — the sheet leaves the top of the canvas
            // visible at its medium height.
            .onTapGesture { highlight(region) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Highlights it on the photo")

            Spacer(minLength: 4)

            // A detection that sits on OCR text can be trimmed to single words,
            // so toggling an address or a long line no longer means blacking out
            // everything next to it.
            let refinable = editor.refinableLines(for: region)
            if !refinable.isEmpty {
                // A word (not an icon): SF Symbol glyphs for text all read as
                // something else in a CJK locale, and this affordance is the one
                // users were missing.
                Button("Words") {
                    refineTarget = ExplodeTarget(region: region, lines: refinable)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(region.isRefined ? Theme.brand : Theme.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(region.isRefined ? Theme.brand.opacity(0.14) : Theme.inkFaint))
                .buttonStyle(.borderless)
                .accessibilityLabel("Refine to words")
            }

            if region.origin == .manual {
                Button(role: .destructive) {
                    withAnimation { editor.removeManualRegion(region) }
                } label: {
                    Image(systemName: "trash").font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete")
            }

            Toggle("", isOn: Binding(
                get: { region.isSelected },
                set: { _ in editor.toggle(region) }))
                .labelsHidden()
                .accessibilityLabel("Hide \(region.type.displayName)")
        }
    }

    private func title(for region: RiskRegion) -> String {
        if let text = region.detectedText { return text }
        if let emoji = region.emoji { return String(localized: "\(emoji) Emoji cover") }
        return region.origin == .manual
            ? String(localized: "Manual box") : String(localized: "Detected region")
    }

    private func levelChip(_ level: RiskLevel) -> some View {
        Text(level.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(levelColor(level))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(levelColor(level).opacity(0.13), in: Capsule())
    }

    private func highlight(_ region: RiskRegion) {
        withAnimation(.snappy) { editor.highlightedRegionID = region.id }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut) {
                if editor.highlightedRegionID == region.id { editor.highlightedRegionID = nil }
            }
        }
    }

    private func levelColor(_ level: RiskLevel) -> Color {
        switch level {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}
