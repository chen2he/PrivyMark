//
//  OnboardingView.swift
//  PrivyMark
//
//  First launch: three short pages that SHOW the product rather than
//  describe it, ending on the Photos pre-permission step.
//
//    1. Scan    — a live demo. A scan sweeps a delivery label and finds the
//                 private fields; the person taps "Cover Them" and watches
//                 green covers land. They've used the app before using it.
//    2. Promise — everything stays on the iPhone (Airplane Mode flips on).
//    3. Access  — why PrivyMark asks for Photos, then the system alert.
//
//  App Review 5.1.1(iv) / HIG "Privacy": page 3 precedes the system
//  permission alert, so it has exactly ONE action, and that action says
//  "Continue" — never "Allow"/"OK", which reads as pre-answering the prompt,
//  and no second way out. The alternatives for people who decline (pick a
//  photo without library access, or try the sample) live on the screen they
//  land on afterwards, `PhotoAccessView`.
//

import SwiftUI
import Photos

struct OnboardingView: View {
    @ObservedObject var library: PhotoLibraryService
    /// Onboarding is done; the permission alert has been answered (or wasn't
    /// needed).
    var onFinish: () -> Void

    fileprivate enum Page: Int, CaseIterable, Identifiable {
        case scan, promise, access
        var id: Int { rawValue }
    }

    @State private var page: Page = .scan
    /// The person has tapped "Cover Them" in the page-1 demo.
    @State private var demoCovered = false
    @State private var isRequesting = false
    @State private var size: CGSize = .zero

    /// Every landscape pose, and the Duo outer display: put the illustration
    /// beside the copy instead of above it.
    private var isWide: Bool { size.width > size.height * 1.05 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(Page.allCases) { page in
                    OnboardingPage(page: page, isActive: self.page == page, isWide: isWide,
                                   demoCovered: demoCovered)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            controls
        }
        .background(Theme.paper.ignoresSafeArea())
        .measureContent(into: $size)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: demoCovered)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            AppMark(size: 26)
            Text(verbatim: "PrivyMark")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer()
            if page != .access {
                // Skips the tour, not the permission step.
                Button("Skip") {
                    withAnimation(.snappy) { page = .access }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .transition(.opacity)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 24)
        .readableColumn(maxWidth: isWide ? 820 : 520)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    private var controls: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(spacing: 20))
            : AnyLayout(VStackLayout(spacing: 20))
        return layout {
            PageDots(count: Page.allCases.count, index: page.rawValue)
            Button(action: advance) {
                ZStack {
                    Text(primaryTitle)
                        .contentTransition(.opacity)
                        .opacity(isRequesting ? 0 : 1)
                    if isRequesting { ProgressView().tint(Theme.onBrand) }
                }
            }
            .buttonStyle(.primary)
            .disabled(isRequesting)
            .frame(maxWidth: isWide ? 320 : .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, isWide ? 8 : 20)
        .padding(.bottom, isWide ? 8 : 16)
        .readableColumn(maxWidth: isWide ? 820 : 520)
        .animation(.easeInOut(duration: 0.2), value: primaryTitle)
    }

    private var primaryTitle: String {
        if page == .scan && !demoCovered { return String(localized: "Cover Them") }
        return String(localized: "Continue")
    }

    private func advance() {
        switch page {
        case .scan:
            if !demoCovered {
                demoCovered = true
            } else {
                withAnimation(.snappy) { page = .promise }
            }
        case .promise:
            withAnimation(.snappy) { page = .access }
        case .access:
            guard !library.isAuthorized else { onFinish(); return }
            isRequesting = true
            Task {
                await library.requestAccess()
                isRequesting = false
                onFinish()
            }
        }
    }
}

// MARK: - Page

private struct OnboardingPage: View {
    let page: OnboardingView.Page
    let isActive: Bool
    let isWide: Bool
    let demoCovered: Bool

