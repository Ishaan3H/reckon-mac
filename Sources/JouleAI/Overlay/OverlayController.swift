import AppKit
import Observation
import SwiftUI

/// What the overlay is currently showing. The panels' SwiftUI views watch
/// this, so changing the card never rebuilds a window.
@MainActor
@Observable
final class OverlayContent {
    var card: AnyView?
    /// Changes each time the overlay appears from hidden, so a new card starts
    /// fresh (its countdowns and text fields reset) instead of reusing old state.
    var showID = UUID()
}

/// Shows and hides the blur overlay across every connected display.
///
/// The panels are long-lived: one per screen, created the first time the
/// overlay is needed and then kept. Showing it again only swaps the card and
/// brings the existing panels forward, so the blur (an NSVisualEffectView that
/// stays alive inside each panel) never has to redraw from scratch, and the
/// card never jumps. Panel frames change only when displays change.
///
/// While visible it also asks macOS to hide the Dock and block Cmd+Tab
/// (Force Quit still works).
@MainActor
final class OverlayController {

    /// What happened, for the event log: shown from hidden, re-asserted while
    /// already visible, or hidden. `trigger` is what caused it (e.g. a bundle ID).
    enum Change { case shown, reasserted, hidden }
    var onChange: ((Change, String?) -> Void)?

    private let content = OverlayContent()
    /// One panel per screen, keyed by the display's ID.
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    /// The panel with the card (on the menu-bar screen); the only one that takes keys.
    private var keyPanel: OverlayPanel?
    private var keyScreenID: CGDirectDisplayID?

    private(set) var isVisible = false
    /// True if macOS says the card's panel can actually be seen right now.
    /// (`isVisible` only means we asked for it to be shown.)
    var isOnScreen: Bool { keyPanel?.occlusionState.contains(.visible) ?? false }
    /// The presentation options in force before we hid the Dock / blocked Cmd+Tab.
    private var savedPresentationOptions: NSApplication.PresentationOptions?

