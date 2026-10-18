# Pembelajaran & Catatan Rekayasa Proyek (ISYARATIN)

Dokumen ini merangkum seluruh catatan eksperimen, pembelajaran teknis, arsitektur sistem, dan perbaikan bug sepanjang pengembangan proyek **ISYARATIN** (Sistem Pengenalan BISINDO & Avatar 3D Responsif).

---

## 1. Konversi OpenCV (`main.py`) ke Web Service FastAPI (`web.py`)
- **Pipeline Dasar**: Ekstraksi 21 koordinat tangan (63 fitur $x, y, z$) via MediaPipe Hands diumpankan ke interpreter TensorFlow Lite (`gesture_recognition.tflite`).
- **Streaming MJPEG**: Menggunakan FastAPI `StreamingResponse` (`multipart/x-mixed-replace`) dengan thread terpisah (`CameraManager`) agar pembacaan frame tidak memblokir async event loop.
- **Lifespan Manager**: Startup/shutdown kamera dikelola via `asynccontextmanager` (`lifespan`).
- **Fitur Frontend Web**: *Sentence Builder* (auto-append saat isyarat ditahan 1 detik), Text-to-Speech (Web Speech API), upload foto statis, dan Kamus Alfabet SIBI A–Z.
- **Dependensi Tambahan**: `fastapi`, `uvicorn`, dan `python-multipart` (diinstal via `uv add`).

---

## 2. Pipeline Sequence Video BISINDO: Multi-Landmark + BiLSTM
- **Dataset Video**: Dataset berbasis sekuens `.mp4` ([datasets/WL-BISINDO/](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/)) dengan 32 kelas kata isyarat BISINDO.
- **Multi-Landmark Holistic (186 Dimensi per Frame)**:
  - Tangan Kiri & Kanan: 42 landmark $\times$ 3 ($x, y, z$) = 126 fitur.
  - Lengan & Bahu: 6 landmark $\times$ 3 = 18 fitur.
  - Kepala & Wajah: 11 landmark $\times$ 3 = 33 fitur.
  - Pinggul / Torso: 2 landmark $\times$ 3 = 6 fitur.
  - Presence Flags: `[has_left_hand, has_right_hand, has_pose]` = 3 fitur.
  - **Total**: $126 + 18 + 33 + 6 + 3 = 186$ fitur per frame.
- **Normalisasi Anatomis Tubuh (Body-Centric Normalization)**:
  - Titik pusat (*origin*): $\text{torso\_center} = \frac{\text{left\_shoulder} + \text{right\_shoulder}}{2}$.
  - Skala tubuh: $\text{torso\_scale} = \|\text{left\_shoulder} - \text{right\_shoulder}\|$.
  - Menghilangkan variasi jarak kamera, resolusi video, dan proporsi fisik signer.
- **Arsitektur Model BiLSTM**:
  - Input: `(Batch, SEQ_LEN=32, 186)` pada 12.0 FPS.
  - `LayerNorm(186)` $\rightarrow$ `BiLSTM L1 (128 hidden)` $\rightarrow$ `Dropout(0.3)` $\rightarrow$ `BiLSTM L2 (96 hidden)` $\rightarrow$ `Dropout(0.3)`.
  - **Dual Temporal Pooling**: Penggabungan `MeanPooling` (rata-rata gerakan) dan `MaxPooling` (puncak isyarat) $\rightarrow 384$ fitur.
  - **Head**: `Linear(384, 192)` $\rightarrow$ `GELU` $\rightarrow$ `Dropout(0.3)` $\rightarrow$ `LayerNorm(192)` $\rightarrow$ `Linear(192, 32)`.
  - **Pelatihan**: CUDA AMP `bfloat16`, AdamW, label smoothing 0.05, ReduceLROnPlateau, Model EMA. Signer 3 di-holdout sebagai set validasi unseen.

---

