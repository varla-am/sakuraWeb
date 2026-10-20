import SwiftUI
import WebKit

/// A WKWebView that knows its tab, so the right-click menu can offer extension items
final class SakuraWebView: WKWebView {
    weak var tab: Tab?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let tab else { return }
        let items = Extensions.shared.contexts.flatMap { $0.menuItems(for: tab) }
        guard !items.isEmpty else { return }
        menu.addItem(.separator())
        items.forEach(menu.addItem)
    }
}

/// Shows the tab's own web view, so switching tabs keeps each page alive
struct WebView: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> SakuraWebView { tab.webView }
    func updateNSView(_ webView: SakuraWebView, context: Context) {}
}

/// Tells the browser which NSWindow it lives in and when that window opens, focuses and closes
struct WindowReader: NSViewRepresentable {
    let browser: Browser

    func makeNSView(context: Context) -> ReaderView { ReaderView(browser: browser) }
    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        private let browser: Browser
        private var observers: [NSObjectProtocol] = []

        init(browser: Browser) {
            self.browser = browser
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Tells the browser where the zoom button is, so the sidebar button can line up with it
        private static func measureLights(in window: NSWindow, for browser: Browser) {
            guard let zoom = window.standardWindowButton(.zoomButton), let content = window.contentView else { return }
            let frame = zoom.convert(zoom.bounds, to: content)
            let top = content.isFlipped ? frame.midY : content.bounds.height - frame.midY
            browser.trafficLightsEnd = CGPoint(x: frame.maxX, y: top)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            browser.window = window
            browser.isFullScreen = window.styleMask.contains(.fullScreen)
            browser.open()
            // After the first layout, once AppKit has placed the traffic lights
            DispatchQueue.main.async { [browser] in Self.measureLights(in: window, for: browser) }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [browser] _ in
                MainActor.assumeIsolated { Extensions.shared.didFocus(browser) }
            })
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [browser] _ in
                MainActor.assumeIsolated { browser.isFullScreen = true }
            })
            // Leaving full screen rebuilds the title bar
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [browser] _ in
                MainActor.assumeIsolated {
                    browser.isFullScreen = false
                    Self.measureLights(in: window, for: browser)
                }
            })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [browser] _ in
                MainActor.assumeIsolated { browser.close() }
            })
        }
    }
}

/// Remembers a toolbar button's view so an extension popup can hang off it
struct PopupAnchor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        Extensions.shared.anchors[id] = view
    }
}
