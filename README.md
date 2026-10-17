# ISYARATIN

AI-Powered Two-Way Sign Language Communication Assistant for Inclusive
Accessibility With 3D Avatar.

Fondasi aplikasi Flutter berdasarkan mockup Figma ISYARATIN, dengan Supabase
sebagai backend dan SQLite/Drift untuk riwayat lokal.

## Menjalankan

Fondasi diverifikasi menggunakan Flutter stable 3.47.7 / Dart 3.13.5. Jalankan:

```powershell
flutter pub get
flutter run -d chrome
```

Tanpa konfigurasi, pilih **Coba tanpa akun**. Pesan ketik dua arah dan riwayat
berfungsi lokal tanpa Supabase. Di Windows, SDK lokal sementara tersedia di
`.tooling/flutter/bin/flutter.bat` bila Flutter belum ada di PATH. Folder ini
diabaikan Git dan tidak wajib untuk developer lain.

## Menghubungkan Supabase

1. Buat project Supabase dan aktifkan autentikasi email/password.
2. Jalankan `supabase/migrations/202610170001_initial_schema.sql` melalui SQL
   Editor pada project baru, atau gunakan Supabase CLI migrations setelah review.
3. Salin `config/example.json` menjadi `config/local.json`, lalu isi
   `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY` dari panel Connect Supabase.
   Jangan gunakan secret/service-role key.
4. Di Authentication > URL Configuration, izinkan callback mobile
   `id.isyaratin.app://auth-callback` dan callback web sesuai origin dev,
   misalnya `http://localhost:7357/auth/callback`.
5. Jalankan:

```powershell
flutter run -d chrome --web-port 7357 --dart-define-from-file=config/local.json
# Android: jalankan emulator/hubungkan HP terlebih dahulu
flutter run --dart-define-from-file=config/local.json
```

Daftar menggunakan email, verifikasi tautan email, lalu masuk. Pemulihan kata
sandi menggunakan tautan email yang membuka kembali aplikasi. Untuk pengujian
web, gunakan port yang sama dengan daftar redirect Supabase.

Di halaman Riwayat, tombol sinkronisasi mengunggah percakapan akun yang belum
tersinkron dan mengambil riwayat cloud. Riwayat tamu tetap terpisah dan tidak
otomatis diunggah ke akun. Sinkronisasi tidak berjalan otomatis di latar belakang.
Database lokal belum dienkripsi; hindari data sensitif nyata selama pengujian.

## Status fitur

- UI login/daftar, beranda, pesan ketik, balasan, riwayat, detail, dan profil.
- Simpan percakapan, edit judul/lokasi, pencarian, dan salin transkrip.
- Integrasi Supabase Auth dan sinkronisasi riwayat siap dikonfigurasi.
- Skema PostgreSQL dengan RLS kepemilikan dan bucket privat `avatar-assets`.
- Pengenalan kamera, rekam suara/TTS, dan animasi avatar **belum diaktifkan**.
  Ilustrasi avatar merupakan pratinjau statis dari Figma, bukan animasi 3D.
- Scaffold Android, iOS, dan web tersedia; build native memerlukan toolchain
  masing-masing. Build iOS membutuhkan macOS/Xcode.

## Pemeriksaan

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
```

Test mencakup alur pesan lokal, pemisahan data pemilik, impor idempoten,
perlindungan perubahan lokal saat sinkronisasi, serta navigasi layar kecil.
Autentikasi, RLS, dan sinkronisasi cloud perlu diuji pada project Supabase yang
sudah dikonfigurasi; tidak ada migration yang otomatis dijalankan ke cloud.

Lihat [keputusan stack](docs/TECH_STACK.md) untuk arsitektur dan batas tahap ini.
Font Inter dibundel dengan [lisensi OFL](assets/fonts/OFL.txt).
