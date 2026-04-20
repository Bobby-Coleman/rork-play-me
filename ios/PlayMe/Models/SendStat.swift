import Foundation

/// Private per-friend send counter persisted under
/// `users/{uid}/sendStats/{friendUid}`. Drives the activity-ordered chip row
/// in the song send sheet.
nonisolated struct SendStat: Hashable, Sendable {
    let count: Int
    let lastSentAt: Date?
}
