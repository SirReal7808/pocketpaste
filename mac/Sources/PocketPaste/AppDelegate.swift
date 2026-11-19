import AppKit
import CryptoKit
import PocketPasteCore
import Network
import ServiceManagement
import SystemConfiguration

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let maxBodyBytes = 30 * 1024 * 1024

    private let root = Paths.root
    private var config: AppConfig!
    private var store: HistoryStore!
    private let keyBox = KeyBox()
    private var server: HTTPServer?
    private var status: StatusController!
    private var pairingWindow: PairingWindowController?
    private var pruneTimer: Timer?

    var macName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try HistoryStore(root: root)
        } catch {
            fatal(L("Couldn’t open the data folder: %@", error.localizedDescription))
        }

        var firstRun = false
        if let saved = AppConfig.load(root: root), saved.symmetricKey != nil {
            config = saved
        } else {
            config = AppConfig(key: AppConfig.newKey())
            firstRun = true
            do { try config.save(root: root) } catch { fatal(L("Couldn’t save the settings: %@", error.localizedDescription)) }
        }
        keyBox.set(config.symmetricKey!)

        status = StatusController(store: store, app: self)
        startServer()

        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.store.prune()
        }
        if firstRun { showPairing() }
    }

    // MARK: Server

    private func startServer() {
        server?.stop()
        let port = config.port
        let server = HTTPServer(port: port, maxBodyBytes: Self.maxBodyBytes) { [weak self] request, respond in
            guard let self else { return respond(.json(500, ["error": "shutting down"])) }
            self.handle(request, respond: respond)
        }
        server.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.listenerChanged(state, port: port) }
        }
        let txt = NWTXTRecord(["v": "1", "kid": config.keyID])
        let service = NWListener.Service(name: macName, type: Pairing.serviceType, domain: nil, txtRecord: txt)
        do {
            try server.start(service: service)
            self.server = server
        } catch {
            status.serverStatus = L("Couldn’t start the server: %@", error.localizedDescription)
        }
    }

    private func listenerChanged(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            let address = NetworkInfo.ipv4Addresses().first?.address ?? L("no network")
            status.serverStatus = L("Listening · %@", "\(address):\(port)")
        case .failed(let error):
            if case .posix(.EADDRINUSE) = error {
                status.serverStatus = L("Port %@ is in use by another app", String(port))
            } else {
                status.serverStatus = L("Server error: %@", error.localizedDescription)
            }
        case .waiting(let error):
            status.serverStatus = L("Waiting for the network: %@", error.localizedDescription)
        default:
            break
        }
    }

    /// Runs on the server queue.
    private func handle(_ request: HTTPRequest, respond: @escaping (HTTPResponse) -> Void) {
        guard request.method == "POST" else { return respond(.json(405, ["error": "method"])) }
        guard request.path == "/v1/items" || request.path == "/v1/ping" else {
            return respond(.json(404, ["error": "not found"]))
        }

        let header: ItemHeader
        let content: Data
        do {
            (header, content) = try Envelope.open(request.body, key: keyBox.get(), path: request.path)
        } catch EnvelopeError.decryptFailed {
            return respond(.json(401, ["error": "unauthorized"]))
        } catch {
            return respond(.json(400, ["error": "malformed"]))
        }

        if request.path == "/v1/ping" {
            guard header.type == "ping" else { return respond(.json(400, ["error": "malformed"])) }
            return respond(.json(200, ["ok": true, "name": macName]))
        }

        DispatchQueue.main.async {
            do {
                let result = try self.store.add(header: header, content: content)
                if result == .added { self.status.notifyNew() }
                respond(.json(200, ["ok": true, "result": String(describing: result)]))
            } catch let error as StoreError {
                respond(.json(error.httpStatus, ["error": error.code]))
            } catch {
                respond(.json(500, ["error": "storage"]))
            }
        }
    }

    // MARK: Menu actions

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L("Clear the history?")
        alert.informativeText = L("All received text and images will be deleted.")
        alert.addButton(withTitle: L("Clear"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }

    func repair() {
        let alert = NSAlert()
        alert.messageText = L("Pair again?")
        alert.informativeText = L("A new key will be created. The phone can’t send until it scans the new QR code. Items waiting on the phone stay in its queue.")
        alert.addButton(withTitle: L("Pair Again"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        config.key = AppConfig.newKey()
        do { try config.save(root: root) } catch {
            showError(L("Couldn’t save the new key: %@", error.localizedDescription))
            return
        }
        keyBox.set(config.symmetricKey!)
        store.resetSeen()
        startServer()
        showPairing()
    }

    func showPairing() {
        pairingWindow?.close()
        let addresses = NetworkInfo.ipv4Addresses()
        let window = PairingWindowController(
            pairingURL: Pairing.url(host: addresses.first?.address ?? "", port: config.port, key: config.key, name: macName),
            addresses: addresses.map(\.address), port: config.port, key: config.key, name: macName)
        pairingWindow = window
        window.showWindow(nil)
        window.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window.window?.makeKeyAndOrderFront(nil)
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            showError(L("Couldn’t set Open at Login: %@\n\nMake sure the app runs from the /Applications folder.", error.localizedDescription))
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PocketPaste"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func fatal(_ message: String) -> Never {
        showError(message)
        exit(1)
    }
}

/// The key is read on the server queue and replaced on the main thread when re-pairing.
final class KeyBox {
    private let lock = NSLock()
    private var key: SymmetricKey?

    func set(_ key: SymmetricKey) {
        lock.lock()
        defer { lock.unlock() }
        self.key = key
    }

    func get() -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        return key!
    }
}
