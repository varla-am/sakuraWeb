import SwiftUI
import WebKit

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var browser: Browser
    let glass: Bool
    let tint: Double
    /// Floating over the page: no traffic lights to make room for
    let isIsland: Bool

    var body: some View {
        VStack(spacing: 10) {
            // The traffic lights sit on the left of this row, and the row is centered on them;
            // the empty part drags the window
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: isIsland ? 0 : max(0, browser.trafficLightsEnd.x + SidebarButton.gap - 10))
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                SidebarButton()
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                if let tab = browser.selected {
                    NavigationButtons(tab: tab)
                }
            }
            .frame(height: SidebarButton.height)
            .padding(.top, isIsland ? 10 : max(0, browser.trafficLightsEnd.y - SidebarButton.height / 2))

            if let tab = browser.selected {
                AddressField(tab: tab, glass: glass, tint: tint)
                    .id(tab.id)
            }

            SidebarFavorites(glass: glass, tint: tint)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(browser.tabs) { tab in
                        TabRow(tab: tab, glass: glass, tint: tint)
                    }
                    NewTabRow()
                }
            }
            .scrollIndicators(.never)

            HStack(spacing: 0) {
                if let tab = browser.selected {
                    ExtensionButtons(tab: tab)
                }
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
            .buttonStyle(ToolbarIconStyle())
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

struct SidebarButton: View {
    @EnvironmentObject private var browser: Browser
    /// The height of a ToolbarIconStyle button
    static let height: CGFloat = 26
    /// Space from the zoom button to this button's frame; the symbol inside adds a few points more
    static let gap: CGFloat = 4

    var body: some View {
        Button {
            withAnimation(.snappy) { browser.toggleSidebar() }
        } label: {
            Label(browser.showsSidebar ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
        }
        .buttonStyle(ToolbarIconStyle())
        .help(browser.showsSidebar ? "Hide Sidebar" : "Show Sidebar")
    }
}

private struct NavigationButtons: View {
    @ObservedObject var tab: Tab

    var body: some View {
        HStack(spacing: 0) {
            Button { tab.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!tab.canNavigateBack)
                .help("Go back")
            Button { tab.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .disabled(!tab.canNavigateForward)
                .help("Go forward")
            Button { tab.reloadOrStop() } label: {
                Label(tab.isLoading ? "Stop" : "Reload", systemImage: tab.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(tab.isLoading ? "Stop loading this page" : "Reload this page")
        }
        .buttonStyle(ToolbarIconStyle())
    }
}

/// Drag the sidebar's right edge to make it wider or narrower
struct ResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            // SwiftUI restores the cursor itself, so it can't get stuck as arrows after a drag
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(380, max(200, start + drag.translation.width))
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .offset(x: 4)
    }
}

// MARK: - Address bar

private struct AddressField: View {
    @EnvironmentObject private var browser: Browser
    @ObservedObject var tab: Tab
    let glass: Bool
    let tint: Double
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var fullURL: String {
        guard let url = tab.address, url.absoluteString != "about:blank" else { return "" }
        return url.absoluteString
    }

    /// Just the site name while not editing, like Arc and Safari; a Sakura page keeps its whole address
    private var shownText: String {
        guard tab.page == nil, let host = tab.url?.host() else { return fullURL }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var icon: String {
        guard !isFocused else { return "magnifyingglass" }
        if let page = tab.page { return page.symbol }
        guard let url = tab.url else { return "magnifyingglass" }
        return url.scheme == "https" ? "lock.fill" : "globe"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .frame(width: 14)
            TextField("Search or enter website name", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    tab.load(text)
                    isFocused = false
                }
                .onExitCommand {
                    isFocused = false
                }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .chrome(in: RoundedRectangle(cornerRadius: 9), glass: glass, tint: tint,
                classic: Color.primary.opacity(0.07))
        .onAppear {
            text = shownText
            // A fresh tab starts with the cursor in the address bar
            if tab.webView.url == nil, tab.page == nil { DispatchQueue.main.async { isFocused = true } }
        }
        .onChange(of: tab.address) {
            // Something opened a page (a file from Finder, a favorite) while the empty bar waited for typing
            if isFocused, text.isEmpty { isFocused = false }
            if !isFocused { text = shownText }
        }
        // Opening a Sakura page (⇧⌘E) leaves the address bar, so it shows the page's address
        .onChange(of: tab.page) {
            isFocused = false
            text = shownText
        }
        .onChange(of: isFocused) {
            // Editing shows the full address, leaving shows the site name again
            text = isFocused ? fullURL : shownText
            // Like Safari: clicking into a filled address bar selects all of it, ready to type over
            if isFocused, !text.isEmpty { Self.selectAllAfterClick() }
        }
        .onChange(of: browser.addressFocusRequest) {
            isFocused = true
        }
    }

    /// The click puts the cursor where the mouse comes up, so the selection waits until the button is released
    private static func selectAllAfterClick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            if NSEvent.pressedMouseButtons != 0 {
                selectAllAfterClick()
            } else {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Tabs

private struct TabRow: View {
    @EnvironmentObject private var browser: Browser
    @ObservedObject var tab: Tab
    let glass: Bool
    let tint: Double
    @State private var isHovered = false

    private var isSelected: Bool { browser.selectedID == tab.id }

    var body: some View {
        HStack(spacing: 8) {
            if let page = tab.page {
                Image(systemName: page.symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16, height: 16)
            } else {
                Favicon(url: tab.favicon)
            }
            Text(tab.displayTitle)
                .lineLimit(1)
                .font(.system(size: 13))
            Spacer(minLength: 0)
            if isHovered {
                Button { browser.close(tab) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close this tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            if isSelected {
                Color.clear
                    .chrome(in: RoundedRectangle(cornerRadius: 9), glass: glass, tint: tint,
                            classic: Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(glass ? 0 : 0.12), radius: 1.5, y: 1)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture { browser.selectedID = tab.id }
        .onHover { isHovered = $0 }
        .help(tab.address?.absoluteString ?? tab.displayTitle)
        .contextMenu {
            Button("Copy Link") {
                guard let url = tab.address else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            .disabled(tab.address == nil)
            Button("Add to Favorites") { Favorites.shared.add(tab) }
                .disabled(tab.page != nil || tab.url == nil || Favorites.shared.contains(tab.url))
            Divider()
            Button("Close Tab") { browser.close(tab) }
        }
    }
}

private struct NewTabRow: View {
    @EnvironmentObject private var browser: Browser
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text("New Tab")
                .font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(isHovered ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { browser.openNewTab() }
        .onHover { isHovered = $0 }
        .help("Open a new tab")
    }
}

private struct Favicon: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high)
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Extension buttons

private struct ExtensionButtons: View {
    @ObservedObject private var extensions = Extensions.shared
    let tab: Tab

    var body: some View {
        ForEach(extensions.contexts, id: \.uniqueIdentifier) { context in
            if let action = context.action(for: tab) {
                Button { context.performAction(for: tab) } label: {
                    Label {
                        Text(action.label)
                    } icon: {
                        Image(nsImage: action.icon(for: CGSize(width: 16, height: 16)) ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)!)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !action.badgeText.isEmpty {
                            Text(action.badgeText)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 2)
                                .background(.red, in: Capsule())
                                .foregroundStyle(.white)
                                .offset(x: 6, y: 4)
                        }
                    }
                }
                .disabled(!action.isEnabled)
                .help(action.label)
                .background(PopupAnchor(id: context.uniqueIdentifier))
            }
        }
    }
}
