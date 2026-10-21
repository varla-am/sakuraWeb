import SwiftUI

// MARK: - Start page

struct StartPage: View {
    let open: (URL) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                // Centered in the page, the tracker card at the bottom; it scrolls when the window is short
                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 80, height: 80)
                        Text("Sakura")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Sakura Homepage")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Favorites")
                            .font(.headline)
                            // Lines up with the first tile's icon, not the edge of its cell
                            .padding(.leading, FavoritesGrid.iconInset)
                        FavoritesGrid(open: open)
                    }
                    Spacer(minLength: 0)
                    TrackerCard()
                }
                .padding(40)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque, so a website under sakura://homepage doesn't show through
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color(nsColor: .textBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
        )
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// How many trackers Sakura has stopped so far
private struct TrackerCard: View {
    @ObservedObject private var trackers = Trackers.shared
    @AppStorage(Trackers.enabledKey) private var isEnabled = true

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isEnabled ? "shield.lefthalf.filled" : "shield.slash")
                .font(.system(size: 24))
                .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
            Text(trackers.blockedCount, format: .number)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.snappy, value: trackers.blockedCount)
            Text(isEnabled ? "Trackers blocked" : "Tracker blocking is off")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(width: 160, height: 140)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .help("Counted on the pages you open; requests a page makes without an element on it aren't seen")
    }
}
