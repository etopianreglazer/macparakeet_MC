import SwiftUI

// The user-selectable accent (design: "Wind Palette Export" / SevenAccentsColorVariations).
// Seven accents, each a full role set. Only the BRAND surfaces are themed — the
// island's idle/ready glow + mark, and the card's brand (buttons, glyph tile,
// toggles, selection). The status colours (recording red, transcribing amber,
// done green, warning amber) are semantic and never themed, per the export's
// `--state-record / --state-done / --state-warn` note.

struct SplayAccent: Identifiable, Equatable, Sendable {
    let id: String        // stable key, e.g. "iris"
    let name: String      // display, e.g. "Iris"
    let accentHex: String // --accent      : brand on light (buttons, selection, card)
    let hoverHex: String  // --accent-hover
    let brightHex: String // --accent-dark : the bright-on-dark colour — island fiber/glow + mark
    let groundTopHex: String
    let groundBaseHex: String

    var brand: Color { Self.color(accentHex) }
    var brandHover: Color { Self.color(hoverHex) }
    /// The colour the island wears on its near-black surface (fiber, bloom, mark).
    var islandBright: Color { Self.color(brightHex) }
    var groundTop: Color { Self.color(groundTopHex) }
    var groundBase: Color { Self.color(groundBaseHex) }

    static func color(_ hex: String) -> Color {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        let n = UInt32(s, radix: 16) ?? 0
        return Color(.sRGB,
                     red: Double((n >> 16) & 0xFF) / 255,
                     green: Double((n >> 8) & 0xFF) / 255,
                     blue: Double(n & 0xFF) / 255,
                     opacity: 1)
    }
}

extension SplayAccent {
    // The seven accents, in the export's order. Iris is the current Splay lavender.
    static let ember  = SplayAccent(id: "ember",  name: "Ember",  accentHex: "#8A3316", hoverHex: "#A8411E", brightHex: "#F0906A", groundTopHex: "#FFEDE3", groundBaseHex: "#FFD6C4")
    static let marine = SplayAccent(id: "marine", name: "Marine", accentHex: "#0E6273", hoverHex: "#147E94", brightHex: "#7FD3E3", groundTopHex: "#EAF4F7", groundBaseHex: "#CFE7EE")
    static let amber  = SplayAccent(id: "amber",  name: "Amber",  accentHex: "#A8710F", hoverHex: "#C88A18", brightHex: "#F2C264", groundTopHex: "#FDF4DC", groundBaseHex: "#F7E3B0")
    static let iris   = SplayAccent(id: "iris",   name: "Iris",   accentHex: "#4A38A6", hoverHex: "#5D49C4", brightHex: "#A99BF2", groundTopHex: "#EFEBFC", groundBaseHex: "#DCD4F6")
    static let fern   = SplayAccent(id: "fern",   name: "Fern",   accentHex: "#1C6A49", hoverHex: "#26855C", brightHex: "#7FD8AE", groundTopHex: "#EBF6EE", groundBaseHex: "#D2E9DA")
    static let rose   = SplayAccent(id: "rose",   name: "Rose",   accentHex: "#B02657", hoverHex: "#CC3670", brightHex: "#F394B4", groundTopHex: "#FFF0F4", groundBaseHex: "#FBD9E3")
    // Vibrant Pantone "Living Coral"-anchored — pinker + more saturated than the
    // export's orange-brown coral (user: "too close to plain orange, want it vibrant").
    static let coral  = SplayAccent(id: "coral",  name: "Coral",  accentHex: "#FB5E4D", hoverHex: "#FF7263", brightHex: "#FF9A8C", groundTopHex: "#FFF0EC", groundBaseHex: "#FFD8CE")

    static let all: [SplayAccent] = [ember, marine, amber, iris, fern, rose, coral]

    static func named(_ id: String) -> SplayAccent { all.first { $0.id == id } ?? iris }
}

/// The process-wide accent selection. `@Observable`, so any SwiftUI view that
/// reads `SplayTheme.shared.accent` in its body recolours live the moment the
/// user picks a swatch — the island and the open card update together.
@MainActor
@Observable
final class SplayTheme {
    static let shared = SplayTheme()

    static let defaultsKey = "splay.accent"

    var accent: SplayAccent {
        didSet {
            guard accent != oldValue else { return }
            UserDefaults.standard.set(accent.id, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let id = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? SplayAccent.iris.id
        accent = SplayAccent.named(id)
    }
}
