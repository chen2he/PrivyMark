//
//  SteganographyAnalyzer.swift
//  PrivyMark
//
//  Best-effort hidden-watermark / steganography handling (PRD §7.8). 100%
//  on-device, no UIKit (compiled by the macOS harness too).
//
//  HONESTY MATTERS HERE. Reliable *general* detection of hidden watermarks is
//  impossible: robust forensic marks (DCT / spread-spectrum, the kind used to
//  trace leaked screenshots) are designed to be undetectable and to survive
//  processing. This analyzer only flags the common LSB-embedding case
//  (data / marks hidden in pixel low-bits), which is well-suited to the flat
//  regions of screenshots. `scrub` removes that removable class (pixel LSBs);
//  the caller also strips ALL metadata. Robust watermarks are NOT removed.
//

import Foundation
import CoreGraphics

nonisolated enum SteganographyAnalyzer {

    /// A flat-region LSB match rate below this reads as "low bits look random"
    /// → likely LSB embedding. Clean flat regions match ~100%.
    private static let matchRateThreshold = 0.88

    /// Best-effort scan. Flags an LSB-embedding signature; never a guarantee.
    static func analyze(_ image: CGImage) -> StegoFinding {
        guard let rate = worstFlatLSBMatchRate(image), rate < matchRateThreshold else {
            return .clean
        }
        return StegoFinding(level: .possible, reasons: [
            "Flat areas have noisy low bits — a signature of data or an invisible "
            + "watermark hidden in the pixels (LSB steganography)."
        ])
    }

    /// Removes fragile pixel-LSB steganography by clearing the least-significant
    /// bit of every colour channel. Visually negligible (≤1/255 per channel).
    /// Robust (DCT / spread-spectrum) watermarks are NOT affected by this.
    static func scrub(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data
        else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        let count = w * h * 4
        var i = 0
        while i < count {
            ptr[i] &= 0xFE       // R
            ptr[i + 1] &= 0xFE   // G
            ptr[i + 2] &= 0xFE   // B  (leave alpha byte i+3 untouched)
            i += 4
        }
        return ctx.makeImage() ?? image
    }

    // MARK: - LSB analysis

    /// Reads the image's ACTUAL stored bytes (via the data provider, so no colour
    /// conversion perturbs the low bits) and, per channel, measures — among
    /// horizontally-adjacent "flat" pairs (equal ignoring the LSB) — how often the
    /// LSBs also match. Clean flat regions match ~100%; LSB-embedded data ~50%.
    /// Returns the worst (lowest) rate across channels that had enough flat pairs,
    /// or nil when the format is unsupported or there isn't enough flat area.
    private static func worstFlatLSBMatchRate(_ image: CGImage) -> Double? {
        let w = image.width, h = image.height
        guard w > 1, h > 0, image.bitsPerComponent == 8 else { return nil }
        let bpp = image.bitsPerPixel / 8
        guard bpp == 3 || bpp == 4 else { return nil }
        guard let data = image.dataProvider?.data,
              let base = CFDataGetBytePtr(data) else { return nil }
        let bpr = image.bytesPerRow
        guard CFDataGetLength(data) >= bpr * h else { return nil }

        // Only the colour channels (never a constant alpha, which would mask the
        // signal). For 4bpp assume alpha is one end byte; scan the other three.
        let channels = bpp == 4 ? [0, 1, 2] : [0, 1, 2]
        var flat = [Int](repeating: 0, count: bpp)
        var match = [Int](repeating: 0, count: bpp)

        for y in 0..<h {
            let row = base + y * bpr
            for x in 1..<w {
                let cur = row + x * bpp
                let left = row + (x - 1) * bpp
                for c in channels {
                    if (cur[c] >> 1) == (left[c] >> 1) {   // same value ignoring LSB
                        flat[c] += 1
                        if (cur[c] & 1) == (left[c] & 1) { match[c] += 1 }
                    }
                }
            }
        }

        let minFlat = max(500, (w * h) / 100)   // need a meaningful flat area to judge
        var worst: Double?
        for c in channels where flat[c] >= minFlat {
            let rate = Double(match[c]) / Double(flat[c])
            worst = min(worst ?? rate, rate)
        }
        return worst
    }
}
