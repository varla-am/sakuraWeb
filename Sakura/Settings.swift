import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PasswordsSettings()
                .tabItem {
                    Label("Passwords", systemImage: "key.fill")
                }

            AboutSettings()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480)
    }
}

struct GeneralSettingsTab: View {
    @AppStorage(Homepage.key) private var homepage = ""
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage(Chrome.liquidGlassKey) private var liquidGlass = false
    @AppStorage(Chrome.glassTintKey) private var glassTint = 0.5
    @AppStorage("searchEngine") private var searchEngine = SearchEngine.duckDuckGo
    @AppStorage("language") private var language = AppLanguage.system
    @AppStorage(Trackers.enabledKey) private var blockTrackers = true
    /// The language Sakura was launched with; a different pick needs a restart
    @State private var launchLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system

    var body: some View {
        Form {
            TextField("Homepage", text: $homepage, prompt: Text("Sakura Homepage"))

            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { appearance.apply() }

            Section {
                Toggle("Liquid Glass", isOn: $liquidGlass.animation())
                if liquidGlass {
                    GlassPreview(tint: glassTint)
                    Slider(value: $glassTint, in: 0...1) {
                        Text("Glass")
                    } minimumValueLabel: {
                        Text("Clear")
                    } maximumValueLabel: {
                        Text("Tinted")
                    }
                }
            } footer: {
                if !liquidGlass {
                    Text("Off: the classic look, like macOS Sequoia.")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Search Engine", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
            }

            Section {
                Toggle("Block Trackers", isOn: $blockTrackers)
                    .onChange(of: blockTrackers) { Trackers.shared.update() }
            } footer: {
                Text("Analytics and ad trackers don't load. Sakura keeps no history either.")
                    .foregroundStyle(.secondary)
            }

            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: language) { language.apply() }

            if language != launchLanguage {
                HStack {
                    Text("Restart Sakura to change the language.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now", action: restart)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
