//
//  SettingsView.swift
//  PrivyMark
//
//  Settings (PRD §10.4): the promise, defaults, support, and the links that
//  live on the website.
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @StateObject private var tips = TipStore()
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Defaults") {
                    Picker(selection: toolBinding) {
                        ForEach(RedactionStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    } label: {
                        rowLabel("Default tool", systemImage: "rectangle.fill", color: .green)
                    }
                    Toggle(isOn: $settings.autoEditLatest) {
                        rowLabel("Auto-edit newest photo", systemImage: "bolt.fill", color: .blue,
                                 detail: "Opens a photo taken in the last minute automatically.")
                    }
                    Toggle(isOn: $settings.aiDetectionEnabled) {
                        rowLabel("AI-enhanced detection", systemImage: "sparkles", color: .purple,
                                 detail: "Uses on-device intelligence to catch names and other sensitive text. Runs 100% on your device — nothing is uploaded. Needs a supported device.")
                    }
                }
                .listRowBackground(Theme.card)

                Section("Support Us") {
                    // Only shown once StoreKit actually returns the product —
                    // no store, no row (rather than a dead or erroring button).
                    if let product = tips.product {
                        tipRow(product)
                    }
                    ShareLink(item: Links.appStore) {
                        rowLabel("Share PrivyMark", systemImage: "square.and.arrow.up", color: .blue)
                    }
                    Button {
                        requestReview()
                    } label: {
                        rowLabel("Rate Us", systemImage: "star.fill", color: .yellow)
                    }
                    Link(destination: Links.feedback) {
                        rowLabel("Send Feedback", systemImage: "envelope.fill", color: .green)
                    }
                }
                .listRowBackground(Theme.card)

                Section("More") {
                    Button {
                        showHelp = true
                    } label: {
                        rowLabel("How to Use", systemImage: "questionmark", color: .indigo)
                    }
                    Button(action: replayWelcome) {
                        rowLabel("Show Welcome Again", systemImage: "sparkles.rectangle.stack",
                                 color: .teal)
                    }
                    Link(destination: Links.web("support")) {
                        rowLabel("Documentation", systemImage: "book.fill", color: .orange,
                                 external: true)
                    }
                    Link(destination: Links.web("privacy")) {
                        rowLabel("Privacy Policy", systemImage: "hand.raised.fill", color: .gray,
                                 external: true)
                    }
                    Link(destination: Links.web("terms")) {
                        rowLabel("Terms of Use", systemImage: "doc.plaintext.fill", color: .gray,
                                 external: true)
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    footer
                        .listRowBackground(Color.clear)
                }
            }
            .paperBackground()
            .tint(Theme.brand)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await tips.load() }
            .onChange(of: tips.state) { _, state in
                if state == .thanks { settings.hasTipped = true }
            }
            .sheet(isPresented: showsThanks) { TipThanksSheet() }
            .sheet(isPresented: $showHelp) { HelpSheet() }
            .alert("Buy Me a Coffee", isPresented: showsAlert) {
                Button("OK") { tips.state = .idle }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    // MARK: Header & footer

    /// Reassurance, not an upsell — the app is fully free.
    private var header: some View {
        HStack(spacing: 16) {
            AppMark(size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "PrivyMark")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("Free, forever. Every scan runs on your device — nothing is ever uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(cornerRadius: 22)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(verbatim: "PrivyMark \(Self.version)")
                .font(.footnote.weight(.semibold))
            Text("Made for the moment before you hit send.")
                .font(.footnote)
        }
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    // MARK: Rows

    private func rowLabel(_ title: LocalizedStringKey, systemImage: String, color: Color,
                          detail: LocalizedStringKey? = nil, external: Bool = false) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: systemImage, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if external {
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func replayWelcome() {
        dismiss()
        // After the sheet is gone: the router swaps the home for onboarding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            settings.hasSeenWelcome = false
        }
    }

    // MARK: Tip jar

    /// Wording is the only thing a tip changes — the app unlocks nothing.
    private var tipTitle: LocalizedStringKey {
        settings.hasTipped ? "Buy Me Another Coffee" : "Buy Me a Coffee"
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await tips.purchase() }
        } label: {
            HStack {
                rowLabel(tipTitle, systemImage: "cup.and.saucer.fill", color: .brown)
                Spacer()
                if tips.state == .purchasing {
                    ProgressView()
                } else {
                    // Always StoreKit's localized price — never a hardcoded one.
                    Text(product.displayPrice).foregroundStyle(Theme.inkSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(tips.state == .purchasing)
    }

    private var showsThanks: Binding<Bool> {
        Binding(get: { tips.state == .thanks },
                set: { if !$0 { tips.state = .idle } })
    }

    /// Cancelling is not an error, so `.userCancelled` never reaches here.
    private var alertMessage: String? {
        switch tips.state {
        case .failed(let message):
            return message
        case .pending:
            return String(localized: "Thanks! This one needs approval before it goes through.")
        default:
            return nil
        }
    }

    private var showsAlert: Binding<Bool> {
        Binding(get: { alertMessage != nil },
                set: { if !$0 { tips.state = .idle } })
    }

    private var toolBinding: Binding<RedactionStyle> {
        Binding(get: { settings.defaultTool }, set: { settings.defaultTool = $0 })
    }
}

// MARK: - Links

enum Links {
    static let appStore = URL(string: "https://apps.apple.com/app/id6782443539")!
    static let feedback = URL(string: "mailto:support@zhe.ltd")!

    /// A page on privymark.o-c.do in the language the app is running in.
    /// English is the site's unprefixed default; the others carry a prefix
    /// (next-intl, `localePrefix: "as-needed"`).
    static func web(_ page: String) -> URL {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let prefix: String
        switch language {
        case "zh-Hans": prefix = "/zh-Hans"
        case "zh-Hant": prefix = "/zh-Hant"
        case "es": prefix = "/es-ES"
        case "pt": prefix = "/pt-BR"
        case "fr", "de", "it": prefix = "/\(language)"
        default: prefix = ""
        }
        return URL(string: "https://privymark.o-c.do\(prefix)/\(page)")!
    }
}

/// Thank-you after a tip. Deliberately grants nothing — it just says thanks.
struct TipThanksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(verbatim: "☕️").font(.system(size: 64))
                Text("Thank you!")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("PrivyMark stays free and on-device for everyone. Your coffee keeps it that way.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Buy Me a Coffee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SettingsView(settings: SettingsStore())
}
