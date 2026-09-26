//
//  PhotoAccessView.swift
//  PrivyMark
//
//  Home, when PrivyMark can't read the photo library (PRD §7.1).
//
//  • Not asked yet (someone who finished onboarding on an older version):
//    the pre-permission page again. App Review 5.1.1(iv) / HIG "Privacy": it
//    precedes the system alert, so it has ONE action, labelled "Continue" —
//    never "Allow"/"OK", and no second way out.
//  • Declined or restricted: the alternatives 5.1.1(iv) asks for. Pick a
//    single photo with the system picker (it runs out of process, so it needs
//    no library access at all), try the sample, or turn access on in Settings.
//

import SwiftUI
import Photos
import PhotosUI

struct PhotoAccessView: View {
    @ObservedObject var library: PhotoLibraryService
    @ObservedObject var settings: SettingsStore
    /// A photo picked through the system picker (no library access needed).
    var onPickItem: (PhotosPickerItem) -> Void
    var onTrySample: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showSettings = false
    @State private var isRequesting = false
    @State private var isMarked = false
    @State private var size: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isWide: Bool { size.width > size.height * 1.05 }
    private var isUndetermined: Bool { library.status == .notDetermined }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if isWide {
                // Landscape and the Duo outer display: the actions join the
                // copy column instead of stretching across the whole width.
                HStack(alignment: .center, spacing: 32) {
                    illustration
                    VStack(alignment: .leading, spacing: 18) {
                        copy
                        actions
                    }
                    .frame(maxWidth: 380)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    illustration
                    copy
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                actions
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
            }
        }
        .readableColumn(maxWidth: isWide ? 820 : 520)
        .background(Theme.paper.ignoresSafeArea())
        .measureContent(into: $size)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            onPickItem(item)
        }
        .task {
            if reduceMotion { isMarked = true; return }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.5)) { isMarked = true }
        }
    }

    // MARK: Pieces

    private var illustration: some View {
        FitToSpace(ideal: CGSize(width: 330, height: 330)) {
            AccessIllustration(isActive: true, isDenied: !isUndetermined)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            AppMark(size: 26)
            Text(verbatim: "PrivyMark")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer()
            // Not on the pre-permission page, which keeps a single action.
            if !isUndetermined {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 24)
    }

    private var copy: some View {
        ViewThatFits(in: .vertical) {
            copyStack
            ScrollView(showsIndicators: false) { copyStack }
        }
    }

    private var copyStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isUndetermined {
                MarkedHeadline(lead: "Your photos,", marked: "your call", isMarked: isMarked)
                Text("PrivyMark only reads the photos you open. Share your whole library or just a few — you can change this anytime in Settings.")
                    .modifier(BodyCopy())
            } else {
                MarkedHeadline(lead: "Check any photo,", marked: "one at a time", isMarked: isMarked)
                Text("Photos access is off, so PrivyMark sees only the photo you pick. Turn access on in Settings to browse your library here.")
                    .modifier(BodyCopy())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if isUndetermined {
                Button(action: requestAccess) {
                    ZStack {
                        Text("Continue").opacity(isRequesting ? 0 : 1)
                        if isRequesting { ProgressView().tint(Theme.onBrand) }
                    }
                }
                .buttonStyle(.primary)
                .disabled(isRequesting)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.primary)

                HStack(spacing: 12) {
                    Button("Try the Sample", action: onTrySample)
                        .buttonStyle(.secondary)
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.secondary)
                }
            }
        }
    }

    // MARK: Actions

    private func requestAccess() {
        isRequesting = true
        Task {
            await library.requestAccess()
            isRequesting = false
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Secondary body copy under a `MarkedHeadline`.
struct BodyCopy: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    PhotoAccessView(library: PhotoLibraryService(), settings: SettingsStore(),
                    onPickItem: { _ in }, onTrySample: {})
}
