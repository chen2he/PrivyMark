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

@MainActor
final class PhotoLibraryService: ObservableObject {
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var assets: [PHAsset] = []
    @Published var isLoading = false

    private let imageManager = PHCachingImageManager()

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
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
        isLoading = false
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
