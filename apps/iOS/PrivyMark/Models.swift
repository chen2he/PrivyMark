//
//  Models.swift
//  PrivyMark
//
//  Core data model per PRD §9.3.
//

import Foundation
import CoreGraphics

nonisolated enum RiskType: String, CaseIterable, Codable, Sendable {
    case face
    case code
    case email
    case phone
    case address
    case url
    case payment
    case name
    case idNumber
    case orderNumber
    case licensePlateCandidate
    case otherText

    var displayName: String {
        switch self {
        case .face: return "Face"
        case .code: return "QR / Barcode"
        case .email: return "Email"
        case .phone: return "Phone"
        case .address: return "Address"
        case .url: return "Link"
        case .payment: return "Card Number"
        case .name: return "Name"
        case .idNumber: return "ID Number"
        case .orderNumber: return "Order / Tracking"
        case .licensePlateCandidate: return "License Plate"
        case .otherText: return "Manual Area"
        }
    }

    var symbolName: String {
        switch self {
        case .face: return "face.smiling"
        case .code: return "qrcode"
        case .email: return "envelope"
        case .phone: return "phone"
        case .address: return "mappin.and.ellipse"
        case .url: return "link"
        case .payment: return "creditcard"
        case .name: return "person.text.rectangle"
        case .idNumber: return "person.badge.key"
        case .orderNumber: return "shippingbox"
        case .licensePlateCandidate: return "car"
        case .otherText: return "rectangle.dashed"
        }
    }

    /// Default risk level for regions of this type (PRD §9.2 第三层 may upgrade).
    var defaultRiskLevel: RiskLevel {
        switch self {
        case .face, .code, .email, .phone, .payment, .idNumber: return .high
        case .address, .orderNumber, .url, .name: return .medium
        case .licensePlateCandidate: return .low
        case .otherText: return .medium
        }
    }
}

nonisolated enum RiskLevel: Int, Comparable, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Maybe" // PRD §8.3: low confidence shown as "Maybe"
        }
    }
}

nonisolated enum RegionOrigin: String, Codable, Sendable {
    case automatic
    case manual
}

/// Redaction styles per PRD §7.4. Block is the irreversible default.
nonisolated enum RedactionStyle: String, CaseIterable, Codable, Sendable {
    case block
    case pixelate
    case blur
    case hideText

    var displayName: String {
        switch self {
        case .block: return "Block"
        case .pixelate: return "Pixelate"
        case .blur: return "Blur"
        case .hideText: return "Hide Text"
        }
    }

    var symbolName: String {
        switch self {
        case .block: return "rectangle.fill"
        case .pixelate: return "squareshape.split.3x3"
        case .blur: return "drop.halffull"
        case .hideText: return "character.textbox"
        }
    }

    /// Pixelate/blur on text can be reversed; block and hideText are opaque.
    var isReversibleOnText: Bool { self == .pixelate || self == .blur }
}

/// An RGBA color decoupled from UIKit/SwiftUI so model + renderer stay
/// platform-neutral. Components are 0...1.
nonisolated struct RGBAColor: Equatable, Codable, Sendable {
    var r: Double, g: Double, b: Double, a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    static let black = RGBAColor(r: 0, g: 0, b: 0)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let red = RGBAColor(r: 0.90, g: 0.16, b: 0.22)
    static let brandGreen = RGBAColor(r: 0.23, g: 0.78, b: 0.43)
}

/// A freehand marker stroke. Points and width are normalized to the image
/// (top-left origin, width as a fraction of image width).
nonisolated struct Stroke: Identifiable, Equatable, Sendable {
    let id: UUID
    var points: [CGPoint]
    var width: CGFloat
    var color: RGBAColor

    init(id: UUID = UUID(), points: [CGPoint], width: CGFloat, color: RGBAColor = .black) {
        self.id = id
        self.points = points
        self.width = width
        self.color = color
    }
}

/// One OCR word with its normalized (top-left) box — used for long-press
/// single-word redaction (PRD §7.5).
nonisolated struct TextWord: Equatable, Sendable {
    let boundingBox: CGRect
    let text: String
}

/// One OCR line (Vision observation): its union box, full string, and the
/// per-word boxes it contains. Powers the "Text Explode" (文字大爆炸) picker —
/// long-press a line to fan its words out as tappable chips (PRD §7.5).
nonisolated struct TextLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let boundingBox: CGRect
    let text: String
    let words: [TextWord]

    init(id: UUID = UUID(), boundingBox: CGRect, text: String, words: [TextWord]) {
        self.id = id
        self.boundingBox = boundingBox
        self.text = text
        self.words = words
    }
}

/// A suggested or manual redaction region.
/// `boundingBox` is normalized to the image with a TOP-LEFT origin
/// (Vision's bottom-left boxes are converted at scan time).
/// Regions with a non-nil `emoji` (faces) are covered by that emoji instead
/// of the fill style; their box can be dragged to fine-tune placement.
nonisolated struct RiskRegion: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: RiskType
    var boundingBox: CGRect
    let confidence: Float
    let detectedText: String?
    let riskLevel: RiskLevel
    var isSelected: Bool
    var origin: RegionOrigin
    var emoji: String?

    init(
        id: UUID = UUID(),
        type: RiskType,
        boundingBox: CGRect,
        confidence: Float,
        detectedText: String? = nil,
        riskLevel: RiskLevel,
        isSelected: Bool? = nil,
        origin: RegionOrigin = .automatic,
        emoji: String? = nil
    ) {
        self.id = id
        self.type = type
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.detectedText = detectedText
        self.riskLevel = riskLevel
        // PRD §8.3: low-confidence results are shown as "Maybe" and not pre-selected.
        self.isSelected = isSelected ?? (riskLevel > .low)
        self.origin = origin
        self.emoji = emoji
    }
}

/// An emoji cover baked into the export (faces). Rect is normalized, top-left.
nonisolated struct EmojiStamp: Equatable, Sendable {
    let rect: CGRect
    let emoji: String
}

/// Result of the best-effort hidden-watermark / steganography scan (PRD §7.8).
/// `.possible` means an LSB-embedding signature was found — NOT a guarantee, and
/// robust forensic watermarks are undetectable, so the UI stays honest about it.
nonisolated struct StegoFinding: Equatable, Sendable {
    enum Level: Equatable, Sendable { case clean, possible }
    let level: Level
    let reasons: [String]
    var isSuspicious: Bool { level == .possible }
    static let clean = StegoFinding(level: .clean, reasons: [])
}
