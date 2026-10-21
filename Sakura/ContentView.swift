import SwiftUI
import WebKit

struct BrowserWindow: View {
    @StateObject private var browser = Browser()
    @AppStorage(Chrome.liquidGlassKey) private var liquidGlass = false
    @AppStorage(Chrome.glassTintKey) private var glassTint = 0.5
    @AppStorage("sidebarWidth") private var sidebarWidth = 250.0

    /// The sidebar as a column beside the page, which only a window has; otherwise it floats as an island
    private var isDocked: Bool { browser.isSidebarVisible && !browser.isFullScreen }
    private var showsIsland: Bool { !isDocked && browser.isPeeking }

    var body: some View {
        HStack(spacing: 0) {
            if isDocked {
                Sidebar(glass: liquidGlass, tint: glassTint, isIsland: false)
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) { ResizeHandle(width: $sidebarWidth) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            PageCard()
                .padding(.top, isDocked ? 8 : 30)
                .padding([.bottom, .trailing], 8)
                .padding(.leading, isDocked ? 0 : 8)
        }
        .background { WindowTint(glass: liquidGlass, tint: glassTint) }
        .overlay(alignment: .topLeading) {
            // With the sidebar hidden, its button stays right after the traffic lights (at the edge in full screen)
            if !isDocked {
                SidebarButton()
                    .padding(.leading, browser.controlsStart.x + SidebarButton.gap)
                    .padding(.top, browser.controlsStart.y - SidebarButton.height / 2)
            }
        }
        .overlay(alignment: .leading) {
            if !isDocked {
                // An invisible strip at the left edge: touching it slides the island out
                Color.clear
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { withAnimation(.snappy) { browser.isPeeking = true } }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if showsIsland {
                Sidebar(glass: liquidGlass, tint: glassTint, isIsland: true)
                    .frame(width: sidebarWidth)
                    .chrome(in: RoundedRectangle(cornerRadius: 14), glass: liquidGlass, tint: glassTint,
                            classic: Material.regular)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                    .overlay(alignment: .trailing) { ResizeHandle(width: $sidebarWidth) }
                    // Below the traffic lights in a window, from the top in full screen
                    .padding(.top, browser.isFullScreen ? 8 : 30)
                    .padding([.leading, .bottom], 8)
                    .onHover { inside in
                        if !inside { withAnimation(.snappy) { browser.isPeeking = false } }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 640)
        .navigationTitle(browser.selected?.displayTitle ?? "Sakura")
        .background(WindowReader(browser: browser))
        .environmentObject(browser)
        .focusedSceneObject(browser)
        // HTML files from Finder (Open With, a double-click, the Dock icon) open as tabs in this window,
        // instead of SwiftUI making a new window for each
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            if url.isFileURL { browser.openFile(url) }
        }
    }
}

// MARK: - The page

private struct PageCard: View {
    @EnvironmentObject private var browser: Browser

    var body: some View {
        ZStack {
            if let tab = browser.selected {
                TabPage(tab: tab).id(tab.id)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

private struct TabPage: View {
    @ObservedObject var tab: Tab

    var body: some View {
        ZStack(alignment: .top) {
            WebView(tab: tab)
            switch tab.shownPage {
            case .homepage: StartPage { tab.load($0) }
            case .extensions: ExtensionsPage()
            case nil: EmptyView()
            }
            if let error = tab.error {
                ErrorPage(message: error) { tab.retry() }
            }
            if let missing = tab.missingPage {
                MissingPage(address: missing.absoluteString) { tab.load(SakuraPage.homepage.url) }
            }
            if tab.isLoading, tab.page == nil, tab.missingPage == nil {
                ProgressBar(progress: tab.progress)
            }
        }
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * max(0.05, progress))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
    }
}

private struct ErrorPage: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't Open This Page", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// sakura://something that Sakura doesn't have
private struct MissingPage: View {
    let address: String
    let goHome: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No such Sakura page", systemImage: "questionmark.square.dashed")
        } description: {
            Text("\(address) isn't one of Sakura's pages. Try sakura://homepage or sakura://extensions.")
        } actions: {
            // No Return shortcut: Return belongs to the address bar, which often has focus here
            Button("Open Homepage", action: goHome)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
