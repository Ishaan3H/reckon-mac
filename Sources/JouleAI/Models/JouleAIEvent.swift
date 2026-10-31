import Foundation

/// One line in the event log: something that happened around a commitment,
/// with the exact time it happened.
///
/// The log is how you (and later, the History screen) can see how the lead-up
/// to a session actually went: when the heads-up appeared, what you answered,
/// whether you pushed it back, cancelled, started, or broke out.
struct JouleAIEvent: Codable {

    enum Kind: String, Codable {
        case headsUpShown        // 20-minute heads-up appeared
        case respondedReady      // "I'll be ready"
        case respondedPush       // "Push 30 min"
        case respondedNotToday   // "Not today"
        case reminderShown       // 5-minute reminder appeared
        case overlayShown        // full-screen Start card appeared
        case startCardHidden     // Start card was up but not visible on screen
        case rescheduled         // moved 30 minutes later
        case cancelled           // "Not today" or Cancel on the overlay
        case started             // Start pressed
        case brokeOut            // ended early with the typed phrase
        case completed           // the timer ran out
        case sessionInterrupted  // found at launch: JouleAI quit or crashed during this session
        case reflected           // answered the end-of-session window
        case reflectionSkipped   // closed it without answering
        case parkedToCommitment  // a parking-lot item became a new commitment
        case parkedDismissed     // a parking-lot item was dismissed
        case focusShortcut       // a Focus shortcut was run (or found missing), with the result
        case browserBlocked      // a browser was blocked: its pages couldn't be checked
        case lockShown           // (older logs) the lock card appeared; now lockOverlayShown
        case lockOverlayShown       // lock overlay appeared from hidden; detail = what caused it (app bundle ID, tab host, or blocked browser)
        case lockOverlayReasserted  // already up, brought back to front after an app switch; detail = the bundle ID
        case lockOverlayHidden      // taken down; detail = why (back to task, session ended, broke early)
        case emergencyExit          // ⌃⌥⌘⎋ pressed: overlay removed, session ended as broke early
        case caffeinateOn           // power assertion taken: the Mac won't idle-sleep during the session
        case caffeinateOff          // power assertion released; detail = why
        case meetingLinkFound       // a meeting link was detected in a calendar event; detail = service and link
        case meetingSession         // a session started with a meeting: link opened, brown noise off, sound on
        case backToTask          // "Back to task" pressed on the lock card
    }

    var timestamp: Date
    var kind: Kind
    var commitmentId: UUID
    var commitmentTitle: String
    /// Extra context, e.g. "14:00 → 14:30 (from heads-up)" or "via notification".
    var detail: String?
    /// True for events from the Debug menu's test overlay.
    var isTest: Bool?
}
