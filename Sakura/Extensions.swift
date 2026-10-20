import AppKit
import WebKit

/// Safari Web Extensions: finds them, loads them into one shared controller and answers their requests
@MainActor
final class Extensions: NSObject, ObservableObject {
    static let shared = Extensions()

    let controller = WKWebExtensionController(configuration: .default())
    @Published private(set) var contexts: [WKWebExtensionContext] = []
    /// Extensions that failed to load, shown in the Extensions menu
    @Published private(set) var failures: [String] = []

    /// Open browser windows, most recently focused first
    private(set) var browsers: [Browser] = []
    /// Toolbar buttons register here so an action popup can point at its button
    var anchors: [String: NSView] = [:]

    private static let unpackedKey = "UnpackedExtensions"
    /// Each extension's answer to "can it read and change websites", asked once
    private static let siteAccessKey = "ExtensionSiteAccess"
    private var siteAccess: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: Self.siteAccessKey) as? [String: Bool] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.siteAccessKey) }
    }
    private var unpackedPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.unpackedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.unpackedKey) }
    }

    private override init() {
        super.init()
        controller.delegate = self
        Task { await loadAll() }
    }

    // MARK: Loading

    private func loadAll() async {
        // Looking through every app's bundle is slow disk work, so it stays off the main thread
        let found = await Task.detached(priority: .utility) { Self.installedAppExtensions() }.value
        for bundle in found.compactMap(Bundle.init(url:)) {
            await load(id: bundle.bundleIdentifier ?? bundle.bundlePath, name: bundle.bundleURL.lastPathComponent) {
                try await WKWebExtension(appExtensionBundle: bundle)
            }
        }
        for path in unpackedPaths {
            await loadUnpacked(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    /// Safari Web Extensions ship inside apps as .appex bundles
    nonisolated private static func installedAppExtensions() -> [URL] {
        let folders = [URL(fileURLWithPath: "/Applications"), Paths.home.appendingPathComponent("Applications")]
        let apps = folders.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        return apps.filter { $0.pathExtension == "app" }.flatMap { app -> [URL] in
            let plugins = app.appendingPathComponent("Contents/PlugIns")
            let appexes = (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
            return appexes.filter { appex in
                let info = Bundle(url: appex)?.infoDictionary?["NSExtension"] as? [String: Any]
                return info?["NSExtensionPointIdentifier"] as? String == "com.apple.Safari.web-extension"
            }
        }
    }

    @discardableResult
    private func loadUnpacked(_ folder: URL) async -> Bool {
        await load(id: folder.path, name: folder.lastPathComponent) {
            try await WKWebExtension(resourceBaseURL: folder)
        }
    }

    @discardableResult
    private func load(id: String, name: String, _ make: () async throws -> WKWebExtension) async -> Bool {
        guard !contexts.contains(where: { $0.uniqueIdentifier == id }) else { return true }
        do {
            let context = WKWebExtensionContext(for: try await make())
            // A fixed identifier keeps the extension's storage between launches
            context.uniqueIdentifier = id
            context.isInspectable = true
            grantRequestedPermissions(to: context)
            try controller.load(context)
            contexts.append(context)
            return true
        } catch {
            failures.append("\(name): \(error.localizedDescription)")
            return false
        }
    }

    /// The APIs an extension's manifest asks for are granted with it; reading and changing websites
    /// is asked once and remembered. Optional permissions still prompt when the extension wants them
    private func grantRequestedPermissions(to context: WKWebExtensionContext) {
        let webExtension = context.webExtension
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        let patterns = webExtension.allRequestedMatchPatterns
        guard !patterns.isEmpty else { return }
        let id = context.uniqueIdentifier
        let allowed = siteAccess[id] ?? {
            let list = patterns.map(\.string).sorted().joined(separator: ", ")
            let answer = ask(String(localized: "\(name(context)) wants to read and change: \(list)"))
            siteAccess[id] = answer
            return answer
        }()
        for pattern in patterns {
            context.setPermissionStatus(allowed ? .grantedExplicitly : .deniedExplicitly, for: pattern)
        }
    }

    // MARK: Menu commands

    func chooseUnpackedExtension() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose the folder that contains the extension's manifest.json")
        panel.prompt = String(localized: "Load Extension")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            if await loadUnpacked(folder), !unpackedPaths.contains(folder.path) {
                unpackedPaths.append(folder.path)
            }
        }
    }

    func remove(_ context: WKWebExtensionContext) {
        try? controller.unload(context)
        contexts.removeAll { $0 === context }
        unpackedPaths.removeAll { $0 == context.uniqueIdentifier }
        siteAccess[context.uniqueIdentifier] = nil
    }

    func openOptions(for context: WKWebExtensionContext) {
        guard let url = context.optionsPageURL, let browser = browsers.first else { return }
        browser.newTab(configuration: context.webViewConfiguration).load(url)
    }

    // MARK: Windows

    func didOpen(_ browser: Browser) {
        browsers.insert(browser, at: 0)
        controller.didOpenWindow(browser)
    }

    func didClose(_ browser: Browser) {
        browsers.removeAll { $0 === browser }
        for tab in browser.tabs {
            controller.didCloseTab(tab, windowIsClosing: true)
        }
        controller.didCloseWindow(browser)
    }

    func didFocus(_ browser: Browser) {
        browsers.removeAll { $0 === browser }
        browsers.insert(browser, at: 0)
        controller.didFocusWindow(browser)
    }
}

// MARK: - Requests from extensions

extension Extensions: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        browsers
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        browsers.first { $0.window?.isKeyWindow == true } ?? browsers.first
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let browser = (configuration.window as? Browser) ?? browsers.first else {
            completionHandler(nil, nil)
            return
        }
        let tab = browser.newTab(select: configuration.shouldBeActive)
        if let url = configuration.url { tab.load(url) }
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        openOptions(for: extensionContext)
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let list = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        completionHandler(ask(String(localized: "\(name(extensionContext)) wants these permissions: \(list)")) ? permissions : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let hosts = Set(urls.compactMap { $0.host() }).sorted().joined(separator: ", ")
        completionHandler(ask(String(localized: "\(name(extensionContext)) wants to read and change: \(hosts)")) ? urls : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let list = matchPatterns.map(\.string).sorted().joined(separator: ", ")
        completionHandler(ask(String(localized: "\(name(extensionContext)) wants to read and change: \(list)")) ? matchPatterns : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        objectWillChange.send()
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover,
              let anchor = anchors[context.uniqueIdentifier] ?? browsers.first?.window?.contentView
        else {
            completionHandler(nil)
            return
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        completionHandler(nil)
    }

    private func name(_ context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? String(localized: "An extension")
    }

    private func ask(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
