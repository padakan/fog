import SwiftUI
import AppKit

enum ColorMode: String, Codable {
    case solid
    case gradient
}

/// A selectable color theme for the border.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let mode: ColorMode
    let colors: [Color]

    var primary: Color { colors.first ?? .orange }

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }
}

enum Themes {
    /// Solid single-hue templates. Claude orange is the default.
    static let solid: [Theme] = [
        Theme(id: "solid.claude",  name: "Claude Orange", mode: .solid, colors: [Color(hex: 0xD97757)]),
        Theme(id: "solid.sky",     name: "Sky",           mode: .solid, colors: [Color(hex: 0x38BDF8)]),
        Theme(id: "solid.violet",  name: "Violet",        mode: .solid, colors: [Color(hex: 0xA78BFA)]),
        Theme(id: "solid.emerald", name: "Emerald",       mode: .solid, colors: [Color(hex: 0x34D399)]),
    ]

    /// Gradient templates based on AI tool branding palettes.
    static let gradient: [Theme] = [
        Theme(id: "grad.claude", name: "Claude", mode: .gradient,
              colors: [Color(hex: 0xD97757), Color(hex: 0xE9A06B), Color(hex: 0xCC5C3A)]),
        Theme(id: "grad.gemini", name: "Gemini", mode: .gradient,
              colors: [Color(hex: 0x4285F4), Color(hex: 0x9B72CB), Color(hex: 0xD96570)]),
        Theme(id: "grad.codex",  name: "Codex",  mode: .gradient,
              colors: [Color(hex: 0x10A37F), Color(hex: 0x19C37D), Color(hex: 0x0E8C6B)]),
        Theme(id: "grad.cursor", name: "Cursor", mode: .gradient,
              colors: [Color(hex: 0x7C5CFF), Color(hex: 0x3B82F6), Color(hex: 0x22D3EE)]),
    ]

    static let all = solid + gradient
    static let `default` = solid[0]

    static func by(id: String?) -> Theme {
        all.first { $0.id == id } ?? `default`
    }
}

/// Codable form of a custom theme for UserDefaults.
struct StoredTheme: Codable {
    var id: String
    var name: String
    var mode: String
    var hexes: [UInt]

    init(_ t: Theme) {
        id = t.id
        name = t.name
        mode = t.mode.rawValue
        hexes = t.colors.map { $0.hexValue }
    }

    var theme: Theme {
        Theme(id: id, name: name,
              mode: ColorMode(rawValue: mode) ?? .solid,
              colors: hexes.map { Color(hex: $0) })
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue:  Double(hex & 0xff) / 255,
            opacity: 1
        )
    }

    var hexValue: UInt {
        let n = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = UInt((n.redComponent * 255).rounded()) & 0xff
        let g = UInt((n.greenComponent * 255).rounded()) & 0xff
        let b = UInt((n.blueComponent * 255).rounded()) & 0xff
        return (r << 16) | (g << 8) | b
    }

    /// Blend toward white by `amount` (0...1).
    func brightened(_ amount: Double) -> Color {
        let n = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(
            .sRGB,
            red:   min(1, n.redComponent + amount),
            green: min(1, n.greenComponent + amount),
            blue:  min(1, n.blueComponent + amount),
            opacity: 1
        )
    }
}