    init() {
        let center = NotificationCenter.default

        // Displays plugged in, removed or rearranged: re-fit the panels (the
        // only time their frames change).
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refitPanels() }
        }

        // JouleAI became the active app while the overlay is up: that's the
        // moment macOS lets us block Cmd+Tab.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.lockAppSwitching()
            }
        }
    }

    // MARK: - Show / hide

    /// Covers every screen and shows `card` centred on the main screen.
    /// If the overlay is already up, this swaps the card and re-asserts it.
    func show<Card: View>(_ card: Card, trigger: String? = nil) {
        content.card = AnyView(card)
        if isVisible {
            reassert(trigger: trigger)
            return
        }
        content.showID = UUID()
        ensurePanels()
        isVisible = true
        for panel in panels.values {
            panel.alphaValue = 1        // no fade: it's simply there
            panel.orderFrontRegardless()
        }
        bringForward()
        onChange?(.shown, trigger)
    }

    /// Already visible: bring the existing panels back to the front and take
    /// the keyboard. Creates nothing.
    func reassert(trigger: String?) {
        guard isVisible else { return }
        for panel in panels.values { panel.orderFrontRegardless() }
        bringForward()
        onChange?(.reasserted, trigger)
    }

    /// Hides the overlay. The panels are kept for next time.
    func hide(reason: String? = nil) {
        guard isVisible else { return }
        isVisible = false
        for panel in panels.values { panel.orderOut(nil) }
        restoreAppSwitching()
        onChange?(.hidden, reason)
    }

    /// The emergency exit: take every panel down and give back Cmd+Tab and the
    /// Dock, whatever state things are in, even if the overlay thinks it's hidden.
    func forceHide(reason: String) {
        let wasVisible = isVisible
        isVisible = false
        for panel in panels.values { panel.orderOut(nil) }
        if let saved = savedPresentationOptions {
            NSApp.presentationOptions = saved
            savedPresentationOptions = nil
        } else if NSApp.presentationOptions.contains(.disableProcessSwitching) {
            NSApp.presentationOptions = []
        }
        if wasVisible { onChange?(.hidden, reason) }
    }

    /// Makes the card's panel the window that receives key presses.
    func grabKeyboard() {
        guard isVisible else { return }
        keyPanel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Private

    private func bringForward() {
        // Ask to become the front app (macOS may decline; the non-activating
        // panel takes the keyboard either way).
        NSApp.activate()
        keyPanel?.makeKey()
        lockAppSwitching()
    }

    /// The display ID macOS uses for a screen.
    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Creates any missing panels (first use, or a new display). Never called
    /// to replace panels that already exist.
    private func ensurePanels() {
        // The first screen in the list is the one with the menu bar.
        let mainID = NSScreen.screens.first.map(Self.displayID)

        for screen in NSScreen.screens {
            let id = Self.displayID(of: screen)
            if let existing = panels[id] {
                existing.place(on: screen)
                continue
            }
            let isMain = (id == mainID)
            let panel = OverlayPanel(screen: screen, acceptsKeyboard: isMain)
            if isMain { attachCard(to: panel) }
            panels[id] = panel
        }
        keyScreenID = mainID
        keyPanel = mainID.flatMap { panels[$0] }
        watchKeyboard()
    }

    /// Puts the SwiftUI card view inside a panel, over its blur.
    private func attachCard(to panel: OverlayPanel) {
        guard let blur = panel.contentView else { return }
        let host = NSHostingView(rootView: OverlayRoot(content: content))
        // Don't let SwiftUI resize the window to fit the card: the panel is
        // always exactly the screen, and the card is centred inside it.
        host.sizingOptions = []
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
    }

    /// Displays changed: drop panels for screens that are gone, add panels for
    /// new ones, and re-fit the rest to their screen's full frame.
    private func refitPanels() {
        guard !panels.isEmpty else { return }
        let screens = NSScreen.screens
        let ids = Set(screens.map(Self.displayID))
        let mainID = screens.first.map(Self.displayID)

        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        // The menu-bar screen changed: the card has to move to the new one.
        if mainID != keyScreenID {
            panels.values.forEach { $0.orderOut(nil) }
            panels.removeAll()
        }
        ensurePanels()
        if isVisible {
            for panel in panels.values { panel.orderFrontRegardless() }
            keyPanel?.makeKey()
        }
    }

    /// If something takes the keyboard from the card while the overlay is up,
    /// take it back, unless it's another JouleAI window (the parking lot).
    private var keyObserver: NSObjectProtocol?
    private func watchKeyboard() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        guard let keyPanel else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: keyPanel, queue: .main
        ) { [weak self] _ in
            // A tiny delay lets the other app finish its switch before we take
            // focus back; otherwise it can win the race.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated {
                    if let key = NSApp.keyWindow, !(key is OverlayPanel) { return }
                    self?.grabKeyboard()
                }
            }
        }
    }

    /// Hides the Dock and blocks Cmd+Tab. macOS only allows this while JouleAI
    /// is the active app; if it isn't yet, `didBecomeActive` tries again.
    /// Force Quit (Cmd+Option+Esc) is deliberately left working.
    private func lockAppSwitching() {
        guard NSApp.isActive else { return }
        if savedPresentationOptions == nil { savedPresentationOptions = NSApp.presentationOptions }
        NSApp.presentationOptions = [.hideDock, .disableProcessSwitching]
    }

    private func restoreAppSwitching() {
        guard let saved = savedPresentationOptions else { return }
        NSApp.presentationOptions = saved
        savedPresentationOptions = nil
    }
}

/// The SwiftUI side of the card panel: dims the blur slightly and keeps the
/// card dead centre at any size, so it can't jump or get cut off.
private struct OverlayRoot: View {
    let content: OverlayContent

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            if let card = content.card {
                card.id(content.showID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
