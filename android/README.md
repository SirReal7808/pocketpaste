# MacClip · Android uygulaması

Paylaş menüsüne "Mac'e gönder" ekler. Seçilen metni veya görselleri aynı Wi-Fi'daki Mac'e şifreli olarak gönderir. Mac'e ulaşamazsa sıraya alır ve sonra kendisi dener. Protokol ve kararlar için `../SPEC.md`.

Gereksinim: Android 8.0 (API 26) veya üstü. QR okutmak için Google Play hizmetleri gerekir. Play hizmetleri yoksa elle giriş kullanılabilir.

## Derleme

Android Studio'da `android` klasörünü açıp **Build › Build APK(s)** deyin, ya da komut satırından derleyin (JDK 17 ve Android SDK gerekir):

```bash
./gradlew assembleDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`

## Kurulum

- **USB ile:** Telefonda Geliştirici seçenekleri › USB hata ayıklama açıkken:
  ```bash
  adb install -r app/build/outputs/apk/debug/app-debug.apk
  ```
- **Elle:** APK'yı telefona kopyalayıp dosya yöneticisinden açın. Android "bilinmeyen kaynaklardan yükleme" izni ister. Bu izni yalnızca o dosya yöneticisine verin.

Güncellerken aynı makinede derlenmiş APK'yı kurun. Debug imza anahtarı farklı olursa Android güncellemeyi reddeder. Bu durumda önce uygulamayı kaldırmanız gerekir; eşleşme ve sıradaki öğeler silinir.

## Eşleştirme

1. Mac'te MacClip ilk açılışta QR kodu gösterir. Daha sonra menüden **Yeniden eşleştir…** ile açılabilir.
2. Telefonda MacClip'i açın, **QR kodu okut** deyin.
3. Uygulama otomatik bağlantı testi yapar ve "Bağlantı başarılı ✓" yazmalı.

QR okunmazsa Mac'teki pencerede yazan adres, port ve anahtarı **Elle giriş** bölümüne yazıp **Kaydet** deyin.

## Kullanım

Herhangi bir uygulamada metin seçip ya da görsel/ekran görüntüsü açıp **Paylaş › Mac'e gönder** deyin.
- Ekranda bir şey açılmaz. Birkaç saniye içinde kısa bir mesaj görünür: "Gönderildi" ya da "Mac'e ulaşılamadı, sıraya alındı". Uygulama son kullanılanlar listesinde kalmaz, bildirim göstermez.
- Birden fazla görsel seçerseniz her biri Mac'te ayrı kayıt olur.
- Sınırlar: görsel başına 25 MB, metin 1 MB.

### Sıra

Mac kapalıyken ya da başka bir ağdayken paylaştıklarınız telefonda bekler:
- Telefon bir Wi-Fi'a bağlıyken yaklaşık 15 dakikada bir arka planda tekrar denenir. Android pil tasarrufu nedeniyle gecikme biraz daha uzun olabilir.
- Hemen göndermek için MacClip'i açıp **Şimdi gönder** deyin.
- En fazla 20 öğe bekler. 10 günden eskiler silinir. Mac'te sıralama paylaştığınız saate göre yapılır.

## İzinler

Çalışma zamanında sorulan izin yoktur. Manifest'te yalnızca `INTERNET` ve `ACCESS_NETWORK_STATE` var.
- **Düz HTTP:** Android 9'dan beri düz HTTP varsayılan olarak kapalıdır. `res/xml/network_security_config.xml` bunu açar. İçerik zaten AES-256-GCM ile şifrelenir, anahtar ağda dolaşmaz.
- **Yedekleme:** Kapalıdır (`allowBackup="false"`). Eşleşme anahtarı Google yedeğine gitmez.
- **Yerel ağ izni:** Yeni Android sürümleri yerel ağ erişimi için ayrı bir izin getirebilir. Uygulama şu an `targetSdk 36` ile derleniyor. İleride bir "yakındaki cihazlar / yerel ağ" izni sorulursa izin verin.

## Sorun giderme

**"Mac'e ulaşılamadı"**
1. Mac'te MacClip açık mı? Menünün altındaki gri satır "Dinleniyor · IP:port" yazmalı.
2. Telefon ve Mac aynı Wi-Fi'da mı? Misafir ağı ya da "AP izolasyonu" cihazların birbirini görmesini engeller.
3. Telefonun tarayıcısında `http://<Mac IP>:47812/` açın. `{"error":"method"}` görünüyorsa ağ bağlantısı vardır. Sorun anahtardadır: yeniden eşleştirin.
4. Sayfa açılmıyorsa Mac'in güvenlik duvarında MacClip'e gelen bağlantı izni verilmemiş olabilir (Mac README'sine bakın).

**Bonjour (mDNS) çalışmıyor**
Uygulama önce eşleşmedeki IP'yi dener, ulaşamazsa Bonjour ile arar. Statik IP kullanıyorsanız Bonjour'a hiç ihtiyaç olmaz. Bazı modemler ve mesh sistemleri multicast'i engeller. Bu durumda Mac'in IP'si değişirse uygulamada adresi elle güncelleyin ya da yeniden eşleştirin.

**"Anahtar uyuşmuyor"**
Mac'te yeniden eşleştirme yapılmış. QR kodunu tekrar okutun. Sıradaki öğeler kaybolmaz.

**Sıradakiler hiç gitmiyor**
Bazı üreticiler (Xiaomi, Huawei, Samsung'un bazı ayarları) arka plan işlerini durdurur. Ayarlar › Uygulamalar › MacClip › Pil bölümünden kısıtlamayı kaldırın, ya da **Şimdi gönder**'i kullanın.

## Testler

```bash
./gradlew testDebugUnitTest
```

Çalışan bir Mac uygulamasına karşı uçtan uca test (ping, metin, görsel, yanlış anahtar). Anahtar Mac'teki `config.json` dosyasından alınır:

```bash
./gradlew testDebugUnitTest -PmacclipTestKey=<anahtar> -PmacclipTestPort=47812 -PmacclipTestHost=<Mac IP>
```
