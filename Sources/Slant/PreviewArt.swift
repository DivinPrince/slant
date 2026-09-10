import AppKit

/// The sample desktop shown in the settings preview: a dusk sky, a moon, two hills
/// and the lock-screen clock, drawn with Core Graphics so no image ships with the app.
enum PreviewArt {
    static let aspect: CGFloat = 280.0 / 182.0

    static func image(width: Int = 1400) -> CGImage? {
        let height = Int(CGFloat(width) / aspect)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Work in the SVG's 280x182 space with y pointing down.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / 280, y: -CGFloat(height) / 182)

        func gradient(_ from: String, _ to: String) -> CGGradient {
            CGGradient(colorsSpace: colorSpace, colors: [color(from), color(to)] as CFArray, locations: [0, 1])!
        }

        context.drawLinearGradient(gradient("4c5a70", "c2cbd8"), start: .zero, end: CGPoint(x: 0, y: 182), options: [])

        context.setFillColor(color("eff5ff", alpha: 0.85))
        context.fillEllipse(in: CGRect(x: 202, y: 38, width: 22, height: 22))

        let far = CGMutablePath()
        far.move(to: CGPoint(x: 0, y: 116))
        far.addCurve(to: CGPoint(x: 190, y: 112), control1: CGPoint(x: 40, y: 132), control2: CGPoint(x: 120, y: 100))
        far.addCurve(to: CGPoint(x: 280, y: 96), control1: CGPoint(x: 260, y: 124), control2: CGPoint(x: 260, y: 96))
        far.addLine(to: CGPoint(x: 280, y: 182))
        far.addLine(to: CGPoint(x: 0, y: 182))
        far.closeSubpath()
        context.saveGState()
        context.addPath(far)
        context.clip()
        context.drawLinearGradient(gradient("e0e5ec", "85919f"), start: CGPoint(x: 280, y: 96), end: CGPoint(x: 0, y: 182), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()

        let near = CGMutablePath()
        near.move(to: CGPoint(x: 0, y: 131))
        near.addCurve(to: CGPoint(x: 150, y: 138), control1: CGPoint(x: 40, y: 111), control2: CGPoint(x: 100, y: 112))
        near.addCurve(to: CGPoint(x: 280, y: 153), control1: CGPoint(x: 200, y: 164), control2: CGPoint(x: 230, y: 160))
        near.addLine(to: CGPoint(x: 280, y: 182))
        near.addLine(to: CGPoint(x: 0, y: 182))
        near.closeSubpath()
        context.saveGState()
        context.addPath(near)
        context.clip()
        context.drawLinearGradient(gradient("ccd4de", "75879a"), start: CGPoint(x: 0, y: 111), end: CGPoint(x: 140, y: 182), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()

        context.setFillColor(color("ffffff", alpha: 0.7))
        context.addPath(CGPath(roundedRect: CGRect(x: 112, y: 182 - 3.45 * 2.8 - 1.03 * 2.8, width: 56, height: 1.03 * 2.8), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil))
        context.fillPath()

        // Text goes through AppKit so the system font renders with proper kerning.
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext
        let white = NSColor(white: 1, alpha: 0.9)
        let date = NSAttributedString(string: "Wednesday, September 9", attributes: [
            .font: NSFont.systemFont(ofSize: 6.2, weight: .medium), .foregroundColor: white.withAlphaComponent(0.85), .kern: -0.06,
        ])
        let time = NSAttributedString(string: "9:41", attributes: [
            .font: NSFont.systemFont(ofSize: 35, weight: .medium), .foregroundColor: white, .kern: -1.4,
        ])
        let dateSize = date.size()
        date.draw(at: CGPoint(x: 140 - dateSize.width / 2, y: 182 * 0.13))
        let timeSize = time.size()
        time.draw(at: CGPoint(x: 140 - timeSize.width / 2, y: 182 * 0.13 + dateSize.height))
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }

    private static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
}
