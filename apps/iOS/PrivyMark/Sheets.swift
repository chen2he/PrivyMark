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
    }
}

/// The metadata screen itself — shown as a sheet from the export menu and
/// pushed from the Detected Risks list, so the feature is reachable from both
/// the "what did you find" surface and the "what am I about to send" surface.
struct MetadataList: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
            List {
                if editor.metadata.isEmpty {
                    ContentUnavailableView(
                        "No Metadata in This File",
                        systemImage: "checkmark.shield",
                        description: Text("This image carries no GPS, capture or device data. Screenshots and images saved by other apps usually have none; a photo taken with the Camera app normally does."))
                } else {
                    Section {
                        ForEach(MetadataCategory.allCases) { category in
                            if let summary = editor.metadata.present[category] {
                                Toggle(isOn: binding(for: category)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.displayName)
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
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

                    Section {
                        Button("Remove All Metadata", role: .destructive) {
                            editor.keptMetadata = []
                        }
                    }
                }
            }
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

// MARK: - Risk list

struct RiskListSheet: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    /// Detection being trimmed word by word in the Text Explode picker.
    @State private var refineTarget: ExplodeTarget?

    var body: some View {
        NavigationStack {
            List {
                // Metadata is a risk the scan found too, so it belongs in this
                // list — not only behind the export menu (App Review 2.3).
                Section {
                    NavigationLink {
                        MetadataList(editor: editor)
                            .navigationTitle("Photo Metadata")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Photo Metadata")
                                Text(metadataSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                    }
                } header: {
                    Text("In the file itself")
                }

                if editor.regions.isEmpty {
                    ContentUnavailableView(
                        "No Risks Detected",
                        systemImage: "checkmark.shield",
                        description: Text("Drag on the image to add a redaction box manually."))
                }
                ForEach(editor.groupedRegions, id: \.type) { group in
                    Section {
                        ForEach(group.regions) { region in
                            row(region)
                        }
                    } header: {
                        HStack {
                            Label("\(group.type.displayName) (\(group.regions.count))",
                                  systemImage: group.type.symbolName)
                            Spacer()
                            let allOn = group.regions.allSatisfy(\.isSelected)
                            Button(allOn ? "None" : "All") {
                                editor.setAll(ofType: group.type, selected: !allOn)
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
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
        }
        .presentationDetents([.medium, .large])
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
            Text(region.riskLevel.displayName)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(levelColor(region.riskLevel).opacity(0.18), in: Capsule())
                .foregroundStyle(levelColor(region.riskLevel))

            Text(region.detectedText
                 ?? region.emoji.map { "\($0) Emoji cover" }
                 ?? (region.origin == .manual ? "Manual box" : "Detected region"))
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

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
                .font(.caption.weight(.medium))
                .foregroundStyle(region.isRefined ? Color.accentColor : Color.secondary)
                .buttonStyle(.borderless)
                .accessibilityLabel("Refine to words")
            }

            if region.origin == .manual {
                Button(role: .destructive) {
                    editor.removeManualRegion(region)
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Toggle("", isOn: Binding(
                get: { region.isSelected },
                set: { _ in editor.toggle(region) }))
                .labelsHidden()
                .accessibilityLabel("Hide \(region.type.displayName)")
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