## 3. Analisis Ketidakakuratan Live Testing & Arsitektur MGN
- **Akar Masalah Uji Langsung & Solusi**:
  1. **Temporal FPS Mismatch**: Training pada 12 FPS (~2.67 detik untuk 32 frame), sedangkan buffer kamera 30 FPS terisi hanya dalam ~1.06 detik (2.5x terlalu cepat). *Solusi*: Throttling waktu sampling buffer tepat pada interval $1/12$ detik (~83 ms).
  2. **False Positive Saat Tangan Diam (Idle State)**: Softmax memaksakan probabilitas 100% pada frame diam. *Solusi*: **Motion Energy Gate** — mengukur magnitudo kecepatan pergerakan sendi tangan (`instant_motion`); jika diam, status beralih ke standby dan inferensi dilewati.
  3. **Keterbatasan Fitur Statis**: Fitur statis 186-D tidak mencatat arah/kecepatan gerak dan jarak relatif. *Solusi*: **Ekspansi Spatio-Temporal Dinamis (386 Dimensi)**: 186 fitur statis + 183 instantaneous velocity ($\Delta P_t = P_t - P_{t-1}$) + 17 relasional spasial (jarak pergelangan, jarak tangan ke hidung/mulut/bahu, dan *finger curl ratio*).
  4. **Hand Inversion Akibat `cv2.flip`**: Melakukan flip sebelum MediaPipe membalik tangan kanan signer menjadi tangan kiri secara anatomis. *Solusi*: Ekstraksi MediaPipe wajib pada `raw_frame` asli; flip visualisasi hanya pada kanvas display.
- **Arsitektur Multi-Granularity Network (MGN)**:
  - **Micro-Branch**: Multi-scale temporal Conv1D ($k=3, k=5$) + residual untuk menangkap lekukan mikro jari jemari (*finger curls*).
  - **Macro-Branch**: 2-Layer BiLSTM untuk alur spasio-temporal global.
  - **Temporal Stroke Attention Pooling**: Pembobotan atensi otomatis pada fase puncak gerakan (*stroke phase*) dan mereduksi fase diam awal/akhir.

---

