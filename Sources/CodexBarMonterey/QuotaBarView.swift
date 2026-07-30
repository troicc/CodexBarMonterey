@preconcurrency import AppKit

final class QuotaBarView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    var fillColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 5)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rounded = bounds.insetBy(dx: 0, dy: 0)
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: rounded, xRadius: 2.5, yRadius: 2.5).fill()

        let fraction = CGFloat(max(0, min(100, progress)) / 100)
        guard fraction > 0 else { return }
        let fillRect = NSRect(x: rounded.minX, y: rounded.minY, width: rounded.width * fraction, height: rounded.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5).fill()
    }
}
