import AppKit
import SwiftUI

/// A Safari-style dropdown of saved logins, floated just under the focused field.
/// It is a child window of the browser, so it rides along and never steals the typing focus.
@MainActor
final class SuggestionPanel {
    private var panel: NSPanel?
    /// The logins currently on screen, so repeated offers for the same field just reposition
    private var shownIDs: [String] = []

    /// Shows the saved logins for a field at `rect` (in `webView`'s own coordinates).
    func show(_ credentials: [WebCredential], below rect: CGRect, in webView: NSView,
              pick: @escaping (WebCredential) -> Void) {
        guard !credentials.isEmpty, let window = webView.window else { hide(); return }

        let onScreen = window.convertToScreen(webView.convert(rect, to: nil))
        let width = max(onScreen.width, 280)
        let ids = credentials.map(\.id)

        // Same list already up (e.g. the page scrolled): just slide it under the field, no rebuild
        if let panel, panel.parent != nil, ids == shownIDs {
            let height = panel.frame.height
            panel.setFrame(CGRect(x: onScreen.minX, y: onScreen.minY - height - 4, width: panel.frame.width, height: height),
                           display: true)
            return
        }

        let list = SuggestionList(credentials: credentials, width: width) { [weak self] credential in
            pick(credential)
            self?.hide()
        }
        let hosting = NSHostingView(rootView: list)
        hosting.layoutSubtreeIfNeeded()
        let height = hosting.fittingSize.height

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.setFrame(CGRect(x: onScreen.minX, y: onScreen.minY - height - 4, width: width, height: height),
                       display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        self.panel = panel
        shownIDs = ids
    }

    func hide() {
        shownIDs = []
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = true
        return panel
    }
}

// MARK: - The list

private struct SuggestionList: View {
    let credentials: [WebCredential]
    let width: CGFloat
    let pick: (WebCredential) -> Void
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(credentials.enumerated()), id: \.element.id) { index, credential in
                let isHighlighted = hovered == credential.id || (hovered == nil && index == 0)
                Button { pick(credential) } label: {
                    SuggestionRow(credential: credential, highlighted: isHighlighted)
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? credential.id : (hovered == credential.id ? nil : hovered) }
            }
        }
        .padding(6)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.primary.opacity(0.12)))
    }
}

private struct SuggestionRow: View {
    let credential: WebCredential
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 14))
                .frame(width: 26, height: 26)
                .background(highlighted ? .white.opacity(0.2) : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(credential.username.isEmpty ? credential.host : credential.username)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("Password for \(credential.host)")
                    .font(.caption)
                    .foregroundStyle(highlighted ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(highlighted ? Color.white.opacity(0.9) : Color.secondary.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(highlighted ? .white : .primary)
        .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
