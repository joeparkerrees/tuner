import AppKit

/// The dial again at 14pt: a ring with the bead where you're tuned, or the
/// numbered square while NTS 1 or 2 is on. Filled solid while it's playing,
/// so you can tell from across the menu bar.
enum MenuBarIcon {
    static func image(position: Int, of count: Int, channel: String?, playing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            if let channel {
                drawChannel(channel, in: rect.insetBy(dx: 2.5, dy: 2.5), playing: playing)
                return true
            }
            let ring = rect.insetBy(dx: 2, dy: 2)
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

    private static func drawChannel(_ channel: String, in square: CGRect, playing: Bool) {
        let shape = NSBezierPath(roundedRect: square.insetBy(dx: 0.6, dy: 0.6), xRadius: 2, yRadius: 2)
        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let text = NSAttributedString(string: channel, attributes: [.font: font, .foregroundColor: NSColor.black])
        let size = text.size()
        let origin = CGPoint(x: square.midX - size.width / 2, y: square.midY - size.height / 2 + 0.5)

        NSColor.black.set()
        if playing {
            shape.fill()
            // Knock the number out of the filled square.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            text.draw(at: origin)
        } else {
            shape.lineWidth = 1.2
            shape.stroke()
            text.draw(at: origin)
        }
    }
}
