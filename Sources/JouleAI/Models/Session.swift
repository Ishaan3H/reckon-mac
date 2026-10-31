import Foundation

/// A record of one time a commitment fired: whether you did it, skipped it, or
/// broke it early, plus the "where I left off" note.
///
/// When a session ends, the end-of-session window fills in `outcome`
/// (Done / Partly / Didn't) and `leftOffNote`.
struct Session: Codable, Identifiable, Hashable {

    enum Outcome: String, Codable {
        case done
        case partly
        case didnt
        case skipped
        case brokeEarly
        case interrupted   // JouleAI quit or crashed while it was running
    }

    var id: UUID = UUID()
    var commitmentId: UUID
    /// Copied from the commitment so history still reads well if the commitment is gone.
    var commitmentTitle: String
    var startedAt: Date
    var endedAt: Date?
    var outcome: Outcome?
    var leftOffNote: String?
    var breakReason: String?
    /// What you typed into the parking lot during the session (one item per line).
    var parkedNotes: String?

    /// Set when the end-of-session window was closed without answering.
    /// The window then comes back once, the next time the popover opens.
    var reflectionSkippedAt: Date?
    /// Set when that one re-ask has happened, so it never nags twice.
    var reflectionReaskedAt: Date?

    /// The parking-lot lines, without blanks.
    var parkedItems: [String] {
        (parkedNotes ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
