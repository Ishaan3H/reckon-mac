import SwiftUI

/// The Commitments tab: today's items on the left, the selected one's editor
/// (duration and what opens when you press Start) on the right.
struct CommitmentsPage: View {

    @Environment(AppState.self) private var appState
    @Environment(MainWindowModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 260)
            Rectangle().fill(Theme.border).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - List

    /// Today's items, with an unsaved new one (from "Add") at the top.
    private var items: [Commitment] {
        (model.newDraft.map { [$0] } ?? []) + appState.todayItems
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Today").font(Theme.Font.title).foregroundStyle(Theme.text)
                Spacer()
                if appState.calendarAccess == .granted {
                    CalendarRefreshButton(isRefreshing: appState.isReloadingCalendar,
                                          action: appState.reloadCalendar)
                }
                Button {
                    let draft = appState.newManualCommitment()
                    model.newDraft = draft
                    model.selectedID = draft.id
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xl)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        Button { model.selectedID = item.id } label: {
                            listRow(item, isSelected: item.id == model.selectedID)
                        }
                        .buttonStyle(.plain)
                    }
                    if items.isEmpty {
                        Text("Nothing today yet.")
                            .font(Theme.Font.detail)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Space.m)
                    }
                }
                .padding(.horizontal, Theme.Space.s)
            }
        }
    }

    private func listRow(_ item: Commitment, isSelected: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            Button { toggleCommit(item) } label: {
                Image(systemName: item.isCommitted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCommitted ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(item.isCommitted ? "Committed. Click to uncommit." : "Click to commit")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "New commitment" : item.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: Theme.Space.xs) {
                    Text(item.startTime.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("\(item.durationMinutes) min")
                    if !item.launchTargets.isEmpty {
                        Text("·")
                        Image(systemName: "arrow.up.forward.app")
                        Text("\(item.launchTargets.count)")
                    }
                }
                .font(Theme.Font.detail)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if item.source == .calendar {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .padding(.horizontal, Theme.Space.m)
        .background(isSelected ? Theme.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        .contentShape(Rectangle())
    }

    private func toggleCommit(_ item: Commitment) {
        if item.id == model.newDraft?.id {
            model.newDraft?.isCommitted.toggle()    // not saved yet
        } else if item.isCommitted {
            appState.setCommitted(false, for: item.id)
        } else if ConflictWarning.confirm(item, conflicts: appState.conflicts(for: item)) {
            appState.setCommitted(true, for: item.id)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedID,
           let draft = (model.newDraft?.id == id ? model.newDraft : appState.commitment(withID: id)) {
            CommitmentEditorView(
                draft: draft,
                isNew: model.newDraft?.id == id,
                onClose: { saved in
                    model.newDraft = nil
                    if !saved { model.selectedID = nil }
                }
            )
            .id(id)   // a fresh editor (and fresh copy) for each selection
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("Choose a commitment")
                    .font(Theme.Font.bodyEmphasis)
                    .foregroundStyle(Theme.text)
                Text("Set how long it lasts and what opens when you press Start.")
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
