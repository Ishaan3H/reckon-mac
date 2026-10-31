import SwiftUI

/// The note shown when Firefox-style browsers are installed: their tab
/// addresses can't be read, so they're checked by window title (with
/// Accessibility permission) or blocked.
struct UnreadableBrowsersNote: View {
    var body: some View {
        let names = BrowserTabs.installedUnreadableNames
        if !names.isEmpty {
            let list = names.joined(separator: " and ")
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(systemName: "info.circle").foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(WindowTitleReader.isAllowed
                         ? "\(list): checked by window title. Playlist and video links can’t be recognised there, so use Chrome or Safari for those."
                         : "\(list): blocked during sessions that open a website, because JouleAI needs Accessibility permission to see which page \(names.count == 1 ? "it’s" : "they’re") on. Links open in Chrome or Safari.")
                        .fixedSize(horizontal: false, vertical: true)
                    if !WindowTitleReader.isAllowed {
                        Button("Allow page checking…") { WindowTitleReader.requestPermission() }
                            .buttonStyle(TextButtonStyle(color: Theme.accent))
                            .padding(.leading, -Theme.Space.s)
                    }
                }
            }
            .font(Theme.Font.detail)
            .foregroundStyle(Theme.textSecondary)
        }
    }
}
