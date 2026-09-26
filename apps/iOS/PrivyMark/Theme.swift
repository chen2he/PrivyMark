//
//  Theme.swift
//  PrivyMark
//
//  The app's visual language — the same one the website and the App Store art
//  use: warm paper, near-black ink, and one green. Ink bars are the private
//  details a scan finds; green means covered.
//
//  Everything here is plain SwiftUI that runs on the iOS 17.6 floor; newer
//  materials (Liquid Glass) are layered on through `floatingGlass`.
//

import SwiftUI

// MARK: - Colors

enum Theme {
    /// The page: warm off-white by day, deep warm ink by night.
    static let paper = Color(light: 0xF6F4EE, dark: 0x14130F)
    /// Cards, grouped rows and sheets that sit on the paper.
    static let card = Color(light: 0xFFFFFF, dark: 0x201E19)
    /// The editor's backdrop — a shade darker than the paper so a white
    /// screenshot still reads as an object lying on it.
    static let canvas = Color(light: 0xECEAE3, dark: 0x0C0B09)
    /// Type and illustration ink.
    static let ink = Color(light: 0x171511, dark: 0xF3F1EA)
    /// Secondary copy on the paper.
    static let inkSecondary = Color(light: 0x171511, lightAlpha: 0.62,
                                    dark: 0xF3F1EA, darkAlpha: 0.62)
    /// Placeholder text lines and quiet fills in illustrations.
    static let inkFaint = Color(light: 0x171511, lightAlpha: 0.10,
                                dark: 0xF3F1EA, darkAlpha: 0.12)
    /// Hairline borders around cards.
    static let hairline = Color(light: 0x171511, lightAlpha: 0.08,
                                dark: 0xFFFFFF, darkAlpha: 0.09)
    /// The one accent — the asset catalog's AccentColor, so system controls
    /// (toggles, links, pickers) pick it up too.
    static let brand = Color.accentColor
    /// Label color on a brand-filled control: white on the deeper light-mode
    /// green, near-black on the brighter dark-mode green (white there would
    /// fall well short of legible contrast).
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x0B1A10)
    /// The dark "promise" card: a green-black that stays dark in both modes.
    static let vault = Color(light: 0x15302A, dark: 0x173A30)
}

extension Color {
    /// A color that follows the interface style, from 0xRRGGBB literals.
    init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Buttons

/// The full-width capsule every primary call to action uses.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onBrand)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .background(Capsule().fill(Theme.brand))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The quieter capsule that sits under a primary button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .background(Capsule().fill(Theme.inkFaint.opacity(configuration.isPressed ? 1.4 : 0.8)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A small press-to-shrink for tappable cards and thumbnails.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Headline with a marked phrase

/// A two-part headline whose second part carries a green highlighter swipe —
/// the website's "the keyword is what gets covered" motif.
///
/// The swipe can be drawn in (`marked` false → true) so a page can land its
/// headline with a little motion; under Reduce Motion it simply appears.
struct MarkedHeadline: View {
    let lead: LocalizedStringKey
    let marked: LocalizedStringKey
    var isMarked = true
    var alignment: HorizontalAlignment = .leading
    var font: Font = .system(.largeTitle, design: .default, weight: .bold)

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(lead)
            Text(marked)
                .padding(.horizontal, 6)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.brand.opacity(0.32))
                            // Lower ~60% of the line, like a highlighter pass.
                            .frame(height: proxy.size.height * 0.6)
                            .offset(y: proxy.size.height * 0.4)
                            .scaleEffect(x: isMarked ? 1 : 0.001, anchor: .leading)
                    }
                }
                .padding(.horizontal, -6)
        }
        .font(font)
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Surfaces

extension View {
    /// A card on the paper: a raised fill, a hairline and a very soft shadow.
    func paperCard(cornerRadius: CGFloat = 22) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    /// Paints the paper behind a scrolling list or form.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
    }
}

extension View {
    /// Floating chrome along the bottom edge (a switch, a tool palette): laid
    /// out in the safe area so content scrolls clear of it, and — on iOS 26+ —
    /// as a system bar, so the scroll edge effect softens what's beneath it.
    @ViewBuilder
    func bottomBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: VerticalEdge.bottom) { content() }
        } else {
            safeAreaInset(edge: VerticalEdge.bottom) { content() }
        }
    }
}

/// The editor's backdrop: a quiet dot grid, like a cutting mat.
struct DotGrid: View {
    var spacing: CGFloat = 18
    var dot: CGFloat = 1.6

    var body: some View {
        Canvas { context, size in
            let color = Theme.ink.opacity(0.10)
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2,
                                                        width: dot, height: dot)),
                                 with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .accessibilityHidden(true)
    }
}

/// A rounded, filled square carrying an SF Symbol — the leading glyph of a
/// settings or help row, in the style of the system Settings app.
struct IconTile: View {
    let systemName: String
    var color: Color = Theme.brand
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The app mark drawn in SwiftUI — a card with a line of text and two
/// redaction bars, echoing the app icon — for places the icon itself can't go.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        let unit = size / 64
        RoundedRectangle(cornerRadius: 15 * unit, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2BB463), Color(hex: 0x1B8A4C)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 7 * unit, style: .continuous)
                    .fill(.white)
                    .frame(width: 40 * unit, height: 44 * unit)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 5 * unit) {
                            Capsule().fill(Color(hex: 0x171511, alpha: 0.18))
                                .frame(width: 20 * unit, height: 4 * unit)
                            RoundedRectangle(cornerRadius: 2 * unit)
                                .fill(Color(hex: 0x171511))
                                .frame(width: 28 * unit, height: 6 * unit)
                            RoundedRectangle(cornerRadius: 2 * unit)
                                .fill(Color(hex: 0x21A653))
                                .frame(width: 22 * unit, height: 6 * unit)
                            Capsule().fill(Color(hex: 0x171511, alpha: 0.18))
                                .frame(width: 16 * unit, height: 4 * unit)
                        }
                        .padding(6 * unit)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 3 * unit, y: 1.5 * unit)
            }
            .accessibilityHidden(true)
    }
}

extension Color {
    /// A fixed (non-adaptive) color from a 0xRRGGBB literal.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
