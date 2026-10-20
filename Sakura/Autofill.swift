import AppKit
import WebKit

/// One saved login: the site, the account, and its password.
struct WebCredential: Identifiable, Hashable {
    let host: String
    let username: String
    let password: String

    /// Stable per host + account, so SwiftUI and the reveal set can track rows
    var id: String { "\(host)\u{0}\(username)" }
}

/// Saved logins live in the login keychain as internet passwords.
/// They carry our own security domain, so Sakura only ever sees the items it created
/// and never touches Safari's or any other app's passwords.
enum PasswordStore {
    private static let securityDomain = "Sakura"
    private static let ignoredKey = "autofillIgnoredHosts"

    private static func query(host: String? = nil, username: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSecurityDomain as String: securityDomain,
        ]
        if let host { query[kSecAttrServer as String] = host }
        if let username { query[kSecAttrAccount as String] = username }
        return query
    }

    /// Adds a new login, or updates the password if that host + account already exists
    @discardableResult
    static func save(host: String, username: String, password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let match = query(host: host, username: username)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Sakura — \(host)"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Every account saved for this host
    static func credentials(for host: String) -> [WebCredential] {
        read(query(host: host))
    }

    /// Everything Sakura has saved, for the settings list
    static func all() -> [WebCredential] {
        read(query()).sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    @discardableResult
    static func remove(host: String, username: String) -> Bool {
        SecItemDelete(query(host: host, username: username) as CFDictionary) == errSecSuccess
    }

    private static func read(_ base: [String: Any]) -> [WebCredential] {
        // The legacy macOS keychain refuses kSecReturnData together with kSecMatchLimitAll (it fails
        // with errSecParam, -50). So list the matching items with a persistent reference each, then
        // fetch every password by its own reference. This also copes with items that have no account.
        var request = base
        request[kSecReturnAttributes as String] = true
        request[kSecReturnPersistentRef as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String,
                  let ref = item[kSecValuePersistentRef as String] as? Data,
                  let password = password(forPersistentRef: ref) else { return nil }
            let account = item[kSecAttrAccount as String] as? String ?? ""
            return WebCredential(host: host, username: account, password: password)
        }
    }

    private static func password(forPersistentRef ref: Data) -> String? {
        let query: [String: Any] = [
            kSecValuePersistentRef as String: ref,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Sites the user chose never to save

    static func isIgnored(_ host: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []).contains(host)
    }

    static func ignore(_ host: String) {
        var list = UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []
        guard !list.contains(host) else { return }
        list.append(host)
        UserDefaults.standard.set(list, forKey: ignoredKey)
    }
}

// MARK: - The page side

enum Autofill {
    static let handlerName = "sakuraAutofill"
    /// A private JavaScript world: the page shares the DOM but can't see or tamper with our script,
    /// its message handler, or the fill function it would otherwise use to steal the credentials
    static let world = WKContentWorld.world(name: "SakuraAutofill")

    /// Runs in every page: finds the login form, fills it on request, and reports submissions.
    /// Handles both one-page logins and two-step ones (e.g. Google: e-mail first, password next).
    static let script = """
    "use strict";
    (function () {
      if (window.__sakuraAutofill) return;
      window.__sakuraAutofill = true;

      function send(name, extra) {
        try {
          // The host is not sent: Sakura trusts only WebKit's verified origin for the frame
          window.webkit.messageHandlers.sakuraAutofill.postMessage(Object.assign({ name: name }, extra || {}));
        } catch (e) {}
      }

      // Set a value the way a real keystroke would, so React and friends notice it
      function setValue(el, value) {
        try {
          var proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(proto, "value").set.call(el, value);
        } catch (e) {
          el.value = value;
        }
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
      }

      function visible(el) {
        return !!(el.offsetParent || el.getClientRects().length);
      }

      function passwordFields() {
        return Array.prototype.filter.call(document.querySelectorAll('input[type="password"]'), visible);
      }

      // A clear account field, even with no password on the page: an e-mail box or one marked as the username
      function strictUsername(el) {
        if (!(el instanceof HTMLInputElement) || !visible(el)) return false;
        var t = (el.type || "text").toLowerCase();
        return t === "email" || el.autocomplete === "username";
      }

      // A looser guess at the account field, used only next to a known password field
      function looksLikeUser(el) {
        if (!visible(el)) return false;
        var t = (el.type || "text").toLowerCase();
        if (t === "email" || t === "tel") return true;
        if (t !== "text") return false;
        if (el.autocomplete === "username") return true;
        var hint = ((el.name || "") + " " + (el.id || "") + " " + (el.autocomplete || "") + " " + (el.placeholder || "")).toLowerCase();
        return /user|email|login|account|mail|phone|name/.test(hint);
      }

      function usernameFor(pw) {
        var scope = pw.form || document;
        var inputs = Array.prototype.slice.call(scope.querySelectorAll("input"));
        var index = inputs.indexOf(pw);
        for (var i = index - 1; i >= 0; i--) {
          if (looksLikeUser(inputs[i])) return inputs[i];
        }
        for (var j = 0; j < inputs.length; j++) {
          if (looksLikeUser(inputs[j])) return inputs[j];
        }
        return null;
      }

      function firstStrictUsername() {
        return Array.prototype.filter.call(document.querySelectorAll("input"), strictUsername)[0] || null;
      }

      // Called by Sakura with a stored login: fill the password step, or just the e-mail on step one
      window.__sakuraFill = function (username, password) {
        var pws = passwordFields();
        if (pws.length) {
          var pw = pws[0];
          if (password) setValue(pw, password);
          var user = usernameFor(pw);
          if (user && username) setValue(user, username);
          return true;
        }
        var field = firstStrictUsername();
        if (field && username) { setValue(field, username); return true; }
        return false;
      };

      // Report a login being sent: full login, or just the e-mail on a two-step form's first page
      function reportSubmit(scope) {
        var pw = scope.querySelector('input[type="password"]');
        if (pw && pw.value) {
          var user = usernameFor(pw);
          send("submit", { username: user ? user.value : "", password: pw.value });
          return;
        }
        var field = firstStrictUsername();
        if (field && field.value) send("username", { username: field.value });
      }

      document.addEventListener("submit", function (e) {
        try { reportSubmit(e.target); } catch (err) {}
      }, true);

      document.addEventListener("keydown", function (e) {
        if (e.key !== "Enter") return;
        var el = e.target;
        if (!(el instanceof HTMLInputElement)) return;
        if (el.type === "password" && el.value) {
          var user = usernameFor(el);
          send("submit", { username: user ? user.value : "", password: el.value });
        } else if (strictUsername(el) && el.value && !passwordFields().length) {
          send("username", { username: el.value });
        }
      }, true);

      // A field Sakura can offer suggestions for: a password box, or a clear account box
      function isLoginField(el) {
        return el instanceof HTMLInputElement &&
          ((el.type || "").toLowerCase() === "password" || strictUsername(el));
      }

      var offeredEl = null;

      // Tell Sakura where the field sits on screen, so it can float the dropdown under it
      function offerSuggestions(el) {
        var r = el.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) return; // not laid out yet
        offeredEl = el;
        send("focusField", { x: r.left, y: r.top, width: r.width, height: r.height });
      }

      function activeLoginField() {
        var el = document.activeElement;
        return isLoginField(el) ? el : null;
      }

      document.addEventListener("focusin", function (e) {
        if (isLoginField(e.target)) offerSuggestions(e.target);
      }, true);

      document.addEventListener("focusout", function (e) {
        var el = e.target;
        if (!isLoginField(el)) return;
        offeredEl = null;
        send("dismiss", {});
        // Moving on from the e-mail box is enough to remember it, even with no real submit
        if (strictUsername(el) && el.value && !passwordFields().length) {
          send("username", { username: el.value });
        }
      }, true);

      // While a login field stays focused the dropdown rides along; otherwise it hides
      function reanchorOrDismiss() {
        var el = activeLoginField();
        if (el) offerSuggestions(el); else send("dismiss", {});
      }
      window.addEventListener("scroll", reanchorOrDismiss, true);
      window.addEventListener("resize", reanchorOrDismiss);

      // Catch a login field focused before we were listening (autofocus) or rendered late by the site,
      // so the dropdown appears the moment the e-mail box is asked for — no click needed
      function catchFocused() {
        var el = activeLoginField();
        if (el && el !== offeredEl) offerSuggestions(el);
      }
      catchFocused();
      var tries = 0;
      var poll = setInterval(function () {
        catchFocused();
        if (++tries >= 20) clearInterval(poll);
      }, 150);
      new MutationObserver(catchFocused).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """
}

/// Lives on a tab's web view: fills saved logins and offers to save new ones.
/// Holds the web view weakly, so it never keeps the tab alive through the content controller.
@MainActor
final class AutofillCoordinator: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    /// E-mail typed on a two-step form's first page, kept so the password step can save both together
    private var pendingUsernames: [String: String] = [:]
    private let suggestions = SuggestionPanel()
    /// Hiding the dropdown is delayed a touch, so a click on it lands before the field's blur closes it
    private var hideWork: DispatchWorkItem?
    /// The save sheet, kept alive while it is on screen
    private var saveAlert: NSAlert?
    /// The last login we offered to save, to ignore the duplicate that Enter sends (keydown + form submit)
    private var lastOffer: (signature: String, time: Date)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["name"] as? String else { return }
        // The host comes from WebKit's verified origin, never from the page: a malicious site could
        // otherwise claim to be github.com and be offered GitHub's saved password.
        let host = message.frameInfo.securityOrigin.host
        guard !host.isEmpty else { return }

        switch event {
        case "focusField":
            showSuggestions(host: host, body: body)
        case "dismiss":
            scheduleHide()
        case "username":
            // First step of a two-step login: remember the account for when the password arrives
            if let username = body["username"] as? String, !username.isEmpty {
                pendingUsernames[host] = username
            }
        case "submit":
            let username = body["username"] as? String ?? ""
            offerToSave(host: host,
                        username: username.isEmpty ? (pendingUsernames[host] ?? "") : username,
                        password: body["password"] as? String ?? "")
        default:
            break
        }
    }

    // MARK: Suggestion dropdown

    private func showSuggestions(host: String, body: [String: Any]) {
        hideWork?.cancel()
        let matches = PasswordStore.credentials(for: host)
        guard !matches.isEmpty, let webView,
              let x = body["x"] as? Double, let y = body["y"] as? Double,
              let width = body["width"] as? Double, let height = body["height"] as? Double else {
            suggestions.hide()
            return
        }
        // CSS pixels from the page become view points once scaled by the page's zoom
        let scale = webView.pageZoom
        let rect = CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
        suggestions.show(matches, below: rect, in: webView) { [weak self] credential in
            self?.fill(credential)
        }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.suggestions.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func fill(_ credential: WebCredential) {
        hideWork?.cancel()
        // Called in our private world, where __sakuraFill lives and the page can't have replaced it.
        // The values go as JS arguments, so there's nothing to escape or inject.
        webView?.callAsyncJavaScript(
            "if (window.__sakuraFill) window.__sakuraFill(username, password);",
            arguments: ["username": credential.username, "password": credential.password],
            in: nil, in: Autofill.world, completionHandler: nil)
    }

    private func offerToSave(host: String, username: String, password: String) {
        guard !password.isEmpty, !PasswordStore.isIgnored(host) else { return }

        // Pressing Enter fires both the form's submit and our keydown handler, so the same login
        // arrives twice; a second sheet on the window would dismiss the first. Ignore the duplicate.
        let signature = "\(host)\u{0}\(username)\u{0}\(password)"
        if let last = lastOffer, last.signature == signature, Date().timeIntervalSince(last.time) < 3 { return }
        lastOffer = (signature, Date())

        // A sheet is already up; don't try to present another
        if saveAlert != nil { return }

        let existing = PasswordStore.credentials(for: host)
        // Nothing new to remember
        if existing.contains(where: { $0.username == username && $0.password == password }) { return }
        let isUpdate = existing.contains { $0.username == username }

        guard let window = webView?.window else {
            PasswordStore.save(host: host, username: username, password: password)
            return
        }

        let alert = NSAlert()
        alert.messageText = isUpdate
            ? String(localized: "Update the saved password for \(host)?")
            : String(localized: "Save this password for \(host)?")
        if !username.isEmpty { alert.informativeText = username }
        alert.addButton(withTitle: isUpdate ? String(localized: "Update Password") : String(localized: "Save Password"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.addButton(withTitle: String(localized: "Never for This Website"))

        // Present a beat later: the Return that submitted the form would otherwise reach the sheet
        // and click its default button, and the post-login navigation would dismiss it. Waiting lets
        // the keystroke finish and the page settle, so the sheet stays until the user answers.
        _ = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.saveAlert == nil, let window = self.webView?.window else { return }
            self.saveAlert = alert
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.saveAlert = nil
                switch response {
                case .alertFirstButtonReturn:
                    PasswordStore.save(host: host, username: username, password: password)
                case .alertThirdButtonReturn:
                    PasswordStore.ignore(host)
                default:
                    break
                }
            }
        }
    }
}

extension Tab {
    /// Wires the autofill script and message handler into this tab's web view
    func installAutofill() {
        let controller = webView.configuration.userContentController
        let coordinator = AutofillCoordinator(webView: webView)
        // Everything lives in our private world, out of the page's reach
        controller.add(coordinator, contentWorld: Autofill.world, name: Autofill.handlerName)
        controller.addUserScript(WKUserScript(source: Autofill.script,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true,
                                              in: Autofill.world))
        autofill = coordinator
    }
}
