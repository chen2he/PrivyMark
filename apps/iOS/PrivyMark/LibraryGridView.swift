//
//  LibraryGridView.swift
//  PrivyMark
//
//  Photo grid home (PRD §10.1): the user's photos, newest first, with a
//  Screenshots / All Photos switch floating at the bottom. Tap one to scan it.
//

import SwiftUI
import Photos
import UniformTypeIdentifiers

struct LibraryGridView: View {
    @ObservedObject var library: PhotoLibraryService
    @ObservedObject var settings: SettingsStore
    var onPick: (PHAssetWrapper) -> Void
    var onImport: (Data) -> Void
    var onTrySample: () -> Void
    /// False when the grid is the sidebar of a split view, which supplies the
    /// navigation container itself.
    var embedsNavigation = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("libraryFilter") private var storedFilter = LibraryFilter.all.rawValue
    @State private var showSettings = false
    @State private var showImporter = false

    private var filter: LibraryFilter { LibraryFilter(rawValue: storedFilter) ?? .all }

    /// Even column count, wider on the inner display: a partially folded device
    /// splits the grid down the middle, and an even count divides cleanly on
    /// either side of the fold instead of leaving a column straddling it.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2),
              count: horizontalSizeClass.evenGridColumns)
    }

    /// Screenshots are tall; show more of each one.
    private var cellAspect: CGFloat { filter == .screenshots ? 0.75 : 1 }

    var body: some View {
        if embedsNavigation {
            NavigationStack { grid }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            header
            if library.isLimited {
                limitedCard
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    Button {
                        onPick(PHAssetWrapper(asset: asset))
                    } label: {
                        ThumbnailCell(asset: asset, library: library, aspect: cellAspect)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(accessibilityLabel(for: asset))
                    .accessibilityHint("Scans this photo for private details")
                }
            }
            if library.assets.isEmpty && !library.isLoading {
                emptyState
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(filter.title)
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import from Files", systemImage: "folder")
                    }
                    Button(action: onTrySample) {
                        Label("Try the Sample", systemImage: "doc.text.image")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            .overflowPriority(.high)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .overflowPriority(.low)
        }
        .bottomBar { FilterSwitch(selection: filterBinding) }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                importFile(url)
            }
        }
        .onAppear {
            // Setting a different filter refetches on its own.
            if library.filter != filter {
                library.filter = filter
            } else {
                library.fetchAssets()
            }
        }
    }

    private var filterBinding: Binding<LibraryFilter> {
        Binding(get: { filter }, set: { new in
            storedFilter = new.rawValue
            library.filter = new
        })
    }

    // MARK: Pieces

    private var header: some View {
        Label {
            Text("Tap a photo to check it. Nothing leaves this iPhone.")
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Theme.brand)
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var limitedCard: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "photo.badge.checkmark", size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing the photos you picked")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("PrivyMark can only see these. Add more anytime.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Manage") {
                if let vc = UIApplication.shared.topViewController {
                    library.presentLimitedPicker(from: vc)
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(14)
        .paperCard(cornerRadius: 18)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: filter == .screenshots ? "camera.viewfinder" : "photo.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.inkSecondary)
            Text(filter == .screenshots ? "No Screenshots" : "No Photos")
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text(filter == .screenshots
                 ? "Screenshots you take show up here."
                 : "Import an image from Files, or try the sample.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Group {
                if filter == .screenshots {
                    Button("Show All Photos") { filterBinding.wrappedValue = .all }
                } else {
                    Button("Try the Sample", action: onTrySample)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func accessibilityLabel(for asset: PHAsset) -> Text {
        let kind = asset.mediaSubtypes.contains(.photoScreenshot)
            ? String(localized: "Screenshot") : String(localized: "Photo")
        guard let date = asset.creationDate else { return Text(kind) }
        return Text("\(kind), \(date.formatted(date: .abbreviated, time: .shortened))")
    }

    private func importFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            onImport(data)
        }
    }
}

// MARK: - Filter switch

/// Screenshots / All Photos, as a floating capsule over the bottom of the grid.
private struct FilterSwitch: View {
    @Binding var selection: LibraryFilter
    @Namespace private var namespace

    private let order: [LibraryFilter] = [.screenshots, .all]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(order) { filter in
                let isSelected = selection == filter
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = filter }
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 38)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.card)
                                    .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .floatingGlass(in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Cell

/// One grid cell with an async-loaded thumbnail.
/// Sized via aspectRatio + center-cropped via overlay/clipped — no
/// GeometryReader and no fixed-size stack, so the cell's visual content
/// always coincides with its hit area on every OS version (the older
/// GeometryReader + fixed-frame ZStack spilled outside the cell on iOS 27).
private struct ThumbnailCell: View {
    let asset: PHAsset
    @ObservedObject var library: PhotoLibraryService
    var aspect: CGFloat = 1
    @State private var image: UIImage?

    var body: some View {
        Theme.inkFaint
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                let loaded = await library.requestThumbnail(
                    for: asset, targetSize: CGSize(width: 300, height: 300 / aspect))
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
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
