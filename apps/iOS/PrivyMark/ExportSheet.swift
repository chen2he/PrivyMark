//
//  ExportSheet.swift
//  PrivyMark
//
//  "What am I about to send?" (PRD §7.6): a last look at the covered photo,
//  what the file still carries, the export options, then Share or Save.
//
//  Photo Metadata is PUSHED inside this sheet rather than presented on top of
//  it, so there is no dismiss-then-present dance (the old export popover
//  needed a timed delay to open the metadata sheet reliably on iOS 26+).
//

import SwiftUI

struct ExportSheet: View {
    @ObservedObject var editor: EditorModel
    /// Called after the sheet dismisses itself, with a confirmation to show
    /// in the editor (nil when the person just closed the sheet).
    var onFinish: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sharePayload: SharePayload?
    @State private var busy: Action?
    @State private var errorMessage: String?
    @State private var confirmReplace = false

    private enum Action { case share, shareAndDelete, saveCopy, replace }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                }

                Section {
                    NavigationLink {
                        MetadataList(editor: editor)
                            .navigationTitle("Photo Metadata")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        row("Photo Metadata", subtitle: Text(metadataSummary),
                            systemImage: "doc.text.magnifyingglass", color: .blue)
                    }
                    Toggle(isOn: $editor.compress) {
                        row("Compress similar colors", subtitle: nil,
                            systemImage: "rectangle.compress.vertical", color: .gray)
                    }
                    Toggle(isOn: $editor.scrubHiddenMarks) {
                        row("Remove hidden marks",
                            subtitle: Text("Clears pixel low-bits + all metadata. Can't remove robust forensic watermarks."),
                            systemImage: "eye.slash.fill", color: .orange)
                    }
                } header: {
                    Text("Options")
                }
                .listRowBackground(Theme.card)
            }
            .paperBackground()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            // A swipe-down can close the share sheet without its completion
            // handler running; never leave the Share button spinning.
            .sheet(item: $sharePayload, onDismiss: { busy = nil }) { payload in
                ShareSheet(url: payload.url) { completed in
                    finishShare(deleteAfter: payload.deleteAfter, completed: completed)
                }
            }
            .alert("Couldn't Export", isPresented: showsError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Replace the original photo?", isPresented: $confirmReplace,
                                titleVisibility: .visible) {
                Button("Replace Original") { run(.replace) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The covered version takes its place in your library. You can revert it later in the Photos app.")
            }
        }
        // Tall enough for the summary, the options and the pinned actions at
        // the default text size; larger sizes scroll the options.
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy != nil)
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: 16) {
            Group {
                if let preview = editor.previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    Theme.inkFaint
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Ready to share")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Theme.brand)
                    Text(coveredSummary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var coveredSummary: String {
        let covered = editor.selectedRegions.count + editor.strokes.count
        return covered == 0
            ? String(localized: "Nothing covered yet")
            : String(localized: "\(covered) covered · flattened into the pixels")
    }

    /// What the exported file will keep, in a few words.
    private var metadataSummary: String {
        if editor.scrubHiddenMarks { return String(localized: "All removed") }
        let present = MetadataCategory.allCases.filter { editor.metadata.present[$0] != nil }
        guard !present.isEmpty else { return String(localized: "None in this file") }
        let kept = present.filter { editor.keptMetadata.contains($0) }
        guard !kept.isEmpty else { return String(localized: "All removed") }
        return String(localized: "Keeping \(kept.map(\.displayName).formatted(.list(type: .and)))")
    }

    private func row(_ title: LocalizedStringKey, subtitle: Text?, systemImage: String,
                     color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemImage, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    subtitle
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                run(.share)
            } label: {
                busyLabel(.share) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            .buttonStyle(.primary)

            Button {
                run(.saveCopy)
            } label: {
                busyLabel(.saveCopy) { Label("Save a Copy to Photos", systemImage: "square.and.arrow.down") }
            }
            .buttonStyle(.secondary)

            if editor.hasSourceAsset {
                HStack(spacing: 20) {
                    Button("Replace Original") { confirmReplace = true }
                        .foregroundStyle(Theme.ink)
                    Button("Share & Delete Original", role: .destructive) { run(.shareAndDelete) }
                        .foregroundStyle(.red)
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 4)
            }
        }
        .disabled(busy != nil)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            Theme.paper
                .ignoresSafeArea()
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func busyLabel<L: View>(_ action: Action, @ViewBuilder label: () -> L) -> some View {
        ZStack {
            label().opacity(busy == action ? 0 : 1)
            if busy == action { ProgressView() }
        }
    }

    private func run(_ action: Action) {
        busy = action
        Task {
            guard let export = await editor.makeExport() else {
                busy = nil
                errorMessage = String(localized: "Couldn't prepare image")
                return
            }
            switch action {
            case .share, .shareAndDelete:
                guard let url = editor.shareURL(for: export) else {
                    busy = nil
                    errorMessage = String(localized: "Couldn't prepare image")
                    return
                }
                sharePayload = SharePayload(url: url, deleteAfter: action == .shareAndDelete)
            case .saveCopy:
                do {
                    try await editor.saveToPhotos(export)
                    close(with: String(localized: "Saved a copy"))
                } catch {
                    busy = nil
                    errorMessage = error.localizedDescription
                }
            case .replace:
                do {
                    try await editor.overwriteOriginal(export)
                    close(with: String(localized: "Saved · original updated"))
                } catch {
                    busy = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// The share sheet closed. Cancelled: stay, so the person can try again
    /// or save instead — and never delete an original that wasn't shared.
    private func finishShare(deleteAfter: Bool, completed: Bool) {
        busy = nil
        guard completed else { return }
        guard deleteAfter else {
            dismiss()
            onFinish(nil)
            return
        }
        Task {
            do {
                try await editor.deleteOriginal()
                close(with: String(localized: "Shared · original deleted"))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close(with message: String) {
        busy = nil
        dismiss()
        onFinish(message)
    }

    private var showsError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
