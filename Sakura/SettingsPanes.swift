import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A tiny Sakura window over a colorful desktop, so the slider's effect is visible right away
struct GlassPreview: View {
    let tint: Double

    var body: some View {
        ZStack {
            // The "desktop" behind the window
            LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.75), Color(red: 0.55, green: 0.42, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 1, green: 0.85, blue: 0.3)).frame(width: 70).offset(x: -120, y: -30)
            Circle().fill(.white.opacity(0.8)).frame(width: 40).offset(x: -60, y: 40)

            HStack(spacing: 6) {
                // Sidebar: blurred desktop, mostly covered by the window color
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 7) }
                    }
                    .padding(.bottom, 4)
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 5).fill(.clear)
                        .chrome(in: RoundedRectangle(cornerRadius: 5), glass: true, tint: tint)
                        .frame(height: 16)
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.12)).frame(width: 60, height: 6)
                            .frame(height: 16, alignment: .leading).padding(.leading, 6)
                    }
                    Spacer()
                }
                .padding(8)
                .frame(width: 110)

                // The page card
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .padding([.vertical, .trailing], 6)
            }
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color(nsColor: .windowBackgroundColor).opacity(Chrome.windowOpacity(glass: true, tint: tint))
                    Color.accentColor.opacity(0.07)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(14)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

/// The logins Sakura has saved, with a way to reveal or remove each one
struct PasswordsSettings: View {
    @State private var credentials: [WebCredential] = []
    @State private var revealed: Set<String> = []
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if credentials.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Passwords", systemImage: "key")
                    } description: {
                        Text("Passwords you save while browsing appear here. You can also import a CSV.")
                    }
                } else {
                    List {
                        ForEach(credentials) { credential in
                            Row(credential: credential,
                                isRevealed: revealed.contains(credential.id),
                                toggle: { toggle(credential) },
                                remove: { remove(credential) })
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack(spacing: 10) {
                Button {
                    importCSV()
                } label: {
                    Label("Import from CSV…", systemImage: "square.and.arrow.down")
                }
                .help("Import a passwords CSV exported from Apple Passwords, Chrome, and others")
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(height: 360)
        .onAppear { credentials = PasswordStore.all() }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a passwords CSV exported from Apple Passwords, Chrome, or similar.")
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let result = PasswordImport.importCSV(at: url)
        credentials = PasswordStore.all()
        revealed = []
        status = String(localized: "Imported \(result.imported), skipped \(result.skipped).")
    }

    private func toggle(_ credential: WebCredential) {
        if revealed.contains(credential.id) { revealed.remove(credential.id) } else { revealed.insert(credential.id) }
    }

    private func remove(_ credential: WebCredential) {
        PasswordStore.remove(host: credential.host, username: credential.username)
        revealed.remove(credential.id)
        credentials = PasswordStore.all()
    }

    private struct Row: View {
        let credential: WebCredential
        let isRevealed: Bool
        let toggle: () -> Void
        let remove: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credential.host)
                        .fontWeight(.medium)
                    Text(credential.username.isEmpty ? String(localized: "No username") : credential.username)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(isRevealed ? credential.password : "••••••••")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(action: toggle) {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide password" : "Show password")
                Button(action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this password")
            }
            .padding(.vertical, 2)
        }
    }
}

struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("Sakura")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(verbatim: "© Varlaam (varla-am) 2026")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
