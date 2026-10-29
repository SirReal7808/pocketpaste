# MacClip · Mac uygulaması

Telefondan gelen metin ve görselleri menü çubuğunda listeler. Bir kayda tıklayınca içerik panoya kopyalanır. Protokol ve kararlar için `../SPEC.md`.

Gereksinim: macOS 13 veya üstü, Xcode (veya Xcode Command Line Tools).

## Derleme ve kurulum

```bash
./scripts/build-app.sh
```

Çıktılar:
- `build/MacClip.app`: uygulama
- `build/macclip-send`: telefon olmadan test için gönderici

Uygulamayı `/Applications` klasörüne taşıyın ve açın. "Girişte başlat" yalnızca uygulama oradan çalışırken düzgün çalışır.

```bash
cp -R build/MacClip.app /Applications/ && open /Applications/MacClip.app
```

### İmzalama

Betik varsayılan olarak ad hoc imza kullanır. Bu durumda macOS, her yeniden derlemeden sonra güvenlik duvarı ve yerel ağ iznini tekrar sorabilir. Apple geliştirici sertifikanız varsa bunu kullanın, izinler kalıcı olur:

```bash
security find-identity -p codesigning -v
MACCLIP_SIGN_IDENTITY="Apple Development: Ad Soyad (XXXXXXXXXX)" ./scripts/build-app.sh
```

## İlk açılış ve izinler

1. **Eşleştirme penceresi:** İlk açılışta QR kodu otomatik açılır. Telefondaki MacClip ayar ekranından okutun. Daha sonra menüden **Yeniden eşleştir…** ile tekrar açabilirsiniz. Bu işlem yeni anahtar üretir, eski anahtar geçersiz olur.
2. **Gelen bağlantılar:** macOS güvenlik duvarı açıksa "MacClip'in gelen ağ bağlantılarını kabul etmesine izin verilsin mi?" diye sorar. **İzin Ver** deyin.
3. **Yerel ağ:** Sorulursa izin verin. Sonradan değiştirmek için: Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ › MacClip.

## Kullanım

- Yeni bir şey gelince ikon 5 saniye yanıp söner, sonra köşesinde nokta kalır. Menüyü açınca nokta kaybolur.
- Son 5 kayıt ana menüde, sonraki 15 kayıt **Daha eski** altında. Sıralama ve saat, telefonda paylaşıldığı zamana göredir.
- Bir kayda tıklayınca panoya kopyalanır. Görseller her zaman PNG olarak kopyalanır. Uzun kenarı 4096 pikselden büyük fotoğraflar panoya küçültülerek yazılır (50 MP'lik bir fotoğraf ~45 MB yerine ~12 MB olur); diskteki orijinal değişmez. Üzerine gelince tam tarih görünür.
- En fazla 20 kayıt tutulur. 10 günden eskiler silinir.
- Menünün altındaki gri satır sunucunun durumunu ve dinlediği adresi gösterir.

Veriler `~/Library/Application Support/MacClip` klasöründe durur. Klasör `0700`, dosyalar `0600` izinlidir, yani yalnızca sizin kullanıcınız erişebilir.

| Dosya | İçerik |
|---|---|
| `config.json` | Anahtar ve port (varsayılan 47812) |
| `history.json` | Kayıt listesi |
| `items/` | Metin ve görseller (görseller telefonun gönderdiği biçimde) |
| `seen.json` | Daha önce gelen kayıt kimlikleri (tekrar gönderimi engellemek için) |

## Telefon olmadan test

`macclip-send`, anahtarı aynı `config.json` dosyasından okur ve Android uygulamasının yaptığı gibi şifreli istek gönderir:

```bash
build/macclip-send ping
```

```bash
build/macclip-send text "Merhaba Mac"
```

```bash
build/macclip-send image ~/Desktop/ekran.jpg
```

```bash
build/macclip-send --age 3600 text "bir saat önce paylaşılmış gibi"
```

Uygulamanın gerçek verisine dokunmadan denemek için `MACCLIP_HOME` ile ayrı bir klasör kullanılabilir. Gerçek uygulamayla çakışmasın diye o klasördeki `config.json` içinde farklı bir port verin:

```bash
MACCLIP_HOME=/tmp/macclip-test build/MacClip.app/Contents/MacOS/MacClip
```

```bash
MACCLIP_HOME=/tmp/macclip-test build/macclip-send text "deneme"
```

Birim testleri:

```bash
swift test
```

## Sorun giderme

**Telefon "Mac'e ulaşılamadı" diyor**
1. Menünün altındaki gri satıra bakın. "Dinleniyor · 192.168.x.x:47812" yazmalı.
2. Mac'te `build/macclip-send ping` çalıştırın. `200` dönüyorsa uygulama sağlam, sorun ağdadır.
3. Telefonun tarayıcısında `http://<Mac IP>:47812/` adresini açın. `{"error":"method"}` görünüyorsa bağlantı var demektir. Sayfa açılmıyorsa güvenlik duvarına bakın: Sistem Ayarları › Ağ › Güvenlik Duvarı › Seçenekler › MacClip "Gelen bağlantılara izin ver" olmalı.
4. Telefon ile Mac aynı Wi-Fi'da mı? Misafir ağları cihazların birbirini görmesini genelde engeller.

**Bonjour (mDNS) çalışmıyor**
Mac'te duyurunun yapıldığını kontrol edin (Ctrl-C ile çıkın):

```bash
dns-sd -B _macclip._tcp
```

Satırda Mac adınız görünüyorsa Mac tarafı tamamdır. Bazı modemler ve mesh sistemleri multicast trafiği engeller. Bu durumda telefon QR'daki IP adresine düşer. Statik IP kullanıyorsanız ek bir şey yapmanıza gerek yok. IP değiştiyse yeniden eşleştirin ya da telefonda adresi elle girin.

**"Port 47812 başka bir uygulama tarafından kullanılıyor"**
Uygulamadan çıkın, `config.json` içindeki `port` değerini değiştirin, uygulamayı açın ve yeniden eşleştirin.

**`401 unauthorized`**
Telefondaki anahtar Mac'tekiyle uyuşmuyor. Menüden **Yeniden eşleştir…** deyip QR'ı tekrar okutun.

**Her şeyi sıfırlamak**
Uygulamadan çıkın, sonra:

```bash
rm -rf ~/Library/Application\ Support/MacClip
```
