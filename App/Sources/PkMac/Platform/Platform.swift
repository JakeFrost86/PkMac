import SwiftUI

// Shared code between PkMac for macOS and PkMac for iPhone / iPad.
// On iOS the few AppKit names the views use are mapped to UIKit equivalents, and Liquid Glass
// (iOS 26+) falls back to the classic materials on older systems.

#if os(iOS)
import UIKit

typealias NSImage = UIImage

extension UIImage {
    convenience init?(contentsOf url: URL) { self.init(contentsOfFile: url.path) }
}

extension Image {
    init(nsImage: UIImage) { self.init(uiImage: nsImage) }
}

/// Clipboard (text only).
final class NSPasteboard {
    enum PasteboardType { case string }
    nonisolated(unsafe) static let general = NSPasteboard()
    func clearContents() {}
    @discardableResult func setString(_ s: String, forType: PasteboardType) -> Bool { UIPasteboard.general.string = s; return true }
    func string(forType: PasteboardType) -> String? { UIPasteboard.general.string }
}

/// No modifier keys on touch screens (⌥-drag to copy is a Mac gesture).
enum NSEvent {
    struct ModifierFlags: OptionSet { let rawValue: Int; static let option = ModifierFlags(rawValue: 1) }
    static var modifierFlags: ModifierFlags { [] }
}

/// Opening URLs; revealing files in Finder has no iOS equivalent.
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    @discardableResult func open(_ url: URL) -> Bool {
        if url.isFileURL { return false }
        UIApplication.shared.open(url)
        return true
    }
    func activateFileViewerSelecting(_ urls: [URL]) {}
}
#endif

// MARK: - Liquid Glass with a fallback before iOS 26

struct PKGlassButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if prominent { Button(configuration).buttonStyle(.glassProminent) } else { Button(configuration).buttonStyle(.glass) }
        } else {
            if prominent { Button(configuration).buttonStyle(.borderedProminent) } else { Button(configuration).buttonStyle(.bordered) }
        }
    }
}

extension PrimitiveButtonStyle where Self == PKGlassButtonStyle {
    static var pkGlass: PKGlassButtonStyle { PKGlassButtonStyle() }
    static var pkGlassProminent: PKGlassButtonStyle { PKGlassButtonStyle(prominent: true) }
}

/// The glass variants PkMac uses.
enum PKGlass {
    case regular, clear, interactive, tinted(Color)
}

extension View {
    @ViewBuilder func pkGlassEffect<S: Shape>(_ glass: PKGlass = .regular, in shape: S) -> some View {
        if #available(iOS 26, macOS 26, *) {
            switch glass {
            case .regular: glassEffect(.regular, in: shape)
            case .clear: glassEffect(.clear, in: shape)
            case .interactive: glassEffect(.regular.interactive(), in: shape)
            case .tinted(let c): glassEffect(.regular.tint(c), in: shape)
            }
        } else {
            switch glass {
            case .clear: self
            case .tinted(let c): background(c.opacity(0.18), in: shape).background(.ultraThinMaterial, in: shape)
            default: background(.ultraThinMaterial, in: shape)
            }
        }
    }
}

/// GlassEffectContainer on iOS 26+ / macOS 26, a plain group before.
struct PKGlassContainer<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content
    @Environment(\.pkCompact) private var compact
    var body: some View {
        // Narrow screens: the action buttons of a header show only their icons.
        Group {
            if #available(iOS 26, macOS 26, *) {
                GlassEffectContainer(spacing: spacing) { content }
            } else {
                content
            }
        }
        .modifier(PKIconOnlyIfCompact(compact: compact))
    }
}

private struct PKIconOnlyIfCompact: ViewModifier {
    var compact: Bool
    func body(content: Content) -> some View {
        if compact { content.labelStyle(.iconOnly) } else { content }
    }
}

// MARK: - Settings

/// Opens Settings: the Settings window on macOS, a sheet on iPhone / iPad.
struct SettingsButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var label: Label
    var body: some View {
        #if os(macOS)
        SettingsLink { label }
        #else
        Button { model.showSettings = true } label: { label }
        #endif
    }
}

enum Platform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif
}

// MARK: - Mac-only modifiers

