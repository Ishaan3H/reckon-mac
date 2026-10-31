import SwiftUI
import UniformTypeIdentifiers

/// The editor for one commitment: title and time (manual items), session length,
/// and what opens when you press Start. Shown on the right of the Commitments tab.
///
/// It works on a *copy* of the commitment (`draft`). Nothing is saved until you
/// press Save, so Cancel really does throw your changes away.
struct CommitmentEditorView: View {

    @Environment(AppState.self) private var appState

    /// The working copy being edited. `@State` lets the form change it.
    @State var draft: Commitment
    let isNew: Bool
    /// Called when the editor is done: `true` after Save, `false` after Cancel or Delete.
    let onClose: (_ saved: Bool) -> Void
    /// For an unsaved new commitment: what its circle in the list is set to.
    var newDraftIsCommitted: () -> Bool? = { nil }

    /// Text typed into the "Add URL" field before pressing Add.
    @State private var urlText = ""
    /// Shown under the URL field when the typed text isn't a valid URL.
    @State private var urlError: String?

    /// True when "Custom" is selected for the session length.
    @State private var isCustomLength = false
    /// What's typed in the custom minutes box. Kept as text so you can clear
    /// it and type a new number without it snapping back while you type.
    @State private var customMinutesText = ""

    /// Custom lengths can be anything from 1 minute to 8 hours.
    static let customRange = 1...480

