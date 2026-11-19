// Test sender: does what the Android app does, so the Mac app can be tested without a phone.
import Foundation
import PocketPasteCore

let usage = """
Usage: pocketpaste-send [options] text <text>
       pocketpaste-send [options] image <file>
       pocketpaste-send [options] ping

Options:
  --host <address>    Default 127.0.0.1
  --port <port>       Default: the port in config.json
  --id <uuid>         Item ID (to test duplicate sends)
  --age <seconds>     Move the share time back by this much (negative moves it forward)
  --key <base64url>   Use this key instead of config.json

Key and port are read from config.json in POCKETPASTE_HOME (default ~/Library/Application Support/PocketPaste).
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
var options: [String: String] = [:]
while let first = args.first, first.hasPrefix("--") {
    guard args.count >= 2 else { fail(usage) }
    options[String(first.dropFirst(2))] = args[1]
    args.removeFirst(2)
}
guard let command = args.first else { fail(usage) }

let config = AppConfig.load(root: Paths.root)
guard let keyString = options["key"] ?? config?.key,
      let key = AppConfig(key: keyString).symmetricKey
else { fail("No key found. Run the Mac app first or pass --key.") }
let host = options["host"] ?? "127.0.0.1"
let port = options["port"] ?? String(config?.port ?? AppConfig.defaultPort)
let age = Double(options["age"] ?? "0") ?? 0
let sentAt = Int64((Date().timeIntervalSince1970 - age) * 1000)
let id = options["id"] ?? UUID().uuidString

let path: String
let header: ItemHeader
let content: Data
switch command {
case "text":
    guard args.count >= 2 else { fail(usage) }
    path = "/v1/items"
    header = ItemHeader(id: id, type: "text", mime: "text/plain", sentAt: sentAt)
    content = Data(args[1].utf8)
case "image":
    guard args.count >= 2 else { fail(usage) }
    let url = URL(fileURLWithPath: args[1])
    guard let data = try? Data(contentsOf: url) else { fail("Couldn't read the file: \(args[1])") }
    let mimes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "heic": "image/heic",
                 "webp": "image/webp", "gif": "image/gif"]
    path = "/v1/items"
    header = ItemHeader(id: id, type: "image", mime: mimes[url.pathExtension.lowercased()] ?? "image/png", sentAt: sentAt)
    content = data
case "ping":
    path = "/v1/ping"
    header = ItemHeader(id: id, type: "ping", mime: "", sentAt: sentAt)
    content = Data()
default:
    fail(usage)
}

let body = try Envelope.seal(header: header, content: content, key: key, path: path)
var request = URLRequest(url: URL(string: "http://\(host):\(port)\(path)")!)
request.httpMethod = "POST"
request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
request.httpBody = body
request.timeoutInterval = 10

let done = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1
URLSession.shared.dataTask(with: request) { data, response, error in
    if let error {
        print("Hata: \(error.localizedDescription)")
    } else if let http = response as? HTTPURLResponse {
        print("\(http.statusCode) \(String(data: data ?? Data(), encoding: .utf8) ?? "")")
        exitCode = http.statusCode == 200 ? 0 : 1
    }
    done.signal()
}.resume()
done.wait()
exit(exitCode)
