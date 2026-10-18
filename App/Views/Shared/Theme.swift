import AppKit
import KnobsCore
import SwiftUI

extension Color {
    /// Knobs' signal orange (#FF5B1F). Only for the primary action and the brand mark (docs/DESIGN.md).
    static let signal = Color(red: 1, green: 91 / 255, blue: 31 / 255)
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
    static let gridUnit: CGFloat = 4
    static let cardRadius: CGFloat = 14
    static let wellRadius: CGFloat = 12
    static let contentMaxWidth: CGFloat = 720
    static let springResponse: Double = 0.35
}

extension Animation {
    /// The one spring used for state changes: subtle and quick.
    static let knobs = Animation.spring(response: Metrics.springResponse, dampingFraction: 0.86)
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