    private var isCalendar: Bool { draft.source == .calendar }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    detailsSection
                    lengthSection
                    targetsSection
                    allowSection
                }
                .padding(Theme.Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            buttons
                .padding(.horizontal, Theme.Space.xxl)
                .padding(.vertical, Theme.Space.l)
        }
        .onAppear {
            // Opening a commitment that already has a non-preset length?
            // Start with "Custom" selected and its number filled in.
            isCustomLength = ![25, 50].contains(draft.durationMinutes)
            customMinutesText = String(draft.durationMinutes)
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if isCalendar {
                // Calendar events own their title and time; edit them in Calendar.
                Text(draft.title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.text)
                Label("\(draft.startTime.formatted(date: .omitted, time: .shortened)) · from your calendar",
                      systemImage: "calendar")
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                TextField("", text: $draft.title, prompt: Text("What will you do?"))
                    .textFieldStyle(.plain)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.text)
                HStack(spacing: Theme.Space.s) {
                    Text("Starts at").font(Theme.Font.detail).foregroundStyle(Theme.textSecondary)
                    DatePicker("", selection: $draft.startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }
        }
    }

    private var lengthSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel("Session length")
            // Two presets plus "Custom" (value 0).
            ChipPicker(options: [("25 min", 25), ("50 min", 50), ("Custom", 0)],
                       selection: Binding(
                get: { isCustomLength ? 0 : draft.durationMinutes },
                set: { newValue in
                    if newValue == 0 {
                        isCustomLength = true
                        customMinutesText = String(draft.durationMinutes)
                    } else {
                        isCustomLength = false
                        draft.durationMinutes = newValue
                    }
                }
            ))

            if isCustomLength {
                HStack(spacing: Theme.Space.s) {
                    // Type any number...
                    TextField("", text: $customMinutesText, prompt: Text("90"))
                        .fieldStyle()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: customMinutesText) { _, text in
                            applyCustomMinutes(text)
                        }
                    // ...or nudge it up and down by 1.
                    Stepper("", value: Binding(
                        get: { draft.durationMinutes },
                        set: { newValue in
                            draft.durationMinutes = newValue
                            customMinutesText = String(newValue)
                        }
                    ), in: Self.customRange)
                    .labelsHidden()
                    Text("minutes").font(Theme.Font.body).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel("Opens when you press Start")

            if draft.launchTargets.isEmpty {
                Text("Nothing yet. Add the page, file or app you need to begin.")
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(draft.launchTargets) { target in
                        targetRow(target)
                        if target.id != draft.launchTargets.last?.id {
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                    }
                }
                .card(padding: 0)
            }

            // Add a URL (web page, Google Doc, obsidian:// link...)
            HStack(spacing: Theme.Space.s) {
                TextField("", text: $urlText, prompt: Text("Paste a link: https://… or obsidian://…"))
                    .fieldStyle()
                    .onSubmit(addURL)   // pressing Return adds it too
                Button("Add", action: addURL)
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let urlError {
                Text(urlError).font(Theme.Font.detail).foregroundStyle(Theme.danger)
            }

            HStack(spacing: Theme.Space.s) {
                Button { pickFile() } label: { Label("Add file…", systemImage: "doc") }
                    .buttonStyle(OutlineButtonStyle())
                Button { pickApp() } label: { Label("Add app…", systemImage: "app") }
                    .buttonStyle(OutlineButtonStyle())
            }
        }
    }

    /// Which apps and websites the session lock lets you use.
    private var allowSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel("Allowed during the session")
            Text("What opens on Start is always allowed, and so is Finder. Add a preset, and any other apps or sites you’ll need.")
                .font(Theme.Font.detail)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.s) {
                Text("Preset").font(Theme.Font.body).foregroundStyle(Theme.text)
                Picker("", selection: $draft.presetID) {
                    Text("None").tag(UUID?.none)
                    ForEach(appState.presets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            if let preset = appState.preset(withID: draft.presetID) {
                Text(preset.rules.isEmpty ? "This preset is empty. Edit it in Settings."
                                          : preset.rules.map(\.label).joined(separator: " · "))
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }

            AllowRulesEditor(rules: Binding(
                get: { draft.allowRules ?? [] },
                set: { draft.allowRules = $0 }
            ))

            if watchesWeb {
                Text("Tip: a YouTube channel rule covers the channel’s pages, not its videos. Use a playlist link to allow a set of videos.")
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                UnreadableBrowsersNote()
            }
        }
    }

    /// True when this commitment will check browser tabs (it has any web link or rule).
    private var watchesWeb: Bool {
        let presetRules = appState.preset(withID: draft.presetID)?.rules ?? []
        return !Launcher.webTargets(of: draft).isEmpty
            || (presetRules + (draft.allowRules ?? [])).contains { $0.kind == .site }
    }

    private func targetRow(_ target: LaunchTarget) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: target.symbolName)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.label)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(target.value)
                    .font(Theme.Font.detail)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                draft.launchTargets.removeAll { $0.id == target.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(TextButtonStyle())
            .help("Remove")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }

    private var buttons: some View {
        HStack(spacing: Theme.Space.s) {
            if !isNew && !isCalendar {
                Button("Delete") {
                    appState.delete(draft.id)
                    onClose(false)
                }
                .buttonStyle(TextButtonStyle(color: Theme.danger))
            }
            Spacer()
            Button("Cancel") { onClose(false) }
                .buttonStyle(TextButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                draft.title = draft.title.trimmingCharacters(in: .whitespaces)
                // The list's circle may have changed this since the editor opened.
                if let saved = appState.commitment(withID: draft.id) {
                    draft.isCommitted = saved.isCommitted
                    draft.cancelledAt = saved.cancelledAt
                    if saved.durationMinutes != draft.durationMinutes { draft.hasCustomLength = true }
                } else if let committed = newDraftIsCommitted() {
                    draft.isCommitted = committed
                }
                // A committed item whose new time clashes gets the same warning.
                if draft.isCommitted,
                   !ConflictWarning.confirm(draft, conflicts: appState.conflicts(for: draft)) {
                    return
                }
                appState.save(draft)
                onClose(true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    /// Reads the typed text and, if it's a whole number of minutes, uses it
    /// (limited to 1–480). Anything else (like an empty box mid-edit) is ignored.
    private func applyCustomMinutes(_ text: String) {
        let digits = text.filter(\.isNumber)
        if digits != text { customMinutesText = digits }   // drop letters and symbols
        guard let minutes = Int(digits) else { return }
        draft.durationMinutes = min(max(minutes, Self.customRange.lowerBound), Self.customRange.upperBound)
    }

    private func addURL() {
        guard let target = LaunchTarget.fromTypedURL(urlText) else {
            urlError = "That doesn't look like a valid URL."
            return
        }
        draft.launchTargets.append(target)
        urlText = ""
        urlError = nil
    }

    /// Shows the standard macOS "Open" panel to choose one or more files.
    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true   // folders are fine too; they open in Finder
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            draft.launchTargets += panel.urls.map(LaunchTarget.fromFile)
        }
    }

    /// Shows the "Open" panel in /Applications, limited to apps.
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            draft.launchTargets += panel.urls.compactMap(LaunchTarget.fromApp)
        }
    }
}
