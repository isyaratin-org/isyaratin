# Panduan Build APK & Install ke Device via ADB

Panduan untuk project **ISYARATIN** (Flutter). Berlaku untuk Windows (PowerShell/cmd).

---

## 1. Prasyarat

Pastikan sudah terpasang:

| Kebutuhan                            | Cek perintah        |
| ------------------------------------ | ------------------- |
| Flutter SDK                          | `flutter --version` |
| Android SDK + platform tools (adb)   | `adb --version`     |
| Java 17+                             | `java -version`     |
| Device Android (USB debugging aktif) | `adb devices`       |

> **Catatan project ini:**
>
> - `applicationId` = `id.isyaratin.app` (lihat [`android/app/build.gradle.kts`](android/app/build.gradle.kts:18))
> - Build **release** saat ini memakai **debug signing key** (lihat [`android/app/build.gradle.kts`](android/app/build.gradle.kts:35)) — cukup untuk uji internal, **bukan** untuk rilis Play Store.
> - Aplikasi butuh izin **Kamera** (sudah ditambahkan di [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml:3)).

---

## 2. Build APK

### A. Build Debug APK (untuk pengujian cepat)

```bash
flutter build apk --debug
```

Hasil: `build/app/outputs/flutter-apk/app-debug.apk`

### B. Build Release APK (lebih kecil & optimal)

```bash
flutter build apk --release
```

Hasil: `build/app/outputs/flutter-apk/app-release.apk`

### C. Build APK per-ABI (opsional, ukuran lebih kecil)

```bash
flutter build apk --release --split-per-abi
```

Hasil di `build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-release.apk` — kebanyakan HP modern (disarankan)
- `app-armeabi-v7a-release.apk` — HP lama 32-bit
- `app-x86_64-release.apk` — emulator 64-bit

> **Tips:** Untuk install ke HP fisik, gunakan `app-arm64-v8a-release.apk` (paling umum).

---

## 3. Menyiapkan Device & ADB

### A. Aktifkan USB Debugging di HP

1. Buka **Settings → About phone**.
2. Ketuk **Build number** 7× hingga muncul "You are now a developer".
3. Buka **Settings → Developer options**.
4. Aktifkan **USB debugging**.
5. Sambungkan HP ke komputer via kabel USB.
6. Jika muncul dialog "Allow USB debugging?", pilih **Allow**.

### B. Cek device terdeteksi

```bash
adb devices
```

Output yang diharapkan:

```
List of devices attached
R58M1234567    device
```

- Status `device` = siap.
- Status `unauthorized` = belum approve di HP.
- Status `offline` = coba cabut-tancap kabel / restart adb (`adb kill-server` lalu `adb start-server`).

---

## 4. Install APK ke Device

### A. Install dari hasil build

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Keterangan flag:

- `-r` → reinstall (pertahankan data aplikasi yang sudah ada).
- `-d` → izinkan downgrade versi (tambahkan jika versi lebih rendah).
- `-t` → izinkan install APK yang menandai `testOnly` (jarang dipakai).

Contoh gabungan:

```bash
adb install -r -d build/app/outputs/flutter-apk/app-release.apk
```

### B. Install ke semua device yang terhubung

```bash
adb devices | tail -n +2 | cut -sf1 | xargs -I{} adb -s {} install -r build/app/outputs/flutter-apk/app-release.apk
```

### C. Install APK dari lokasi lain

```bash
adb install -r "C:\path\ke\app-release.apk"
```

---

## 5. Menjalankan & Menguji Aplikasi

### A. Buka aplikasi setelah install

```bash
adb shell am start -n id.isyaratin.app/.MainActivity
```

### B. Lihat log aplikasi (logcat)

```bash
adb logcat -s flutter
```

Filter berdasarkan package:

```bash
adb logcat --pid=$(adb shell pidof id.isyaratin.app)
```

### C. Hentikan aplikasi

```bash
adb shell am force-stop id.isyaratin.app
```

### D. Uninstall aplikasi

```bash
adb uninstall id.isyaratin.app
```

---

## 6. Cara Cepat: Build + Install Sekaligus

### Debug (langsung jalan dengan hot reload)

```bash
flutter run -d <device-id>
```

Contoh: `flutter run -d R58M1234567`

### Release build + install otomatis

```bash
flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## 7. Troubleshooting

| Masalah                                          | Solusi                                                                                               |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `adb: device unauthorized`                       | Di HP, buka dialog USB debugging → **Allow**, lalu `adb devices` lagi.                               |
| `adb: device offline`                            | `adb kill-server` → `adb start-server` → cabut-tancap kabel.                                         |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE`             | Uninstall dulu: `adb uninstall id.isyaratin.app`, lalu install ulang.                                |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE`            | Kosongkan penyimpanan HP, atau pakai APK per-ABI yang lebih kecil.                                   |
| `INSTALL_FAILED_VERSION_DOWNGRADE`               | Tambahkan flag `-d`: `adb install -r -d ...`.                                                        |
| `Failure [INSTALL_PARSE_FAILED_NO_CERTIFICATES]` | APK korup — build ulang dengan `flutter clean` lalu `flutter build apk`.                             |
| Build gagal karena cache                         | `flutter clean` lalu `flutter pub get`, build ulang.                                                 |
| `No devices found`                               | Pastikan USB debugging aktif, kabel data (bukan hanya charge), dan `adb devices` menampilkan device. |

---

## 8. Catatan Penting untuk Project Ini

1. **Signing release** masih memakai debug key. Untuk distribusi publik, buat keystore sendiri dan konfigurasi di [`android/app/build.gradle.kts`](android/app/build.gradle.kts:31) (blok `signingConfigs`).
2. **Supabase**: pastikan `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY` di-set saat build (via `--dart-define`), contoh:

   ```bash
   flutter build apk --release --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=eyJ...
   ```

   Tanpa keduanya, aplikasi tetap berjalan dalam **mode lokal** (tanpa akun/sinkronisasi).
3. **Model isyarat**: letakkan `sign_model.tflite` (input `[1, 32, 186]` float32) dan `labels.txt` di `assets/models/` sebelum build agar ikut ter-bundle. Lihat [`assets/models/README.md`](assets/models/README.md:1) untuk kontrak lengkap dan panduan konversi ONNX→TFLite.
4. **Izin kamera** sudah ada di manifest; saat pertama membuka halaman Kamera, sistem akan meminta izin.
5. **Pengenalan isyarat real-time** hanya aktif di Android (pakai `hand_landmarker`/MediaPipe). Di platform lain, aplikasi tetap berjalan dengan input ketik.
