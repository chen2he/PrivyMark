//
//  LibraryGridView.swift
//  PrivyMark
//
//  Photo grid home (PRD §10.1). Mirrors DAMA: import button, album title,
//  settings gear, and a grid of the user's photos. Tap one to scan it.
//

import SwiftUI
import Photos
import UniformTypeIdentifiers

struct LibraryGridView: View {
    @ObservedObject var library: PhotoLibraryService
    @ObservedObject var settings: SettingsStore
    var onPick: (PHAssetWrapper) -> Void
    var onImport: (Data) -> Void
    /// False when the grid is the sidebar of a split view, which supplies the
    /// navigation container itself.
    var embedsNavigation = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSettings = false
    @State private var showImporter = false

    /// Even column count, wider on the inner display: a partially folded device
    /// splits the grid down the middle, and an even count divides cleanly on
    /// either side of the fold instead of leaving a column straddling it.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3),
              count: horizontalSizeClass.evenGridColumns)
    }

    var body: some View {
        if embedsNavigation {
            NavigationStack { grid }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            if library.isLimited {
                limitedBanner
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    Button {
                        onPick(PHAssetWrapper(asset: asset))
                    } label: {
                        ThumbnailCell(asset: asset, library: library)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo, tap to scan")
                }
            }
            .padding(.horizontal, 3)

            if library.assets.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle",
                    description: Text("Import an image or try a sample to get started."))
                    .padding(.top, 80)
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showImporter = true
                } label: {
                    Label("Import image from Files",
                          systemImage: "square.and.arrow.down.on.square")
                }
            }
            .overflowPriority(.high)
            ToolbarItem(placement: .principal) {
                Text("All Photos").font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .overflowPriority(.low)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                importFile(url)
            }
        }
        .onAppear { library.fetchAssets() }
    }

    private var limitedBanner: some View {
        Button {
            if let vc = UIApplication.shared.topViewController {
                library.presentLimitedPicker(from: vc)
            }
        } label: {
            HStack {
                Image(systemName: "checkmark.circle")
                Text("You've allowed access to selected photos. Tap to manage.")
                    .font(.footnote)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding([.horizontal, .top], 12)
    }

    private func importFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            onImport(data)
        }
    }
}

/// One grid cell with an async-loaded thumbnail.
/// Square via aspectRatio + center-cropped via overlay/clipped — no
/// GeometryReader and no fixed-size stack, so the cell's visual content
/// always coincides with its hit area on every OS version (the older
/// GeometryReader + fixed-frame ZStack spilled outside the cell on iOS 27).
private struct ThumbnailCell: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                image = await library.requestThumbnail(
                    for: asset, targetSize: CGSize(width: 300, height: 300))
            }
    }
}

extension UIApplication {
    /// Topmost view controller — used to present the Limited-access picker.
    var topViewController: UIViewController? {
        let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
