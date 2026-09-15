//
//  PhotoAccessView.swift
//  PrivyMark
//
//  Shown before photo access is granted (PRD §7.1). Mirrors DAMA:
//  illustration, reassurance that nothing is uploaded, Continue + Try sample.
//
//  App Review 5.1.1(iv): this screen precedes the system permission alert, so
//  its button must NOT say "Allow"/"OK"/"Grant" — that reads as pre-answering
//  the system prompt on the user's behalf. It says "Continue".
//

import SwiftUI
import Photos

struct PhotoAccessView: View {
    @ObservedObject var library: PhotoLibraryService
    var onTrySample: () -> Void

    @State private var showDeniedAlert = false

    var body: some View {
        // Centred when there's room, scrollable when there isn't — landscape and
        // the Duo outer display are short enough to squeeze the buttons against
        // the bottom edge otherwise.
        ViewThatFits(in: .vertical) {
            content(scrolls: false)
            ScrollView { content(scrolls: true) }
        }
        .alert("Access Denied", isPresented: $showDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Enable Photos access for PrivyMark in Settings, or try a sample image.")
        }
    }

    @ViewBuilder
    private func content(scrolls: Bool) -> some View {
        VStack(spacing: 0) {
            if !scrolls { Spacer() }

            Image(systemName: "photo.badge.checkmark")
                .font(.system(size: 84))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Photo Access")
                .font(.title2.bold())
                .padding(.top, 28)

            Text("PrivyMark needs access to your photos so you can pick one to redact.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Text("Your photos are never uploaded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .underline()
                .padding(.top, 10)

            if scrolls {
                Color.clear.frame(height: 32)
            } else {
                Spacer()
            }

            VStack(spacing: 12) {
                Button {
                    authorize()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onTrySample()
                } label: {
                    Text("Try a Sample Image")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.secondary)
            }
        }
        .padding(28)
        .readableColumn()
    }

    private func authorize() {
        Task {
            await library.requestAccess()
            if library.status == .denied || library.status == .restricted {
                showDeniedAlert = true
            }
        }
    }
}

#Preview {
    PhotoAccessView(library: PhotoLibraryService(), onTrySample: {})
}
