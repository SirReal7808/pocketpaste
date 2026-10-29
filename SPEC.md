# MacClip: Telefondan Mac'e yerel pano köprüsü

Android'de Paylaş menüsünden seçilen metni veya görseli aynı Wi-Fi'daki Mac'e gönderir. Mac'te menü çubuğundaki listeden bir kayda tıklayınca içerik panoya kopyalanır.

## Kararlar

### Genel
- Yalnızca yerel ağ, yalnızca telefon → Mac, yalnızca metin ve görsel.
- Taşıma düz HTTP. İçerik, eşleşmede paylaşılan 256-bit anahtarla AES-256-GCM ile şifrelenir. Anahtar ağda hiç dolaşmaz.
- Tek telefon eşleşir. Yeniden eşleştirme yeni anahtar üretir, eskisi geçersiz olur.
- Eşleşme Mac'te gösterilen QR koduyla yapılır.
- Bulma: önce eşleşmedeki IP ve port (statik IP ile en hızlısı), ulaşılamazsa Bonjour (`_macclip._tcp`, TXT `kid` ile doğru Mac seçilir).

### Mac uygulaması
- Swift, yalnızca menü çubuğu (Dock'ta yok).
- Liste: ilk 5 kayıt ana menüde, sonraki 15 kayıt "Daha eski" alt menüsünde. Metin ve görsel tek listede.
- Sıralama ve gösterilen saat: telefonda **paylaşıldığı** saat (gelme saati değil).
- Metin: tek satıra indirilmiş, 50 karakterde kısaltılmış.
- Görsel: küçük önizleme ve "Görsel · SS:DD".
- Tıklayınca panoya kopyalanır. Görseller panoya **her zaman PNG** olarak yazılır. Gelen içerik panoya kendiliğinden yazılmaz.
- Diskte saklanır (`~/Library/Application Support/MacClip`, klasör 0700, dosyalar 0600). Görsel telefonun gönderdiği biçimde saklanır.
- En fazla 20 kayıt, 10 günden eskiler otomatik silinir.
- Yeni kayıt gelince ikon 5 saniye yanıp söner, sonra üzerinde nokta kalır. Menü açılınca nokta kaybolur. macOS bildirimi yok.
- Menüde: Geçmişi temizle, Yeniden eşleştir, Girişte başlat, Çık.

### Android uygulaması
- Kotlin, APK elle kurulur.
- Paylaş menüsünde "Mac'e gönder". Birden fazla görsel paylaşılırsa her biri ayrı kayıt olur.
- Paylaşınca görünmez bir ekran açılır, içerik uygulamanın özel alanındaki sıraya yazılır, yaklaşık 3 saniye hemen gönderim denenir, kısa bir Toast gösterilir ("Gönderildi" veya "Mac'e ulaşılamadı, sıraya alındı") ve ekran kapanır. Son uygulamalar listesinde kalmaz, bildirim gösterilmez, ön planda servis çalışmaz.
- Gönderilemeyenler WorkManager ile Wi-Fi varken arka planda tekrar denenir (birkaç dakika ile ~15 dakika gecikme olabilir).
- Telefondaki sıra: en fazla 20 kayıt, 10 günden eskiler silinir.
- Ayar ekranı: QR okutma, manuel giriş, bağlantı testi, bekleyen sayısı ve "Şimdi gönder".

## Protokol (v1)

### Eşleşme QR içeriği
```
macclip://pair?v=1&h=<ipv4>&p=<port>&k=<base64url anahtar, 32 bayt>&n=<Mac adı>
```

### İstekler
Tek uç nokta türü, gövde ikili (binary):

- `POST /v1/items`: kayıt gönderir.
- `POST /v1/ping`: bağlantı ve anahtar testi.

Gövde: `nonce (12 bayt) || AES-256-GCM şifreli metin || etiket (16 bayt)`. AAD: istek yolu (`/v1/items` veya `/v1/ping`).

Şifresi çözülmüş içerik:
```
başlık uzunluğu (4 bayt, big-endian) || başlık JSON (UTF-8) || ham içerik baytları
```
Başlık JSON:
```json
{"id": "<UUID>", "type": "text" | "image" | "ping", "mime": "text/plain" | "image/png" | ..., "sentAt": <epoch ms>}
```

### Yanıtlar
- `200` kabul edildi (aynı `id` daha önce geldiyse de `200`, tekrar eklenmez).
- `400` bozuk istek, `401` şifre çözülemedi (yanlış anahtar), `404` bilinmeyen yol, `413` çok büyük, `422` desteklenmeyen tür veya süresi geçmiş (`sentAt` 10 günden eski ya da 5 dakikadan fazla ileride).

### Sınırlar
- Gövde en fazla 30 MB, metin en fazla 1 MB.
- Mac, gördüğü `id`'leri 11 gün saklar. Tekrar gönderim koruması bu kimliklere dayanır.
