import AppKit

/// One thing a session lets you use: an app, or a website rule.
///
/// Website rules come in three strengths, decided by what you type:
/// - **A domain** (`khanacademy.org`): the whole site, including subdomains.
/// - **A path** (`youtube.com/@3blue1brown`): that page and everything under it.
/// - **A link with `?…`** (`youtube.com/playlist?list=PL123`, `youtube.com/watch?v=abc`):
///   any page on that site carrying those exact values, so a playlist rule also
///   allows its videos while they play inside the playlist.
struct AllowRule: Codable, Identifiable, Hashable {

    enum Kind: String, Codable {
        case app    // value is a bundle ID
        case site   // value is a normalised rule like "youtube.com/@3blue1brown"
    }

    var id = UUID()
    var kind: Kind
    var value: String
    /// Shown in lists: the app's name, or the site rule itself.
    var label: String

    // MARK: - Making rules

    /// A website rule from typed text. Accepts "youtube.com", "www.youtube.com/@x",
    /// or a full pasted link. Returns nil if there's no recognisable site in it.
    static func site(from text: String) -> AllowRule? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let url = URL(string: trimmed),
              let host = SiteMatch.normalizedHost(url), host.contains(".") else { return nil }

        var value = host
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        value += path
        if let query = url.query, !query.isEmpty { value += "?" + query }
        return AllowRule(kind: .site, value: value, label: value)
    }

    /// An app rule from an .app picked in a file panel.
    static func app(from appURL: URL) -> AllowRule? {
        guard let target = LaunchTarget.fromApp(appURL) else { return nil }
        return AllowRule(kind: .app, value: target.value, label: target.label)
    }

    // MARK: - Matching

    /// The rule's parts, re-read from `value`.
    private var siteParts: (host: String, path: String, query: [URLQueryItem])? {
        guard kind == .site, let url = URL(string: "https://" + value), let host = url.host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return (host.lowercased(), url.path.lowercased(), items)
    }

    /// Does this website rule allow `url`?
    func matches(_ url: URL) -> Bool {
        guard let rule = siteParts, let tabHost = SiteMatch.normalizedHost(url) else { return false }

        // Same site (subdomains count: m.youtube.com matches youtube.com).
        guard tabHost == rule.host || tabHost.hasSuffix("." + rule.host) else { return false }

        // A link with ?…: every value in the rule must be in the tab's address.
        if !rule.query.isEmpty {
            let tabItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return rule.query.allSatisfy { item in tabItems.contains { $0.name == item.name && $0.value == item.value } }
        }

        // Just a domain: the whole site.
        if rule.path.isEmpty || rule.path == "/" { return true }

        // A path: that page or anything under it ("/@x" allows "/@x/videos", not "/@xyz").
        let tabPath = url.path.lowercased()
        return tabPath == rule.path || tabPath.hasPrefix(rule.path + "/")
    }

    // MARK: - Soft warnings

    /// Sites that tend to eat sessions, and how to describe allowing them.
    private static let distractions: [String: String] = [
        "youtube.com": "YouTube",
        "instagram.com": "Instagram",
        "x.com": "X",
        "twitter.com": "X",
        "reddit.com": "Reddit",
    ]

    /// A gentle warning if this rule allows a common distraction as a whole.
    /// Narrow rules (one channel, playlist, video or subreddit) get no warning.
    var distractionWarning: String? {
        guard let rule = siteParts, let name = Self.distractions[rule.host],
              rule.query.isEmpty, rule.path.isEmpty || rule.path == "/" else { return nil }
        return name == "YouTube"
            ? "This allows all of YouTube, homepage included. A channel, playlist or video link is safer."
            : "\(name) is a common distraction. This allows all of it."
    }

    var symbolName: String { kind == .app ? "app" : "globe" }
}
