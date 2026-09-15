//
//  WelcomeView.swift
//  PrivyMark
//
//  First-launch onboarding (PRD §10.1). Mirrors DAMA's welcome layout:
//  label, big title, a detection illustration card, promise copy, CTA.
//

import SwiftUI

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        // Portrait fits the whole thing; a wide-and-short layout — landscape, or
        // the Duo outer display — does not, and this screen holds the only way
        // forward, so it scrolls rather than pushing the button off-screen.
        ViewThatFits(in: .vertical) {
            content(scrolls: false)
            ScrollView { content(scrolls: true) }
        }
    }

    @ViewBuilder
    private func content(scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text("Find private details\nin your images")
                .font(.system(size: 40, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            DetectionShowcase()
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 18) {
                Text("PrivyMark detects private info in a photo — faces, phone numbers, emails, names, card numbers, IDs, license plates — and redacts it for you.")
                Text("Scanning happens offline. Nothing you open is ever uploaded.")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 28)

            if scrolls {
                Color.clear.frame(height: 28)
            } else {
                Spacer(minLength: 20)
            }

            Button(action: onStart) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Get started")
        }
        .padding(28)
        .readableColumn(alignment: .leading)
    }
}

/// The green-highlighted "what we detect" mock card.
private struct DetectionShowcase: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                badge(systemName: "faceid")
                highlightRow("Alex Rivera", align: .leading)
            }
            HStack(spacing: 10) {
                highlight("4393 1235 8893 4413")
                Spacer(minLength: 0)
                highlight("$1,000")
            }
            HStack(spacing: 14) {
                badge(systemName: "qrcode")
                VStack(spacing: 10) {
                    HStack { Spacer(); highlight("steve@gmail.com") }
                    HStack { Spacer(); highlight("+1 237-342-988") }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }

    private func badge(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.accentColor.opacity(0.22))
            .frame(width: 64, height: 64)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            )
    }

    private func highlight(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
    }

    private func highlightRow(_ text: String, align: HorizontalAlignment) -> some View {
        HStack {
            highlight(text)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    WelcomeView(onStart: {})
}
