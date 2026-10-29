import AppKit

/// Menu row for an image: thumbnail, title, and a folder button on the right that reveals the file in Finder.
/// Clicking anywhere else copies, like a normal menu item. A view-based menu item draws its own highlight.
final class ImageRowView: NSView {
    private static let height: CGFloat = 36
    private static let leading: CGFloat = 14
    private static let trailing: CGFloat = 10
    private static let thumbnailSlot: CGFloat = 28
    private static let buttonSize: CGFloat = 24

    private let thumbnail: NSImage?
    private let title: String
    private let onCopy: () -> Void
    private let onReveal: () -> Void
    private let folderIcon = NSImage(systemSymbolName: "folder", accessibilityDescription: "Finder'da göster")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    private var hoveringButton = false {
        didSet { if hoveringButton != oldValue { needsDisplay = true } }
    }

    init(thumbnail: NSImage?, title: String, toolTip: String, onCopy: @escaping () -> Void, onReveal: @escaping () -> Void) {
        self.thumbnail = thumbnail
        self.title = title
        self.onCopy = onCopy
        self.onReveal = onReveal
        let titleWidth = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)]).size().width
        let width = Self.leading + Self.thumbnailSlot + 8 + ceil(titleWidth) + 24 + Self.buttonSize + Self.trailing
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        self.toolTip = toolTip
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    private var buttonRect: NSRect {
        NSRect(x: bounds.maxX - Self.trailing - Self.buttonSize, y: (bounds.height - Self.buttonSize) / 2,
               width: Self.buttonSize, height: Self.buttonSize)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        hoveringButton = buttonRect.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveringButton = false
    }

    override func mouseUp(with event: NSEvent) {
        let reveal = buttonRect.insetBy(dx: -4, dy: -6).contains(convert(event.locationInWindow, from: nil))
        var menu = enclosingMenuItem?.menu
        while let parent = menu?.supermenu { menu = parent }
        menu?.cancelTracking()
        reveal ? onReveal() : onCopy()
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = isHighlighted
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
        }

        var x = Self.leading
        if let thumbnail {
            let size = thumbnail.size
            thumbnail.draw(in: NSRect(x: x + (Self.thumbnailSlot - size.width) / 2, y: (bounds.height - size.height) / 2,
                                      width: size.width, height: size.height))
        }
        x += Self.thumbnailSlot + 8

        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
        ])
        text.draw(at: NSPoint(x: x, y: (bounds.height - text.size().height) / 2))

        if hoveringButton {
            (highlighted ? NSColor.white.withAlphaComponent(0.25) : NSColor.labelColor.withAlphaComponent(0.1)).setFill()
            NSBezierPath(roundedRect: buttonRect, xRadius: 5, yRadius: 5).fill()
        }
        if let folderIcon {
            let tint = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor
            let size = folderIcon.size
            let rect = NSRect(x: buttonRect.midX - size.width / 2, y: buttonRect.midY - size.height / 2,
                              width: size.width, height: size.height)
            Self.tinted(folderIcon, tint).draw(in: rect)
        }
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }
}
