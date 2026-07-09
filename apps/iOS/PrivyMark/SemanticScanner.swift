//
//  SemanticScanner.swift
//  PrivyMark
//
//  Optional on-device semantic PII pass (iOS 26+ Apple Foundation Models).
//  Progressive enhancement layered on top of the Vision + rule pipeline: it
//  catches names, ID numbers, and context-sensitive info the regexes miss, using
//  the model's understanding of the OCR text.
//
//  PRIVACY: strictly on-device. Uses `SystemLanguageModel.default` and NEVER
//  `PrivateCloudComputeLanguageModel` (or any server / third-party provider), so
//  PrivyMark's "nothing leaves the device" promise holds. The model classifies
//  the OCR *text*; geometry stays with Vision — ScanService maps each returned
//  span back to a box via the OCR word boxes (`ScanService.locate`).
//

import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
nonisolated enum SemanticScanner {

    /// A sensitive span the model found in the OCR text.
    struct Hit: Sendable {
        let text: String
        let type: RiskType
        let level: RiskLevel
    }

    /// Runs the on-device model over the OCR transcript. Returns nil when the
    /// model is unavailable (device without Apple Intelligence, model not yet
    /// downloaded, etc.) or on any error — the caller then keeps the Vision +
    /// rule results (PRD §8.3 resilience). Never throws.
    static func detect(transcript: String) async -> [Hit]? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        // On-device model ONLY. Do not substitute a PCC / server model here.
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: "OCR text from a screenshot the user wants to share:\n\n\(trimmed)",
                generating: Scan.self)
            return response.content.items.compactMap(Self.hit)
        } catch {
            return nil
        }
    }

    private static let instructions = """
        You help people redact private information from screenshots before they \
        share them. You receive raw OCR text extracted from an image; it may be \
        in English or Chinese. Find every span that is personally identifying or \
        sensitive: people's names (including Chinese names), ID / passport / SSN \
        / 身份证 / account / membership numbers, postal addresses (including \
        Chinese addresses), phone numbers, email addresses, and financial details \
        such as card numbers or balances. Copy each span EXACTLY as it appears in \
        the text — never paraphrase, translate, or invent text that is not \
        present. Ignore generic UI labels, button text, dates, and ordinary \
        non-sensitive words.
        """

    private static func hit(_ item: Item) -> Hit? {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return nil }
        let type: RiskType
        let level: RiskLevel
        switch item.category {
        case .personName: type = .name;      level = .medium
        case .idNumber:   type = .idNumber;  level = .high
        case .address:    type = .address;   level = .medium
        case .phone:      type = .phone;      level = .high
        case .email:      type = .email;      level = .high
        case .financial:  type = .payment;    level = .high
        case .other:      type = .otherText;  level = .medium
        }
        return Hit(text: text, type: type, level: level)
    }

    // MARK: - Guided-generation schema (@Generable)

    @Generable
    struct Scan {
        @Guide(description: "Every span of personal or sensitive information found in the text")
        let items: [Item]
    }

    @Generable
    struct Item {
        @Guide(description: "The sensitive text, copied verbatim from the input")
        let text: String
        @Guide(description: "Which kind of sensitive information this span is")
        let category: Category
    }

    @Generable
    enum Category {
        case personName
        case idNumber
        case address
        case phone
        case email
        case financial
        case other
    }
}
