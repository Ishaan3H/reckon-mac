import SwiftUI

/// Everything the popover needs to draw, as plain values.
///
/// Keeping the popover's drawing separate from the app's live state means the
/// view is simple to read, and can be rendered with sample data (that's how
/// the design screenshots are made; see SnapshotRenderer).
struct PopoverModel {

    /// The big card at the top: the answer to "what's next?".
    enum Hero {
        case inSession(title: String, endsAt: Date, remaining: String)
        case next(NextItem)
        case nothingCommitted(hasItems: Bool)
    }

    struct NextItem {
        let id: UUID
        let title: String
        let startTime: Date
        let durationMinutes: Int
        /// "12:34" when it starts within 20 minutes; nil when it's further off.
        let countdown: String?
        let leftOffNote: String?
        /// The 20-minute lead-up: show "I'll be ready / Push / Not today".
        let showHeadsUpActions: Bool
        let saidReady: Bool
        let canPush: Bool
        /// e.g. "Google Meet" when the calendar event has a meeting link.
        var meetingService: String? = nil
    }

    /// One of today's other items in the list below the hero.
    struct Row: Identifiable {
        let id: UUID
        let title: String
        let startTime: Date
        let isCommitted: Bool
        let isCancelled: Bool
    }

    var hero: Hero
    var rows: [Row]
    var calendarConnected: Bool
    var calendarRefreshing = false
}

/// What the popover's buttons do. The container fills these in.
struct PopoverActions {
    var openWindow: () -> Void = {}
    var add: () -> Void = {}
    var toggleCommit: (UUID) -> Void = { _ in }
    var ready: (UUID) -> Void = { _ in }
    var push: (UUID) -> Void = { _ in }
    var notToday: (UUID) -> Void = { _ in }
    var connectCalendar: () -> Void = {}
    var refreshCalendar: () -> Void = {}
    var openParkingLot: () -> Void = {}
}

/// The menu bar popover. It answers one question: what's next.
struct NextUpView: View {
    let model: PopoverModel
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.m)

            hero
                .padding(.horizontal, Theme.Space.l)

            if !model.rows.isEmpty {
                laterToday
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.xl)
            }

            if !model.calendarConnected {
                calendarHint
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.l)
            }

            Button(action: actions.add) {
                Label("Add commitment", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle())
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xl)
            .padding(.bottom, Theme.Space.l)
        }
        .frame(width: 340)
        .background(Theme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(Theme.Font.detail.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if model.calendarConnected {
                CalendarRefreshButton(isRefreshing: model.calendarRefreshing,
                                      action: actions.refreshCalendar)
            }
            IconButton(systemName: "gearshape", help: "History, settings and launch targets",
                       action: actions.openWindow)
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        switch model.hero {
        case .inSession(let title, let endsAt, let remaining):
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel("In session")
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(remaining).font(Theme.Font.countdown).foregroundStyle(Theme.accent)
                    Text("left").font(Theme.Font.detail).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("ends \(endsAt.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.Font.detail).foregroundStyle(Theme.textSecondary)
                }
                Button(action: actions.openParkingLot) {
                    Label("Parking lot  ⌘⇧J", systemImage: "square.and.pencil")
                }
                .buttonStyle(TextButtonStyle(color: Theme.accent))
                .padding(.leading, -Theme.Space.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Theme.Space.xl)

        case .next(let item):
            nextCard(item)

        case .nothingCommitted(let hasItems):
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionLabel("Next")
                Text(hasItems ? "Nothing committed yet" : "Your day is clear")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.text)
                Text(hasItems
                     ? "Tap something below to commit to it. JouleAI takes it from there."
                     : "Add a commitment, or put an event in your calendar.")
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Theme.Space.xl)
        }
    }

    private func nextCard(_ item: PopoverModel.NextItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionLabel(item.countdown == nil ? "Next" : "Starting soon")
                Text(item.title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.startTime.formatted(date: .omitted, time: .shortened)) · \(item.durationMinutes) min")
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Countdown: exact to the second in the last 20 minutes,
            // otherwise a live "in 2 hr, 10 min".
            if let countdown = item.countdown {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(countdown).font(Theme.Font.countdown).foregroundStyle(Theme.accent)
                    Text("to go").font(Theme.Font.detail).foregroundStyle(Theme.textSecondary)
                }
            } else {
                (Text("in ") + Text(item.startTime, style: .relative))
                    .font(Theme.Font.countdownSmall)
                    .foregroundStyle(Theme.accent)
            }

            if let service = item.meetingService {
                Label("Meeting link found: will open at start (\(service))", systemImage: "video")
                    .font(Theme.Font.detail.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }

            if let note = item.leftOffNote, !note.isEmpty {
                LeftOffNote(note: note)
            }

            if item.showHeadsUpActions {
                headsUpActions(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Space.xl)
    }

    /// "I'll be ready" as the main action; Push and Not today quieter below it.
    private func headsUpActions(_ item: PopoverModel.NextItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if item.saidReady {
                Label("You said you’ll be ready", systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.detail.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 6)
            } else {
                Button { actions.ready(item.id) } label: {
                    Text("I’ll be ready").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: Theme.Space.s) {
                if item.canPush {
                    Button("Push 30 min") { actions.push(item.id) }
                        .buttonStyle(OutlineButtonStyle())
                }
                Spacer(minLength: 0)
                Button("Not today") { actions.notToday(item.id) }
                    .buttonStyle(TextButtonStyle())
            }
        }
    }

    // MARK: - List

    private var laterToday: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("Later today")
            VStack(spacing: 2) {
                ForEach(model.rows) { row in
                    Button { actions.toggleCommit(row.id) } label: {
                        rowView(row)
                    }
                    .buttonStyle(.plain)
                    .help(row.isCommitted ? "Committed. Click to uncommit." : "Click to commit")
                }
            }
        }
    }

    private func rowView(_ row: PopoverModel.Row) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: row.isCommitted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(row.isCommitted ? Theme.accent : Theme.textTertiary)
            Text(row.title)
                .font(Theme.Font.body)
                .foregroundStyle(row.isCancelled ? Theme.textTertiary : Theme.text)
                .strikethrough(row.isCancelled, color: Theme.textTertiary)
                .lineLimit(1)
            Spacer()
            Text(row.startTime.formatted(date: .omitted, time: .shortened))
                .font(Theme.Font.detail.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())   // the whole row is clickable, not just the text
    }

    private var calendarHint: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "calendar.badge.exclamationmark")
            Text("Calendar not connected")
            Spacer()
            Button("Connect", action: actions.connectCalendar)
                .buttonStyle(TextButtonStyle(color: Theme.accent))
        }
        .font(Theme.Font.detail)
        .foregroundStyle(Theme.textSecondary)
    }
}
