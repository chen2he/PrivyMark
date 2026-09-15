//
//  SettingsView.swift
//  PrivyMark
//
//  Settings (PRD §10.4). Mirrors DAMA: Pro card, defaults, support, legal.
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @StateObject private var tips = TipStore()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    freeCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Defaults") {
                    Picker("Default tool", selection: toolBinding) {
                        ForEach(RedactionStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Toggle(isOn: $settings.autoEditLatest) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-edit newest photo")
                            Text("Opens a photo taken in the last minute automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $settings.aiDetectionEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("AI-enhanced detection", systemImage: "sparkles")
                            Text("Uses on-device intelligence to catch names and other sensitive text. Runs 100% on your device — nothing is uploaded. Needs a supported device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Support Us") {
                    // Only shown once StoreKit actually returns the product —
                    // no store, no row (rather than a dead or erroring button).
                    if let product = tips.product {
                        tipRow(product)
                    }
                    ShareLink(item: URL(string: "https://apps.apple.com/app/privymark")!) {
                        Label("Share PrivyMark", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        requestReview()
                    } label: {
                        Label("Rate Us", systemImage: "star")
                    }
                    Link(destination: URL(string: "mailto:support@zhe.ltd")!) {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }

                Section("More") {
                    row("Documentation", systemImage: "book")
                    row("Privacy Policy", systemImage: "hand.raised")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await tips.load() }
            .onChange(of: tips.state) { _, state in
                if state == .thanks { settings.hasTipped = true }
            }
            .sheet(isPresented: showsThanks) { TipThanksSheet() }
            .alert("Buy Me a Coffee", isPresented: showsAlert) {
                Button("OK") { tips.state = .idle }
            } message: {
                Text(alertMessage ?? "")
            }
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
                Label(tipTitle, systemImage: "cup.and.saucer")
                Spacer()
                if tips.state == .purchasing {
                    ProgressView()
                } else {
                    // Always StoreKit's localized price — never a hardcoded one.
                    Text(product.displayPrice).foregroundStyle(.secondary)
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

    /// Reassurance banner (replaces the old Pro upsell — the app is fully free).
    private var freeCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor)
                    Text("PrivyMark").font(.title2.bold())
                }
                Text("Free, forever. Every scan runs on your device — nothing is ever uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(18)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.vertical, 4)
    }

    private func row(_ title: LocalizedStringKey, systemImage: String) -> some View {
        // Docs / privacy policy land with the website (PRD: deferred).
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
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
                Text("PrivyMark stays free and on-device for everyone. Your coffee keeps it that way.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
