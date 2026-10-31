import AppKit
import EventKit
import Observation

/// The single source of truth for the app: today's commitments, calendar
/// permission, and the actions that change them.
///
/// `@Observable` (macOS 14+) makes SwiftUI views automatically redraw when any
/// property they read here changes. `@MainActor` means all of this runs on the
/// main thread, which is where UI work must happen.
@MainActor
@Observable
final class AppState {

    // MARK: - State the UI reads

    /// Every commitment we have saved (calendar-linked and manual, any day).
    private(set) var commitments: [Commitment] = []

    /// Every session ever logged (started, skipped, broken...). Newest last.
    private(set) var sessions: [Session] = []

    /// Current calendar permission.
    private(set) var calendarAccess: CalendarService.Access

    /// True for a moment after the refresh button is pressed, to show a spinner.
    private(set) var isReloadingCalendar = false

    /// Identifiers of the calendar events that exist today, so we can hide saved
    /// commitments whose event was deleted or moved to another day.
    private var todaysEventIdentifiers: Set<String> = []

    /// What the popover shows: today's commitments, sorted by time.
    var todayItems: [Commitment] {
        commitments
            .filter { item in
                guard Calendar.current.isDateInToday(item.startTime) else { return false }
                switch item.source {
                case .manual:
                    return true
                case .calendar:
                    // Only show calendar items whose event still exists today.
                    guard let identifier = item.calendarEventIdentifier else { return false }
                    // No calendar access means we can't tell if the event still
                    // exists, so trust what's saved: a commitment still fires.
                    guard calendarAccess == .granted else { return true }
                    return todaysEventIdentifiers.contains(identifier)
                }
            }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Helpers

    private let calendarService = CalendarService()
    private static let commitmentsFile = "commitments.json"
    private static let sessionsFile = "sessions.json"

    // MARK: - Setup

    init() {
        calendarAccess = calendarService.access
        commitments = Storage.load([Commitment].self, from: Self.commitmentsFile) ?? []
        sessions = Storage.load([Session].self, from: Self.sessionsFile) ?? []
        refresh()

        // Re-read the calendar whenever it changes (an event added in Calendar.app,
        // a Google sync arriving, etc.) and when the date rolls over at midnight.
        let center = NotificationCenter.default
        center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        // Left alone, macOS can take a while to fetch new Google events, so
        // nudge it every 5 minutes for as long as the app runs.
        Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncCalendar() }
        }
    }

    // MARK: - Calendar

    /// Asks macOS to fetch new calendar data. Any new events reach `refresh()`
    /// through the EKEventStoreChanged observer above.
    func syncCalendar() {
        guard calendarAccess == .granted else { return }
        calendarService.askForSync()
    }

    /// Asks for calendar permission (shows the system prompt the first time).
    func requestCalendarAccess() {
        Task {
            calendarAccess = await calendarService.requestAccess()
            refresh()
        }
    }

    /// Opens System Settings → Privacy & Security → Calendars.
    func openCalendarPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    /// The refresh button: asks macOS to re-check the calendar accounts, then
    /// reads today's events again. The second read picks up a quick sync; a
    /// slower one still arrives through the EKEventStoreChanged observer above.
    func reloadCalendar() {
        guard !isReloadingCalendar else { return }
        isReloadingCalendar = true
        calendarService.reload()
        refresh()
        Task {
            try? await Task.sleep(for: .seconds(2))
            refresh()
            isReloadingCalendar = false
        }
    }

    /// Re-reads today's calendar events and merges them with saved commitment data.
    ///
    /// For each event today:
    /// - if we already have a commitment for that event today, update its title,
    ///   time and length from the calendar (the calendar is always right about those);
    /// - otherwise create a new commitment for it. If the same event
    ///   appeared on an earlier day (a repeating event), copy its launch targets
    ///   so you don't have to set them up again.
    func refresh() {
        calendarAccess = calendarService.access
        let events = calendarService.todaysEvents()
        todaysEventIdentifiers = Set(events.compactMap { $0.eventIdentifier })

        var changed = false
        for event in events {
            guard let identifier = event.eventIdentifier else { continue }
            let title = event.title ?? "Untitled event"

            if let index = commitments.firstIndex(where: {
                $0.calendarEventIdentifier == identifier &&
                Calendar.current.isDate($0.startTime, inSameDayAs: event.startDate)
            }) {
                // A commitment you pushed back keeps its new time; otherwise the
                // calendar's time wins.
                let eventStart: Date = event.startDate
                let calendarTime = commitments[index].originalStartTime == nil
                    ? eventStart : commitments[index].startTime
                if commitments[index].title != title || commitments[index].startTime != calendarTime {
                    commitments[index].title = title
                    commitments[index].startTime = calendarTime
                    changed = true
                }
                // A calendar event's session is always as long as the event.
                if commitments[index].durationMinutes != Self.minutes(of: event) {
                    commitments[index].durationMinutes = Self.minutes(of: event)
                    changed = true
                }
            } else {
                let previous = commitments.last(where: { $0.calendarEventIdentifier == identifier })
                commitments.append(Commitment(
                    title: title,
                    startTime: event.startDate,
                    durationMinutes: Self.minutes(of: event),
                    source: .calendar,
                    calendarEventIdentifier: identifier,
                    launchTargets: previous?.launchTargets ?? [],
                    // New events start committed, unless already under way:
                    // that one shouldn't take over the screen the moment it appears.
                    isCommitted: event.startDate > Date(),
                    extraAllowedApps: previous?.extraAllowedApps ?? []
                ))
                changed = true
            }

            // Look for a meeting link: the event's URL first, then its
            // location, then its notes. The first one found is used.
            let meeting = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
            if let index = commitments.lastIndex(where: {
                $0.calendarEventIdentifier == identifier &&
                Calendar.current.isDate($0.startTime, inSameDayAs: event.startDate)
            }), commitments[index].meetingLink != meeting?.url.absoluteString {
                commitments[index].meetingLink = meeting?.url.absoluteString
                changed = true
                if let meeting {
                    EventLog.record(.meetingLinkFound, commitments[index],
                                    detail: "\(meeting.service.rawValue): \(meeting.url.absoluteString)")
                }
            }
        }
        if changed { persist() }
    }

    /// A calendar event's length in minutes, within what a session can be.
    private static func minutes(of event: EKEvent) -> Int {
        let minutes = Int((event.endDate.timeIntervalSince(event.startDate) / 60).rounded())
        guard minutes > 0 else { return AppSettings.defaultDurationMinutes }
        return min(minutes, CommitmentEditorView.customRange.upperBound)
    }

    // MARK: - Editing commitments

    /// Flips the Commit toggle for one commitment.
    /// Re-committing something you'd cancelled gives it a fresh lead-up
    /// (heads-up and reminder show again).
    func setCommitted(_ committed: Bool, for id: Commitment.ID) {
        update(id) { item in
            item.isCommitted = committed
            if committed && item.isCancelled {
                // Undo the cancellation, including the "skipped" record it left.
                sessions.removeAll { $0.commitmentId == id && $0.outcome == .skipped }
                Storage.save(sessions, to: Self.sessionsFile)
                item.cancelledAt = nil
                item.headsUpShownAt = nil
                item.headsUpResponse = nil
                item.reminderShownAt = nil
            }
        }
    }

    /// Changes one commitment in place and saves. Returns the updated copy.
    @discardableResult
    func update(_ id: Commitment.ID, _ change: (inout Commitment) -> Void) -> Commitment? {
        guard let index = commitments.firstIndex(where: { $0.id == id }) else { return nil }
        change(&commitments[index])
        persist()
        return commitments[index]
    }

    func commitment(withID id: Commitment.ID) -> Commitment? {
        commitments.first { $0.id == id }
    }

    /// Saves a new or edited commitment. If one with the same `id` exists it is
    /// replaced; otherwise the commitment is added.
    func save(_ commitment: Commitment) {
        if let index = commitments.firstIndex(where: { $0.id == commitment.id }) {
            var updated = commitment
            // A new time gets its own heads-up and reminder.
            if commitments[index].startTime != commitment.startTime {
                updated.headsUpShownAt = nil
                updated.headsUpResponse = nil
                updated.reminderShownAt = nil
            }
            commitments[index] = updated
        } else {
            commitments.append(commitment)
        }
        persist()
    }

    /// Deletes a manual commitment. (Calendar commitments come back on the next
    /// refresh, so to remove those, delete the event in Calendar instead.)
    func delete(_ id: Commitment.ID) {
        commitments.removeAll { $0.id == id }
        persist()
    }

    /// A blank manual commitment, already committed, starting at the next quarter hour.
    func newManualCommitment() -> Commitment {
        Commitment(
            title: "",
            startTime: Self.nextQuarterHour(),
            durationMinutes: AppSettings.defaultDurationMinutes,
            source: .manual,
            isCommitted: true
        )
    }

    // MARK: - Sessions

    /// The committed item that should take over the screen right now, if any:
    /// its start time has arrived, its time slot hasn't finished yet, and it has
    /// no session logged (so it hasn't been started or skipped already).
    ///
    /// The "slot hasn't finished" rule means that if your Mac was asleep for the
    /// whole slot, JouleAI won't ambush you with it hours later.
    func dueCommitment(at now: Date = Date()) -> Commitment? {
        todayItems.first { item in
            isLive(item) && item.startTime <= now && now < item.endTime
        }
    }

    /// Committed items whose 20-minute heads-up should appear now
    /// (between 20 and 5 minutes before the start, and not shown yet).
    func headsUpsDue(at now: Date = Date()) -> [Commitment] {
        todayItems.filter { item in
            isLive(item) && item.headsUpShownAt == nil &&
            item.startTime.addingTimeInterval(-20 * 60) <= now &&
            now < item.startTime.addingTimeInterval(-5 * 60)
        }
    }

    /// Committed items whose 5-minute reminder should appear now.
    func remindersDue(at now: Date = Date()) -> [Commitment] {
        todayItems.filter { item in
            isLive(item) && item.reminderShownAt == nil &&
            item.startTime.addingTimeInterval(-5 * 60) <= now &&
            now < item.startTime
        }
    }

    /// The next committed item still to start today — what the menu bar counts
    /// down to.
    func upcoming(at now: Date = Date()) -> Commitment? {
        todayItems.first { isLive($0) && now < $0.startTime }
    }

    /// Committed, not cancelled, and not already started/skipped.
    private func isLive(_ item: Commitment) -> Bool {
        item.isCommitted && !item.isCancelled && !hasSession(for: item.id)
    }

    // MARK: - Overlap warnings

    /// Another committed item that clashes with a commitment.
    struct Conflict {
        let other: Commitment
        /// true = the two sessions overlap; false = less than 15 minutes apart.
        let overlaps: Bool
    }

    /// Other committed items today that overlap `commitment`, or leave less
    /// than 15 minutes between them and it.
    func conflicts(for commitment: Commitment) -> [Conflict] {
        let buffer: TimeInterval = 15 * 60
        return todayItems.compactMap { other in
            guard other.id != commitment.id, other.isCommitted, !other.isCancelled else { return nil }
            if commitment.startTime < other.endTime && other.startTime < commitment.endTime {
                return Conflict(other: other, overlaps: true)
            }
            // Gap between whichever ends first and whichever starts second.
            let gap = max(other.startTime.timeIntervalSince(commitment.endTime),
                          commitment.startTime.timeIntervalSince(other.endTime))
            return gap < buffer ? Conflict(other: other, overlaps: false) : nil
        }
    }

    /// True if a session has been logged for this commitment's current time slot.
    func hasSession(for commitmentId: Commitment.ID) -> Bool {
        // A session that ended before the current start time belongs to an
        // earlier slot: moving a finished commitment later makes it due again.
        let start = commitment(withID: commitmentId)?.startTime ?? .distantPast
        return sessions.contains { $0.commitmentId == commitmentId && ($0.endedAt ?? .distantFuture) > start }
    }

    /// Adds a session, or replaces it if one with the same `id` already exists
    /// (so a session can be saved when it starts and updated when it ends).
    func saveSession(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        Storage.save(sessions, to: Self.sessionsFile)
    }

    /// At launch nothing can be running, so a session with no end was cut off
    /// by a quit or crash. Closes each one at its planned end, or now if sooner.
    func closeUnfinishedSessions(now: Date = Date()) {
        for session in sessions where session.endedAt == nil {
            let commitment = commitment(withID: session.commitmentId)
            let planned = session.startedAt.addingTimeInterval(Double(commitment?.durationMinutes ?? 0) * 60)
            var closed = session
            closed.endedAt = min(planned, now)
            closed.outcome = .interrupted
            saveSession(closed)
            if let commitment { EventLog.record(.sessionInterrupted, commitment) }
        }
    }

    func session(withID id: Session.ID) -> Session? {
        sessions.first { $0.id == id }
    }

    /// The session whose end-of-session window should come back (once): it
    /// ended in the last 24 hours, the window was closed without answering,
    /// and it hasn't been re-asked yet.
    func sessionNeedingReflection(now: Date = Date()) -> Session? {
        sessions.last { session in
            guard let ended = session.endedAt, now.timeIntervalSince(ended) < 24 * 3600 else { return false }
            return session.reflectionSkippedAt != nil &&
                   session.reflectionReaskedAt == nil &&
                   session.leftOffNote == nil &&
                   (session.outcome == nil || session.outcome == .brokeEarly)
        }
    }

    /// The most recent "where I left off" note for the same commitment.
    ///
    /// "The same" means: for calendar items, the same calendar event (so a weekly
    /// repeating event carries its note from week to week); for manual items,
    /// the same title (ignoring upper/lower case).
    func lastLeftOffNote(for commitment: Commitment) -> String? {
        let matching = sessions.reversed().first { session in
            guard let note = session.leftOffNote, !note.isEmpty else { return false }
            let original = commitments.first { $0.id == session.commitmentId }

            switch commitment.source {
            case .calendar:
                return original?.calendarEventIdentifier != nil &&
                       original?.calendarEventIdentifier == commitment.calendarEventIdentifier
            case .manual:
                // If the original commitment was deleted, the title still matches.
                return original?.source != .calendar &&
                       session.commitmentTitle.caseInsensitiveCompare(commitment.title) == .orderedSame
            }
        }
        return matching?.leftOffNote
    }

    // MARK: - Private

    private func persist() {
        Storage.save(commitments, to: Self.commitmentsFile)
    }

    /// e.g. 14:07 → 14:15, 14:50 → 15:00.
    private static func nextQuarterHour(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let minutesToAdd = 15 - (minute % 15)
        let rounded = calendar.date(byAdding: .minute, value: minutesToAdd, to: date) ?? date
        // Drop the seconds so the time reads cleanly.
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rounded)
        return calendar.date(from: parts) ?? rounded
    }
}
