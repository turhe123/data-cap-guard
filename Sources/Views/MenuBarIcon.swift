import AppKit

/// Draws the menu bar gauge (ring and/or percentage) as a colored, non-template image.
enum MenuBarIcon {
    static func color(for fraction: Double) -> NSColor {
        switch fraction {
        case ..<0.75: return .systemGreen
        case ..<0.9: return .systemOrange
        default: return .systemRed
        }
    }

    static func image(fraction: Double, style: MenuBarStyle, configured: Bool) -> NSImage {
        let tint = configured ? color(for: fraction) : .secondaryLabelColor
        let text = configured ? "\(Int((fraction * 100).rounded()))%" : "--"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fraction >= 0.75 && configured ? tint : NSColor.labelColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let ringSize: CGFloat = 15
        let showRing = style != .text
        let showText = style != .ring
        let width = (showRing ? ringSize : 0) + (showRing && showText ? 4 : 0) + (showText ? ceil(textSize.width) : 0)
        let size = NSSize(width: max(width, 1), height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            if showRing {
                let rect = NSRect(x: 1.5, y: (18 - ringSize) / 2 + 1.5, width: ringSize - 3, height: ringSize - 3)
                let track = NSBezierPath(ovalIn: rect)
                track.lineWidth = 2.5
                NSColor.labelColor.withAlphaComponent(0.25).setStroke()
                track.stroke()
                let clamped = min(max(fraction, 0), 1)
                if clamped > 0 {
                    let arc = NSBezierPath()
                    let center = NSPoint(x: rect.midX, y: rect.midY)
                    arc.appendArc(withCenter: center, radius: rect.width / 2, startAngle: 90,
                                  endAngle: 90 - 360 * clamped, clockwise: true)
                    arc.lineWidth = 2.5
                    arc.lineCapStyle = .round
                    tint.setStroke()
                    arc.stroke()
                }
                x += ringSize + (showText ? 4 : 0)
            }
            if showText {
                (text as NSString).draw(at: NSPoint(x: x, y: (18 - textSize.height) / 2), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
