// Test sender: does what the Android app does, so the Mac app can be tested without a phone.
import Foundation
import MacClipCore

let usage = """
Kullanım: macclip-send [seçenekler] text <metin>
          macclip-send [seçenekler] image <dosya>
          macclip-send [seçenekler] ping

Seçenekler:
  --host <adres>      Varsayılan 127.0.0.1
  --port <port>       Varsayılan config.json'daki port
  --id <uuid>         Kayıt kimliği (tekrar gönderim testi için)
  --age <saniye>      Paylaşım saatini bu kadar geriye al (eksi değer ileri alır)
  --key <base64url>   config.json yerine bu anahtarı kullan

Anahtar ve port MACCLIP_HOME (yoksa ~/Library/Application Support/MacClip) içindeki config.json'dan okunur.
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
else { fail("Anahtar bulunamadı. Önce Mac uygulamasını çalıştırın ya da --key verin.") }
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
    guard let data = try? Data(contentsOf: url) else { fail("Dosya okunamadı: \(args[1])") }
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
