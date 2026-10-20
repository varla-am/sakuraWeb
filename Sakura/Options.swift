import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    /// nil follows the system setting
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Homepage {
    static let key = "homepage"

    /// What new tabs open; nil (an empty setting) shows Sakura's own start page
    static var url: URL? {
        Address.url(for: UserDefaults.standard.string(forKey: key) ?? "")
    }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo, google, bing, ecosia, startpage

    var id: Self { self }

    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        }
    }

    private var base: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/"
        case .google: "https://www.google.com/search"
        case .bing: "https://www.bing.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        case .startpage: "https://www.startpage.com/do/search"
        }
    }

    static var current: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: "searchEngine") ?? "") ?? .duckDuckGo
    }

    func url(for query: String) -> URL? {
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ru, lv

    var id: Self { self }

    /// Each language is written in itself, so it can be found whatever the current one is
    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .en: "English"
        case .ru: "Русский"
        case .lv: "Latviešu"
        }
    }

    /// AppleLanguages in the app's own defaults overrides the system order; Cocoa reads it at launch
    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
