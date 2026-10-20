import SwiftUI

struct Favorite: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    /// The site's own icon, remembered when the favorite was added from an open page
    var icon: URL?
}

/// Sites shown as tiles on the start page
@MainActor
final class Favorites: ObservableObject {
    static let shared = Favorites()

    @Published private(set) var items: [Favorite] {
        didSet { save() }
    }

    private static let key = "favorites"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = saved
        } else {
            items = [
                Favorite(title: "YouTube", url: URL(string: "https://www.youtube.com")!),
                Favorite(title: "GitHub", url: URL(string: "https://github.com")!),
                Favorite(title: "Wikipedia", url: URL(string: "https://www.wikipedia.org")!),
                Favorite(title: "Apple", url: URL(string: "https://www.apple.com")!),
            ]
        }
    }

    func add(title: String, url: URL, icon: URL? = nil) {
        items.append(Favorite(title: title, url: url, icon: icon))
    }

    func update(_ favorite: Favorite) {
        guard let index = items.firstIndex(where: { $0.id == favorite.id }) else { return }
        items[index] = favorite
    }

    func remove(_ favorite: Favorite) {
        items.removeAll { $0.id == favorite.id }
    }

    func contains(_ url: URL?) -> Bool {
        guard let host = url?.host() else { return false }
        return items.contains { $0.url.host() == host }
    }

    /// Adds the page open in this tab, unless that site is already a favorite
    func add(_ tab: Tab) {
        guard let url = tab.url, url.host() != nil, !contains(url) else { return }
        add(title: tab.title?.isEmpty == false ? tab.title! : url.host()!, url: url, icon: tab.favicon)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Start page grid

struct FavoritesGrid: View {
    @ObservedObject private var favorites = Favorites.shared
    let open: (URL) -> Void
    @State private var editing: Favorite?
    @State private var isAdding = false

    /// Fixed cells, so the grid has a known width and the header can line up with it
    private static let cell: CGFloat = 84
    static let iconInset = (cell - 64) / 2
    /// Only as wide as its tiles (the + tile included), at most 6, so the page can center it
    private var columns: Int { min(favorites.items.count + 1, 6) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 16), count: columns),
                  alignment: .leading, spacing: 18) {
            ForEach(favorites.items) { favorite in
                FavoriteTile(title: favorite.title, action: { open(favorite.url) }) {
                    SiteIcon(favorite: favorite)
                }
                .contextMenu {
                    Button("Edit…") { editing = favorite }
                    Button("Remove") { favorites.remove(favorite) }
                }
            }
            FavoriteTile(title: String(localized: "Add"), action: { isAdding = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.cell * CGFloat(columns) + 16 * CGFloat(columns - 1), alignment: .leading)
        .sheet(isPresented: $isAdding) {
            FavoriteEditor(favorite: nil)
        }
        .sheet(item: $editing) { favorite in
            FavoriteEditor(favorite: favorite)
        }
    }
}

// MARK: - Sidebar tiles

/// Quick picks above the tabs, like Arc: a click shows the site's tab, or opens it
struct SidebarFavorites: View {
    @EnvironmentObject private var browser: Browser
    @ObservedObject private var favorites = Favorites.shared
    let glass: Bool
    let tint: Double
    @State private var editing: Favorite?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(favorites.items) { favorite in
                SidebarTile(favorite: favorite, isSelected: browser.selected?.url?.host() == favorite.url.host(),
                            glass: glass, tint: tint) {
                    browser.show(favorite.url)
                }
                .contextMenu {
                    Button("Open in New Tab") { browser.newTab(select: false).load(favorite.url) }
                    Divider()
                    Button("Edit…") { editing = favorite }
                    Button("Remove") { favorites.remove(favorite) }
                }
            }
        }
        .sheet(item: $editing) { favorite in
            FavoriteEditor(favorite: favorite)
        }
    }
}

private struct SidebarTile: View {
    let favorite: Favorite
    let isSelected: Bool
    let glass: Bool
    let tint: Double
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SiteIcon(favorite: favorite, size: 24)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    if isSelected {
                        Color.clear
                            .chrome(in: RoundedRectangle(cornerRadius: 10), glass: glass, tint: tint,
                                    classic: Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(glass ? 0 : 0.12), radius: 1.5, y: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isHovered ? 0.11 : 0.06))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(favorite.title)
    }
}

private struct FavoriteTile<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon
                    .frame(width: 64, height: 64)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 6 : 3, y: 2)
                    .scaleEffect(isHovered ? 1.06 : 1)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) { isHovered = hovering }
        }
    }
}

/// The site's icon, fetched from the site itself; a colored letter if it has none
private struct SiteIcon: View {
    let favorite: Favorite
    /// The tile it fills: 64 on the start page, smaller in the sidebar
    var size: CGFloat = 64
    @State private var attempt = 0

    private var candidates: [URL] {
        guard let scheme = favorite.url.scheme, let host = favorite.url.host() else { return [] }
        let root = "\(scheme)://\(host)"
        return [favorite.icon, URL(string: root + "/apple-touch-icon.png"), URL(string: root + "/favicon.ico")]
            .compactMap { $0 }
    }

    var body: some View {
        if attempt < candidates.count {
            AsyncImage(url: candidates[attempt]) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().interpolation(.high).scaledToFit().padding(size > 32 ? size * 10 / 64 : 0)
                case .failure:
                    Color.clear.onAppear { attempt += 1 }
                default:
                    ProgressView().controlSize(size > 32 ? .small : .mini)
                }
            }
            .id(attempt)
        } else {
            Text(favorite.title.prefix(1).uppercased())
                .font(.system(size: size * 28 / 64, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor)
        }
    }
}

// MARK: - Add and edit

private struct FavoriteEditor: View {
    let favorite: Favorite?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var address = ""

    /// Only a real web address, never a search
    private var url: URL? {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        guard let url = URL(string: text.contains("://") ? text : "https://" + text),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".") || host == "localhost"
        else { return nil }
        return url
    }

    var body: some View {
        Form {
            TextField("Name", text: $title)
            TextField("Address", text: $address, prompt: Text(verbatim: "example.com"))
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .navigationTitle(favorite == nil ? "Add Favorite" : "Edit Favorite")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(url == nil)
            }
        }
        .onAppear {
            title = favorite?.title ?? ""
            address = favorite?.url.absoluteString ?? ""
        }
    }

    private func save() {
        guard let url else { return }
        let name = title.trimmingCharacters(in: .whitespaces)
        let shownName = name.isEmpty ? (url.host() ?? url.absoluteString) : name
        if var favorite {
            if favorite.url.host() != url.host() { favorite.icon = nil }
            favorite.title = shownName
            favorite.url = url
            Favorites.shared.update(favorite)
        } else {
            Favorites.shared.add(title: shownName, url: url)
        }
        dismiss()
    }
}
