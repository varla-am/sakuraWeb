import Foundation

enum Address {
    /// Schemes the web view handles itself; anything else (mailto:, zoommtg:…) goes to another app
    static let webSchemes: Set<String> = ["http", "https", "about", "blob", "data", "file", "webkit-extension"]

    /// Turns whatever was typed into the address bar into a URL: a full address, a bare domain or a search
    static func url(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) {
            return url
        }
        if !text.contains(" "), text.contains(".") || text.hasPrefix("localhost") {
            let scheme = text.hasPrefix("localhost") ? "http://" : "https://"
            if let url = URL(string: scheme + text), url.host() != nil { return url }
        }
        return SearchEngine.current.url(for: text)
    }
}

enum Paths {
    /// The real home folder – inside the sandbox NSHomeDirectory() points into the app container
    static let home: URL = {
        let path = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    static var downloads: URL { home.appendingPathComponent("Downloads", isDirectory: true) }

    /// ~/Downloads/name, or "name 2", "name 3"… if that file already exists
    static func download(named filename: String) -> URL {
        let name = filename.isEmpty ? "download" : filename
        let first = downloads.appendingPathComponent(name)
        let base = first.deletingPathExtension().lastPathComponent
        let ext = first.pathExtension
        var url = first
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return url
    }
}
