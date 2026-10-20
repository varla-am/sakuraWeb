import WebKit

/// Blocks common trackers (analytics, ad pixels) with WebKit's own content blocker.
/// The rules compile once; every tab gets them while "Block Trackers" is on
@MainActor
final class Trackers: NSObject, ObservableObject {
    static let shared = Trackers()
    static let enabledKey = "blockTrackers"
    private static let countKey = "blockedTrackers"
    private static let handlerName = "sakuraTrackers"
    /// The counting script's own world, out of the page's reach (like autofill's)
    private static let world = WKContentWorld.world(name: "SakuraTrackers")

    /// How many trackers Sakura has stopped, over all time; shown on the start page
    @Published private(set) var blockedCount = UserDefaults.standard.integer(forKey: countKey) {
        didSet { UserDefaults.standard.set(blockedCount, forKey: Self.countKey) }
    }

    private var rules: WKContentRuleList?
    /// Every tab's content controller, so the setting switches on and off without reopening tabs
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private override init() {
        super.init()
        Task {
            rules = try? await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "SakuraTrackers", encodedContentRuleList: Self.encodedRules)
            update()
        }
    }

    /// Called for each new tab; a pop-up can share its opener's controller, which already has everything
    func attach(to controller: WKUserContentController) {
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
        controller.addUserScript(WKUserScript(source: Self.counterScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.world))
        apply(to: controller)
    }

    /// Re-applies the setting to every open tab; pages already loaded keep their trackers until reloaded
    func update() {
        controllers.allObjects.forEach(apply)
    }

    private func apply(to controller: WKUserContentController) {
        guard let rules else { return }
        controller.remove(rules)
        if isEnabled { controller.add(rules) }
    }

    // MARK: Rules

    /// Tracker and ad hosts, blocked when another site loads them (visiting the site itself still works)
    private static let hosts = [
        // Google
        "google-analytics.com", "googletagmanager.com", "googletagservices.com", "doubleclick.net",
        "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        // Microsoft, X, LinkedIn, TikTok, Yandex, Mail.ru
        "clarity.ms", "bat.bing.com", "analytics.twitter.com", "static.ads-twitter.com",
        "px.ads.linkedin.com", "snap.licdn.com", "analytics.tiktok.com", "mc.yandex.ru", "top-fwz1.mail.ru",
        // Analytics services
        "hotjar.com", "mixpanel.com", "segment.io", "cdn.segment.com", "api.amplitude.com",
        "fullstory.com", "scorecardresearch.com", "quantserve.com",
        // Ad networks
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "adnxs.com", "amazon-adsystem.com",
    ]

    /// Facebook's pixel only, so "Log in with Facebook" buttons on other sites keep working
    private static let patterns = [
        #"^[^:]+://+connect\.facebook\.net/.*/fbevents\.js"#,
        #"^[^:]+://+([^:/]+\.)?facebook\.com/tr[/?]"#,
    ]

    /// WebKit's blocker doesn't say what it stopped, so this script watches the page for the trackers
    /// it adds (scripts, pixels, frames) and reports each address once. Requests made without an element
    /// (fetch, `new Image()`) go unseen, so the real number is a little higher
    private static var counterScript: String {
        let hostList = (try? JSONSerialization.data(withJSONObject: hosts)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        (function () {
          var hosts = \(hostList).map(function (h) { return h.replace(/\\./g, "\\\\."); });
          var known = new RegExp("^https?://([^/]+\\\\.)?(" + hosts.join("|") + ")(:|/|$)");
          var pixels = [/^https?:\\/\\/connect\\.facebook\\.net\\/.*\\/fbevents\\.js/, /^https?:\\/\\/([^\\/]+\\.)?facebook\\.com\\/tr[\\/?]/];
          var seen = {};
          var selector = "script[src],img[src],iframe[src],link[href]";
          // Roughly the site's own domain: the last two labels
          function site(host) { return host.split(".").slice(-2).join("."); }
          function check(el) {
            var url = el.src || el.href;
            if (!url || seen[url]) return;
            if (!known.test(url) && !pixels.some(function (r) { return r.test(url); })) return;
            try { if (site(new URL(url).hostname) === site(location.hostname)) return; } catch (e) { return; }
            seen[url] = true;
            try { window.webkit.messageHandlers.\(handlerName).postMessage(url); } catch (e) {}
          }
          function scan(node) {
            if (node.matches && node.matches(selector)) check(node);
            if (node.querySelectorAll) node.querySelectorAll(selector).forEach(check);
          }
          new MutationObserver(function (changes) {
            changes.forEach(function (c) { c.addedNodes.forEach(scan); });
          }).observe(document, { childList: true, subtree: true });
        })();
        """
    }

    /// WebKit's rule format: one rule per filter, since its regex has no "|"
    static var encodedRules: String {
        let hostFilters = hosts.map { #"^[^:]+://+([^:/]+\.)?"# + $0.replacingOccurrences(of: ".", with: #"\."#) + "[:/]" }
        let rules = (hostFilters + patterns).map { filter in
            ["trigger": ["url-filter": filter, "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        let data = try? JSONSerialization.data(withJSONObject: rules)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

extension Trackers: WKScriptMessageHandler {
    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            if isEnabled { blockedCount += 1 }
        }
    }
}
