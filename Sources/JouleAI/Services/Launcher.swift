import AppKit

/// Opens launch targets, and works out which apps a session is allowed to use.
@MainActor
enum Launcher {

    /// The browser web links open in during sessions: the one chosen in
    /// Settings, else Chrome, else Safari. Never your default browser if that's
    /// one whose tabs can't be read (like Zen), so the lock can always check.
    static var sessionBrowser: BrowserTabs.Browser {
        let installed = BrowserTabs.installed
        return installed.first { $0.bundleID == AppSettings.sessionBrowserID }
            ?? installed.first { $0.bundleID == "com.google.Chrome" }
            ?? BrowserTabs.browser(withID: "com.apple.Safari")!   // Safari is on every Mac
    }

    /// True for http:// and https:// links.
    static func isWebLink(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// The commitment's web links (the ones the tab check compares against).
    static func webTargets(of commitment: Commitment) -> [URL] {
        commitment.launchTargets.compactMap { target in
            guard target.kind == .url, let url = URL(string: target.value), isWebLink(url) else { return nil }
            return url
        }
    }

    /// Opens every target, in order.
    /// - Web links open in the session browser (Settings), so tabs can be tracked.
    /// - Other URLs and files open in whatever app macOS uses for them
    ///   (Obsidian for obsidian:// links, Word for .docx…).
    /// - Apps are launched (or brought forward if already running).
    static func open(_ targets: [LaunchTarget]) {
        for target in targets {
            switch target.kind {
            case .url:
                guard let url = URL(string: target.value) else { continue }
                if isWebLink(url) {
                    // Web links go to the session browser, so JouleAI can watch its tabs.
                    BrowserTabs.open(url, in: sessionBrowser)
                } else {
                    NSWorkspace.shared.open(url)   // e.g. obsidian:// opens Obsidian
                }
            case .file:
                NSWorkspace.shared.open(URL(fileURLWithPath: target.value))
            case .app:
                bringToFront(bundleID: target.value)
            }
        }
    }

    /// Launches an app, or brings it to the front if it's already running.
    ///
    /// We go through `openApplication` (the same thing as clicking the app in
    /// the Dock) because it reliably brings the app forward, even when JouleAI
    /// itself isn't the front app.
    static func bringToFront(bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            print("JouleAI: no app installed with bundle ID \(bundleID)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// The bundle IDs of the apps this commitment's targets open in, in target
    /// order, followed by the commitment's extra allowed apps. No duplicates.
    ///
    /// For a web link this is the session browser; for other URLs, the app that
    /// handles them (Obsidian for obsidian:// links). For a file, the app that opens it.
    static func allowedApps(for commitment: Commitment) -> [String] {
        var result: [String] = []
        func add(_ id: String?) {
            if let id, !result.contains(id) { result.append(id) }
        }

        for target in commitment.launchTargets {
            switch target.kind {
            case .app:
                add(target.value)
            case .url:
                guard let url = URL(string: target.value) else { continue }
                if isWebLink(url) {
                    add(sessionBrowser.bundleID)   // never the default browser
                } else {
                    add(bundleID(ofAppAt: NSWorkspace.shared.urlForApplication(toOpen: url)))
                }
            case .file:
                let fileURL = URL(fileURLWithPath: target.value)
                add(bundleID(ofAppAt: NSWorkspace.shared.urlForApplication(toOpen: fileURL)))
            }
        }
        return result
    }

    /// Bits of macOS that are always allowed during a session, so they never
    /// trigger the lock:
    /// - **Finder**: macOS falls back to it whenever an app quits or its last
    ///   window closes, and clicking the menu bar or Cmd+Tabbing to a minimised
    ///   app can bring it forward. Blocking it could trap you behind the lock.
    /// - Things that briefly become the "front app" on their own: password
    ///   prompts, notifications, the login window, Control Centre, Spotlight.
    static let systemApps: Set<String> = [
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.dock",
    ]

    private static func bundleID(ofAppAt url: URL?) -> String? {
        guard let url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
