import Foundation

/// Imports a passwords CSV like the ones Apple Passwords, Chrome or Safari export.
/// Columns are matched by header name, so the usual `url,username,password` layouts all work.
enum PasswordImport {
    struct Result {
        let imported: Int
        let skipped: Int
    }

    static func importCSV(at url: URL) -> Result {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return Result(imported: 0, skipped: 0) }
        var rows = parse(raw)
        guard !rows.isEmpty else { return Result(imported: 0, skipped: 0) }

        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func column(_ names: [String]) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        let urlColumn = column(["url", "website", "login_uri", "uri", "web site"])
        let userColumn = column(["username", "login", "account", "login_username", "email", "user name"])
        guard let passColumn = column(["password", "login_password", "pass"]) else {
            return Result(imported: 0, skipped: 0)
        }

        var imported = 0
        var skipped = 0
        for row in rows {
            func field(_ index: Int?) -> String { index.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let password = field(passColumn)
            guard !password.isEmpty, let host = host(from: field(urlColumn)) else { skipped += 1; continue }
            if PasswordStore.save(host: host, username: field(userColumn), password: password) {
                imported += 1
            } else {
                skipped += 1
            }
        }
        return Result(imported: imported, skipped: skipped)
    }

    /// The host from a URL cell, whether it's a full URL or a bare domain
    private static func host(from field: String) -> String? {
        let text = field.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let host = url.host(), !host.isEmpty { return host }
        if let url = URL(string: "https://" + text), let host = url.host(), !host.isEmpty { return host }
        return nil
    }

    /// A small RFC-4180 CSV reader: handles quoted fields, escaped quotes, and newlines inside quotes
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var characters = Substring(text)
        // Drop a UTF-8 byte-order mark, which would otherwise glue onto the first header
        if characters.first == "\u{FEFF}" { characters = characters.dropFirst() }

        let chars = Array(characters)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    record.append(field); field = ""
                case "\n":
                    record.append(field); field = ""
                    rows.append(record); record = []
                case "\r":
                    break // CRLF: the following \n ends the record
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            rows.append(record)
        }
        // Drop blank lines
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}
