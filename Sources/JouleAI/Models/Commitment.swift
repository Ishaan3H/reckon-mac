import Foundation

/// Something you intend to do at a specific time today.
///
/// A commitment comes from one of two places:
/// - `.calendar`: an event in the Mac's Calendar app. Its title and start time
///   are always re-read from the calendar; we only store the extra JouleAI data
///   (launch targets, the Commit toggle, duration) alongside it.
/// - `.manual`: something you typed in with "Add commitment".
///
/// `Codable` lets Swift turn this into JSON and back automatically.
/// `Identifiable` lets SwiftUI lists tell rows apart by `id`.
/// `Hashable` lets us compare two commitments for equality.
struct Commitment: Codable, Identifiable, Hashable {

    enum Source: String, Codable {
        case calendar
        case manual
    }

    var id: UUID = UUID()
    var title: String
    var startTime: Date
    var durationMinutes: Int
    var source: Source

    /// For calendar commitments: the EventKit `eventIdentifier` of the event.
    /// `nil` for manual commitments.
    var calendarEventIdentifier: String?

    /// What to open when you press Start (websites, files, apps).
    var launchTargets: [LaunchTarget] = []

    /// A calendar event's own length in minutes, kept up to date from the calendar.
    var calendarMinutes: Int?
    /// True once you've picked a different session length for a calendar event,
    /// so the event's length no longer replaces it. Optional so older saves load.
    var hasCustomLength: Bool?

    /// Only committed items will take over the screen (from Phase 2).
    var isCommitted: Bool = false

    /// No longer used (see `allowRules`). Kept so older saves keep this data.
    var extraAllowedApps: [String] = []

    /// A Google Meet / Zoom / Teams link found in the calendar event's URL,
    /// location or notes. Opened at Start; the session then allows that
    /// meeting site, skips brown noise and turns sound on.
    var meetingLink: String?

    /// No longer used: sessions now allow only what opens on Start. Kept so
    /// older saves keep this data.
    var presetID: UUID?
    var allowRules: [AllowRule]?

    // MARK: Lead-up state
    // All optional, so commitments saved before these existed still load
    // (a missing key in the JSON simply becomes nil).

    /// If the commitment was pushed back, the time it was originally planned for.
    var originalStartTime: Date?
    /// How many times it has been pushed back ("Push 30 min" / "Reschedule 30 min").
    var rescheduleCount: Int?
    /// When the 20-minute heads-up was shown, and how you answered it.
    var headsUpShownAt: Date?
    var headsUpResponse: HeadsUpResponse?
    /// When the 5-minute reminder was shown.
    var reminderShownAt: Date?
    /// Set when you chose "Not today" or Cancel.
    var cancelledAt: Date?

    enum HeadsUpResponse: String, Codable {
        case ready      // "I'll be ready"
        case push       // "Push 30 min"
        case notToday   // "Not today"
    }

    /// Each commitment can be pushed back once; after that it's Start or Cancel.
    static let maxReschedules = 1
    var canReschedule: Bool { (rescheduleCount ?? 0) < Self.maxReschedules }
    var isCancelled: Bool { cancelledAt != nil }

    /// When the session should end, given the start time and duration.
    var endTime: Date {
        startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}
