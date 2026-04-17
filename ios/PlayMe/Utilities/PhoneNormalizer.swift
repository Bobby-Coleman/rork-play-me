import Foundation

/// Normalizes phone numbers to a stable E.164-like key so Firestore
/// documents keyed by phone (e.g. `pendingShares/{phone}`) match whether
/// the number came from CNContacts, a user profile, or the PhoneEntryView.
///
/// Rules (US-centric, matches the existing PhoneEntryView behavior):
///   - Strip all non-digits.
///   - If the number already starts with "+", keep the leading "+".
///   - If it's 10 digits, prepend "+1".
///   - If it's 11 digits and starts with "1", prepend "+".
///   - Otherwise prepend "+" to whatever digits we have (best-effort).
enum PhoneNormalizer {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hadPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        if hadPlus {
            return "+\(digits)"
        }
        if digits.count == 10 {
            return "+1\(digits)"
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return "+\(digits)"
        }
        return "+\(digits)"
    }
}
