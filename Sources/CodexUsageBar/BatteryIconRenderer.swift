import AppKit
import CodexUsageBarCore

enum BatteryIconRenderer {
    static func image(percent: Double?, health: UsageHealth) -> NSImage {
        let size = NSSize(width: 38, height: 17)
        let image = NSImage(size: size)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let outlineColor = NSColor.labelColor
        let fillColor = color(for: health)
        let bodyRect = NSRect(x: 0.5, y: 2.5, width: 31.5, height: 12)
        let terminalRect = NSRect(x: 32.5, y: 5.8, width: 4, height: 5.4)
        let innerRect = bodyRect.insetBy(dx: 2.8, dy: 2.8)

        outlineColor.setStroke()
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 4, yRadius: 4)
        bodyPath.lineWidth = 1.7
        bodyPath.stroke()

        let terminalPath = NSBezierPath(roundedRect: terminalRect, xRadius: 2, yRadius: 2)
        terminalPath.lineWidth = 1.7
        terminalPath.stroke()

        if let percent {
            let clamped = max(0, min(100, percent))
            if clamped > 0 {
                fillColor.setFill()
                let fillWidth = max(1.5, innerRect.width * (clamped / 100))
                let fillRect = NSRect(
                    x: innerRect.minX,
                    y: innerRect.minY,
                    width: min(innerRect.width, fillWidth),
                    height: innerRect.height
                )
                NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()
            }

            drawText("\(Int(clamped.rounded()))%", in: bodyRect)
        } else {
            drawText(">_", in: bodyRect)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func color(for health: UsageHealth) -> NSColor {
        switch health {
        case .ok:
            NSColor.systemGreen
        case .warning:
            NSColor.systemOrange
        case .critical:
            NSColor.systemRed
        case .unknown:
            NSColor.tertiaryLabelColor
        }
    }

    private static func drawText(_ text: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 6.8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        let textRect = rect.insetBy(dx: 0.8, dy: 2.5)
        text.draw(in: textRect, withAttributes: attributes)
    }
}
