import AppKit
import MacClipCore

final class StatusController: NSObject, NSMenuDelegate {
    private static let mainMenuCount = 5
    private static let olderCount = 15
    private static let blinkInterval: TimeInterval = 0.5
    private static let blinkDuration: TimeInterval = 5
    private static let thumbnailPoints: CGFloat = 28

    var serverStatus = L("Starting…")

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let store: HistoryStore
    private unowned let app: AppDelegate
    private let plainIcon = IconRenderer.image(dot: false)
    private let dotIcon = IconRenderer.image(dot: true)

    private var hasUnseen = false
    private var blinkTimer: Timer?
    private var thumbnails: [String: NSImage] = [:]

    init(store: HistoryStore, app: AppDelegate) {
        self.store = store
        self.app = app
        super.init()
        statusItem.button?.image = plainIcon
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: Highlight

    /// Blinks the dot for a few seconds, then leaves it on until the menu is opened.
    func notifyNew() {
        hasUnseen = true
        blinkTimer?.invalidate()
        statusItem.button?.image = dotIcon
        let started = Date()
        let timer = Timer(timeInterval: Self.blinkInterval, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if Date().timeIntervalSince(started) >= Self.blinkDuration {
                timer.invalidate()
                self.statusItem.button?.image = self.hasUnseen ? self.dotIcon : self.plainIcon
            } else {
                let showingDot = self.statusItem.button?.image === self.dotIcon
                self.statusItem.button?.image = showingDot ? self.plainIcon : self.dotIcon
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    func menuWillOpen(_ menu: NSMenu) {
        hasUnseen = false
        blinkTimer?.invalidate()
        statusItem.button?.image = plainIcon
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.prune()
        let items = store.items
        let ids = Set(items.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }

        menu.removeAllItems()
        if items.isEmpty {
            let empty = NSMenuItem(title: L("Nothing received yet"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in items.prefix(Self.mainMenuCount) {
            menu.addItem(menuItem(for: item))
        }
        if items.count > Self.mainMenuCount {
            let older = NSMenuItem(title: L("Older"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for item in items.dropFirst(Self.mainMenuCount).prefix(Self.olderCount) {
                submenu.addItem(menuItem(for: item))
            }
            older.submenu = submenu
            menu.addItem(older)
        }

        menu.addItem(.separator())
        let clear = action(L("Clear History"), #selector(clearHistory))
        clear.isEnabled = !items.isEmpty
        menu.addItem(clear)
        menu.addItem(action(L("Pair Again…"), #selector(repair)))
        let login = action(L("Open at Login"), #selector(toggleLogin))
        login.state = app.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let info = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        info.attributedTitle = NSAttributedString(string: serverStatus, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(action(L("Quit MacClip"), #selector(quit), key: "q"))
    }

    private func menuItem(for item: HistoryItem) -> NSMenuItem {
        let title = item.isImage
            ? MenuText.imageTitle(sentAt: item.sentDate)
            : MenuText.singleLine(item.preview ?? "")
        let menuItem = action(title, #selector(copyItem(_:)))
        menuItem.representedObject = item.id
        menuItem.toolTip = MenuText.fullDate(item.sentDate)
        if item.isImage {
            let url = store.url(for: item)
            menuItem.view = ImageRowView(
                thumbnail: thumbnail(for: item), title: title, toolTip: MenuText.fullDate(item.sentDate),
                onCopy: { [weak self] in self?.copy(id: item.id) },
                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        return menuItem
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func thumbnail(for item: HistoryItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        let pixels = Int(Self.thumbnailPoints * 2)
        guard let cg = ImageRendering.orientedImage(at: store.url(for: item), maxPixelSize: pixels) else { return nil }
        let scale = Self.thumbnailPoints / CGFloat(max(cg.width, cg.height))
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
        thumbnails[item.id] = image
        return image
    }

    // MARK: Actions

    @objc private func copyItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        copy(id: id)
    }

    private func copy(id: String) {
        guard let item = store.items.first(where: { $0.id == id }) else {
            NSSound.beep()
            return
        }
        let url = store.url(for: item)
        // Converting a large photo takes a moment; keep the menu bar responsive meanwhile.
        DispatchQueue.global(qos: .userInitiated).async {
            let content = Pasteboard.Content.load(item, from: url)
            DispatchQueue.main.async {
                if content?.write() != true { NSSound.beep() }
            }
        }
    }

    @objc private func clearHistory() { app.clearHistory() }
    @objc private func repair() { app.repair() }
    @objc private func toggleLogin() { app.toggleLaunchAtLogin() }
    @objc private func quit() { NSApp.terminate(nil) }
}

enum Pasteboard {
    enum Content {
        case text(String)
        case png(Data)

        /// Images always go to the pasteboard as PNG, whatever format the phone sent, scaled down if very large.
        /// Safe to call off the main thread.
        static func load(_ item: HistoryItem, from url: URL) -> Content? {
            if item.isImage {
                return ImageRendering.pngData(contentsOf: url).map(Content.png)
            }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
            return .text(text)
        }

        func write() -> Bool {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch self {
            case .text(let text): return pasteboard.setString(text, forType: .string)
            case .png(let data): return pasteboard.setData(data, forType: .png)
            }
        }
    }
}

enum IconRenderer {
    static func image(dot: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = (NSImage(systemSymbolName: "iphone.and.arrow.forward", accessibilityDescription: "MacClip")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MacClip")!)
            .withSymbolConfiguration(config)!
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let s = symbol.size
            symbol.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            if dot {
                let d: CGFloat = 7
                let circle = NSRect(x: rect.width - d, y: rect.height - d, width: d, height: d)
                // Cut a ring around the dot so it stays readable on top of the symbol.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: circle.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: circle).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
