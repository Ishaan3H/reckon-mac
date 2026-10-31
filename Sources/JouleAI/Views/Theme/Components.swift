import SwiftUI

// Small building blocks shared by every screen, so buttons, fields and
// sections look the same everywhere. None of these use the default Form look.

// MARK: - Buttons

/// The one main action on a screen: solid olive, full weight.
struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .system(size: 17, weight: .semibold) : Theme.Font.bodyEmphasis)
            .lineLimit(1)
            .fixedSize(horizontal: !large, vertical: false)   // never wrap a short label
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, large ? 14 : 9)
            .padding(.horizontal, large ? 24 : 16)
            .frame(maxWidth: large ? .infinity : nil)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// A supporting action: outlined, quieter than primary.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.detail.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(Theme.text)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? Theme.sunken : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// The least important actions: just text, slightly highlighted when pressed.
struct TextButtonStyle: ButtonStyle {
    var color: Color = Theme.textSecondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.detail.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(configuration.isPressed ? Theme.sunken : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// A round icon-only button, e.g. the gear in the popover.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Reloads the calendar events. Shows a small spinner while it's working.
struct CalendarRefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else {
            IconButton(systemName: "arrow.clockwise", help: "Reload calendar events", action: action)
        }
    }
}

// MARK: - Text

/// Small uppercase label above a group, e.g. "LATER TODAY".
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Containers

extension View {
    /// A raised card: surface colour, hairline border, rounded corners.
    func card(padding: CGFloat = Theme.Space.l) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    /// Text-field look: inset, rounded, no system border.
    func fieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.text)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
    }
}

/// The "where you left off" note, used in the popover and on the overlay.
struct LeftOffNote: View {
    let note: String
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel("Where you left off")
            Text(note)
                .font(large ? .system(size: 18) : Theme.Font.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(large ? Theme.Space.l : Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
    }
}

/// A row of pill-shaped choices, used instead of the system segmented control.
struct ChipPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(Theme.Font.detail.weight(.medium))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.text)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(isSelected ? Theme.accent : Theme.sunken, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One settings line: title and explanation on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.detail)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.l)
            control
        }
    }
}
