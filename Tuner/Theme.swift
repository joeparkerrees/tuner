import SwiftUI

/// Flat, Braun-leaning palette: white objects on a pale grey ground,
/// near-black ink, greys for everything secondary and a single Braun red.
enum Theme {
    static let ink = Color(hex: 0x1D1D1D)
    static let paper = Color.white
    static let ground = Color(hex: 0xEEEEEE)
    static let line = Color(hex: 0xDDDDDD)
    static let faint = Color(hex: 0xC8C8C8)
    static let muted = Color(hex: 0xA1A1A1)
    static let hover = Color(hex: 0xF6F6F6)
    /// The one colour, sampled from the power button on a Braun T 1000: the
    /// NTS 1 badge and the small playing dots.
    static let red = Color(hex: 0xE0330C)

    static let panelWidth: CGFloat = 280
    static let gutter: CGFloat = 12
    static let cardRadius: CGFloat = 12

    /// Settle: items land fast and ease the last few pixels.
    static let settle = Animation.timingCurve(0, 0.5, 0.2, 1, duration: 0.35)
    /// Detent-to-detent travel for the tuning bead.
    static let detent = Animation.snappy(duration: 0.26, extraBounce: 0)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
