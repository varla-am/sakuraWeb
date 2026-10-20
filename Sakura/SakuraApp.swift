import SwiftUI
import WebKit

@main
struct SakuraApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            BrowserCommands()
            ExtensionCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.current.apply()
    }
}

// MARK: - Menus

private struct BrowserCommands: Commands {
    @FocusedObject private var browser: Browser?

    private var tab: Tab? { browser?.selected }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { browser?.openNewTab() }
                .keyboardShortcut("t")
            Button("Open Location…") { browser?.focusAddress() }
                .keyboardShortcut("l")
            Button("Close Tab") { browser?.closeSelected() }
                .keyboardShortcut("w")
        }

        CommandGroup(replacing: .sidebar) {
            Button(browser?.showsSidebar == false ? "Show Sidebar" : "Hide Sidebar") {
                withAnimation(.snappy) { browser?.toggleSidebar() }
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        CommandGroup(after: .toolbar) {
            Button("Reload Page") { tab?.webView.reload() }
                .keyboardShortcut("r")
            Button("Stop") { tab?.webView.stopLoading() }
                .keyboardShortcut(".")
            Divider()
            Button("Zoom In") { tab?.zoom(by: 0.1) }
                .keyboardShortcut("=")
            Button("Zoom Out") { tab?.zoom(by: -0.1) }
                .keyboardShortcut("-")
            Button("Actual Size") { tab?.webView.pageZoom = 1 }
                .keyboardShortcut("0")
            Divider()
        }

        CommandMenu("History") {
            Button("Back") { tab?.webView.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { tab?.webView.goForward() }
                .keyboardShortcut("]")
        }

        CommandGroup(before: .windowArrangement) {
            Button("Show Previous Tab") { browser?.selectTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Show Next Tab") { browser?.selectTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Divider()
        }
    }
}

private struct ExtensionCommands: Commands {
    @ObservedObject private var extensions = Extensions.shared

    var body: some Commands {
        CommandMenu("Extensions") {
            Button("Load Unpacked Extension…") { extensions.chooseUnpackedExtension() }
            if !extensions.contexts.isEmpty {
                Divider()
            }
            ForEach(extensions.contexts, id: \.uniqueIdentifier) { context in
                Menu(context.webExtension.displayName ?? context.uniqueIdentifier) {
                    if context.optionsPageURL != nil {
                        Button("Settings…") { extensions.openOptions(for: context) }
                    }
                    Button("Remove") { extensions.remove(context) }
                }
            }
            if !extensions.failures.isEmpty {
                Divider()
                Menu("Failed to Load") {
                    ForEach(extensions.failures, id: \.self) { Text($0) }
                }
            }
        }
    }
}