extension View {
    /// Window subtitle on macOS; navigation subtitle from iOS 26.
    @ViewBuilder func pkNavigationSubtitle(_ text: String) -> some View {
        #if os(macOS)
        navigationSubtitle(text)
        #else
        if #available(iOS 26, *) { navigationSubtitle(text) } else { self }
        #endif
    }

    /// Esc on macOS; there is no Esc key on a touch screen.
    @ViewBuilder func pkOnExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}

// MARK: - Colors

extension Color {
    /// `mix(with:by:)` (macOS 15 / iOS 18) with an sRGB blend on iOS 17.
    func pkMix(with other: Color, by fraction: Double) -> Color {
        if #available(iOS 18, macOS 15, *) { return mix(with: other, by: fraction) }
        #if os(iOS)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = CGFloat(fraction)
        return Color(.sRGB, red: Double(r1 + (r2 - r1) * f), green: Double(g1 + (g2 - g1) * f), blue: Double(b1 + (b2 - b1) * f), opacity: Double(a1 + (a2 - a1) * f))
        #else
        return self
        #endif
    }
}

extension View {
    /// Compact text-field date picker on macOS, the compact button style on iOS.
    @ViewBuilder func pkFieldDatePicker() -> some View {
        #if os(macOS)
        datePickerStyle(.field)
        #else
        datePickerStyle(.compact)
        #endif
    }
}

// MARK: - Narrow layouts (iPhone, iPhone Duo closed, iPad split screen)

private struct PKCompactKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when the window is narrow (horizontal size class compact). Always false on macOS.
    var pkCompact: Bool {
        get { self[PKCompactKey.self] }
        set { self[PKCompactKey.self] = newValue }
    }
}

#if os(iOS)
/// Publishes the size class as `pkCompact` for the shared views.
struct PKSizeClassReader: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        content.environment(\.pkCompact, sizeClass == .compact)
    }
}
#endif

/// Sets `pkCompact` from the width actually available to the content (an iPad in portrait with the
/// sidebar open is "regular" but leaves a narrow column). iOS only; macOS keeps its layout.
struct PKWidthReader: ViewModifier {
    var threshold: CGFloat = 700
    @State private var width: CGFloat = 10_000
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .environment(\.pkCompact, width < threshold)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { _, w in width = w }
            })
        #else
        content
        #endif
    }
}

/// Page padding that shrinks on narrow screens.
private struct PKPadding: ViewModifier {
    @Environment(\.pkCompact) private var compact
    var edges: Edge.Set
    var length: CGFloat
    func body(content: Content) -> some View {
        content.padding(edges, compact ? min(length, 14) : length)
    }
}

extension View {
    func pkPadding(_ length: CGFloat) -> some View { modifier(PKPadding(edges: .all, length: length)) }
    func pkPadding(_ edges: Edge.Set, _ length: CGFloat) -> some View { modifier(PKPadding(edges: edges, length: length)) }
}

/// Side by side on wide screens, one under the other on narrow ones.
struct PKAdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.pkCompact) private var compact
    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: .top, spacing: spacing) { content }
        }
    }
}

// MARK: - Sheets and popovers

extension View {
    /// Fixed sheet size on macOS; on iPhone / iPad the sheet decides and the content fills it.
    @ViewBuilder func pkSheetFrame(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    /// Fixed popover size on macOS. On iPad the popover gets the same size; on iPhone it becomes a
    /// sheet (half height, can be pulled up) and the content fills it.
    @ViewBuilder func pkPopoverFrame(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        frame(minWidth: min(width, 300), idealWidth: width, minHeight: height.map { min($0, 260) }, idealHeight: height)
            .presentationDetents([.medium, .large])
        #endif
    }

    /// iPhone / iPad: the content scrolls when it is taller than the sheet. macOS: unchanged.
    @ViewBuilder func pkSheetScroll() -> some View {
        #if os(macOS)
        self
        #else
        ScrollView { self }
        #endif
    }
}

/// The content as is; on narrow screens `extra` follows on its own row.
struct PKCompactWrap<Content: View, Extra: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    @ViewBuilder var extra: Extra
    @Environment(\.pkCompact) private var compact
    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: spacing) { content; extra }
        } else {
            content
        }
    }
}
