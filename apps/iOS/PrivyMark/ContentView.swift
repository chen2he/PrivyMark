//
//  ContentView.swift
//  PrivyMark
//
//  Top-level router (PRD §10): onboarding → library grid (or the no-access
//  home) → editor.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var library = PhotoLibraryService()
    @StateObject private var editor = EditorModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var loadFailed = false

    var body: some View {
        Group {
            switch route {
            case .onboarding:
                OnboardingView(library: library) { settings.hasSeenWelcome = true }
            case .split:
                splitInterface
            case .editor:
                EditorView(editor: editor, settings: settings)
            case .library:
                LibraryGridView(library: library, settings: settings,
                                onPick: loadFromAsset, onImport: loadData,
                                onTrySample: loadSample)
            case .noAccess:
                PhotoAccessView(library: library, settings: settings,
                                onPickItem: loadPickerItem, onTrySample: loadSample)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: route)
        .tint(.accentColor)
        .task {
            library.refreshStatus()
            maybeAutoEdit()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.refreshStatus()
                pickUpSharedImage()
            }
        }
        .onChange(of: library.status) { _, _ in maybeAutoEdit() }
        .onOpenURL { _ in pickUpSharedImage() }
        .alert("Couldn't Open Photo", isPresented: $loadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This photo couldn't be downloaded. Check your connection and try again.")
        }
    }

    private enum Route: Hashable {
        case onboarding, split, editor, library, noAccess
    }

    private var route: Route {
        if !settings.hasSeenWelcome { return .onboarding }
        if horizontalSizeClass == .regular, library.isAuthorized { return .split }
        if editor.isActive { return .editor }
        return library.isAuthorized ? .library : .noAccess
    }

    // MARK: Regular width — grid and editor side by side

    /// The extra level of hierarchy the HIG asks for on the larger inner
    /// display (and on iPad): the grid stays visible beside the photo being
    /// edited, the way Mail keeps its list beside a message. In compact width —
    /// the outer display, and every current iPhone — the `Group` above takes the
    /// single-screen path instead, so nothing changes there.
    private var splitInterface: some View {
        NavigationSplitView {
            LibraryGridView(library: library, settings: settings,
                            onPick: loadFromAsset, onImport: loadData,
                            onTrySample: loadSample, embedsNavigation: false)
        } detail: {
            if editor.isActive {
                EditorView(editor: editor, settings: settings, showsBackButton: false)
            } else {
                ContentUnavailableView(
                    "Choose a Photo",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Pick a photo to scan for faces, text, and hidden marks."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The editor's mat, waiting for a photo.
                    .background {
                        ZStack { Theme.canvas; DotGrid() }.ignoresSafeArea()
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Loading into the editor

    private func prepareEditor() {
        editor.defaultStyle = settings.defaultTool
        editor.useAIDetection = settings.aiDetectionEnabled
    }

    private func loadFromAsset(_ asset: PHAssetWrapper) {
        prepareEditor()
        editor.beginLoading() // shows the loading screen immediately
        Task {
            let data = await library.requestImageData(for: asset.asset) { progress in
                editor.updateDownloadProgress(progress)
            }
            // Bail if the user backed out during the download.
            guard editor.isPreparing else { return }
            guard let data else {
                editor.failLoading()
                loadFailed = true
                return
            }
            editor.load(data: data)
            editor.sourceAsset = asset.asset // enables overwrite / delete-original
        }
    }

    /// A photo from the system picker — the no-library-access path. The
    /// picker hands over only what was picked, so there is no asset to
    /// overwrite or delete afterwards.
    private func loadPickerItem(_ item: PhotosPickerItem) {
        prepareEditor()
        editor.beginLoading()
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            guard editor.isPreparing else { return }
            guard let data else {
                editor.failLoading()
                loadFailed = true
                return
            }
            editor.load(data: data)
        }
    }

    private func loadSample() {
        guard let data = SampleImage.makeData() else { return }
        prepareEditor()
        editor.load(data: data)
    }

    private func loadData(_ data: Data) {
        prepareEditor()
        editor.load(data: data)
    }

    /// PRD §7.7: images handed off by the Share Extension via the App Group inbox.
    private func pickUpSharedImage() {
        guard !editor.isActive, let data = SharedInbox.takeLatest() else { return }
        prepareEditor()
        editor.load(data: data)
    }

    /// Settings "自动编辑最新的图片": open the newest photo if it's < 60s old.
    private func maybeAutoEdit() {
        guard settings.autoEditLatest, library.isAuthorized, !editor.isActive else { return }
        guard let newest = library.newestImage(),
              let created = newest.creationDate,
              Date().timeIntervalSince(created) < 60 else { return }
        loadFromAsset(PHAssetWrapper(asset: newest))
    }
}

import Photos

/// Identifiable wrapper so PHAsset can drive SwiftUI lists/callbacks.
struct PHAssetWrapper: Identifiable, Hashable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

#Preview {
    ContentView()
}
