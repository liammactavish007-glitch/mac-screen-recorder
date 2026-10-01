import AppKit

enum StudioPalette {
    static let canvas = NSColor(srgbRed: 0.965, green: 0.955, blue: 0.935, alpha: 1)
    static let paper = NSColor(srgbRed: 1, green: 0.997, blue: 0.985, alpha: 1)
    static let ink = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.19, alpha: 1)
    static let muted = NSColor(srgbRed: 0.46, green: 0.47, blue: 0.46, alpha: 1)
    static let line = NSColor(srgbRed: 0.87, green: 0.86, blue: 0.83, alpha: 1)
    static let coral = NSColor(srgbRed: 0.91, green: 0.28, blue: 0.22, alpha: 1)
    static let softCoral = NSColor(srgbRed: 1, green: 0.94, blue: 0.90, alpha: 1)
    static let deck = NSColor(srgbRed: 0.12, green: 0.15, blue: 0.16, alpha: 1)

    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name = weight == .semibold || weight == .bold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

final class StudioPanel: NSView {
    init(color: NSColor = StudioPalette.paper, radius: CGFloat = 16, bordered: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = bordered ? 1 : 0
        layer?.borderColor = StudioPalette.line.withAlphaComponent(0.7).cgColor
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

final class StudioButton: NSButton {
    enum Style { case primary, neutral, quiet }
    private var style: Style = .neutral
    private var hovering = false
    private var hoverArea: NSTrackingArea?

    init(_ title: String, target: AnyObject?, action: Selector?, style: Style = .neutral) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.style = style
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .default
        font = StudioPalette.font(13, weight: .semibold)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var intrinsicContentSize: NSSize {
        let width = (title as NSString).size(withAttributes: [.font: font!]).width + 28
        return NSSize(width: width, height: style == .primary ? 46 : 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(hoverArea!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let down = cell?.isHighlighted == true
        let background: NSColor
        let textColor: NSColor
        switch style {
        case .primary:
            background = isEnabled ? StudioPalette.coral.withAlphaComponent(down ? 0.78 : hovering ? 0.9 : 1) : StudioPalette.line
            textColor = isEnabled ? .white : StudioPalette.muted
        case .neutral:
            background = isEnabled ? (hovering || down ? StudioPalette.canvas : StudioPalette.paper) : StudioPalette.canvas
            textColor = isEnabled ? StudioPalette.ink : StudioPalette.muted.withAlphaComponent(0.55)
        case .quiet:
            background = hovering && isEnabled ? StudioPalette.line.withAlphaComponent(0.25) : .clear
            textColor = isEnabled ? StudioPalette.muted : StudioPalette.muted.withAlphaComponent(0.55)
        }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11)
        background.setFill(); path.fill()
        if style == .neutral {
            StudioPalette.line.withAlphaComponent(isEnabled ? 0.9 : 0.4).setStroke()
            path.lineWidth = 1; path.stroke()
        }
        if window?.firstResponder === self {
            StudioPalette.coral.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 2; path.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font!, .foregroundColor: textColor]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

final class AudioTile: NSButton {
    private var detail = ""
    private var symbol = ""
    init(_ title: String, detail: String, symbol: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.target = target
        self.action = action
        setButtonType(.switch)
        isBordered = false
        setAccessibilityLabel(title)
        setAccessibilityHelp(detail)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 72) }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        (on ? StudioPalette.softCoral : StudioPalette.paper).setFill(); tile.fill()
        (on ? StudioPalette.coral.withAlphaComponent(0.35) : StudioPalette.line.withAlphaComponent(0.7)).setStroke()
        tile.lineWidth = window?.firstResponder === self ? 2 : 1; tile.stroke()
        let opacity: CGFloat = isEnabled ? 1 : 0.45
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [on ? StudioPalette.coral : StudioPalette.muted]))
        image?.draw(in: NSRect(x: 16, y: 14, width: 22, height: 20), from: .zero, operation: .sourceOver, fraction: opacity)
        (title as NSString).draw(at: NSPoint(x: 47, y: 15), withAttributes: [
            .font: StudioPalette.font(14, weight: .semibold), .foregroundColor: StudioPalette.ink.withAlphaComponent(opacity)])
        (detail as NSString).draw(at: NSPoint(x: 16, y: 44), withAttributes: [
            .font: StudioPalette.font(11), .foregroundColor: StudioPalette.muted.withAlphaComponent(opacity)])
        let toggle = NSRect(x: bounds.width - 51, y: 14, width: 34, height: 20)
        (on ? StudioPalette.coral : StudioPalette.line).withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: toggle, xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(opacity).setFill()
        NSBezierPath(ovalIn: NSRect(x: toggle.minX + (on ? 17 : 3), y: toggle.minY + 3, width: 14, height: 14)).fill()
    }
}