    /// The headline's highlighter lands a beat after the page settles.
    @State private var isMarked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 28))
        layout {
            illustration
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            copy
                .frame(maxWidth: isWide ? 360 : .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, isWide ? 4 : 12)
        .readableColumn(maxWidth: isWide ? 820 : 520)
        .task(id: isActive) {
            guard isActive, !isMarked else { return }
            if reduceMotion { isMarked = true; return }
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeOut(duration: 0.5)) { isMarked = true }
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page {
        case .scan:
            FitToSpace(ideal: CGSize(width: 330, height: 370)) {
                ScanDemo(isActive: isActive, isCovered: demoCovered)
            }
        case .promise:
            FitToSpace(ideal: CGSize(width: 330, height: 330)) {
                PromiseIllustration(isActive: isActive)
            }
        case .access:
            FitToSpace(ideal: CGSize(width: 330, height: 330)) {
                AccessIllustration(isActive: isActive)
            }
        }
    }

    /// Scrolls only when it must — the Duo outer display and landscape are
    /// short enough to need it at larger text sizes.
    private var copy: some View {
        ViewThatFits(in: .vertical) {
            copyStack
            ScrollView(showsIndicators: false) { copyStack }
        }
    }

    private var copyStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch page {
            case .scan:
                MarkedHeadline(lead: "Find private details", marked: "before you share",
                               isMarked: isMarked)
                body("PrivyMark spots faces, phone numbers, cards, IDs and addresses in a photo — and covers them in one tap.")
            case .promise:
                MarkedHeadline(lead: "Everything stays", marked: "on your iPhone",
                               isMarked: isMarked)
                body("No uploads, no account, no tracking. Switch on Airplane Mode and it works just the same.")
            case .access:
                MarkedHeadline(lead: "Your photos,", marked: "your call",
                               isMarked: isMarked)
                body("PrivyMark only reads the photos you open. Share your whole library or just a few — you can change this anytime in Settings.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func body(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Page dots

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.brand : Theme.inkFaint)
                    .frame(width: i == index ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
    }
}

// MARK: - Fit helper

/// Lays an illustration out at its designed size and scales it DOWN (never
/// up) to whatever space the page has left — so the same drawing works on a
/// tall phone, in landscape, and on the Duo's short outer display.
struct FitToSpace<Content: View>: View {
    let ideal: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / ideal.width, proxy.size.height / ideal.height)
            content
                .frame(width: ideal.width, height: ideal.height)
                .scaleEffect(max(scale, 0.01))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - 1 · Scan demo

/// A delivery label that gets scanned, then covered when the person taps
/// "Cover Them". Drawn at fixed point sizes: it's a picture, so it stays put
/// while the copy around it follows Dynamic Type.
private struct ScanDemo: View {
    let isActive: Bool
    let isCovered: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the scan started / the covers started landing.
    @State private var scanStart: Date?
    @State private var coverStart: Date?
    /// Both animations have run to the end — the timeline can stop ticking.
    @State private var scanSettled = false
    @State private var coverSettled = false

    // Timeline, in seconds from each start.
    private let sweepDelay = 0.35, sweepLength = 1.5
    private let coverStagger = 0.09, coverLength = 0.26, doneDelay = 0.75

    /// Sensitive items, top to bottom: face, name, QR, phone, address, tracking.
    private let itemCount = 6

    var body: some View {
        Group {
            if reduceMotion {
                // No sweep and no staggering: things simply fade in.
                frame(now: .distantFuture)
                    .animation(.easeInOut(duration: 0.35), value: scanStart)
                    .animation(.easeInOut(duration: 0.35), value: coverStart)
            } else {
                TimelineView(.animation(paused: isPaused)) { context in
                    frame(now: context.date)
                }
            }
        }
        .task(id: isActive) {
            guard isActive, scanStart == nil else { return }
            scanStart = .now
            try? await Task.sleep(for: .seconds(sweepDelay + sweepLength + 0.3))
            scanSettled = true
        }
        .task(id: isCovered) {
            guard isCovered, coverStart == nil else { return }
            coverStart = .now
            try? await Task.sleep(for: .seconds(doneDelay + 0.6))
            coverSettled = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCovered
            ? "A delivery label with the name, face, phone number, address, tracking number and QR code covered in green."
            : "A delivery label being scanned. The name, face, phone number, address, tracking number and QR code are found.")
    }

