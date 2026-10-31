import SwiftUI
import UniformTypeIdentifiers

/// Opens the log in the Mac's default text editor. macOS has no app registered
/// for ".jsonl" files, so asking it to just open the file gets an error dialog.
@MainActor
private func openActivityLog() {
    let log = Storage.directory.appendingPathComponent(EventLog.fileName)
    guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else {
        NSWorkspace.shared.activateFileViewerSelecting([log])
        return
    }
    NSWorkspace.shared.open([log], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
}

/// The History tab, connected to live data.
struct HistoryPage: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HistoryView(sessions: appState.sessions)
    }
}

/// The last 14 days of sessions: three counts at the top, then a list by day.
/// Takes plain data so it can also be rendered with samples.
struct HistoryView: View {
    let sessions: [Session]

    private var recent: [Session] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        return sessions.filter { $0.startedAt >= cutoff }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Last 14 days").font(Theme.Font.title).foregroundStyle(Theme.text)
                    Text("Every session that fired, and how it went.")
                        .font(Theme.Font.detail).foregroundStyle(Theme.textSecondary)
                }

                stats

                if recent.isEmpty {
                    Text("No sessions yet. Commit to something and it will show up here.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    days
                }

                Button {
                    openActivityLog()
                } label: {
                    Label("Open activity log", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(TextButtonStyle())
            }
            .padding(Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Counts

    private var stats: some View {
        let kept = recent.filter { Outcome(session: $0).isKept }.count
        let skipped = recent.filter { Outcome(session: $0) == .skipped }.count
        let broken = recent.filter { Outcome(session: $0) == .broke }.count
        return HStack(spacing: Theme.Space.m) {
            statTile(kept, "Kept", Theme.accent)
            statTile(skipped, "Skipped", Theme.textSecondary)
            statTile(broken, "Broke early", Theme.danger)
        }
    }

    private func statTile(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(value)")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label).font(Theme.Font.detail).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Space.l)
    }

    // MARK: - List by day

    private var days: some View {
        let grouped = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.startedAt) }
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionLabel(dayLabel(day))
                    VStack(spacing: 0) {
                        let daySessions = grouped[day] ?? []
                        ForEach(daySessions) { session in
                            sessionRow(session)
                            if session.id != daySessions.last?.id {
                                Rectangle().fill(Theme.border).frame(height: 1)
                            }
                        }
                    }
                    .card(padding: 0)
                }
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        let outcome = Outcome(session: session)
        return HStack(spacing: Theme.Space.m) {
            Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                .font(Theme.Font.detail.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.commitmentTitle)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                // The "where I left off" note, if one was written.
                if let note = session.leftOffNote, !note.isEmpty {
                    Text(note)
                        .font(Theme.Font.detail)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(outcome.label)
                .font(Theme.Font.label)
                .tracking(0.4)
                .foregroundStyle(outcome.color)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(outcome.color.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// How a session is shown in history. "Kept" means you sat the whole
    /// session; Done / Partly / Didn't is how you said it went.
    private enum Outcome {
        case done, partly, didnt, keptUnrated, skipped, broke, interrupted, inProgress

        init(session: Session) {
            switch session.outcome {
            case .done: self = .done
            case .partly: self = .partly
            case .didnt: self = .didnt
            case .skipped: self = .skipped
            case .brokeEarly: self = .broke
            case .interrupted: self = .interrupted
            case nil: self = session.endedAt == nil ? .inProgress : .keptUnrated
            }
        }

        var isKept: Bool { [.done, .partly, .didnt, .keptUnrated].contains(self) }

        var label: String {
            switch self {
            case .done: return "DONE"
            case .partly: return "PARTLY"
            case .didnt: return "DIDN’T"
            case .keptUnrated: return "KEPT"
            case .skipped: return "SKIPPED"
            case .broke: return "BROKE EARLY"
            case .interrupted: return "INTERRUPTED"
            case .inProgress: return "IN PROGRESS"
            }
        }

        var color: Color {
            switch self {
            case .done, .keptUnrated: return Theme.accent
            case .partly, .inProgress, .interrupted: return Theme.warning
            case .didnt, .skipped: return Theme.textSecondary
            case .broke: return Theme.danger
            }
        }
    }
}
