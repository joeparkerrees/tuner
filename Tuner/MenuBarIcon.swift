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
        guard let context = NSGraphicsContext.current?.cgContext,
              let digit = outline(of: channel, size: 9) else { return }
        // Drawn as a shape, so it doesn't snap to the pixel grid the way text
        // does. Centred on its ink across, since the 1's thin flag would
        // otherwise leave its stem right of centre, and on its outline down.
        let box = digit.boundingBoxOfPath
        let offset = CGPoint(x: ring.midX - inkCentreX(of: digit), y: ring.midY - box.midY)

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
        context.translateBy(x: offset.x, y: offset.y)
        context.addPath(digit)
        context.fillPath()
    }

    private static func outline(of character: String, size: CGFloat) -> CGPath? {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
        var characters = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { return nil }
        return CTFontCreatePathForGlyph(font, glyphs[0], nil)
    }

    /// Where the glyph's ink balances left to right, found by filling it into
    /// a small offscreen bitmap.
    private static func inkCentreX(of path: CGPath) -> CGFloat {
        let box = path.boundingBoxOfPath
        let scale: CGFloat = 16
        let width = Int((box.width * scale).rounded(.up)), height = Int((box.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = bitmap.data else { return box.midX }
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.translateBy(x: -box.minX, y: -box.minY)
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.addPath(path)
        bitmap.fillPath()

        let pixels = data.bindMemory(to: UInt8.self, capacity: bitmap.bytesPerRow * height)
        var moment = 0.0, ink = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let value = Double(pixels[y * bitmap.bytesPerRow + x])
                moment += value * (Double(x) + 0.5)
                ink += value
            }
        }
        return ink > 0 ? box.minX + CGFloat(moment / ink) / scale : box.midX
    }
}
