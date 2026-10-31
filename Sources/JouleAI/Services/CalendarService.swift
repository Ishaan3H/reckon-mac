import EventKit
import Foundation

/// Talks to the Mac's Calendar database through Apple's EventKit framework.
///
/// Any calendar account added to the Mac (iCloud, Google, Exchange…) shows up
/// here, because EventKit reads the same data the Calendar app shows.
final class CalendarService {

    /// Where we stand with calendar permission, simplified for the UI.
    enum Access {
        case notDetermined   // never asked yet
        case granted         // full access
        case denied          // denied, restricted, or only "add events" access
    }

    /// The object that gives us access to calendar data. Apple recommends
    /// creating one and keeping it for the life of the app.
    let store = EKEventStore()

    /// Reads the current permission state without prompting the user.
    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:    return .granted
        case .notDetermined: return .notDetermined
        default:             return .denied   // .denied, .restricted, .writeOnly
        }
    }

    /// Shows the system "JouleAI would like to access your calendar" prompt
    /// (only the first time; later calls return the remembered answer).
    /// `async` means the caller waits for the user's answer without freezing the app.
    func requestAccess() async -> Access {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            print("JouleAI: calendar access request failed: \(error)")
        }
        return access
    }

    /// Drops what this app has cached and asks macOS to check the calendar
    /// accounts (Google, iCloud…) for new data. Anything that arrives later
    /// triggers EKEventStoreChanged, which AppState already listens for.
    func reload() {
        store.reset()
        store.refreshSourcesIfNecessary()
    }

    /// Today's timed events (all-day events are skipped, since they have no
    /// meaningful start time), sorted by start time.
    func todaysEvents() -> [EKEvent] {
        guard access == .granted else { return [] }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }

        // A "predicate" is a search query. calendars: nil means "all calendars".
        let predicate = store.predicateForEvents(withStart: startOfToday,
                                                 end: startOfTomorrow,
                                                 calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate >= startOfToday }
            .sorted { $0.startDate < $1.startDate }
    }
}
