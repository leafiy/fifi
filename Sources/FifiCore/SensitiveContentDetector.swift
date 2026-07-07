import Foundation

public enum SensitiveContentKind: String, CaseIterable, Sendable, Codable {
    case creditCard = "credit_card"
    case apiKey = "api_key"
    case verificationCode = "verification_code"
}

public struct SensitiveDetectionOptions: Sendable, Equatable, Codable {
    public var detectCreditCards: Bool
    public var detectAPIKeys: Bool
    public var detectVerificationCodes: Bool

    public init(
        detectCreditCards: Bool = false,
        detectAPIKeys: Bool = false,
        detectVerificationCodes: Bool = false
    ) {
        self.detectCreditCards = detectCreditCards
        self.detectAPIKeys = detectAPIKeys
        self.detectVerificationCodes = detectVerificationCodes
    }

    public static let allOff: SensitiveDetectionOptions = SensitiveDetectionOptions()

    public var anyEnabled: Bool {
        detectCreditCards || detectAPIKeys || detectVerificationCodes
    }
}

public enum SensitiveContentDetector {
    /// First matching kind in order: apiKey, creditCard, verificationCode. nil when clean or all options off.
    public static func detect(in text: String, options: SensitiveDetectionOptions) -> SensitiveContentKind? {
        guard options.anyEnabled, text.utf16.count <= maxTextLength else { return nil }

        if options.detectAPIKeys, containsAPIKey(in: text) {
            return .apiKey
        }

        if options.detectCreditCards, containsCreditCard(in: text) {
            return .creditCard
        }

        if options.detectVerificationCodes, containsVerificationCode(in: text) {
            return .verificationCode
        }

        return nil
    }

    // MARK: - Rules

    private static let maxTextLength = 4_096
    private static let maxCreditCardTextLength = 512

    private static let apiKeyExpressions: [SensitiveRegularExpression] = [
        SensitiveRegularExpression(#"\bAKIA[0-9A-Z]{16}\b"#),
        SensitiveRegularExpression(#"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#),
        SensitiveRegularExpression(#"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#),
        SensitiveRegularExpression(#"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#),
        SensitiveRegularExpression(#"\bAIza[0-9A-Za-z_-]{35}\b"#),
        SensitiveRegularExpression(#"\b[sr]k_(live|test)_[A-Za-z0-9]{16,}\b"#),
        SensitiveRegularExpression(#"\bsk-[A-Za-z0-9_-]{20,}\b"#),
        SensitiveRegularExpression(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\b"#)
    ]

    private static let genericAssignmentExpression = SensitiveRegularExpression(
        #"\b(api[_-]?key|apikey|secret|token|passwd|password)\b\s*[:=]\s*\S{8,}"#,
        options: [.caseInsensitive]
    )

    private static let creditCardCandidateExpression = SensitiveRegularExpression(
        #"\b(?:\d[ -]?){12,18}\d\b"#
    )

    private static let verificationKeywordExpression = SensitiveRegularExpression(
        #"(verification|verify|one[- ]?time|otp|2fa|passcode|security code|auth code|验证码|認証コード)"#,
        options: [.caseInsensitive]
    )

    private static let verificationCodeExpression = SensitiveRegularExpression(#"\b\d{4,8}\b"#)
    private static let wholeVerificationCodeExpression = SensitiveRegularExpression(#"^\d{4,8}$"#)

    private static func containsAPIKey(in text: String) -> Bool {
        if text.contains("-----BEGIN ") && text.contains("PRIVATE KEY-----") {
            return true
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if apiKeyExpressions.contains(where: { $0.firstMatch(in: text, range: range) != nil }) {
            return true
        }

        return genericAssignmentExpression.firstMatch(in: text, range: range) != nil
    }

    private static func containsCreditCard(in text: String) -> Bool {
        guard text.utf16.count <= maxCreditCardTextLength else { return false }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = creditCardCandidateExpression.matches(in: text, range: range)
        return matches.contains { match in
            guard let candidateRange = Range(match.range, in: text) else { return false }
            let digits = text[candidateRange].filter { $0 != " " && $0 != "-" }
            return isValidCreditCardNumber(digits)
        }
    }

    private static func containsVerificationCode(in text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = NSRange(trimmedText.startIndex..<trimmedText.endIndex, in: trimmedText)
        if wholeVerificationCodeExpression.firstMatch(in: trimmedText, range: trimmedRange) != nil {
            return true
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard verificationKeywordExpression.firstMatch(in: text, range: range) != nil else { return false }
        return verificationCodeExpression.firstMatch(in: text, range: range) != nil
    }

    private static func isValidCreditCardNumber(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count) else { return false }

        var sum = 0
        var shouldDouble = false
        var previousDigit: Int?
        var allDigitsMatch = true

        for character in digits.reversed() {
            guard let digit = character.wholeNumberValue else { return false }

            if let previousDigit, previousDigit != digit {
                allDigitsMatch = false
            }
            previousDigit = digit

            var value = digit
            if shouldDouble {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }

            sum += value
            shouldDouble.toggle()
        }

        guard !allDigitsMatch else { return false }
        return sum % 10 == 0
    }
}

private struct SensitiveRegularExpression: @unchecked Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        self.expression = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func firstMatch(in text: String, range: NSRange) -> NSTextCheckingResult? {
        expression.firstMatch(in: text, options: [], range: range)
    }

    func matches(in text: String, range: NSRange) -> [NSTextCheckingResult] {
        expression.matches(in: text, options: [], range: range)
    }
}
