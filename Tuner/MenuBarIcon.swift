import AppKit
import CoreText

/// The dial again at 14pt: a ring with the bead where you're tuned, or with
/// the channel number in it while NTS 1 or 2 is on, like the badges in the
/// panel. Filled solid while it's playing, so you can tell from across the
/// menu bar.
enum MenuBarIcon {
    static func image(position: Int, of count: Int, channel: String?, playing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ring = rect.insetBy(dx: 2, dy: 2)
            if let channel {
                drawChannel(channel, in: ring, playing: playing)
                return true
            }
            let center = CGPoint(x: ring.midX, y: ring.midY)
            let angle = Double(position) / Double(count) * 2 * .pi
            let orbit = ring.width / 2 - 3.6
            let bead = CGPoint(x: center.x + orbit * sin(angle), y: center.y + orbit * cos(angle))
            let beadRect = CGRect(x: bead.x - 1.9, y: bead.y - 1.9, width: 3.8, height: 3.8)

            NSColor.black.set()
            if playing {
                NSBezierPath(ovalIn: ring).fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: beadRect).fill()
            } else {
                let outline = NSBezierPath(ovalIn: ring.insetBy(dx: 0.6, dy: 0.6))
                outline.lineWidth = 1.2
                outline.stroke()
                NSBezierPath(ovalIn: beadRect).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawChannel(_ channel: String, in ring: CGRect, playing: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: channel, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
        // Centre the digit's own outline, not its line box, so it sits optically
        // in the middle of the ring.
        let glyph = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let origin = CGPoint(x: ring.midX - glyph.midX, y: ring.midY - glyph.midY)

        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.black.cgColor)
        if playing {
            context.fillEllipse(in: ring)
            // Knock the number out of the filled disc.
            context.setBlendMode(.destinationOut)
        } else {
            context.setLineWidth(1.2)
            context.strokeEllipse(in: ring.insetBy(dx: 0.6, dy: 0.6))
        }
        context.textPosition = origin
        CTLineDraw(line, context)
    }
}
