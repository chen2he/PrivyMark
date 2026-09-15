//
//  DuoLayout.swift
//  PrivyMark
//
//  Adaptive-layout helpers for iPhone Duo ("Designing for iPhone Duo", HIG,
//  September 2026). Two displays, a hinge and Split View multitasking mean the
//  app can be handed almost any size, so nothing here asks which device it is
//  running on — only how much room it was given. Every new API is gated so the
//  app still builds and behaves on the iOS 17.6 floor.
//

import SwiftUI

// MARK: - Tool palette placement

/// Which edge of the editor the tool palette occupies.
///
/// The Duo outer display is wider and shorter than any other iPhone screen, and
/// so is every landscape pose. A bottom capsule there spends the axis the layout
/// has least of, which is exactly why the system moves toolbars and tab bars to
/// the side on Duo. The palette follows suit and becomes a vertical rail.
enum PalettePlacement {
    /// The familiar capsule under the photo.
    case bottom
    /// A vertical rail beside the photo, matching the system's side bars.
    case rail

    /// Portrait aspect ratio above which a layout counts as "square and short".
    ///
    /// Every shipping iPhone is 0.57 or narrower in portrait (iPhone 8 is the
    /// squarest at 375/667 ≈ 0.56); the Duo outer display is squarer than that
    /// because it is wider and shorter. Deriving the rail from the shape of the
    /// space rather than from a device keeps this working across Duo's poses,
    /// where the size changes but the size class does not.
    private static let squarePortraitRatio: CGFloat = 0.68

    /// - Parameters:
    ///   - size: the space actually available to the editor's content.
    ///   - horizontalSizeClass: used only to keep iPad's squarer portrait out of
    ///     the rail case — the inner display and iPad are regular width and have
    ///     the height to spare.
    static func forContent(of size: CGSize,
                           horizontalSizeClass: UserInterfaceSizeClass?) -> PalettePlacement {
        guard size.width > 0, size.height > 0 else { return .bottom }
        // Wider than tall: every landscape pose, on either display.
        if size.width > size.height { return .rail }
        // Squarer than any iPhone portrait, in a compact width: the outer display.
        if horizontalSizeClass == .compact,
           size.width / size.height > Self.squarePortraitRatio { return .rail }
        return .bottom
    }
}

extension View {
    /// Hosts the editor's tool palette in the safe area — a bottom bar in tall
    /// layouts, a trailing rail in wide-and-short ones — so the canvas resizes
    /// around it instead of being held clear by a hard-coded padding.
    ///
    /// Uses `safeAreaBar` on iOS 26+, which lays the bar out as chrome the way
    /// the system's own bars are laid out, and falls back to `safeAreaInset`.
    @ViewBuilder
    func paletteBar<Bar: View>(_ placement: PalettePlacement,
                               @ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            switch placement {
            case .rail:
                safeAreaBar(edge: HorizontalEdge.trailing) { content() }
            case .bottom:
                safeAreaBar(edge: VerticalEdge.bottom) { content() }
            }
        } else {
            switch placement {
            case .rail:
                safeAreaInset(edge: HorizontalEdge.trailing) { content() }
            case .bottom:
                safeAreaInset(edge: VerticalEdge.bottom) { content() }
            }
        }
    }

    /// A transient bar along the bottom edge, used for the editor's hint and
    /// hidden-watermark banners so they stay horizontal even when the palette
    /// has become a rail.
    @ViewBuilder
    func hintBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: VerticalEdge.bottom, spacing: 0) { content() }
        } else {
            safeAreaInset(edge: VerticalEdge.bottom, spacing: 0) { content() }
        }
    }
}

extension View {
    /// Reports this view's own size, so layout can key off the space actually
    /// available instead of the device it happens to be running on. On Duo the
    /// size changes as the device folds without the size class changing at all.
    @ViewBuilder
    func measureContent(into size: Binding<CGSize>) -> some View {
        if #available(iOS 18.0, *) {
            onGeometryChange(for: CGSize.self) { $0.size } action: { size.wrappedValue = $0 }
        } else {
            background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { size.wrappedValue = proxy.size }
                        .onChange(of: proxy.size) { _, new in size.wrappedValue = new }
                }
            }
        }
    }
}

extension View {
    /// Caps a single column of text and controls at a comfortable measure and
    /// centres it in whatever width it was given.
    ///
    /// Wide-and-short layouts — every landscape pose, the outer display, the
    /// inner display, iPad — otherwise stretch one column of copy and full-bleed
    /// buttons from edge to edge.
    func readableColumn(maxWidth: CGFloat = 560, alignment: Alignment = .center) -> some View {
        frame(maxWidth: maxWidth, alignment: alignment)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Toolbar overflow order

/// How readily a toolbar item may overflow once the bar runs out of room.
///
/// On Duo the bar is vertical and fits far fewer items, and items overflow from
/// the bottom up by default — which would push the primary action out first.
/// These priorities say what to keep instead.
enum ToolbarPriority {
    /// First to move into the overflow menu.
    case low
    /// Default order.
    case standard
    /// Kept in the bar longest: primary actions and anything carrying status.
    case high
}

extension ToolbarContent {
    /// Applies `visibilityPriority` where the OS has it (iOS 27+); a no-op
    /// before, where bars are horizontal and overflow far less often.
    ///
    /// The `compiler` check is an SDK check, not a language one: Swift 6.4 is
    /// the first toolchain (Xcode 27) whose SDK declares
    /// `ToolbarItemVisibilityPriority` at all, and Xcode Cloud still builds this
    /// app with the previous release. Drop the `#if` once every builder is on
    /// Xcode 27 — the `#available` check is the one that matters at runtime.
    @ToolbarContentBuilder
    func overflowPriority(_ priority: ToolbarPriority) -> some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            visibilityPriority(priority.resolvedPriority)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if compiler(>=6.4)
@available(iOS 27.0, *)
extension ToolbarPriority {
    var resolvedPriority: ToolbarItemVisibilityPriority {
        switch self {
        case .low: return .low
        case .standard: return .automatic
        case .high: return .high
        }
    }
}
#endif

// MARK: - Grids

extension Optional where Wrapped == UserInterfaceSizeClass {
    /// Column count for a thumbnail grid.
    ///
    /// Always even: on the inner display a partially folded device splits the
    /// grid down the middle, and an even count divides cleanly on either side of
    /// the fold instead of leaving a column straddling it.
    var evenGridColumns: Int {
        self == .regular ? 6 : 4
    }
}
