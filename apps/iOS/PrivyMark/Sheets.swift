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
            List {
                if editor.metadata.isEmpty {
                    ContentUnavailableView(
                        "No Metadata Found",
                        systemImage: "checkmark.shield",
                        description: Text("This image contains no EXIF, GPS, or device metadata."))
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
            .navigationTitle("Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    var body: some View {
        NavigationStack {
            List {
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
        }
        .presentationDetents([.medium, .large])
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