## 4. Evaluasi Komprehensif & Penyesuaian Dataset (28 Kelas Akhir)
- **Struktur Label & Profiling**: Standardisasi [labeled.json](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/labeled.json) dan mesin profiling [dataset_visualizer.py](file:///d:/Project/4mlai/hand-isyarat/dataset_visualizer.py) untuk memeriksa class imbalance, signer heatmap, durasi, dan FPS.
- **Eliminasi 4 Kelas Warna**:
  - Isyarat warna (*Merah, Kuning, Hijau, Hitam*) memiliki ambiguitas spasio-temporal tinggi pada area wajah/bibir dan akurasi rendah.
  - Sebanyak 200 video diarsipkan ke `datasets/WL-BISINDO_excluded/`.
  - Dataset aktif disesuaikan menjadi **28 kelas** (1.400 video seimbang, 5 signers) dengan cache landmark `wl_holistic_lstm_cache.npz` (shape `[1400, 120, 186]`).
- **Hasil Retraining MGN (28 Kelas - 1.400 Video Konsensus)**:
  - **Top-1 Accuracy**: **65.71%** (naik signifikan dari baseline 32 kelas 23.44%, kenaikan absolut +42.27%).
  - **Top-3 Accuracy**: **89.93%** | **Top-5 Accuracy**: **94.57%**.
  - **Macro ROC AUC**: **0.9830** | **Micro ROC AUC**: **0.9717** | **Zero Class Collapse** (semua kelas terprediksi).
  - Dilengkapi **Interactive Web Dashboard** standalone di `reports/dashboard.html` (Confusion Matrix 28x28, ROC/PR curves, dan diagnostic table).

---

## 5. Optimalisasi Kinematik Wajah-Tangan (400 Dimensi) & Validasi Mobile
- **Fitur 400 Dimensi (`holistic_extractor.py`)**: 186 statis + 183 velocity + 31 fitur kinematik relasional baru (jarak telunjuk & ibu jari ke bibir/mulut untuk membedakan *Makan* vs *Cari*; jarak telunjuk ke telinga untuk membedakan *Tuli* vs *Cari*; jarak telunjuk ke torso dada untuk membedakan *Saya*, *Kapan*, dan *Rumah*).
- **Temporal Focal Loss & Label Smoothing (`train-new.py`)**: Menggunakan $\gamma = 2.0$, smoothing 0.05, dan class weights untuk memfokuskan gradien pada pasangan isyarat yang tumpang tindih (*hard confused pairs*).
- **Post-Filtering & Re-ranking Top-3 (`bisindo_postprocess.py`)**: Menggunakan matriks transisi probabilitas Bigram BISINDO dan aturan kinematik yang diekspor ke [bisindo_rules.json](file:///d:/Project/4mlai/hand-isyarat/bisindo_rules.json) agar dapat dieksekusi di mobile tanpa runtime Python.
- **Validasi Inferensi Mobile (`mobile_inference.py`)**: ONNX Runtime menghasilkan waktu inferensi **~3.89 ms** dan total pipeline **~4.37 ms** (jauh di bawah batas 33 ms untuk 30 FPS). Ukuran model ONNX hanya **2.6 MB** (TFLite ~700 KB – 1.3 MB).

---

## 6. Pipeline Animasi 3D Avatar Video-Driven (Motion Retargeting)
- **Rig Avatar Humanoid ([avatar/man-rigged.glb](file:///d:/Project/4mlai/hand-isyarat/avatar/man-rigged.glb))**: 54 tulang, root `Hips`, artikulasi 3 ruas tulang per jari tangan kanan dan kiri (`RightHandThumb1-3`, `RightHandIndex1-3`, dst).
- **Retargeting Kinematik (`retargeter.py`)**: Mengonversi landmark MediaPipe 3D ke ruang koordinat avatar (Y-up), menghitung quaternion rotasi lengan atas/bawah, serta sudut tekukan (*flexion curl*) 5 jemari ke format JSON per-frame.
- **Player Dual-Viewport Three.js (`avatar_viewer.html` & `run_viewer.py`)**: Sinkronisasi side-by-side video referensi penutur asli dengan avatar 3D WebGL (dilengkapi timeline slider, speed control 0.25x–1.5x, orbit controls 360°, dan motion switcher dropdown).
- **Katalog Gerakan Awal**: Rumah, Siang, Makan, Saya, Malam, dan Air diorganisir dalam [avatar/motions_manifest.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motions_manifest.json).

---

## 7. Studio Interaktif Pose & Gerakan 3D Custom (`avatar/pose_studio.html`)
- **Penyebab Gerakan Auto-Ekstraksi Video Kurang Pas**:
  1. *Depth Ambiguity*: Estimasi kedalaman monokular ($Z$) MediaPipe berfluktuasi (*jitter*).
  2. *Constraint Mismatch*: Rig 3D memiliki rest-pose dan batasan sudut engsel anatomis; pemetaan tanpa batas IK memicu sendi siku terpelintir (*twisted elbow*).
  3. *Presisi Linguistik BISINDO*: Orientasi telapak tangan, bentuk jemari, dan lokasi kontak menuntut akurasi sudut yang ketat.
- **Fitur Pose Studio**:
  - Slider sendi real-time: Lengan atas, siku, pergelangan tangan, master & individual finger curl/spread, kepala, dan torso.
  - Preset 1-klik bentuk telapak tangan (✋ Terbuka, ✊ Genggam, ☝️ Menunjuk, ✌️ V, 👌 Pinch, 🤟 ILY, 🤙 Telepon) dan preset isyarat penuh.
  - Keyframe sequencer timeline dengan interpolasi mulus (Hermite/Slerp), mirroring pose kanan $\rightarrow$ kiri, dan ekspor/impor JSON animasi.
  - **Koreksi Sumbu Rotasi Kinematik**: Membalik rotasi ke sumbu $-X$ (`-RightArm_up`, `-RightForeArm_bend`, `-curl`) agar lengan dan jemari menekuk ke arah dada, bukan ke belakang punggung.

---

## 8. Live Webcam Motion Capture & Kinematika Lengan Organik
- **Alur MoCap Browser**: Mirroring MediaPipe Holistic realtime $\rightarrow$ hitung mundur 3s/5s $\rightarrow$ cuplikan keyframe per ~90 ms (~11 FPS) ke sequencer timeline $\rightarrow$ auto-loop dan ekspor JSON.
- **Penyelesaian Masalah Lengan & Pergelangan Kaku**:
  1. *Elevasi Lengan 3D Kedalaman*: Mengganti delta vertikal 2D dengan kombinasi kedalaman maju ($dz$) dan ketinggian kerja tangan:
     $$\theta_{up} = \text{atan2}(fwd + up + handLift, dy)$$
  2. *Solver Normal Telapak & Pergelangan*: Menggunakan cross product $\vec{N} = \vec{v}_{palm} \times \vec{v}_{knuckle}$ untuk menghitung `ForeArm_twist` (pronasi/supinasi), `Hand_pitch`, `Hand_yaw`, dan `Hand_roll`.
  3. *Elevasi Selangka Dinamis (Clavicle Kinematics)*: Tulang `RightShoulder` dan `LeftShoulder` otomatis terangkat proporsional ($15\% - 20\%$) saat lengan atas naik.
  4. *Adaptive EMA Filter*: Smoothing responsif ($\alpha = 0.42$) untuk meredam jitter webcam.

---

## 9. Integrasi 3D Avatar ke Aplikasi Mobile Flutter (ISYARATIN)
- **Penyimpanan Aset**: [assets/avatar/](file:///d:/Project/4mlai/apapun/isyaratin/assets/avatar/) menyimpan model `man-rigged.glb`, `viewer.html`, runtime Three.js offline (`three.min.js`, `GLTFLoader.js`), dan motion JSON.
- **Embedded HTTP Streaming ([AvatarMotionService](file:///d:/Project/4mlai/apapun/isyaratin/lib/services/avatar_motion_service.dart))**: Menjalankan loopback server `http://127.0.0.1:<port>` internal via `dart:io` guna mengatasi batasan Android Binder transaction 1 MB dan CORS `file://` WebView.
- **Antarmuka [AvatarScreen](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/conversation/conversation_screens.dart)**: Viewport 3D WebGL, preset sudut kamera (Badan, Zoom Tangan, Kepala), auto-detect isyarat kalimat balasan, dan kontrol kecepatan (0.5x, 1.0x, 1.5x).
- **Perbaikan `ImageError` (IllegalArgumentException) Android Camera**:
  - Native Google ML Kit menolak YUV_420_888 format 35 pada `InputImage.fromByteArray`.
  - *Solusi*: Dibuat fungsi konversi `_yuv420ToNv21()` di [sign_recognition_pipeline.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/services/sign_recognition_pipeline.dart) yang meng-interleave plane V dan U dengan memperhitungkan `bytesPerRow` dan `bytesPerPixel`, lalu dikirimkan sebagai `InputImageFormat.nv21`.
- **Cropping Avatar (Upper Body Focus)**: Menerapkan Three.js GPU hardware clipping plane (`y = -1.02`) di [viewer.html](file:///d:/Project/4mlai/apapun/isyaratin/assets/avatar/viewer.html) untuk memotong tubuh di bawah pinggang (hips, paha, kaki) dan menambahkan pedestal ring minimalis.

---

## 10. Paradigma Pengenalan Isyarat: Record-and-Infer Per-Kata
- **Rasional**: Menggantikan rolling buffer berkelanjutan yang rentan memicu noise dan false positive saat jeda atau transisi tangan.
- **Alur Perekaman Total**:
  1. *Penyelarasan Awal*: Indikator kesiapan `✓ Tubuh Terdeteksi · Tangan: N`.
  2. *Perekaman*: Akumulasi vektor 186-dimensi (~12 FPS) ke `_recordedFrames`.
  3. *Auto-Stop Cerdas*: Otomatis berhenti jika tangan turun $\ge 1.1$ detik ($\ge 14$ frame kosong) atau tangan diam $\ge 1.5$ detik setelah gerakan $\ge 16$ frame. Pengguna juga dapat menekan tombol stop manual kapan saja.
- **Segmentasi & Inferensi Per-Kata (`stopRecordingAndRecognize()`)**:
  - *Activity Trimming*: Memotong frame diam di awal dan akhir rekaman.
  - *Isyarat Tunggal ($\le 42$ frame)*: Resampling linier seragam menjadi tepat 32 frame `[1, 32, 186]` untuk inferensi TFLite.
  - *Multi-Kata ($> 42$ frame)*: Sliding window 32 frame dengan stride 10 frame (~0.83s), repetition suppression pada kata berurutan yang sama, dan pemilihan peak confidence.

---

## 11. Perbaikan Kamera Kotak (1:1), Tombol Berhenti, & Standardisasi Layout
- **Kamera Kotak (1:1 Aspect Ratio) Anti-Gepeng**:
  - Mengubah container kamera menjadi `AspectRatio(aspectRatio: 1.0)`.
  - Menggunakan `LayoutBuilder` + `OverflowBox` yang dipusatkan (`Center`) untuk melakukan center-crop fill manual berdasarkan rasio sensor (`previewRatio`).
  - Memotong luapan secara halus dengan `ClipRRect(borderRadius: BorderRadius.circular(24))` dan menambahkan bingkai viewfinder hijau toska di 4 sudut.
- **Perbaikan Inferensi & Tombol Berhenti**:
  - *Shape Mismatch*: Memperbaiki pengiriman tensor input TFLite di [sign_recognition_model.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/services/sign_recognition_model.dart) dari flat array `[1, 5952]` menjadi tensor 3D `[1, 32, 186]`.
  - Label tombol diperjelas menjadi **"Berhenti & Terjemahkan"** serta tombol mengambang merah di atas pratinjau kamera.
  - Menambahkan tombol kontrol **Jeda / Lanjutkan Kamera** (`_togglePauseCamera()`) pada toolbar atas kamera.
  - Menstandarkan padding `ListView(fromLTRB(20, 16, 20, 24))` dan tombol bersihkan teks (`suffixIcon: Icons.clear`).

---

## 12. Solusi Avatar 3D Loading Terus-Menerus (Infinite Spinner)
- **Akar Masalah**:
  1. *Cleartext HTTP Blocked*: Android 9+ memblokir koneksi HTTP `127.0.0.1` tanpa enkripsi (`net::ERR_CLEARTEXT_NOT_PERMITTED`).
  2. *Silent Failure*: Ketiadaan `setOnConsoleMessage` dan error listener pada WebView Flutter.
  3. *Race Condition JavaScript Bridge*: `notifyFlutter("avatar_ready")` dipanggil sebelum `window.FlutterBridge` terinjeksi.
  4. *Ketiadaan Content-Length*: File model 13 MB dimuat berulang kali dari APK tanpa header ukuran.
  5. *Safety Timeout*: Flag loading Flutter tidak memiliki fallback batas waktu.
- **Solusi Komprehensif**:
  1. Menambahkan `android:usesCleartextTraffic="true"` pada `<application>` di [AndroidManifest.xml](file:///d:/Project/4mlai/apapun/isyaratin/android/app/src/main/AndroidManifest.xml).
  2. Menerapkan antrean pesan (`pendingFlutterMessages`) dan polling retry (120 ms) pada JS bridge di [viewer.html](file:///d:/Project/4mlai/apapun/isyaratin/assets/avatar/viewer.html).
  3. Menyimpan byte model `man-rigged.glb` di memori (`_cachedGlbBytes`) pada [AvatarMotionService](file:///d:/Project/4mlai/apapun/isyaratin/lib/services/avatar_motion_service.dart) lengkap dengan header `Content-Length` dan `Cache-Control`.
  4. Memasang verification polling periodik (600 ms), safety timeout 8 detik, dan tombol darurat manual *"Buka Tampilan 3D Langsung"* di [conversation_screens.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/conversation/conversation_screens.dart).

---

## 13. Penyempurnaan UI/UX & Eliminasi Bloat Teks Kamera
- **Pembersihan Layar Kamera (`CameraScreen`)**: Menghapus teks instruksi panjang di bawah tombol rekam (`"Rekam gerakan total di depan kamera..."`), memperkecil padding kartu kontrol menjadi `EdgeInsets.symmetric(horizontal: 14, vertical: 12)`, dan memperhalus tombol toolbar atas kamera dengan border tipis semi-transparan.
- **Modernisasi Bilah Navigasi Bawah ([AppShell](file:///d:/Project/4mlai/apapun/isyaratin/lib/core/router.dart))**: Mengganti kotak teal kaku dengan konsep *active pill indicator* (kapsul halus `AppColors.primary.withValues(alpha: 0.12)`, label semibold, dan tab non-aktif slate grey netral).
- **Hierarki Komponen**: Memperbarui [StepHeader](file:///d:/Project/4mlai/apapun/isyaratin/lib/core/widgets.dart) dengan badge pill bernomor, merapikan banner panduan suara di `ReplyScreen` dengan palet amber lembut (`0xFFFFF7ED`), dan memangkas margin vertikal berlebihan.

---

## 14. Fitur Penghapusan Riwayat Percakapan (Satuan & Sekaligus)
- **Foreign Key Cascade SQLite ([LocalDatabase](file:///d:/Project/4mlai/apapun/isyaratin/lib/data/local_database.dart))**: Skema dirancang dengan `FOREIGN KEY(conversation_id, owner_id) REFERENCES conversations(id, owner_id) ON DELETE CASCADE` dan `PRAGMA foreign_keys = ON`.
  - `deleteConversation(ownerId, id)`: Menghapus satu percakapan beserta seluruh pesannya via mekanisme cascade.
  - `clearHistory(ownerId)`: Menghapus seluruh percakapan milik pengguna/tamu aktif.
- **Manajemen State & Cloud Sync ([SessionController](file:///d:/Project/4mlai/apapun/isyaratin/lib/core/providers.dart))**:
  - Mereset state percakapan aktif jika percakapan yang dihapus sedang dibuka.
  - Menginvalidasi provider riwayat dan pesan agar UI langsung reaktif.
  - Melakukan *best-effort remote deletion* pada tabel `messages` dan `conversations` di Supabase jika terotentikasi.
- **Aksi UI Multikanal**:
  - Di [HistoryScreen](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/history/history_screen.dart): Tombol bulk delete (*delete sweep*), *Swipe-to-Delete* (`Dismissible`), menu popup `more_vert`, dan gesture *Long-Press*.
  - Di [ConversationDetailScreen](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/history/history_screen.dart): Ikon tong sampah merah pada AppBar dengan dialog konfirmasi.
  - Token warna terpadu `AppColors.error = Color(0xFFDC2626)` di [theme.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/core/theme.dart).

---

## 15. Perbaikan RenderFlex Overflow 107 px pada Header Kartu Balasan
- **Penyebab**: Header kartu teks balasan avatar sebelumnya menggunakan `Row` kaku yang membungkus ikon, judul, dan badge urutan gerakan (`_detectedGestureName`). Pada kalimat multi-gerakan (misal *"Silakan → Siapkan → Berkas"*), teks badge menjadi sangat panjang (~300 px), melebihi lebar layar smartphone dan memicu error `A RenderFlex overflowed by 107 pixels on the right`.
- **Solusi**:
  1. Mengganti `Row` dengan `SizedBox(width: double.infinity, child: Wrap(...))` (`alignment: WrapAlignment.spaceBetween`, `crossAxisAlignment: WrapCrossAlignment.center`, `runSpacing: 6`) di [conversation_screens.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/conversation/conversation_screens.dart).
  2. Menyederhanakan teks badge: jika $>1$ gerakan, menampilkan format ringkas `${_motionQueue.length} Gerakan Sesuai` (misal *"3 Gerakan Sesuai"*), dilengkapi `Tooltip` urutan lengkap saat disentuh dan pembatas `maxLines: 1` dengan `ellipsis`.
  3. Menjamin layout tetap rapi di layar sempit (320px) maupun skala teks besar (1.5x) tanpa overflow.

---

## 16. Penghapusan Fitur Manual Pustaka Gerakan Isyarat BISINDO
- **Latar Belakang**: Kartu manual *"Pustaka Gerakan Isyarat BISINDO"* yang menampilkan puluhan `ChoiceChip` gerakan dihapus dari [AvatarScreen](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/conversation/conversation_screens.dart) karena membuat antarmuka bloat dan menduplikasi fokus layar Langkah 3 yang bertugas memutar animasi respon teks secara otomatis.
- **Pembersihan Kode**:
  1. Menghapus `SurfaceCard` pustaka gerakan beserta widget `ChoiceChip` di dalamnya.
  2. Menghapus method `_switchMotion` dan deklarasi lokal `final motions = AvatarMotionService.instance.motions;` pada `build()`.
  3. Merapikan jarak vertikal antar-kartu (Playback controls langsung tersambung bersih ke kartu Teks balasan).

---

## 17. Ringkasan Verifikasi & Status Kualitas Kode
- **Analisis Statis**: Menjalankan `flutter analyze` secara berkala dengan hasil konsisten **0 issues / warnings** (bebas dari error, warning linting, dan dead code).
- **Pengujian Otomasi**: Menjalankan `flutter test` dengan hasil **21/21 tests passed!** (seluruh unit test dan widget test lolos, mencakup database cascade, alur percakapan, avatar service streaming, dan responsivitas layar kecil 320x640 dengan text scale 1.5x).
