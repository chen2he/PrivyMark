//
//  RedactionRenderer.swift
//  PrivyMark
//
//  Flattens redactions into pixels (PRD §7.4): the output is a plain
//  bitmap — no removable layers. Core Image + Core Graphics; no UIKit, so it
//  stays platform-neutral (compiled by the macOS verification harness too).
//

import Foundation
import CoreGraphics
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

nonisolated enum RedactionRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Renders `image` with every rect in `regions` redacted using `style`,
    /// plus optional marker strokes, emoji covers (faces), a user watermark,
    /// and the free-tier badge.
    /// All geometry is normalized with a top-left origin. Returns a flat CGImage.
    static func render(image: CGImage, regions: [CGRect], style: RedactionStyle,
                       strokes: [Stroke] = [],
                       userWatermark: String? = nil,
                       emojiStamps: [EmojiStamp] = [],
                       blockColor: RGBAColor = .black) -> CGImage {
        let userMark = (userWatermark?.isEmpty == false) ? userWatermark : nil
        let hasOverlay = !strokes.isEmpty || userMark != nil || !emojiStamps.isEmpty
        guard !regions.isEmpty || hasOverlay else { return image }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let base = CIImage(cgImage: image)
        var composite = base

        for normalized in regions {
            // Convert normalized top-left rect to Core Image's bottom-left pixels.
            let pixelRect = CGRect(
                x: (normalized.minX * width).rounded(.down),
                y: ((1 - normalized.maxY) * height).rounded(.down),
                width: (normalized.width * width).rounded(.up),
                height: (normalized.height * height).rounded(.up)
            ).intersection(base.extent)
            guard !pixelRect.isEmpty else { continue }

            let patch: CIImage
            switch style {
            case .block:
                patch = CIImage(color: CIColor(red: blockColor.r, green: blockColor.g,
                                               blue: blockColor.b, alpha: 1)).cropped(to: pixelRect)

            case .pixelate:
                let filter = CIFilter.pixellate()
                filter.inputImage = base.clampedToExtent()
                filter.scale = Float(max(16, min(pixelRect.width, pixelRect.height) / 4))
                filter.center = CGPoint(x: pixelRect.midX, y: pixelRect.midY)
                patch = (filter.outputImage ?? base).cropped(to: pixelRect)

            case .blur:
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = base.clampedToExtent()
                filter.radius = Float(max(14, min(pixelRect.width, pixelRect.height) / 3))
                patch = (filter.outputImage ?? base).cropped(to: pixelRect)

            case .hideText:
                // Fill with the surrounding background color so the text seems
                // to vanish (works best on a solid background — PRD §7.4).
                let bg = backgroundColor(near: pixelRect, in: base)
                patch = CIImage(color: bg).cropped(to: pixelRect)
            }

            composite = patch.composited(over: composite)
        }

        guard var output = context.createCGImage(composite, from: base.extent) else {
            return image
        }
        if hasOverlay {
            output = drawOverlays(on: output, strokes: strokes,
                                  userWatermark: userMark, emojiStamps: emojiStamps) ?? output
        }
        return output
    }

    // MARK: - Hide-text background sampling

    /// Average color of a strip just outside the region (its background).
    private static func backgroundColor(near pixelRect: CGRect, in base: CIImage) -> CIColor {
        let h = max(2, pixelRect.height * 0.5)
        // Prefer the strip visually above the text; fall back to below.
        var sample = CGRect(x: pixelRect.minX, y: pixelRect.maxY, width: pixelRect.width, height: h)
            .intersection(base.extent)
        if sample.height < 2 {
            sample = CGRect(x: pixelRect.minX, y: pixelRect.minY - h,
                            width: pixelRect.width, height: h).intersection(base.extent)
        }
        guard sample.width >= 1, sample.height >= 1 else { return .white }

        let filter = CIFilter.areaAverage()
        filter.inputImage = base
        filter.extent = sample
        guard let out = filter.outputImage else { return .white }
        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &rgba, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return CIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255,
                       blue: CGFloat(rgba[2]) / 255, alpha: 1)
    }

    // MARK: - Overlays (Core Graphics pass)

    private static func drawOverlays(on image: CGImage,
                                     strokes: [Stroke], userWatermark: String?,
                                     emojiStamps: [EmojiStamp] = []) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGSize(width: w, height: h)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        // Emoji covers (faces) — normalized TL rect → CG bottom-left pixels.
        for stamp in emojiStamps {
            let rect = CGRect(x: stamp.rect.minX * size.width,
                              y: (1 - stamp.rect.maxY) * size.height,
                              width: stamp.rect.width * size.width,
                              height: stamp.rect.height * size.height)
            drawEmoji(stamp.emoji, in: rect, context: ctx)
        }

        // Marker strokes (normalized TL points → CG bottom-left).
        for stroke in strokes where stroke.points.count > 0 {
            let lineWidth = max(2, stroke.width * size.width)
            let c = stroke.color
            ctx.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            ctx.setFillColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
            if pts.count == 1 {
                ctx.fillEllipse(in: CGRect(x: pts[0].x - lineWidth / 2, y: pts[0].y - lineWidth / 2,
                                           width: lineWidth, height: lineWidth))
            } else {
                ctx.beginPath()
                ctx.addLines(between: pts)
                ctx.strokePath()
            }
        }

        if let text = userWatermark, !text.isEmpty {
            drawTiledWatermark(text, in: ctx, size: size)
        }
        return ctx.makeImage()
    }

    /// Draws one emoji sized to cover `rect` (CG bottom-left coords), centered.
    /// CoreText + Apple Color Emoji so it bakes into pixels on any platform.
    private static func drawEmoji(_ emoji: String, in rect: CGRect, context ctx: CGContext) {
        guard !emoji.isEmpty, rect.width > 1, rect.height > 1 else { return }
        let fontSize = min(rect.width, rect.height) * 1.1
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateWithName("AppleColorEmoji" as CFString, fontSize, nil),
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: emoji, attributes: attrs))
        let bounds = CTLineGetImageBounds(line, ctx)
        guard bounds.width > 0, bounds.height > 0 else { return }
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Repeating diagonal user watermark (e.g. "Internal use only").
    private static func drawTiledWatermark(_ text: String, in ctx: CGContext, size: CGSize) {
        let fontSize = max(20, size.height * 0.028)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String):
                CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.20),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetImageBounds(line, ctx)
        let stepX = bounds.width + fontSize * 3
        let stepY = fontSize * 4.5

        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: -.pi / 6)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        var y = -size.height
        while y < size.height * 2 {
            var x = -size.width
            while x < size.width * 2 {
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, ctx)
                x += stepX
            }
            y += stepY
        }
        ctx.restoreGState()
    }
}
