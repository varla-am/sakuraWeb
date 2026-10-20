import SwiftUI

/// The look of Sakura's own toolbar pieces: classic (like macOS Sequoia) or Liquid Glass
enum Chrome {
    static let liquidGlassKey = "liquidGlass"
    static let glassTintKey = "glassTint"

    /// 0 is fully clear glass, 1 is glass tinted with the window color
    static func glass(tint: Double) -> Glass {
        let base: Glass = tint < 0.02 ? .clear : .regular
        return base.tint(tint < 0.02 ? nil : Color(nsColor: .windowBackgroundColor).opacity(tint * 0.75))
    }
}

extension Chrome {
    /// How much the window color covers the blurred desktop behind the sidebar.
    /// Never below 0.55, so wallpaper and other windows never show through in color
    static func windowOpacity(glass: Bool, tint: Double) -> Double {
        glass ? 0.55 + 0.4 * tint : 0.82
    }
}

/// The window behind the sidebar and the page card: blurred desktop, mostly covered by the window color
struct WindowTint: View {
    let glass: Bool
    let tint: Double

    var body: some View {
        ZStack {
            BehindWindowBlur()
            Color(nsColor: .windowBackgroundColor).opacity(Chrome.windowOpacity(glass: glass, tint: tint))
            Color.accentColor.opacity(0.07)
        }
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Glass in the given shape, or the classic fill when Liquid Glass is off
    @ViewBuilder
    func chrome(in shape: some Shape, glass: Bool, tint: Double, classic: some ShapeStyle = Color.clear) -> some View {
        if glass {
            glassEffect(Chrome.glass(tint: tint), in: shape)
        } else {
            background(classic, in: shape)
        }
    }
}

/// A toolbar icon button: a plain symbol with a hover highlight, like Sequoia's toolbar
struct ToolbarIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarIcon(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct ToolbarIcon<Content: View>: View {
        let label: Content
        let isPressed: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 26)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isPressed ? 0.14 : isHovered && isEnabled ? 0.07 : 0))
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
