import Foundation

/// Mutes the Mac's sound output when the overlay appears, and puts it back
/// exactly as it was afterwards.
///
/// The key rule: only ever unmute audio that *JouleAI* muted. If you had already
/// muted your Mac yourself, JouleAI leaves it muted.
///
/// It uses AppleScript's built-in volume commands, run through `NSAppleScript`.
@MainActor
final class AudioMuter {

    private static let didMuteKey = "didMuteAudio"

    /// True while audio is muted because of JouleAI (not because of you). Saved,
    /// so if JouleAI crashes while muting, the next launch can put the sound back.
    private(set) var didMute = UserDefaults.standard.bool(forKey: didMuteKey) {
        didSet { UserDefaults.standard.set(didMute, forKey: Self.didMuteKey) }
    }

    /// Mutes output unless it's already muted. Safe to call more than once.
    func mute() {
        guard !didMute else { return }   // already muted by us
        guard let alreadyMuted = isOutputMuted() else { return }  // couldn't tell: do nothing
        if !alreadyMuted {
            run("set volume with output muted")
            didMute = true
        }
    }

    /// Unmutes output, but only if JouleAI was the one who muted it.
    func restore() {
        guard didMute else { return }
        run("set volume without output muted")
        didMute = false
    }

    /// Turns sound on no matter who muted it. Used only for meeting sessions,
    /// where a call without sound is useless.
    func forceUnmute() {
        run("set volume without output muted")
        didMute = false
    }

    // MARK: - Private

    /// Asks macOS whether output is muted. Returns `nil` if the script failed.
    private func isOutputMuted() -> Bool? {
        run("output muted of (get volume settings)")?.booleanValue
    }

    /// Runs one line of AppleScript and returns its result (or `nil` on error).
    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            print("JouleAI: AppleScript failed (\(source)): \(error)")
            return nil
        }
        return result
    }
}
