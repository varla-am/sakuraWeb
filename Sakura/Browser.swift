import AppKit
import UniformTypeIdentifiers
import WebKit

/// One browser window: its tabs and which one is in front
@MainActor
final class Browser: NSObject, ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published var selectedID: Tab.ID? {
        didSet {
            guard isOpen, selectedID != oldValue, let selected else { return }
            Extensions.shared.controller.didActivateTab(selected, previousActiveTab: tabs.first { $0.id == oldValue })
        }
    }
    /// Bumped to ask the address field for focus (⌘L, a new empty tab)
    @Published private(set) var addressFocusRequest = 0
    @Published var isSidebarVisible = true
    /// Where the traffic lights end, from the window's top left: x is the zoom button's right edge, y its middle
    @Published var trafficLightsEnd = CGPoint(x: 72, y: 14)
    /// Full screen has no traffic lights, and the sidebar floats over the page as an island
    @Published var isFullScreen = false {
        didSet { isPeeking = false }
    }
    /// The sidebar floating over the page for a moment: the pointer at the left edge, or the button in full screen
    @Published var isPeeking = false

    /// Docked only in a window; in full screen the sidebar never stays, it only floats while needed
    var showsSidebar: Bool { isFullScreen ? isPeeking : isSidebarVisible }

    func toggleSidebar() {
        if isFullScreen {
            isPeeking.toggle()
        } else {
            isSidebarVisible.toggle()
            isPeeking = false
        }
    }

    /// Where our controls start: after the traffic lights, or at the edge in full screen
    var controlsStart: CGPoint {
        isFullScreen ? CGPoint(x: 4, y: trafficLightsEnd.y) : trafficLightsEnd
    }

    weak var window: NSWindow?
    /// Extensions only hear about this window between open() and close()
    private(set) var isOpen = false

    var selected: Tab? { tabs.first { $0.id == selectedID } }

    override init() {
        super.init()
        openNewTab()
    }

    /// A new tab the person asked for (⌘T, New Tab): the homepage if one is set, else Sakura's start page
    func openNewTab() {
        guard let home = Homepage.url else {
            newTab()
            return
        }
        let tab = newTab(select: false)
        selectedID = tab.id
        tab.load(home)
    }

    @discardableResult
    func newTab(configuration: WKWebViewConfiguration? = nil, select: Bool = true) -> Tab {
        let tab = Tab(configuration: configuration)
        tab.browser = self
        let index = tabs.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        if isOpen { Extensions.shared.controller.didOpenTab(tab) }
        if select {
            selectedID = tab.id
            if configuration == nil { focusAddress() }
        }
        return tab
    }

    /// Shows a site or a Sakura page: its tab if one is open, else the empty tab in front, else a new tab
    func show(_ url: URL) {
        if let page = SakuraPage(url), let tab = tabs.first(where: { $0.page == page }) {
            selectedID = tab.id
        } else if SakuraPage(url) == nil, let tab = tabs.first(where: { $0.page == nil && $0.url?.host() == url.host() }) {
            selectedID = tab.id
        } else if let selected, selected.webView.url == nil {
            selected.load(url)
        } else {
            let tab = newTab(select: false)
            selectedID = tab.id
            tab.load(url)
        }
    }

    /// Opens a file from disk (⌘O, Finder's Open With): in the empty tab in front, else a new tab
    func openFile(_ file: URL) {
        if let selected, selected.webView.url == nil, selected.page == nil, selected.missingPage == nil {
            selected.load(file)
        } else {
            let tab = newTab(select: false)
            selectedID = tab.id
            tab.load(file)
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html] + [UTType("public.xhtml")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Open")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(openFile)
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        guard tabs.count > 1 else {
            window?.performClose(nil)
            return
        }
        tab.webView.stopLoading()
        tabs.remove(at: index)
        if isOpen { Extensions.shared.controller.didCloseTab(tab) }
        if selectedID == tab.id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }

    func closeSelected() {
        if let selected { close(selected) }
    }

    func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        selectedID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    func focusAddress() {
        if isFullScreen { isPeeking = true } else { isSidebarVisible = true }
        addressFocusRequest += 1
    }

    // MARK: Window lifecycle

    func open() {
        guard !isOpen else { return }
        isOpen = true
        Extensions.shared.didOpen(self)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        Extensions.shared.didClose(self)
    }
}

// MARK: - What extensions see as a window

extension Browser: WKWebExtensionWindow {
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { selected }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
    func frame(for context: WKWebExtensionContext) -> CGRect { window?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.screen?.frame ?? .null }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func focus(for context: WKWebExtensionContext) async throws {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close(for context: WKWebExtensionContext) async throws {
        window?.performClose(nil)
    }
}