    private var isPaused: Bool {
        !isActive || (scanSettled && (!isCovered || coverSettled))
    }

    private func frame(now: Date) -> some View {
        let scanT = scanStart.map { now.timeIntervalSince($0) } ?? -1
        let coverT = coverStart.map { now.timeIntervalSince($0) } ?? -1
        let sweep = progress(scanT, from: sweepDelay, to: sweepDelay + sweepLength)
        let scanning = scanT > sweepDelay && scanT < sweepDelay + sweepLength + 0.15

        func detected(_ i: Int) -> Double {
            // Each item lights up as the beam passes its rough height; a tap
            // on "Cover Them" mid-sweep finds everything at once.
            if coverT >= 0 { return 1 }
            let at = sweepDelay + sweepLength * itemY(i)
            return progress(scanT, from: at, to: at + 0.2)
        }
        func covered(_ i: Int) -> Double {
            let from = Double(i) * coverStagger
            return easeOut(progress(coverT, from: from, to: from + coverLength))
        }
        let found = progress(scanT, from: sweepDelay + sweepLength, to: sweepDelay + sweepLength + 0.3)
        let done = progress(coverT, from: doneDelay - 0.2, to: doneDelay + 0.25)

        return VStack(spacing: 18) {
            label(detected: detected, covered: covered)
                .overlay { beam(sweep: sweep).opacity(scanning ? 1 : 0) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .paperCard()
                .rotationEffect(.degrees(-1.5))

            resultPill(found: max(found, coverT >= 0 ? 1 : 0), done: done)
        }
        .padding(.horizontal, 6)
    }

    /// Rough vertical position (0…1) of each sensitive item on the label.
    private func itemY(_ i: Int) -> Double {
        [0.22, 0.24, 0.26, 0.52, 0.65, 0.78][i]
    }

    // MARK: Label

    private func label(detected: (Int) -> Double, covered: (Int) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                Text("Express Delivery")
                Spacer()
                Text(verbatim: "1/1")
                    .foregroundStyle(Theme.inkSecondary)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.brand)
            .padding(.bottom, 14)

            HStack(alignment: .center, spacing: 12) {
                avatar(detected: detected(0), covered: covered(0))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recipient")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                    field("Alex Morgan", size: 17, weight: .semibold,
                          detected: detected(1), covered: covered(1))
                }
                Spacer(minLength: 8)
                qr(detected: detected(2), covered: covered(2))
            }

            DashedDivider()
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 14) {
                row("Phone", value: "+1 415 555 0134", detected: detected(3), covered: covered(3))
                row("Address", value: "42 Willow Ave, Riverton", detected: detected(4), covered: covered(4))
                row("Tracking", value: "SF 1234 5678 90", detected: detected(5), covered: covered(5))
                // Not private — stays uncovered, to show the scan is selective.
                row("Weight", value: "1.2 kg", detected: 0, covered: 0)
            }
        }
        .padding(20)
        .frame(width: 318)
        .background(Theme.card)
    }

    private func row(_ title: LocalizedStringKey, value: LocalizedStringKey,
                     detected: Double, covered: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 78, alignment: .leading)
            field(value, size: 14, weight: .medium, detected: detected, covered: covered)
            Spacer(minLength: 0)
        }
    }

    private func field(_ text: LocalizedStringKey, size: CGFloat, weight: Font.Weight,
                       detected: Double, covered: Double) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.brand)
                    .padding(.horizontal, -3)
                    .padding(.vertical, -1)
                    .scaleEffect(x: max(covered, 0.001), anchor: .leading)
                    .opacity(covered > 0 ? 1 : 0)
            }
            .overlay { detectionRing(detected * (1 - covered), inset: -5) }
    }

    private func avatar(detected: Double, covered: Double) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xF5C9A8), Color(hex: 0xE9A987)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 46, height: 46)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(hex: 0x8A5A3C).opacity(0.75))
                    .offset(y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                // Faces get an emoji, the way the editor covers them.
                Text(verbatim: "😎")
                    .font(.system(size: 40))
                    .scaleEffect(0.3 + 0.7 * overshoot(covered))
                    .opacity(covered)
            }
            .overlay { detectionRing(detected * (1 - covered), inset: -4) }
    }

    private func qr(detected: Double, covered: Double) -> some View {
        Image(systemName: "qrcode")
            .font(.system(size: 42, weight: .regular))
            .foregroundStyle(Theme.ink)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.brand)
                    .padding(-2)
                    .scaleEffect(max(covered, 0.001))
                    .opacity(covered > 0 ? 1 : 0)
            }
            .overlay { detectionRing(detected * (1 - covered), inset: -5) }
    }

    private func detectionRing(_ amount: Double, inset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.brand.opacity(0.10)))
            .padding(.horizontal, inset)
            .padding(.vertical, inset * 0.6)
            .opacity(amount)
            .scaleEffect(1.1 - 0.1 * amount)
    }

    // MARK: Beam & result

    private func beam(sweep: Double) -> some View {
        GeometryReader { proxy in
            let y = proxy.size.height * sweep
            ZStack(alignment: .top) {
                LinearGradient(colors: [Theme.brand.opacity(0), Theme.brand.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                    .offset(y: y - 70)
                Rectangle()
                    .fill(Theme.brand)
                    .frame(height: 2)
                    .shadow(color: Theme.brand.opacity(0.8), radius: 6)
                    .offset(y: y - 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    /// "6 found" in ink once the scan ends; "6 covered" in green once the
    /// person covers them.
    private func resultPill(found: Double, done: Double) -> some View {
        ZStack {
            pill(Text("\(itemCount) found"), systemImage: "eye.trianglebadge.exclamationmark",
                 foreground: Theme.card, background: Theme.ink)
                .opacity(found * (1 - done))
            pill(Text("\(itemCount) covered"), systemImage: "checkmark.circle.fill",
                 foreground: Theme.onBrand, background: Theme.brand)
                .opacity(done)
                .scaleEffect(0.85 + 0.15 * overshoot(done))
        }
        .scaleEffect(0.7 + 0.3 * found)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func pill(_ text: Text, systemImage: String,
                      foreground: Color, background: Color) -> some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(background))
            .shadow(color: background.opacity(0.3), radius: 10, y: 4)
    }

    // MARK: Easing

    private func progress(_ t: Double, from: Double, to: Double) -> Double {
        guard t >= 0 else { return 0 }
        return min(1, max(0, (t - from) / (to - from)))
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// A light overshoot, for things that pop into place.
    private func overshoot(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

private struct DashedDivider: View {
    var body: some View {
        Line()
            .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(height: 1.5)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

// MARK: - 2 · Promise

private struct PromiseIllustration: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var airplaneOn = false
    @State private var shownRows = 0

    private let rows: [LocalizedStringKey] = [
        "Scanned on this iPhone — never uploaded",
        "No account. No ads. No tracking.",
        "Nothing is kept once you're done",
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                IconTile(systemName: "airplane", color: .orange, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Airplane Mode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(airplaneOn ? "On — still works" : "Off")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                Toggle("", isOn: .constant(airplaneOn))
                    .labelsHidden()
                    .tint(.orange)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .paperCard(cornerRadius: 18)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                    Text("On-device")
                }
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: 0x5FD68E))

                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: 0x5FD68E))
                            .scaleEffect(index < shownRows ? 1 : 0.4)
                        Text(row)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(index < shownRows ? 1 : 0.15)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.vault)
                    .shadow(color: Theme.vault.opacity(0.35), radius: 20, y: 10)
            )
        }
        .frame(width: 318)
        .task(id: isActive) {
            guard isActive else { return }
            if reduceMotion {
                airplaneOn = true
                shownRows = rows.count
                return
            }
            guard shownRows == 0 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { airplaneOn = true }
            for i in rows.indices {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shownRows = i + 1 }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: airplaneOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Airplane Mode on, and PrivyMark still works. Scanned on this iPhone, never uploaded. No account, no ads, no tracking. Nothing is kept once you're done.")
    }
}

// MARK: - 3 · Access

/// A small photo picker: a few tiles, two of them picked. Also used by the
/// Photos-access screen shown after onboarding.
struct AccessIllustration: View {
    let isActive: Bool
    var isDenied = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: Set<Int> = []

    private enum Tile { case photo(Color, Color), screenshot }

    private let tiles: [Tile] = [
        .screenshot,
        .photo(Color(hex: 0xFFB36B), Color(hex: 0xF0607A)),
        .photo(Color(hex: 0x7CC6F2), Color(hex: 0x3B7BD9)),
        .photo(Color(hex: 0xB8E08A), Color(hex: 0x4FA66A)),
        .screenshot,
        .photo(Color(hex: 0xC9A8F5), Color(hex: 0x6F5BD6)),
        .photo(Color(hex: 0xFFD88A), Color(hex: 0xF29B4B)),
        .photo(Color(hex: 0x9FE3D8), Color(hex: 0x3AA59A)),
        .screenshot,
    ]
    private let pickOrder = [4, 0]

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 8), count: 3),
                      spacing: 8) {
                ForEach(tiles.indices, id: \.self) { i in
                    tile(tiles[i], picked: picked.contains(i))
                }
            }
            .padding(14)
            .paperCard(cornerRadius: 26)
            .saturation(isDenied ? 0 : 1)
            .opacity(isDenied ? 0.55 : 1)
            .overlay(alignment: .bottom) {
                badge
                    .offset(y: 18)
            }
        }
        .frame(width: 318, height: 330)
        .task(id: isActive) {
            guard isActive, !isDenied else { return }
            if reduceMotion { picked = Set(pickOrder); return }
            guard picked.isEmpty else { return }
            for i in pickOrder {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { _ = picked.insert(i) }
            }
        }
        .accessibilityHidden(true)
    }

    private var badge: some View {
        Label {
            Text(isDenied ? "Photos access is off" : "Only what you open is read")
        } icon: {
            Image(systemName: isDenied ? "lock.fill" : "lock.shield.fill")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    @ViewBuilder
    private func tile(_ tile: Tile, picked: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            switch tile {
            case let .photo(top, bottom):
                shape.fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
                    .overlay(alignment: .bottomLeading) {
                        // A suggestion of a horizon, so it reads as a photo.
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(8)
                    }
            case .screenshot:
                shape.fill(Theme.paper)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Theme.inkFaint).frame(width: 40, height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Theme.ink.opacity(0.85))
                                .frame(width: 58, height: 8)
                            RoundedRectangle(cornerRadius: 2).fill(Theme.brand)
                                .frame(width: 46, height: 8)
                            Capsule().fill(Theme.inkFaint).frame(width: 52, height: 5)
                            Capsule().fill(Theme.inkFaint).frame(width: 30, height: 5)
                        }
                        .padding(11)
                    }
                    .overlay(shape.strokeBorder(Theme.hairline))
            }
        }
        .frame(width: 88, height: 88)
        .overlay(alignment: .bottomTrailing) {
            if picked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.brand)
                    .background(Circle().fill(.white).padding(2))
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            if picked {
                shape.strokeBorder(Theme.brand, lineWidth: 3)
            }
        }
        .scaleEffect(picked ? 0.94 : 1)
    }
}

#Preview {
    OnboardingView(library: PhotoLibraryService(), onFinish: {})
}
