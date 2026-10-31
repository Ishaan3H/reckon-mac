import AppKit
import Observation
import SwiftUI

/// Which tab the JouleAI window shows, and which commitment is selected.
/// Shared between the window and whoever opens it (the popover's gear and Add buttons).
@MainActor
@Observable
final class MainWindowModel {
    enum Page: String, CaseIterable {
        case commitments = "Commitments"
        case history = "History"
        case settings = "Settings"
    }

    var page: Page = .commitments
    /// The commitment open in the editor.
    var selectedID: UUID?
    /// A brand-new commitment that hasn't been saved yet (from "Add").
    var newDraft: Commitment?
}

/// Opens the JouleAI window (gear icon): commitments and launch targets,
/// history, and settings, as tabs in one window.
///
/// Like the other windows, this is an AppKit `NSWindow` hosting SwiftUI.
@MainActor
final class MainWindowController {

    static let shared = MainWindowController()

    let model = MainWindowModel()
    private var window: NSWindow?

    /// Shows the window on `page`.
    func open(_ page: MainWindowModel.Page, appState: AppState, coordinator: SessionCoordinator) {
        model.page = page
        show(appState: appState, coordinator: coordinator)
    }

    /// Shows the Commitments tab with `commitment` open in the editor.
    func openEditor(for commitment: Commitment, isNew: Bool,
                    appState: AppState, coordinator: SessionCoordinator) {
        model.page = .commitments
        model.newDraft = isNew ? commitment : nil
        model.selectedID = commitment.id
        show(appState: appState, coordinator: coordinator)
    }

    private func show(appState: AppState, coordinator: SessionCoordinator) {
        if window == nil {
            let root = MainWindowView()
                .environment(model)
                .environment(appState)
                .environment(coordinator)
            let host = NSHostingController(rootView: root)
            // The view draws under the title bar, so don't add the title bar's
            // height to the window: that left an empty strip along the bottom.
            host.safeAreaRegions = []
            let window = NSWindow(contentViewController: host)
            // A clean window: no visible title bar, content runs to the top edge.
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "JouleAI"
            window.isReleasedWhenClosed = false
            // SwiftUI hasn't sized the window yet. Centring it now would centre an
            // empty window, and it would then grow off the right of the screen.
            window.setContentSize(host.view.fittingSize)
            window.center()
            self.window = window
        }
        // Menu bar apps aren't "active" by default; bring JouleAI forward.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
