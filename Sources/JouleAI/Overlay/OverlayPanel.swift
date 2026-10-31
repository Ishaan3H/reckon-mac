import AppKit

/// One full-screen, borderless window that sits above everything else on a
/// single display, blurring whatever is underneath.
///
/// `NSPanel` is a kind of window meant for floating helper UI. We customise it so it:
/// - covers the whole screen, including the menu bar and Dock
/// - appears on every Space and over full-screen apps
/// - takes the keyboard away from whatever app is underneath
/// - can't be closed with Escape, Cmd+W, Cmd+Q or Cmd+H
final class OverlayPanel: NSPanel {

    /// Only the panel showing the card takes keyboard input. The blur-only
    /// panels on other displays never do, so they can't steal it from the card.
    private let acceptsKeyboard: Bool

    init(screen: NSScreen, acceptsKeyboard: Bool) {
        self.acceptsKeyboard = acceptsKeyboard

        // `.nonactivatingPanel` is the important part for keyboard capture.
        // Since macOS 14, an app can only *ask* to become the front app, and
        // macOS may say no — which is how your key presses reached the app
        // underneath. A non-activating panel can take the keyboard WITHOUT
        // JouleAI becoming the front app (the same trick Spotlight-style
        // launchers use), so typing always lands on the overlay.
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        // .screenSaver is one of the highest window levels: above normal
        // windows, the menu bar and the Dock.
        level = .screenSaver

        // .canJoinAllSpaces: show on every desktop/Space.
        // .fullScreenAuxiliary: allowed on top of apps in full-screen mode.
        // .stationary: not moved around by Mission Control / Exposé.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false      // stay visible even if another app gets focus
        canHide = false                // survive another app's "Hide Others"
        isReleasedWhenClosed = false   // OverlayController manages the lifetime
        place(on: screen)

        // The blur. `.behindWindow` blurs the other windows and desktop below us.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active           // always blurred, even when not focused
        blur.autoresizingMask = [.width, .height]
        contentView = blur
    }

    /// Sizes the panel to the screen's full frame (menu bar and Dock included),
    /// not `visibleFrame`, so it covers everything. Called once at creation and
    /// again only when displays change.
    func place(on screen: NSScreen) {
        if frame != screen.frame { setFrame(screen.frame, display: false) }
    }

    /// Borderless windows normally can't receive keyboard focus. The card's
    /// panel needs it (for buttons and, in the lock screen, a text field).
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { acceptsKeyboard }

    /// Escape sends `cancelOperation`. Doing nothing here means Escape can't
    /// dismiss the overlay.
    override func cancelOperation(_ sender: Any?) {}

    /// Cmd+W (File ▸ Close) sends `performClose`. Ignore it too.
    override func performClose(_ sender: Any?) {}

    /// Every Cmd-key shortcut (Cmd+Q quit, Cmd+H hide, Cmd+W close, Cmd+V paste…)
    /// is offered to the key window before the app's menus. Returning `true`
    /// means "handled", so the shortcut does nothing while the overlay is up.
    /// (Blocking paste is deliberate: the lock's phrase has to be typed.)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
