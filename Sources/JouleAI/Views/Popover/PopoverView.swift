import SwiftUI

/// Connects the popover's drawing (`NextUpView`) to the live app state.
///
/// It reads AppState and SessionCoordinator, turns them into a `PopoverModel`,
/// and wires each button to the action that already existed before the
/// redesign. No behaviour lives here, only translation.
struct PopoverView: View {

    @Environment(AppState.self) private var appState
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        NextUpView(model: model, actions: actions)
            // Refresh every time the popover appears, so the list is never stale.
            .onAppear {
                appState.refresh()
                appState.syncCalendar()
                // A skipped "Where did you leave off?" comes back once, here.
                coordinator.offerPendingReflection()
            }
    }

    // MARK: - Model

    private var model: PopoverModel {
        let items = appState.todayItems
        let now = Date()

        // The hero: the running session, or else the next committed item that
        // hasn't been started, skipped or cancelled and whose slot isn't over.
        var heroID: UUID?
        let hero: PopoverModel.Hero
        if let active = coordinator.activeSession {
            heroID = active.commitment.id
            hero = .inSession(title: active.commitment.title,
                              endsAt: active.endsAt,
                              remaining: coordinator.remainingText ?? "")
        } else if let next = items.first(where: {
            $0.isCommitted && !$0.isCancelled && !appState.hasSession(for: $0.id) && $0.endTime > now
        }) {
            heroID = next.id
            let isLeadUp = coordinator.upcoming?.id == next.id
            hero = .next(.init(
                id: next.id,
                title: next.title,
                startTime: next.startTime,
                durationMinutes: next.durationMinutes,
                countdown: isLeadUp ? coordinator.upcomingText : nil,
                leftOffNote: appState.lastLeftOffNote(for: next),
                showHeadsUpActions: isLeadUp,
                saidReady: next.headsUpResponse == .ready,
                canPush: next.canReschedule,
                meetingService: next.meetingLink.flatMap(MeetingLink.init(string:))?.service.rawValue
            ))
        } else {
            hero = .nothingCommitted(hasItems: items.contains { $0.endTime > now })
        }

        // Everything else still to come today.
        let rows = items
            .filter { $0.id != heroID && $0.endTime > now }
            .map { PopoverModel.Row(id: $0.id, title: $0.title, startTime: $0.startTime,
                                    isCommitted: $0.isCommitted, isCancelled: $0.isCancelled) }

        return PopoverModel(hero: hero, rows: rows,
                            calendarConnected: appState.calendarAccess == .granted,
                            calendarRefreshing: appState.isReloadingCalendar)
    }

    // MARK: - Actions

    private var actions: PopoverActions {
        PopoverActions(
            openWindow: {
                MainWindowController.shared.open(.commitments, appState: appState, coordinator: coordinator)
            },
            add: {
                MainWindowController.shared.openEditor(for: appState.newManualCommitment(), isNew: true,
                                                       appState: appState, coordinator: coordinator)
            },
            toggleCommit: { id in
                guard let item = appState.commitment(withID: id) else { return }
                if item.isCommitted {
                    appState.setCommitted(false, for: id)
                } else if ConflictWarning.confirm(item, conflicts: appState.conflicts(for: item)) {
                    appState.setCommitted(true, for: id)
                }
            },
            ready: { coordinator.respond(.ready, to: $0, via: "menu bar") },
            push: { coordinator.respond(.push, to: $0, via: "menu bar") },
            notToday: { coordinator.respond(.notToday, to: $0, via: "menu bar") },
            connectCalendar: {
                if appState.calendarAccess == .notDetermined {
                    appState.requestCalendarAccess()
                } else {
                    appState.openCalendarPrivacySettings()
                }
            },
            refreshCalendar: { appState.reloadCalendar() },
            openParkingLot: { coordinator.toggleParkingLot() }
        )
    }
}
