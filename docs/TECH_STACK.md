# ISYARATIN — keputusan stack

Fondasi yang disepakati: Flutter/Dart, Riverpod, GoRouter, Supabase Auth,
PostgreSQL dan Storage, serta SQLite/Drift untuk penyimpanan lokal.

## Arsitektur

- `lib/core`: konfigurasi, tema, router, komponen bersama.
- `lib/data`: database lokal, model, repository, dan sinkronisasi Supabase.
- `lib/features`: autentikasi, beranda, percakapan, riwayat, dan profil.
- `lib/services`: kontrak integrasi pengenalan isyarat dan avatar.
- `supabase/migrations`: skema SQL dan RLS yang ditinjau sebelum diterapkan.

UI mengikuti file Figma ISYARATIN
<https://www.figma.com/design/GjaMlv1DqQmgrOf2KCtPN3/ISYARATIN?node-id=0-1>.
Frame utama: login `57:107`, daftar `53:63`, beranda `133:39`, kamera `17:1935`,
balasan `17:1989`, avatar `105:2009`, riwayat `132:45`, profil `80:4`.
Warna utama `#146C74`, latar `#F4F8FA`, font Inter (dibundel dengan lisensi OFL).
Status bar dan area gesture menggunakan sistem operasi, bukan gambar statis Figma.
Nama, email, riwayat, dan isi percakapan berasal dari data pengguna.

## Batas tahap fondasi

- Aplikasi bisa dijalankan tanpa kredensial Supabase melalui mode lokal.
- Pesan ketik dan riwayat tersimpan lokal. Data tamu dipisahkan dari data akun.
- Sinkronisasi dilakukan secara eksplisit dari halaman riwayat setelah login.
- Supabase menangani autentikasi dan penyimpanan; tidak memproses video kamera.
- Android menjadi target awal integrasi AI. Scaffold iOS/web disertakan untuk UI;
  dukungan native yang sama belum dijanjikan.
- Bridge Kotlin/CameraX/MediaPipe merupakan tahap lanjutan setelah pilihan
  BISINDO/SIBI, dataset, dan model dikonfirmasi. MediaPipe bawaan bukan penerjemah.
- Halaman avatar menggunakan ilustrasi Figma yang diberi label pratinjau statis.
  Renderer Three.js/WebView belum dikunci atau dimasukkan sebelum ada aset GLB
  dan animasi isyarat yang tervalidasi.
- Speech-to-text/TTS belum diaktifkan pada fondasi ini. Pengguna dapat mengetik.
- Riwayat lintas perangkat tidak tersinkron otomatis; tidak ada penghapusan
  tersinkron atau resolusi konflik lintas perangkat pada tahap ini.

## Data dan akses

`profiles`, `conversations`, `messages` menggunakan RLS berbasis `auth.uid()`.
Pesan harus memiliki pasangan `(conversation_id, owner_id)` yang valid.
Pesan cloud bersifat append-only. Bucket `avatar-assets` bersifat privat, dapat
dibaca pengguna yang sudah login, dan hanya diunggah melalui administrasi.
Hanya publishable key yang digunakan aplikasi. Service-role/secret key tidak
boleh dibundel. Mode lokal tidak mengirim pesan atau data kamera ke Supabase.

## Keputusan yang masih dibutuhkan

1. Apakah iOS termasuk target rilis pertama?
2. BISINDO atau SIBI, cakupan kosakata, dan sumber dataset/model?
3. Aset avatar, rig tangan, dan animasi isyarat yang tervalidasi?
4. Project URL dan publishable key Supabase untuk pengujian integrasi nyata?
