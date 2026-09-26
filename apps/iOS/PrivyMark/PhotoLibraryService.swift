//
//  PhotoLibraryService.swift
//  PrivyMark
//
//  Photo library access for the grid home (PRD §7.1). Supports Limited
//  access — with Limited, only the user-selected photos are fetched.
//  Nothing leaves the device.
//

import Foundation
import Photos
import PhotosUI
import UIKit
import Combine

/// Which photos the grid home shows.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    /// Screenshots — the thing people most often need to redact.
    case screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All Photos")
        case .screenshots: return String(localized: "Screenshots")
        }
    }
}

@MainActor
final class PhotoLibraryService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var assets: [PHAsset] = []
    @Published var isLoading = false
    /// The grid's filter. Changing it refetches.
    @Published var filter: LibraryFilter = .all {
        didSet { if filter != oldValue { fetchAssets() } }
    }

    private let imageManager = PHCachingImageManager()
    private var isObservingChanges = false
    private var refetchTask: Task<Void, Never>?

    /// Keeps the grid current while the app is open — a screenshot taken a
    /// moment ago is there when you switch back.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.scheduleRefetch() }
    }

    /// Changes arrive in bursts (an iCloud sync can send dozens); refetch once
    /// the burst settles rather than re-enumerating the library for each one.
    private func scheduleRefetch() {
        refetchTask?.cancel()
        refetchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            fetchAssets()
        }
    }

    var isAuthorized: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }

    func requestAccess() async {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = newStatus
        if isAuthorized { fetchAssets() }
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if isAuthorized && assets.isEmpty { fetchAssets() }
    }

    func fetchAssets() {
        guard isAuthorized else { return }
        isLoading = true
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch filter {
        case .all:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .screenshots:
            options.predicate = NSPredicate(
                format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
                PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoScreenshot.rawValue)
        }
        if !isObservingChanges {
            PHPhotoLibrary.shared().register(self)
            isObservingChanges = true
        }
        let result = PHAsset.fetchAssets(with: options)
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
        isLoading = false
    }

    /// The newest image in the library, whatever the grid is filtered to —
    /// for Settings' "Auto-edit newest photo".
    func newestImage() -> PHAsset? {
        guard isAuthorized else { return nil }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: options).firstObject
    }

    /// Presents the system "select more photos" UI in Limited mode.
    func presentLimitedPicker(from viewController: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }

    // MARK: Thumbnails

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            // Allow iCloud so cloud-only photos show a real thumbnail, not a
            // gray box (opportunistic still returns the local low-res first).
            options.isNetworkAccessAllowed = true
            var resumed = false
            imageManager.requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
            ) { image, info in
                guard !resumed else { return }
                // opportunistic can call back twice (degraded then full). Resume on
                // the full image, or on error/cancel so the continuation never leaks.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let failed = info?[PHImageErrorKey] != nil
                    || (info?[PHImageCancelledKey] as? Bool) ?? false
                if !isDegraded || failed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// Full-resolution image data for the editor. Allows iCloud download of the
    /// user's own photo (fetched by Apple to their device — nothing is uploaded
    /// to us) and reports download progress so the UI can show it.
    func requestImageData(for asset: PHAsset,
                          onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in onProgress(progress) }
            }
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
