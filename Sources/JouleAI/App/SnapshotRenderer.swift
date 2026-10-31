import AppKit
import SwiftUI

/// Renders JouleAI's screens to PNG files with sample data, in light and dark
/// mode. Used to review the design without clicking through the app:
///
///     build/JouleAI.app/Contents/MacOS/JouleAI --snapshots ~/Desktop/jouleai-shots
///
/// Nothing is started (no scheduler, no notifications) and no data is changed.
@MainActor
enum SnapshotRenderer {

    /// The folder passed after `--snapshots`, if the app was launched that way.
    static var requestedDirectory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshots"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: (args[index + 1] as NSString).expandingTildeInPath)
    }

    static func renderAll(to directory: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, view) in screens {
            for dark in [false, true] {
                let url = directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                render(view, to: url, dark: dark)
            }
        }
        print("Snapshots written to \(directory.path)")
    }

    // MARK: - Sample screens

    private static var screens: [(String, AnyView)] {
        let now = Date()
        let soon = now.addingTimeInterval(12 * 60 + 48)
        let rows = [
            PopoverModel.Row(id: UUID(), title: "Gym", startTime: now.addingTimeInterval(3 * 3600),
                             isCommitted: false, isCancelled: false),
            PopoverModel.Row(id: UUID(), title: "Read: Deep Work ch. 4", startTime: now.addingTimeInterval(5 * 3600),
                             isCommitted: true, isCancelled: false),
            PopoverModel.Row(id: UUID(), title: "Inbox zero", startTime: now.addingTimeInterval(6 * 3600),
                             isCommitted: false, isCancelled: true),
        ]
        let note = "Halfway through section 3. Next: the evaluation table."

        let startingSoon = PopoverModel(
            hero: .next(.init(id: UUID(), title: "Write thesis intro", startTime: soon, durationMinutes: 50,
                              countdown: "12:48", leftOffNote: note, showHeadsUpActions: true,
                              saidReady: false, canPush: true)),
            rows: rows, calendarConnected: true)
        let laterToday = PopoverModel(
            hero: .next(.init(id: UUID(), title: "Write thesis intro", startTime: now.addingTimeInterval(2 * 3600 + 600),
                              durationMinutes: 50, countdown: nil, leftOffNote: note,
                              showHeadsUpActions: false, saidReady: false, canPush: true)),
            rows: rows, calendarConnected: true)
        let overdue = PopoverModel(
            hero: .next(.init(id: UUID(), title: "Write thesis intro", startTime: now.addingTimeInterval(-683),
                              durationMinutes: 50, countdown: nil, leftOffNote: note,
                              showHeadsUpActions: false, saidReady: false, canPush: true,
                              hasStarted: true, canStartNow: true)),
            rows: rows, calendarConnected: true)
        let inSession = PopoverModel(
            hero: .inSession(title: "Write thesis intro", endsAt: now.addingTimeInterval(23 * 60), remaining: "23:10"),
            rows: rows, calendarConnected: true)
        let empty = PopoverModel(hero: .nothingCommitted(hasItems: true), rows: rows, calendarConnected: false)

        let sampleTargets = [
            LaunchTarget(kind: .url, value: "https://docs.google.com/document/d/1AbC/edit", label: "docs.google.com"),
            LaunchTarget(kind: .url, value: "obsidian://open?vault=Uni&file=Thesis", label: "Obsidian: Thesis"),
            LaunchTarget(kind: .app, value: "com.apple.Notes", label: "Notes"),
        ]
        var draft = Commitment(title: "Write thesis intro", startTime: soon, durationMinutes: 50, source: .manual)
        draft.launchTargets = sampleTargets

        func session(_ title: String, _ hoursAgo: Double, _ outcome: Session.Outcome?) -> Session {
            let start = now.addingTimeInterval(-hoursAgo * 3600)
            return Session(commitmentId: UUID(), commitmentTitle: title, startedAt: start,
                           endedAt: start.addingTimeInterval(25 * 60), outcome: outcome)
        }
        var noted = session("Write thesis intro", 2, .done)
        noted.leftOffNote = note
        let sessions = [
            noted,
            session("Inbox zero", 4, .skipped),
            session("Write thesis intro", 26, nil),
            session("Problem set 6", 28, .brokeEarly),
            session("Inbox zero", 30, .partly),
            session("Read: Deep Work ch. 3", 50, nil),
        ]

        return [
            ("popover-starting-soon", AnyView(NextUpView(model: startingSoon, actions: .init()))),
            ("popover-later-today", AnyView(NextUpView(model: laterToday, actions: .init()))),
            ("popover-overdue", AnyView(NextUpView(model: overdue, actions: .init()))),
            ("popover-in-session", AnyView(NextUpView(model: inSession, actions: .init()))),
            ("popover-nothing-committed", AnyView(NextUpView(model: empty, actions: .init()))),
            ("overlay-start", AnyView(backdrop(StartCardView(
                title: "Write thesis intro", startTime: now, durationMinutes: 50, leftOffNote: note,
                canReschedule: true, onStart: {}, onReschedule: {}, onCancel: {})))),
            ("overlay-start-meeting", AnyView(backdrop(StartCardView(
                title: "Weekly sync with Prof. Lee", startTime: now, durationMinutes: 30, leftOffNote: nil,
                canReschedule: true, meetingService: "Google Meet", onStart: {}, onReschedule: {}, onCancel: {})))),
            ("overlay-lock", AnyView(backdrop(LockCardView(
                title: "Write thesis intro", endsAt: now.addingTimeInterval(18 * 60 + 42),
                detail: "That tab isn’t part of this session.", onBackToTask: {}, onBreak: { _ in })))),
            ("end-of-session", AnyView(EndOfSessionView(
                title: "Write thesis intro", endedEarly: false, onSave: { _, _ in }, onSkip: {}))),
            ("end-of-session-parked", AnyView(EndOfSessionView(
                title: "Write thesis intro", endedEarly: false,
                parkedItems: ["Email Prof. Lee about the deadline", "Look up the 2019 survey paper", "Buy printer ink"],
                onSave: { _, _ in }, onSkip: {}))),
            ("parking-lot", AnyView(ZStack {
                Color(white: 0.5)
                ParkingLotView(model: { let m = ParkingLotModel(); m.text = "Email Prof. Lee about the deadline\nLook up the 2019 survey paper"; return m }(),
                               onClose: {}, onMove: { _ in })
            }.frame(width: 360, height: 290))),
            ("end-of-session-early", AnyView(EndOfSessionView(
                title: "Write thesis intro", endedEarly: true, onSave: { _, _ in }, onSkip: {}))),
            ("window-editor", AnyView(CommitmentEditorView(draft: draft, isNew: false, onClose: { _ in })
                .frame(width: 520, height: 1100).background(Theme.background)
                .environment(AppState()))),   // the editor expects the app's data object
            ("window-history", AnyView(HistoryView(sessions: sessions)
                .frame(width: 780, height: 580).background(Theme.background))),
            ("window-settings", AnyView(SettingsPage()
                .frame(width: 780, height: 2350).background(Theme.background)
                .environment(AppState()))),
        ]
    }

    /// Stands in for the blurred screen behind the overlay card.
    private static func backdrop<Card: View>(_ card: Card) -> some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(0.25)
            card
        }
        .frame(width: 900, height: 760)
    }

    // MARK: - Rendering

    /// Draws a view offscreen into a PNG. Uses a hidden window so AppKit-backed
    /// controls (text fields, switches) render as well as plain SwiftUI.
    private static func render(_ view: AnyView, to url: URL, dark: Bool) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))   // let SwiftUI finish drawing

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
