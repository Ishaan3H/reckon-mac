import AppKit

/// Everything a running session allows, worked out once when you press Start.
///
/// What opens on Start is what's allowed: the launch targets' apps and web
/// links, plus a calendar event's meeting link.
///
/// The lock asks it two questions: "may this app be in front?" and "may this
/// browser tab be open?".
@MainActor
struct SessionAllowlist {

    /// Allowed apps, most important first (launch-target apps lead, so
    /// "Back to task" returns to the app you started in).
    private(set) var apps: [String] = []
    /// Website rules from the meeting link and narrowed launch links.
    private(set) var siteRules: [AllowRule] = []
    /// Launch-target links that allow their whole site (e.g. your Google Doc
    /// allows docs.google.com, so you can open its sibling docs and sign in).
    private(set) var targetSites: [URL] = []
    /// Launch-target links, used to find "your" tab again.
    private(set) var targetLinks: [URL] = []

    /// True when this session has any website rules, so browsers are checked.
    var watchesWeb: Bool { !siteRules.isEmpty || !targetSites.isEmpty }

    /// Launch links on these sites only allow that exact page, not the whole
    /// site, so a YouTube playlist target doesn't open up all of YouTube.
    private static let narrowSites: Set<String> = [
        "youtube.com", "instagram.com", "x.com", "twitter.com", "reddit.com", "tiktok.com", "facebook.com",
    ]

    init(commitment: Commitment, meeting: MeetingLink? = nil) {
        func addApp(_ id: String?) {
            if let id, !apps.contains(id) { apps.append(id) }
        }

        // 0. A meeting from the calendar event: only that meeting site (e.g.
        //    meet.google.com), the browser it opens in, and the call app it may
        //    hand over to (Zoom, Teams). Its tab is "your" tab for Back to task.
        if let meeting {
            addApp(Launcher.sessionBrowser.bundleID)
            meeting.appBundleIDs.forEach { addApp($0) }
            if let site = AllowRule.site(from: meeting.host) { siteRules.append(site) }
            targetLinks.append(meeting.url)
        }

        // 1. Launch targets.
        for app in Launcher.allowedApps(for: commitment) { addApp(app) }
        for link in Launcher.webTargets(of: commitment) {
            targetLinks.append(link)
            if let host = SiteMatch.normalizedHost(link), Self.narrowSites.contains(host),
               let exact = AllowRule.site(from: link.absoluteString) {
                siteRules.append(exact)
            } else {
                targetSites.append(link)
            }
        }
    }

    // MARK: - The two questions

    /// May this app be in front during the session?
    ///
    /// With website rules, browsers may be used, but only if their pages can be
    /// checked: Safari and Chromium browsers by tab address, Firefox-based ones
    /// (Zen, Firefox) by window title, which needs Accessibility permission.
    /// A browser whose pages can't be checked is never allowed automatically.
    func allowsApp(_ bundleID: String) -> Bool {
        if bundleID == Bundle.main.bundleIdentifier || Launcher.systemApps.contains(bundleID) { return true }
        if apps.contains(bundleID) { return true }   // you listed it yourself: allowed whole
        guard watchesWeb else { return false }
        if BrowserTabs.browser(withID: bundleID) != nil { return true }
        if BrowserTabs.unreadable[bundleID] != nil { return WindowTitleReader.isAllowed }
        return false
    }

    /// True if this app was allowed by name (a launch target or an app rule),
    /// so its pages aren't checked.
    func explicitlyAllows(_ bundleID: String) -> Bool { apps.contains(bundleID) }

    /// May a Firefox-based browser window with this title be in front?
    ///
    /// Titles look like "Calculus | Khan Academy — Zen Browser". A site counts
    /// as matching when every word of its name appears in the title
    /// (khanacademy.org → "khanacademy"; docs.google.com → "docs" + "google").
    /// A path rule also needs its last part (youtube.com/@3blue1brown →
    /// "3blue1brown"). Playlist and video links can't be recognised from a
    /// title, so in these browsers they don't match: use Chrome or Safari.
    func allowsTitle(_ rawTitle: String) -> Bool {
        let title = Self.stripBrowserName(rawTitle)
        let squashed = Self.squash(title)
        // Empty, new or private tab: nothing to judge yet.
        if squashed.isEmpty || ["newtab", "privatebrowsing", "newprivatetab"].contains(squashed) { return true }
        if squashed.contains("signin") || squashed.contains("googleaccounts") { return true }

        let hosts = targetSites.compactMap(SiteMatch.normalizedHost)
        if hosts.contains(where: { Self.titleMentions(squashed, host: $0) }) { return true }

        return siteRules.contains { rule in
            guard let url = URL(string: "https://" + rule.value), let host = SiteMatch.normalizedHost(url),
                  url.query == nil, Self.titleMentions(squashed, host: host) else { return false }
            let lastPart = Self.squash(url.lastPathComponent)
            return lastPart.isEmpty || squashed.contains(lastPart)
        }
    }

    /// Every word of the site's name is in the title.
    private static func titleMentions(_ squashedTitle: String, host: String) -> Bool {
        var labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return false }
        labels.removeLast()                                         // "org", "com"…
        if let last = labels.last, ["co", "com", "ac", "org"].contains(last), labels.count > 1 {
            labels.removeLast()                                     // "co" in .co.uk
        }
        let words = labels.filter { !["www", "m", "app"].contains($0) }.map(squash)
        return !words.isEmpty && words.allSatisfy { squashedTitle.contains($0) }
    }

    /// Removes " — Zen Browser", " - Mozilla Firefox" and similar from the end.
    private static func stripBrowserName(_ title: String) -> String {
        let suffixes = ["Zen Browser", "Zen", "Mozilla Firefox", "Firefox Developer Edition",
                        "Firefox Nightly", "Firefox", "LibreWolf", "Waterfox"]
        for separator in [" — ", " – ", " - "] {
            for suffix in suffixes where title.hasSuffix(separator + suffix) {
                return String(title.dropLast(separator.count + suffix.count))
            }
        }
        return suffixes.contains(title) ? "" : title
    }

    /// Lowercase letters and digits only: "Khan Academy" → "khanacademy".
    private static func squash(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// May a tab with this address be open?
    func allowsAddress(_ address: String) -> Bool {
        guard let url = URL(string: address), SiteMatch.isWeb(url) else { return true }   // new tab, settings…
        if let host = url.host?.lowercased(), SiteMatch.signInHosts.contains(host) { return true }
        return allowsWebPage(url)
    }

    /// Does a web page match a launch site or a rule?
    func allowsWebPage(_ url: URL) -> Bool {
        targetSites.contains { SiteMatch.isSameSite(url, $0) } || siteRules.contains { $0.matches(url) }
    }

    /// Where "Back to task" sends a browser when no allowed tab is open:
    /// your first launch link, else the first website rule.
    var fallbackPage: URL? {
        targetLinks.first ?? siteRules.first.flatMap { URL(string: "https://" + $0.value) }
    }
}
