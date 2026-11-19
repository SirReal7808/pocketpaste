import AppKit
import CoreImage
import PocketPasteCore

final class PairingWindowController: NSWindowController {
    init(pairingURL: String, addresses: [String], port: UInt16, key: String, name: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "PocketPaste · " + L("Pair")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let title = NSTextField(labelWithString: L("Scan this code with the PocketPaste app on your phone"))
        title.font = .boldSystemFont(ofSize: 13)
        title.alignment = .center

        let qr = NSImageView(image: Self.qrImage(pairingURL) ?? NSImage())
        qr.imageScaling = .scaleProportionallyUpOrDown
        qr.translatesAutoresizingMaskIntoConstraints = false
        qr.widthAnchor.constraint(equalToConstant: 260).isActive = true
        qr.heightAnchor.constraint(equalToConstant: 260).isActive = true

        let addressText = addresses.isEmpty ? L("not found (connected to a network?)") : addresses.joined(separator: ", ")
        let details = NSTextField(wrappingLabelWithString: """
            \(L("For manual entry:"))
            Mac: \(name)
            \(L("Address:")) \(addressText)
            Port: \(port)
            \(L("Key:")) \(key)
            """)
        details.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        details.isSelectable = true

        let note = NSTextField(wrappingLabelWithString: L("Don’t share this key with anyone. Pairing again makes the old key invalid."))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let close = NSButton(title: L("Close"), target: nil, action: #selector(NSWindow.performClose(_:)))
        close.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, qr, details, note, close])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        details.widthAnchor.constraint(equalToConstant: 340).isActive = true
        note.widthAnchor.constraint(equalToConstant: 340).isActive = true
        window.contentView = stack
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func qrImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
