//
//  ImageMetadataStore.swift
//  PrivyMark
//
//  PRD §7.6: read what metadata a file actually contains, let the user
//  toggle categories, and write only the kept categories on export.
//  GPS is removed by default. ImageIO only; platform-neutral.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MetadataCategory: String, CaseIterable, Identifiable, Sendable {
    case location
    case captureInfo
    case deviceInfo
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .location: return "Location (GPS)"
        case .captureInfo: return "Capture Info"
        case .deviceInfo: return "Device Info"
        case .other: return "Other Metadata"
        }
    }

    var detail: String {
        switch self {
        case .location: return "Where the photo was taken"
        case .captureInfo: return "Date, exposure, lens settings"
        case .deviceInfo: return "Camera make, model, software"
        case .other: return "IPTC, color profile notes, etc."
        }
    }

    /// PRD §7.6: GPS stripped by default, the rest kept by default.
    var keptByDefault: Bool { self != .location }

    fileprivate var propertyKeys: [CFString] {
        switch self {
        case .location: return [kCGImagePropertyGPSDictionary]
        case .captureInfo: return [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary]
        case .deviceInfo: return [kCGImagePropertyTIFFDictionary, kCGImagePropertyMakerAppleDictionary]
        case .other: return [kCGImagePropertyIPTCDictionary, kCGImagePropertyPNGDictionary,
                             kCGImagePropertyHEICSDictionary]
        }
    }
}

// Property dictionaries are plists from ImageIO and only read after creation.
nonisolated struct ImageMetadata: @unchecked Sendable {
    /// Categories actually present in the file, with a short value summary.
    var present: [MetadataCategory: String] = [:]
    /// Full property dictionary from CGImageSource (not Sendable-checked; read-only).
    fileprivate var properties: [CFString: Any] = [:]
    /// Source format.
    var sourceUTType: UTType = .jpeg

    var isEmpty: Bool { present.isEmpty }

    // MARK: Read

    static func read(from data: Data) -> ImageMetadata {
        var meta = ImageMetadata()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return meta }

        if let typeID = CGImageSourceGetType(source),
           let ut = UTType(typeID as String) {
            meta.sourceUTType = ut
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return meta }
        meta.properties = props

        for category in MetadataCategory.allCases {
            let dicts = category.propertyKeys.compactMap { props[$0] as? [CFString: Any] }
            guard dicts.contains(where: { !$0.isEmpty }) else { continue }
            meta.present[category] = summary(for: category, in: props)
        }
        return meta
    }

    private static func summary(for category: MetadataCategory, in props: [CFString: Any]) -> String {
        switch category {
        case .location:
            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               let lat = gps[kCGImagePropertyGPSLatitude], let lon = gps[kCGImagePropertyGPSLongitude] {
                return "Coordinates \(lat), \(lon)"
            }
            return "GPS data present"
        case .captureInfo:
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                return "Taken \(date)"
            }
            return "EXIF data present"
        case .deviceInfo:
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                let make = tiff[kCGImagePropertyTIFFMake] as? String
                let model = tiff[kCGImagePropertyTIFFModel] as? String
                let name = [make, model].compactMap(\.self).joined(separator: " ")
                if !name.isEmpty { return name }
            }
            return "Device data present"
        case .other:
            return "Additional metadata present"
        }
    }

    // MARK: Write

    /// Builds the export property dictionary containing only kept categories.
    func exportProperties(keeping kept: Set<MetadataCategory>) -> [CFString: Any] {
        var out: [CFString: Any] = [:]
        for category in MetadataCategory.allCases where kept.contains(category) {
            for key in category.propertyKeys {
                if let dict = properties[key] { out[key] = dict }
            }
        }
        // Pixels are exported upright; never carry a rotation flag.
        out[kCGImagePropertyOrientation] = 1
        if var tiff = out[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        return out
    }

    /// Export format: PNG stays PNG, everything else (incl. HEIC) becomes JPEG.
    var exportUTType: UTType { sourceUTType == .png ? .png : .jpeg }
    var exportFileExtension: String { exportUTType == .png ? "png" : "jpg" }

    /// Encodes the flattened image with only the kept metadata categories.
    /// `compress` forces a smaller JPEG (DAMA-style "压缩相似颜色").
    func encode(image: CGImage, keeping kept: Set<MetadataCategory>, compress: Bool = false) -> Data? {
        let data = NSMutableData()
        let outType: UTType = compress ? .jpeg : exportUTType
        guard let dest = CGImageDestinationCreateWithData(
            data, outType.identifier as CFString, 1, nil) else { return nil }

        var props = exportProperties(keeping: kept)
        if outType == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = compress ? 0.6 : 0.9
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
