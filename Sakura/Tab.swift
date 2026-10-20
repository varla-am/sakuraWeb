import AppKit
import Combine
import WebKit

@MainActor
final class Tab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: SakuraWebView
    weak var browser: Browser?

    @Published private(set) var title: String?
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var error: String?
    @Published private(set) var favicon: URL?
    private var failedURL: URL?
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    /// Fills saved logins and offers to save new ones; set up in init
    var autofill: AutofillCoordinator?

    /// A configuration from WebKit (window.open, an extension page) must be used as is
    init(configuration: WKWebViewConfiguration? = nil) {
        webView = SakuraWebView(frame: .zero, configuration: configuration ?? Tab.makeConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        webView.tab = self
        installAutofill()
        Trackers.shared.attach(to: webView.configuration.userContentController)

        webView.publisher(for: \.title).receive(on: DispatchQueue.main).assign(to: &$title)
        webView.publisher(for: \.url).receive(on: DispatchQueue.main).assign(to: &$url)
        webView.publisher(for: \.canGoBack).receive(on: DispatchQueue.main).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).receive(on: DispatchQueue.main).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).receive(on: DispatchQueue.main).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress).receive(on: DispatchQueue.main).assign(to: &$progress)

        // Extensions see tab changes through chrome.tabs.onUpdated
        $title.dropFirst().removeDuplicates().sink { [weak self] _ in self?.changed(.title) }.store(in: &subscriptions)
        $url.dropFirst().removeDuplicates().sink { [weak self] _ in self?.changed(.URL) }.store(in: &subscriptions)
        $isLoading.dropFirst().removeDuplicates().sink { [weak self] _ in self?.changed(.loading) }.store(in: &subscriptions)
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // Without "Safari" in the user agent some sites (Google, YouTube) serve an old desktop page
        configuration.applicationNameForUserAgent = "Version/27.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.webExtensionController = Extensions.shared.controller
        return configuration
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return url?.host() ?? String(localized: "New Tab")
    }

    func load(_ input: String) {
        guard let url = Address.url(for: input) else { return }
        load(url)
    }

    func load(_ url: URL) {
        error = nil
        webView.load(URLRequest(url: url))
    }

    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func retry() {
        if let failedURL { load(failedURL) } else { webView.reload() }
    }

    func zoom(by step: CGFloat) {
        webView.pageZoom = min(3, max(0.5, webView.pageZoom + step))
    }

    /// The icon the page declares, or /favicon.ico; loaded from the site itself, not a third-party service
    private func updateFavicon() async {
        let script = """
            (document.querySelector('link[rel~="icon"][sizes="32x32"]')
             || document.querySelector('link[rel~="icon"]')
             || document.querySelector('link[rel="apple-touch-icon"]'))?.href ?? ''
            """
        if let href = try? await webView.evaluateJavaScript(script) as? String, let icon = URL(string: href), !href.isEmpty {
            favicon = icon
        } else if let url, let scheme = url.scheme, scheme.hasPrefix("http"), let host = url.host() {
            favicon = URL(string: "\(scheme)://\(host)/favicon.ico")
        }
    }

    private func changed(_ properties: WKWebExtension.TabChangedProperties) {
        guard browser?.isOpen == true else { return }
        Extensions.shared.controller.didChangeTabProperties(properties, for: self)
    }

    private func show(_ error: Error) {
        let error = error as NSError
        // -999: a newer load replaced this one; 102: the response turned into a download
        if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) { return }
        failedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        self.error = error.localizedDescription
    }
}

// MARK: - Navigation

extension Tab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if let scheme = url.scheme?.lowercased(), !Address.webSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        // ⌘-click opens the link in a background tab, like Safari
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command) {
            browser?.newTab(select: false).webView.load(action.request)
            return .cancel
        }
        return action.shouldPerformDownload ? .download : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        response.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await updateFavicon() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        show(error)
    }
}

// MARK: - Pop-ups, alerts, file pickers

extension Tab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        browser?.newTab(configuration: configuration).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        browser?.close(self)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = frame.request.url?.host() ?? ""
        alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = frame.request.url?.host() ?? ""
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        return panel.runModal() == .OK ? panel.urls : nil
    }
}

// MARK: - Downloads

extension Tab: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let destination = Paths.download(named: suggestedFilename)
        downloads[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard var file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Marks the file as downloaded from the web, like Safari, so Gatekeeper checks it before it first opens
        var values = URLResourceValues()
        var quarantine: [String: Any] = [
            kLSQuarantineAgentNameKey as String: "Sakura",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        if let source = download.originalRequest?.url { quarantine[kLSQuarantineDataURLKey as String] = source }
        values.quarantineProperties = quarantine
        try? file.setResourceValues(values)
        // Makes the Downloads stack in the Dock bounce, like Safari does
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: file.path)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        show(error)
    }
}

// MARK: - What extensions see as a tab

extension Tab: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { browser }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { browser?.tabs.firstIndex(of: self) ?? NSNotFound }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { title }
    func url(for context: WKWebExtensionContext) -> URL? { url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !isLoading }
    func isSelected(for context: WKWebExtensionContext) -> Bool { browser?.selectedID == id }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { webView.pageZoom }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        webView.pageZoom = zoomFactor
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        load(url)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
    }

    func goBack(for context: WKWebExtensionContext) async throws {
        webView.goBack()
    }

    func goForward(for context: WKWebExtensionContext) async throws {
        webView.goForward()
    }

    func activate(for context: WKWebExtensionContext) async throws {
        browser?.selectedID = id
        browser?.window?.makeKeyAndOrderFront(nil)
    }

    func close(for context: WKWebExtensionContext) async throws {
        browser?.close(self)
    }
}
