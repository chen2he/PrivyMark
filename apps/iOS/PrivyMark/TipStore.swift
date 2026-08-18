//
//  TipStore.swift
//  PrivyMark
//
//  "Buy Me a Coffee" — a consumable tip that unlocks nothing. The app is and
//  stays fully free (PRD §10.4); this only says thank you. No server receipt
//  validation is needed because no entitlement is granted, and there is
//  deliberately no "Restore Purchases": consumables aren't restorable.
//

import Combine
import Foundation
import StoreKit

@MainActor
final class TipStore: ObservableObject {
    /// Matches the Consumable created in App Store Connect. Deliberately not
    /// prefixed with the bundle ID — that's allowed, don't "fix" it.
    static let productID = "Privymark.coffee"

    enum TipState: Equatable {
        case idle
        case loading
        case purchasing
        case thanks
        /// Pending external approval (Ask to Buy, bank confirmation) — NOT a sale.
        case pending
        case failed(String)
    }

    @Published private(set) var product: Product?
    @Published var state: TipState = .idle

    /// Watches for transactions completed outside the app (an approved Ask to
    /// Buy, a retried payment). Detached so it outlives any one view.
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update, announce: true)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Loads the product. A failure here is silent on purpose: if the store is
    /// unreachable the tip row simply doesn't appear, which is better than an
    /// error alert for something the user never asked for.
    func load() async {
        guard product == nil else { return }
        state = .loading
        defer { if state == .loading { state = .idle } }
        product = try? await Product.products(for: [Self.productID]).first
    }

    func purchase() async {
        guard let product, state != .purchasing else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification, announce: true)

            case .userCancelled:
                // Silent. Backing out of the system sheet is not an error.
                state = .idle

            case .pending:
                state = .pending

            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Verifies, thanks, and — critically — finishes the transaction. An
    /// unfinished consumable is redelivered on every launch, which would show
    /// the thank-you sheet again out of nowhere.
    private func handle(_ result: VerificationResult<Transaction>, announce: Bool) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == Self.productID else {
                await transaction.finish()
                return
            }
            await transaction.finish()
            if announce { state = .thanks }

        case .unverified:
            // Failed App Store signature check — treat as a failed purchase and
            // do not finish it.
            if announce { state = .failed(String(localized: "That purchase couldn't be verified.")) }
        }
    }
}
