//
//  TextRuleMatcher.swift
//  PrivyMark
//
//  Second detection layer per PRD §9.2: pure-Foundation rule matching
//  over OCR text. Platform-neutral and unit-testable.
//

import Foundation

/// One sensitive span found in an OCR line. `range` is the exact text to cover —
/// geometry is always derived from it, so no rule can force a whole-line box.
nonisolated struct RuleMatch: Equatable, Sendable {
    let range: Range<String.Index>
    let type: RiskType
    let level: RiskLevel
}

nonisolated enum TextRuleMatcher {

    // MARK: - Regexes

    private static let emailRegex = regex(
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, caseInsensitive: true)

    private static let urlRegex = regex(
        #"(?:https?://|www\.)[^\s<>"']+|\b[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:com|net|org|io|co|app|dev|me|info|biz|ly|us|uk|de|fr|es|it|pt|br|mx|ar|cl|ca|eu|edu|gov)\b(?:/[^\s<>"']*)?"#,
        caseInsensitive: true)

    /// 13–19 digits, optionally separated by spaces/dashes; validated with Luhn.
    private static let paymentRegex = regex(
        #"(?<!\d)(?:\d[ \-]?){12,18}\d(?!\d)"#, caseInsensitive: false)

    /// Phone candidates; post-filtered on digit count.
    private static let phoneRegex = regex(
        #"(?<![\d/.])(?:\+\d{1,3}[ .\-]?)?(?:\(\d{1,4}\)[ .\-]?)?\d(?:[ .\-]?\d){5,12}(?!\d)"#,
        caseInsensitive: false)

    /// UPS-style tracking numbers.
    private static let carrierRegex = regex(#"\b1Z[0-9A-Z]{16}\b"#, caseInsensitive: false)

    /// US Social Security Number: NNN-NN-NNNN. Dashes required so it stays
    /// distinctive (a bare 9-digit run would drown in false positives).
    private static let ssnRegex = regex(
        #"(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)"#, caseInsensitive: false)

    /// Keyword-anchored government / ID numbers (passport, national ID, SSN,
    /// driver's licence, tax ID, UK NINO…). Capture group 1 = the identifier.
    /// Kept keyword-anchored on purpose — bare alphanumeric IDs are too noisy.
    private static let idRegex = regex(
        #"\b(?:passport|national\s*id|identity(?:\s*(?:card|no\.?|number))?|id\s*(?:card|no\.?|number)|driver'?s?\s+licen[cs]e|dl\s*no\.?|licen[cs]e\s*(?:no\.?|number)|ssn|social\s*security(?:\s*(?:no\.?|number))?|tax\s*id|national\s*insurance|nino)(?:\s*(?:no\.?|number|id|#|:|：))*\s+([A-Z0-9][A-Z0-9\-]{4,18})"#,
        caseInsensitive: true)

    /// Labeled personal names common in receipts / invoices / forms:
    /// "Name: John Doe", "Billed to: Jane Roe", "Attn: Dr. Smith". The label is
    /// matched case-insensitively via `(?i:…)`, but the name itself stays
    /// case-SENSITIVE (must be Capitalized) so labels followed by a lowercase
    /// value or a number (e.g. "Ship to: 123 Main St") don't match. This backs
    /// up the on-device NER, which can miss labeled names. Capture group 1 = name.
    /// The name value allows Capitalized ("John") AND ALL-CAPS ("MANSIR")
    /// words — card-holder names are often printed in all caps.
    private static let nameRegex = regex(
        #"\b(?i:name|full\s*name|billed\s+to|bill\s+to|cardholder|card\s*holder|account\s+holder|customer|recipient|patient|attention|attn|dear|mr|mrs|ms|dr)\b[:.\s#]{1,3}([A-Z][a-zA-Z'.\-]+(?:\s+[A-Z][a-zA-Z'.\-]+){0,3})"#,
        caseInsensitive: false)

    /// Keyword-anchored order/tracking references. Capture group 1 = the code.
    /// The separator group repeats: "Order #: X", "Tracking no.: X", etc.
    private static let orderRegex = regex(
        #"\b(?:order|tracking|track|ref(?:erence)?|invoice|shipment|pedido|rastreio|seguimiento|commande|bestellung|ordine)(?:\s*(?:no\.?|number|id|#|:|：))*\s+([A-Z0-9][A-Z0-9\-]{5,24})"#,
        caseInsensitive: true)

    /// License plate candidates: uppercase letter/digit tokens (matched case-sensitively).
    private static let plateRegex = regex(
        #"\b[A-Z]{1,3}[ \-]?\d{1,4}[ \-]?[A-Z0-9]{0,3}\b"#, caseInsensitive: false)

    /// Address keywords across launch-region languages (PRD §9.2).
    /// German street names are compounds (Hauptstraße, Bahnhofstr.), so those
    /// tokens allow a word prefix instead of a leading boundary.
    private static let addressRegex = regex(
        #"\b(street|avenue|ave|boulevard|blvd|road|lane|drive|apartment|apt|suite|zip ?code|zip|postcode|postal code|p\.?o\.? box|calle|avenida|colonia|c[oó]digo postal|rua|bairro|cep|rue|code postal|\w*stra(?:ss|ß)e|\w*str\.|platz|plz|via|piazza|cap)\b"#,
        caseInsensitive: true)

    /// Short suffix tokens (st/rd/dr/ln) only count as address markers when they
    /// directly follow a capitalized word ("Main St", "Oak Rd").
    private static let addressSuffixRegex = regex(
        #"\b[A-Z][a-z]+ (St|Rd|Dr|Ln)\.?\b"#, caseInsensitive: false)

    // MARK: - China (Mainland launch region)

    /// Mainland China resident ID card (身份证号): 18 chars = 6 region digits +
    /// 8-digit birthdate + 3 sequence + 1 checksum ([0-9] or X). Birthdate is
    /// validated so random 18-digit runs (and most cards) don't match. Uses
    /// digit-lookbehind boundaries because CJK text has no `\b` before digits.
    private static let chinaIDRegex = regex(
        #"(?<!\d)\d{6}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?![\dXx])"#,
        caseInsensitive: false)

    /// Labeled Chinese personal names: "姓名：张三", "收件人 李四", "检测人：郭涛".
    /// Capture group 1 = the 2–4 character name.
    private static let chineseNameRegex = regex(
        #"(?:姓名|收件人|收货人|客户|持卡人|联系人|户名|开户名|检测人|受理人|经办人|负责人|报修人)[:：\s]*([\x{4e00}-\x{9fff}]{2,4})"#,
        caseInsensitive: false)

    /// Keyword-anchored Chinese order / service numbers: "服务单号：AS123",
    /// "订单号 12345". Capture group 1 = the code.
    private static let chineseOrderRegex = regex(
        #"(?:订单号|服务单号|受理单号|工单号|流水号|快递单号|物流单号|单号|编号)[:：\s]*([A-Za-z0-9][A-Za-z0-9\-]{5,24})"#,
        caseInsensitive: false)

    /// Card security code (CVV/CVC/安全码) followed by a 3–4 digit value, on one
    /// line. Vertical "CVV\n782" layouts are recovered by the label→value pass.
    private static let cvvRegex = regex(
        #"\b(?i:cvv2?|cvc2?|cid|安全码|校验码)\b[:.：\s#]{0,3}(\d{3,4})(?!\d)"#,
        caseInsensitive: false)

    /// Chinese address markers (matched anywhere — CJK has no word boundaries).
    /// Combined with the "line also contains a digit" rule this yields the line.
    private static let chineseAddressRegex = regex(
        #"(省|市|区|县|镇|乡|村|路|街|巷|弄|号|栋|幢|单元|室|楼|大厦|花园|小区|广场|邮编|邮政编码)"#,
        caseInsensitive: false)

    /// Mainland China license plate: province char + city letter + 5–6 alnum
    /// (regular = 5, new-energy = 6). Best-effort → low confidence ("Maybe").
    private static let chinesePlateRegex = regex(
        #"[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼][A-Z][A-Z0-9]{5,6}(?![A-Z0-9])"#,
        caseInsensitive: false)

    /// Scene-hint keywords that raise risk levels (PRD §9.2 第三层).
    private static let contextKeywordRegex = regex(
        #"\b(order|tracking|address|phone|tel|email|ship(?:ping)? to|deliver(?:y)? to)\b"#,
        caseInsensitive: true)

    /// A leading address label ("Address:", "Addr.", "地址：", "收件地址") — skipped
    /// so the cover starts at the address itself instead of the field name.
    private static let addressLabelRegex = regex(
        #"^\s*(?:shipping address|billing address|delivery address|address|addr\.?|ship to|deliver to|地\s*址|住\s*址|收货地址|收件地址|通讯地址)\s*[:：]?\s*"#,
        caseInsensitive: true)

    private static func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure is a programmer error.
        try! NSRegularExpression(
            pattern: pattern,
            options: caseInsensitive ? [.caseInsensitive] : [])
    }

    // MARK: - Matching

    /// Returns sensitive matches found in one OCR line.
    /// Precedence on overlap: email > url > payment > order > id > name > phone > plate.
    /// Address matches are line-level and reported independently.
    static func matches(in line: String, sceneHint: Bool = false) -> [RuleMatch] {
        guard !line.isEmpty else { return [] }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var taken: [NSRange] = []
        var results: [RuleMatch] = []

        func claim(_ r: NSRange, _ type: RiskType, _ level: RiskLevel) {
            guard !taken.contains(where: { NSIntersectionRange($0, r).length > 0 }),
                  let range = Range(r, in: line) else { return }
            taken.append(r)
            results.append(RuleMatch(range: range, type: type, level: level))
        }

        func boost(_ level: RiskLevel) -> RiskLevel {
            sceneHint && level == .medium ? .high : level
        }

        // 1. Email
        for m in emailRegex.matches(in: line, range: full) {
            claim(m.range, .email, .high)
        }

        // 2. URL
        for m in urlRegex.matches(in: line, range: full) {
            claim(m.range, .url, boost(.medium))
        }

        // 3. Payment (Luhn-validated digit runs) + card security codes.
        for m in paymentRegex.matches(in: line, range: full) {
            let digits = ns.substring(with: m.range).filter(\.isNumber)
            guard (13...19).contains(digits.count), passesLuhn(digits) else { continue }
            claim(m.range, .payment, .high)
        }
        for m in cvvRegex.matches(in: line, range: full) where m.numberOfRanges > 1 {
            claim(m.range(at: 1), .payment, .high)
        }

        // 4. Order / tracking numbers
        for m in carrierRegex.matches(in: line, range: full) {
            claim(m.range, .orderNumber, boost(.medium))
        }
        for m in orderRegex.matches(in: line, range: full) where m.numberOfRanges > 1 {
            let code = m.range(at: 1)
            let text = ns.substring(with: code)
            guard text.contains(where: \.isNumber) else { continue }
            claim(code, .orderNumber, boost(.medium))
        }
        for m in chineseOrderRegex.matches(in: line, range: full) where m.numberOfRanges > 1 {
            claim(m.range(at: 1), .orderNumber, boost(.medium))
        }

        // 4.5 Government / ID numbers. Claim SSN BEFORE phone so a
        // NNN-NN-NNNN isn't swallowed by the phone matcher (9 digits).
        for m in ssnRegex.matches(in: line, range: full) {
            claim(m.range, .idNumber, .high)
        }
        for m in idRegex.matches(in: line, range: full) where m.numberOfRanges > 1 {
            let code = m.range(at: 1)
            guard ns.substring(with: code).contains(where: \.isNumber) else { continue }
            claim(code, .idNumber, .high)
        }
        // China resident ID (身份证号) — 18 chars, birthdate-validated.
        for m in chinaIDRegex.matches(in: line, range: full) {
            claim(m.range, .idNumber, .high)
        }

        // 4.6 Labeled personal names ("Billed to: Jane Roe" / "姓名：张三").
        for m in nameRegex.matches(in: line, range: full) where m.numberOfRanges > 1 {
            claim(m.range(at: 1), .name, .medium)
        }
        for m in chineseNameRegex.matches(in: line, range: full) where m.numberOfRanges > 1 {
            claim(m.range(at: 1), .name, .medium)
        }

        // 5. Phone numbers
        for m in phoneRegex.matches(in: line, range: full) {
            let text = ns.substring(with: m.range)
            let digits = text.filter(\.isNumber)
            guard (7...15).contains(digits.count) else { continue }
            guard Set(digits).count > 1 else { continue } // 0000000…
            claim(m.range, .phone, .high)
        }

        // 6. License plate candidates (always low confidence → "Maybe")
        for m in plateRegex.matches(in: line, range: full) {
            let text = ns.substring(with: m.range)
            let letters = text.filter(\.isLetter).count
            let digits = text.filter(\.isNumber).count
            let alnum = letters + digits
            guard (5...8).contains(alnum), letters >= 2, digits >= 2 else { continue }
            claim(m.range, .licensePlateCandidate, .low)
        }
        // China plates (省份简称 + 字母 + 5–6): distinctive prefix, still "Maybe".
        for m in chinesePlateRegex.matches(in: line, range: full) {
            claim(m.range, .licensePlateCandidate, .low)
        }

        // 7. Address: an address keyword (Latin / "Main St" suffix / Chinese
        //    marker) plus either a digit OR a comma (a street name + city +
        //    country with no house number still reads as an address). The right
        //    edge of an address is unknowable, so the match runs to the end of
        //    the line — but a leading "Address:" label is left readable.
        let hasKeyword = addressRegex.firstMatch(in: line, range: full) != nil
            || addressSuffixRegex.firstMatch(in: line, range: full) != nil
            || chineseAddressRegex.firstMatch(in: line, range: full) != nil
        if hasKeyword, line.contains(where: \.isNumber) || line.contains(",") || line.contains("，"),
           let whole = Range(full, in: line) {
            let start = addressLabelRegex.firstMatch(in: line, range: full)
                .flatMap { Range($0.range, in: line)?.upperBound } ?? whole.lowerBound
            if start < whole.upperBound {
                results.append(RuleMatch(
                    range: start..<whole.upperBound, type: .address, level: boost(.medium)))
            }
        }

        return results
    }

    /// True when a line is ONLY a name-field label — English ("Card Holder",
    /// "Name") or Chinese ("姓名：", "收件人", "检测人"). Forms often lay label and
    /// value on separate OCR lines (vertical, or Vision's horizontal split at the
    /// colon); ScanService pairs a label line with an adjacent `looksLikeName`
    /// line to recover the value a same-line rule can't.
    static func isNameLabelLine(_ line: String) -> Bool {
        nameLabelLineRegex.firstMatch(in: line, range: nsRange(line)) != nil
    }

    /// True when a line is just a plausible bare name: 2–4 CJK chars, or 1–4
    /// Capitalized / ALL-CAPS Latin words ("MANSIR USMAN", "张伟").
    static func looksLikeName(_ line: String) -> Bool {
        nameValueRegex.firstMatch(in: line, range: nsRange(line)) != nil
    }

    /// True when a line is ONLY a card-security-code label (CVV / CVC / 安全码).
    static func isCVVLabel(_ line: String) -> Bool {
        cvvLabelLineRegex.firstMatch(in: line, range: nsRange(line)) != nil
    }

    /// True when a line is just a bare 3–4 digit value (a paired CVV/CVC).
    static func looksLikeCVV(_ line: String) -> Bool {
        cvvValueRegex.firstMatch(in: line, range: nsRange(line)) != nil
    }

    private static func nsRange(_ s: String) -> NSRange {
        NSRange(location: 0, length: (s as NSString).length)
    }

    private static let nameLabelLineRegex = regex(
        #"^\s*(?i:card\s*holder|cardholder|account\s*holder|full\s*name|name|recipient|customer|attention|attn|收件人|收货人|姓名|客户|持卡人|联系人|户名|开户名|检测人|受理人|经办人|负责人|报修人)\s*[:：]?\s*$"#,
        caseInsensitive: false)
    private static let nameValueRegex = regex(
        #"^\s*(?:[\x{4e00}-\x{9fff}]{2,4}|[A-Z][a-zA-Z'.\-]+(?:\s+[A-Z][a-zA-Z'.\-]+){0,3})\s*$"#,
        caseInsensitive: false)
    private static let cvvLabelLineRegex = regex(
        #"^\s*(?i:cvv2?|cvc2?|cid|安全码|校验码)\s*[:：]?\s*$"#, caseInsensitive: false)
    private static let cvvValueRegex = regex(#"^\s*\d{3,4}\s*$"#, caseInsensitive: false)

    /// Scene hint per PRD §9.2 第三层: does any OCR line contain context keywords?
    static func containsContextKeywords(_ lines: [String]) -> Bool {
        lines.contains { line in
            contextKeywordRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        }
    }

    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard let d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }
}
