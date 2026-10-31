import SwiftUI

/// The app's entry point. `@main` tells Swift to start the program here.
///
/// JouleAI has no normal windows at launch: it only puts an icon in the menu bar.
/// Clicking the icon shows `PopoverView` in a small panel (that's what
/// `.menuBarExtraStyle(.window)` does — without it you'd get a plain menu).
@main
struct JouleAIApp: App {

    /// Created once when the app launches and shared with every view.
    /// `@State` keeps them alive for as long as the app runs.
    @State private var appState: AppState
    @State private var coordinator: SessionCoordinator

    /// The coordinator needs the app state, so both are created here, in order.
    /// (`_appState` is the underlying storage behind the `@State` property.)
    init() {
        LegacyMigration.run()            // bring over data and settings from the old "Reckon" name
        AppSettings.registerDefaults()   // fill in default settings before anything reads them

        // `--calendar-report <file>`: write what the calendar shows JouleAI, and quit.
        if let path = CalendarReport.requestedPath {
            CalendarReport.write(to: path)
            exit(0)
        }

        // `--snapshots <folder>`: render the screens to images and quit (design review).
        if let folder = SnapshotRenderer.requestedDirectory {
            SnapshotRenderer.renderAll(to: folder)
            exit(0)
        }

        // `--export-data`: write the same file as Settings → Export my data
        // (anonymised) to ~/Downloads, print where, and quit.
        if DataExport.isRequested {
            do {
                print(try DataExport.run(anonymise: !CommandLine.arguments.contains("--raw")).path)
                exit(0)
            } catch {
                print("Export failed: \(error)")
                exit(1)
            }
        }

        let state = AppState()
        _appState = State(initialValue: state)
        _coordinator = State(initialValue: SessionCoordinator(appState: state))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)      // makes appState available to all child views
                .environment(coordinator)
        } label: {
            MenuBarLabel(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}

/// What appears in the menu bar: the ✓ icon normally, or the time left
/// (e.g. "23:10") while a session is running.
private struct MenuBarLabel: View {
    let coordinator: SessionCoordinator

    var body: some View {
        if let remaining = coordinator.remainingText {
            Text(remaining).monospacedDigit()
        } else if coordinator.firingCommitment != nil {
            // The Start card is up: it's time, nothing left to count down.
            Text("Start now")
        } else if let untilStart = coordinator.upcomingText {
            // Counting down to the next session, e.g. "in 12:34".
            Text("in \(untilStart)").monospacedDigit()
        } else {
            Image(systemName: "checkmark.circle")
        }
    }
}
