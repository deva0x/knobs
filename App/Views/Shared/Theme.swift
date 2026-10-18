import AppKit
import KnobsCore
import SwiftUI

extension Color {
    /// Knobs' signal orange (#FF5B1F). Only for the primary action and the brand mark (docs/DESIGN.md).
    static let signal = Color(red: 1, green: 91 / 255, blue: 31 / 255)
    /// Card and well outlines: the system separator color, which adapts to light, dark and increased contrast.
    static let hairline = Color(nsColor: .separatorColor)
}

extension Font {
    /// Section headers: 13 pt semibold (docs/DESIGN.md, Type). Use with the secondary color.
    static let sectionHeader = Font.body.weight(.semibold)
    /// Captions and help: 11 pt. On macOS `.caption` is 10 pt, which is below the spec.
    static let helpText = Font.subheadline
}

extension Tint {
    /// The system color for a manifest tint. System colors adapt to light and dark mode on their own.
    var color: Color {
        switch self {
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        case .indigo: .indigo
        case .orange: .orange
        case .blue: .blue
        case .gray: .gray
        case .green: .green
        case .cyan: .cyan
        case .brown: .brown
        case .pink: .pink
        case .yellow: .yellow
        case .mint: .mint
        }
    }
}

/// Spacing and shape tokens from docs/DESIGN.md, so every view uses the same scale.
enum Metrics {
    static let cardRadius: CGFloat = 14
    static let wellRadius: CGFloat = 12
    static let contentMaxWidth: CGFloat = 720
    static let springResponse: Double = 0.35
}

extension Animation {
    /// The one spring used for state changes: subtle and quick.
    static let knobs = Animation.spring(response: Metrics.springResponse, dampingFraction: 0.86)
}

extension View {
    /// A neutral glass button for second choices. `.glass` fills with any tint set above it, and task screens set
    /// the tool's tint for their one accent (docs/DESIGN.md, Brand).
    func secondaryGlassButton() -> some View {
        buttonStyle(.glass).tint(nil)
    }

    /// A transition that becomes a plain crossfade when Reduce Motion is on (docs/DESIGN.md, Motion).
    func knobsTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionAwareTransition(transition: transition))
    }
}

private struct MotionAwareTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum ByteCount {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
