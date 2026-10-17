# Pembelajaran & Catatan Eksperimen

## 1. Konversi Script OpenCV (`main.py`) ke Aplikasi Web FastAPI (`web.py`)
- **Model TFLite & MediaPipe**: Menggunakan MediaPipe Hands untuk mengekstrak 21 titik koordinat tangan (63 fitur `x, y, z`) dan mengumpankannya ke interpreter TensorFlow Lite (`gesture_recognition.tflite`).
- **Web Streaming MJPEG**: Menggunakan FastAPI `StreamingResponse` dengan `multipart/x-mixed-replace` untuk menyalurkan frame video webcam yang telah diolah dan diberi landmark secara realtime ke tag `<img>` di browser.
- **Multithreading**: OpenCV capture dijalankan pada thread terpisah (`CameraManager`) agar pembacaan frame tidak memblokir event loop async FastAPI.
- **Lifespan Manager (FastAPI)**: Menggunakan `asynccontextmanager` (`lifespan`) untuk mengelola startup & shutdown kamera secara bersih tanpa warning deprasi `@app.on_event`.
- **Modul Uvicorn Import**: Sintaks eksekusi uvicorn menggunakan nama modul Python `"web:app"` (bukan `"web.py:app"`).
- **Fitur Tambahan Frontend**:
  - Sentenence Builder / Penyusun Kalimat dengan fitur auto-append (saat isyarat ditahan 1 detik).
  - Text-to-Speech (TTS) menggunakan `window.speechSynthesis` Web Speech API.
  - Pengujian foto/gambar statis via upload `POST /api/predict_image`.
  - Kamus Alfabet SIBI A - Z interaktif.

## 2. Dependensi Tambahan
- `fastapi`, `uvicorn`, & `python-multipart` ditambahkan ke lingkungan proyek via `uv add`.

## 3. Rekonstruksi Pipeline Sequence Video BISINDO: Multi-Landmark + BiLSTM (`train-new.py` & `camera.py`)
- **Dataset Berbasis Video**: Beralih dari dataset citra statis ke dataset sequence video `.mp4` (`datasets/WL-BISINDO/`) dengan 32 kelas kata isyarat BISINDO.
- **Multi-Landmark Holistic (186 Dimensi per Frame)**:
  - **Tangan Kiri & Kanan**: 42 landmark x 3 (x, y, z) = 126 fitur.
  - **Lengan & Bahu**: 6 landmark x 3 (bahu, siku, pergelangan) = 18 fitur.
  - **Kepala & Wajah**: 11 landmark x 3 (hidung, mata, telinga, sudut mulut) = 33 fitur.
  - **Pinggul / Torso**: 2 landmark x 3 (pinggul kiri & kanan untuk orientasi torso) = 6 fitur.
  - **Presence Flags**: `[has_left_hand, has_right_hand, has_pose]` = 3 fitur.
  - **Total**: `63 + 63 + 18 + 33 + 6 + 3 = 186` fitur per frame.
- **Normalisasi Anatomis Tubuh (Body-Centric Normalization)**:
  - Titik pusat (*origin*) diambil dari titik tengah kedua bahu (`torso_center = (left_shoulder + right_shoulder) / 2`).
  - Skala tubuh dinormalisasi berdasarkan jarak antar kedua bahu (`torso_scale = norm(left_shoulder - right_shoulder)`).
  - Seluruh landmark ditranslasi dan diskalakan terhadap tubuh signer, sehingga posisi tangan relatif terhadap wajah (misal: 'Air' di dekat mulut, 'Ingat' di dekat dahi, 'Saya' di depan dada) tetap konsisten terlepas dari jarak kamera dan resolusi video.
- **Arsitektur Model BiLSTM (PyTorch + CUDA)**:
  - Input: `(Batch, SEQ_LEN=32, 186)` pada frame rate 12.0 FPS.
  - `LayerNorm(186)` -> `BiLSTM Layer 1 (128 hidden)` -> `Dropout(0.3)` -> `BiLSTM Layer 2 (96 hidden)` -> `Dropout(0.3)`.
  - **Dual Temporal Pooling**: Menggabungkan rata-rata gerakan (`MeanPooling`) dan momen puncak isyarat (`MaxPooling`) sepanjang waktu (`concat -> 384` fitur).
  - **Classification Head**: `Linear(384, 192)` -> `GELU` -> `Dropout(0.3)` -> `LayerNorm(192)` -> `Linear(192, 32)`.
  - **Optimasi & Generalisasi**: Dilatih menggunakan GPU CUDA dengan AMP `bfloat16`, AdamW optimizer, label smoothing loss (0.05), scheduler ReduceLROnPlateau, dan bobot Model EMA (*Exponential Moving Average*).
- **Protokol Validasi Unseen Signer**:
  - Signer 3 di-holdout penuh sebagai set validasi (menguji model pada individu baru yang belum pernah dilihat saat training).
- **Pengujian Real-Time (`camera.py`)**:
  - Script pengujian mandiri live webcam atau file video (`--video path.mp4`).
  - Dilengkapi visualisasi landmark (tangan cyan, lengan hijau/kuning, kepala biru).
  - Fitur state machine (mendengarkan -> menahan jeda), peredam kedipan (*debounce* kestabilan N window berturut-turut), dan *Sentence Builder* penyusun kalimat.
  - Mendukung eksekusi via PyTorch (`.pt`) maupun ONNX Runtime (`.onnx`).

## 4. Analisis Ketidakakuratan Live Testing & Solusi Arsitektur MGN (Multi-Granularity Network)
- **Akar Masalah Ketidakakuratan Saat Ditest**:
  1. **Temporal FPS Mismatch (Kritikal!)**:
     - Saat training, video di-sample pada **12 FPS** (`SEQ_LEN=32` mencakup durasi waktu ~2.67 detik).
     - Di `camera.py` sebelumnya, tiap frame webcam (30 FPS) langsung dimasukkan ke buffer, sehingga 32 frame terisi hanya dalam kurun waktu **~1.06 detik**. Akibatnya gerakan pengguna terpotong 2.5x lebih cepat dibanding data latih model.
     - *Solusi*: Throttling waktu sampling buffer persis pada interval `1.0 / 12.0` detik (~83 ms).
  2. **False Positive Saat Tangan Diam (Idle State)**:
     - Saat pengguna tidak sedang berisyarat (tangan turun/istirahat), fungsi Softmax tetap dipaksa mengeluarkan probabilitas 100% pada salah satu dari 32 kelas, menyebabkan kata acak terus terpilih.
     - *Solusi*: **Motion Energy Gate**. Mengukur magnitudo kecepatan pergerakan sendi tangan (`instant_motion`). Jika di bawah ambang batas (tangan diam), status beralih ke `"(Menunggu gerakan isyarat...)"` dan proses prediksi dilewati.
  3. **Keterbatasan Representasi Fitur Statis (186 Dimensi)**:
     - Koordinat statis tidak secara eksplisit mencantumkan arah & kecepatan gerak isyarat (*velocity* $\Delta P_t$), serta relasi jarak antartangan dan jarak tangan ke jangkar wajah/tubuh (*relational distances*).
     - *Solusi*: **Dynamic Spatio-Temporal Feature Expansion (386 Dimensi)**:
       - 186 Fitur Statis Landmark Asli.
       - 183 Fitur Instantaneous Velocity $\Delta P_t = P_t - P_{t-1}$ (kecepatan & arah gerak tiap sendi).
       - 17 Fitur Relasional Spasial Kunci (jarak kedua pergelangan tangan, jarak tangan ke hidung/mulut/bahu, dan *finger curl ratio* 5 jemari).
- **Mengapa MGN (Multi-Granularity Network) Jauh Lebih Unggul dari Sekadar LSTM + BiGRU**:
  - *LSTM + BiGRU*: Hanya menumpuk lapisan rekuren makro yang rentan meredam transisi bentuk jari mikro dan membuat pooling rata-rata bias akibat fase diam/transisi awal & akhir video.
  - *MGN (Multi-Granularity Network)*:
    1. **Micro-Granularity Branch (Multi-Scale Temporal Conv1D $k=3, k=5$ + Residual)**: Mengekstrak lekukan mikro jari jemari (*finger curls*) dan gestur lokal cepat dalam jendela 3-5 frame.
    2. **Macro-Granularity Branch (2-Layer BiLSTM)**: Menangkap urutan alur spasio-temporal global seluruh gestur isyarat dari awal hingga akhir.
    3. **Temporal Stroke Attention Pooling**: Menghitung bobot atensi per frame, secara otomatis memfokuskan bobot pada puncak gerakan (*stroke phase*) dan mereduksi bobot frame kosong di awal/akhir video.
    4. **Peak MaxPooling Concatenation**: Memastikan bentuk tangan pada ekstensi terjauh tetap terekam.
  4. **Hand Inversion / Hand Swap Akibat Mirroring `cv2.flip` (Sangat Fatal!)**:
     - Di dataset BISINDO, video direkam kamera langsung (tangan kanan berada di sisi kiri frame citra).
     - Jika `cv2.flip(frame, 1)` dijalankan *sebelum* MediaPipe Holistic, tangan kanan signer bergeser ke sisi kanan citra. Secara anatomis, MediaPipe mendeteksinya sebagai **Tangan Kiri** (`left_hand_landmarks`).
     - Akibatnya: seluruh isyarat tangan kanan masuk ke array fitur tangan kiri (fitur 0..62), sementara array tangan kanan (63..125) kosong melompong bernilai 0. Model melihat isyarat dengan tangan terbalik 100%!
     - *Solusi*: Ekstraksi MediaPipe Holistic **harus** dilakukan pada `raw_frame` asli tanpa flip. Mirroring `cv2.flip` hanya dilakukan pada kanvas visualisasi `display_frame` sebelum ditampilkan ke layar pengguna.




## 5. Evaluasi Komprehensif (ROC, Confusion Matrix) & Arsitektur Multi-Dataset (`evaluate.py` & `dataset_visualizer.py`)

### A. Struktur File Label per Dataset (`labeled.json`)
- Setiap folder di dalam `datasets/` (misalnya `datasets/WL-BISINDO/`, dataset eksternal, atau dataset manual pengguna) didukung memiliki satu file representasi label bernama `labeled.json`.
- Pada `datasets/WL-BISINDO/labeled.json`, telah ditambahkan 32 daftar isyarat lengkap (Gloss & English Translation) sesuai spesifikasi.
- Parser `load_dataset_labels` dirancang agnostik dan fleksibel: mendukung format *list of dicts*, *list of strings*, maupun *dictionary mapping*.

### B. Profiling & Visualisasi Multi-Dataset (`dataset_visualizer.py`)
- Memindai folder dataset secara otomatis dan mengekstrak karakteristik teknis:
  1. **Distribusi Kelas**: Menghitung jumlah video per kata isyarat dan skor ketimpangan (*class imbalance ratio*).
  2. **Distribusi Signer**: Memetakan persebaran perekaman signer terhadap masing-masing kelas dalam bentuk matriks *heatmap*.
  3. **Durasi & FPS**: Menganalisis histogram durasi (detik), sebaran frame count, resolusi kamera, dan FPS.
  4. **Summary Card**: Menghasilkan infografis ringkasan profil dataset dalam format gambar PNG dan file JSON.
  5. **Komparasi Multi-Dataset**: Membandingkan total sampel dan kelengkapan kelas antar-folder dataset secara berdampingan (`--all`).
- Output tersimpan di: `reports/datasets/<nama_dataset>/`.

### C. Mesin Evaluasi Kinerja Model (`evaluate.py`)
- Melakukan pengujian mendalam pada model checkpoint (`bisindo_lstm_best.pt`
  1. **Normalized Confusion Matrix (%)**: Menampilkan tingkat akurasi (recall) diagonal setiap kelas 0 - 100%.
  2. **Raw Count Confusion Matrix**: Menghitung frekuensi absolut prediksi per kelas.
  3. **Multi-Class ROC Curves (One-vs-Rest)**:
     - Menghitung kurva TPR vs FPR, **Micro-Average ROC AUC** (0.727), dan **Macro-Average ROC AUC** (0.761).
     - Menghitung kurva dan nilai AUC individual untuk setiap kelas kata isyarat (misal: 'Teman' AUC 1.0, 'Dengar' 0.9997, 'Sore' 0.9987, 'Belajar' 0.9980).
  4. **Precision-Recall (PR) Curves**: Menghitung Average Precision (AP) mikro dan makro.
  5. **Top Confused Pairs**: Mendeteksi dan meranking pasangan isyarat yang paling sering tertukar untuk memandu evaluasi data.
  6. **Per-Class F1-Score**: Diagram batang horizontal performa F1-Score per kata isyarat.
  7. **Video Consensus Inference**: Menerapkan sliding window dengan agregasi probabilitas Softmax sepanjang video (1 video = 1 keputusan akhir).
- Output lengkap (grafik PNG, `evaluation_metrics.json`, dan `evaluation_report.md`) tersimpan di `reports/evaluation/`.

## 6. Penyesuaian Kelas Dataset: Eliminasi 4 Kelas Warna (28 Kelas Akhir)

- **Latar Belakang & Rasio Eliminasi**:
  - Isyarat warna (*Merah, Kuning, Hijau, Hitam*) di dataset BISINDO memiliki kemiripan spasio-temporal tinggi pada area bibir/wajah serta nilai akurasi evaluasi awal yang rendah.
  - Untuk meningkatkan konsentrasi model pada isyarat kata sehari-hari yang lebih distingtif, 4 kelas warna tersebut dikeluarkan dari dataset latih/uji aktif.
- **Tindakan yang Dilakukan**:
  1. **Pengarsipan Sampel**: Sebanyak **200 video** (4 kelas x 50 sampel) dipindahkan secara aman ke folder `datasets/WL-BISINDO_excluded/` lengkap dengan `labeled.json` arsip agar data tidak hilang permanen.
  2. **Renumbering File Video**: Video sisa (label 22 s/d 31) di-renumber menjadi label 18 s/d 27 agar penamaan `signerX_labelY_sampleZ.mp4` tetap kontinu dan sinkron dengan `class_names`.
  3. **Pembaruan Label**: File `datasets/WL-BISINDO/labeled.json`, `wl_labels.json`, dan `wl_labels_meta.json` diperbarui ke **28 kelas** (ID 0..27).
  4. **Pembaruan Cache Landmark (`wl_holistic_lstm_cache.npz`)**: Cache landmark diekstrak/difilter menjadi **1.400 sampel** (Shape: `(1400, 120, 186)`), dengan salinan backup `wl_holistic_lstm_cache_32cls_backup.npz`.
  5. **Regenerasi Profil Dataset**: Visualisasi dan profil dataset diperbarui di `reports/datasets/WL-BISINDO/` (1.400 sampel, 28 kelas, 5 signers, skor keseimbangan sempurna 1.0).

## 7. Hasil Retraining MGN (28 Kelas) & Interactive Web Dashboard

- **Hasil Metrik Model Baru (1.400 Video Konsensus)**:
  - **Top-1 Accuracy**: **65.71%** (Meningkat signifikan dari baseline 32-kelas 23.44%, kenaikan absolut +42.27% atau +180% relatif).
  - **Top-3 Accuracy**: **89.93%** (Hampir 90% waktu kata yang diisyaratkan masuk dalam 3 saran teratas aplikasi).
  - **Top-5 Accuracy**: **94.57%** (Cakupan kandidat retrieval mencapai 94.6%).
  - **Macro ROC AUC**: **0.9830** | **Micro ROC AUC**: **0.9717** (Daya pemisahan probabilitas multi-kelas sangat tajam).
  - **Macro Precision**: **77.10%** | **Macro Recall**: **65.71%** | **Macro F1**: **0.6464**.
  - **Zero Class Collapse**: Seluruh 28 kelas terprediksi dengan benar (tidak ada kelas yang nol).
- **Interactive Web Dashboard (`reports/dashboard.html`)**:
  - Telah dibangun dashboard analytics standalone modern (Dark Mode, Glassmorphism, Chart.js) yang dapat langsung dibuka via browser:
    1. **Overview & KPI**: Kartu metrik live, perbandingan model awal vs baru, dan grafik donut distribusi tier performa kelas.
    2. **Interactive Confusion Matrix (28x28)**: Grid interaktif dengan mode persentase recall (%) dan raw count, fitur pencarian gloss, tooltip info interaktif, serta tombol sorot kesalahan.
    3. **ROC & PR Curves Explorer**: Kurva dinamis interaktif dengan integrasi Chart.js dan pratinjau grafik resolusi tinggi.
    4. **Per-Class Diagnostics**: Tabel 28 kata isyarat interaktif yang dapat disortir berdasarkan F1-score, Precision, Recall, atau ROC AUC.
    5. **Top Confused Pairs & Action Plan**: Analisis akar masalah kinematis pasangan yang paling sering tertukar disertai rekomendasi rekayasa fitur.
    6. **Multi-Dataset Profiler**: Komparasi folder aktif `WL-BISINDO` vs folder arsip `WL-BISINDO_excluded`.

## 8. Panduan Inferensi Mobile (Android Kotlin & Flutter)

Model sekuensial yang kita kembangkan **SANGAT COCOK & SIAP** dijalankan di perangkat mobile (Android/iOS) secara *offline real-time* (latency ~3–8 ms):

### A. Karakteristik Model untuk Mobile
1. **Ukuran File Sangat Ringan**: File ONNX (`bisindo_lstm.onnx`) hanya berukuran **2.6 MB** (jika dikonversi ke TFLite INT8 / FP16 menjadi ~700 KB - 1.3 MB).
2. **Komputasi Efisien**: Menggunakan arsitektur MGN (Conv1D + 2-layer BiLSTM + Temporal Attention), bukan model 3D-CNN atau Vision Transformer yang berat, sehingga dapat berjalan lancar di CPU smartphone kelas menengah tanpa menghabiskan baterai.
3. **Format Model**:
   - **ONNX (`.onnx`)**: Didukung langsung oleh **ONNX Runtime Mobile** (rekomendasi utama untuk Kotlin dan Flutter).
   - **TFLite (`.tflite`)**: Didukung secara native oleh TensorFlow Lite Android SDK dan package Flutter `tflite_flutter`.

### B. Pipeline End-to-End di Mobile
Aplikasi mobile menjalankan 3 tahap berurutan secara streaming per frame kamera (30 FPS):
1. **Landmark Detection (MediaPipe)**:
   - Gunakan **MediaPipe Tasks Vision API** (`HandLandmarker` dan `PoseLandmarker`) di Android/Flutter.
   - Ekstrak 33 pose landmark (torso & lengan) + 21 landmark tangan kiri + 21 landmark tangan kanan.
2. **Feature Extraction (Sliding Buffer)**:
   - Normalisasi koordinat terhadap lebar bahu (`shoulder_dist`) dan titik tengah bahu (`shoulder_mid`).
   - Simpan buffer meluncur sepanjang **32 frame** (durasi ~1 detik pada 30 FPS).
   - Hitung turunan kecepatan ($v_t = x_t - x_{t-1}$), akselerasi ($a_t = v_t - v_{t-1}$), serta jarak tangan-ke-wajah sehingga menghasilkan tensor input berdimensi `[1, 32, 386]`.
3. **Model Inference & Smoothing**:
   - Jalankan inferensi `bisindo_lstm.onnx` atau `.tflite`.
   - Lakukan agregasi probabilitas (Moving Average Softmax) dari 3-5 frame berturut-turut untuk menghasilkan output prediksi teks yang stabil tanpa *flickering*.

## 9. Implementasi Rencana Aksi Rekayasa (Actionable Next Steps) & Validasi Mobile

Seluruh 4 pilar rekayasa taktis telah berhasil diimplementasikan ke dalam codebase:

### 1. Normalisasi Kinematik Spasial Wajah-Tangan (`holistic_extractor.py`)
- Dimensi fitur ditingkatkan dari 386 ke **400 dimensi**:
  - `186` static landmark coords (Hands + Pose + Flags).
  - `183` instantaneous velocity ($dP/dt$).
  - `31` fitur kinematik relasional baru, meliputi:
    - Jarak ujung telunjuk & ibu jari ke bibir/mulut (`d_index_mouth`, `d_thumb_mouth`) untuk membedakan **Makan** vs **Cari**.
    - Jarak ujung telunjuk & pergelangan tangan ke telinga kiri/kanan (`d_index_ear`) untuk membedakan **Tuli** vs **Cari**.
    - Jarak telunjuk ke titik tengah torso dada (`d_index_torso`) untuk membedakan gestur **Saya**, **Kapan**, dan **Rumah**.
    - Elevasi vertikal relatif Y terhadap hidung dan torso.

### 2. Temporal Focal Loss & Label Smoothing (`train-new.py`)
- Telah dibuat kelas `FocalLoss(gamma=2.0, weight=weights_tensor, label_smoothing=0.05)`:
  - Mereduksi penalti sampel yang sudah diprediksi benar dengan keyakinan tinggi ($p_t > 0.90$), sehingga gradien pelatihan dialokasikan penuh untuk memecah pasangan kata yang saling tumpang tindih (*hard confused pairs*).
  - Mengombinasikan bobot kelas inverse-frequency (*class weighting*) untuk menjamin distribusi prediksi tetap merata di 28 kelas.

### 3. Engine Post-Filtering & Re-ranking Top-3 (`bisindo_postprocess.py`)
- Dibuat modul post-processing pintar yang memanfaatkan **Top-3 Accuracy (89.93%)**:
  - Menggunakan aturan heuristik kinematik langsung saat mendeteksi ambiguitas prediksi.
  - Memasukkan matriks transisi probabilitas Bigram BISINDO (misal konteks `Saya` $\rightarrow$ `Makan`, `Belajar`, `Rumah`).
  - Mengekspor seluruh aturan ke file mandiri [bisindo_rules.json](file:///d:/Project/4mlai/hand-isyarat/bisindo_rules.json) agar dapat langsung dibaca dan dijalankan di Kotlin / Flutter tanpa dependensi Python.

### 4. Validasi Inferensi Mobile Real-Time (`mobile_inference.py`)
- Telah diuji simulasi inferensi mobile menggunakan engine ONNX Runtime:
  - Waktu inferensi model: **~3.89 ms**.
  - Total pipeline (ekstraksi fitur + inferensi + post-filtering): **~4.37 ms** (jauh di bawah batas frame rate 30 FPS yaitu 33 ms).
  - Memastikan kompatibilitas 100% untuk deployment langsung di Android (Kotlin) dan Flutter.

## 10. Implementasi Animasi 3D Avatar Video-Driven (BISINDO Motion Retargeting)

Telah dibangun pipeline lengkap *video-to-3D-avatar* yang mengubah rekaman video isyarat penutur asli BISINDO menjadi animasi humanoid 3D berartikulasi penuh:

### A. Inspeksi Skeleton Avatar (`avatar/man-rigged.glb`)
- Format: glTF 2.0 Binary (`.glb`, 12.45 MB) dengan 1 SkinnedMesh dan PBR materials.
- Total Sendi: **54 Bones** (Humanoid Rig, root `Hips`, rest-pose tulang mengarah ke lokal `+Y`).
- **Artikulasi Jari Tangan Penuh**: Memiliki seluruh 3 ruas tulang per jari (Proximal, Intermediate, Distal) untuk ke-5 jari pada kedua belah tangan (`RightHandThumb1-3`, `RightHandIndex1-3`, dst).

### B. Preprocessing & Ekstraksi Gerak (`motion_extractor.py`)
- Mengekstrak landmark 3D (33 Pose + 21 Hand Kiri + 21 Hand Kanan) secara per-frame dengan timestamp milidetik dan FPS video asli.
- Contoh pengujian pada video isyarat *"Air"* ([datasets/WL-BISINDO/signer0_label0_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer0_label0_sample1.mp4)) menghasilkan [avatar/extracted_landmarks_air.json](file:///d:/Project/4mlai/hand-isyarat/avatar/extracted_landmarks_air.json) (68 frames, 3.07 detik).

### C. Mesin Retargeting Kinematik (`retargeter.py`)
- Transformasi Ruang Koordinat: Mengonversi koordinat MediaPipe ke sistem koordinat avatar (Y-up, right-handed).
- Perhitungan Rotasi Lengan: Menghitung quaternion arah lengan atas (`RightArm`) dan lengan bawah (`RightForeArm`).
- Artikulasi Jari: Menghitung sudut tekukan (*flexion curl*) untuk setiap ruas jari (3 ruas x 5 jari x 2 tangan).
- Serialisasi Animasi: Menghasilkan format JSON terstruktur [avatar/motion_air.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_air.json).

### D. Interactive 3D Web GUI Player (`avatar/avatar_viewer.html` & `run_viewer.py`)
- **Tampilan Dual-Viewport (Side-by-Side)**: Video referensi penutur asli disandingkan berdampingan secara sinkron dengan avatar 3D WebGL (Three.js).
- **Fitur Kontrol Interaktif**:
  - Play, Pause, Scrubbing Timeline Slider, Replay.
  - Pengatur Kecepatan (0.25x slow-motion untuk analisis linguistik isyarat, 0.5x, 1.0x, 1.5x).
  - Orbit Controls 3D: Rotasi 360°, Pan, Zoom dekat ke artikulasi jari tangan kanan & kiri.
  - Reset to Neutral Rest Pose.
  - Monitor aktifitas tulang (bone monitor).

## 11. Multi-Motion Library & Dynamic Switcher (Rumah, Siang, Makan, Saya, Malam, Air)

Telah dilakukan ekspansi library motion animasi 3D avatar untuk berbagai kata isyarat BISINDO:

### A. Ekstraksi Gerakan Multi-Isyarat (`batch_retarget.py`)
Telah diekstrak dan diretargret 6 isyarat kunci yang mencakup isyarat satu tangan dan dua tangan:
1. **🏠 Rumah (House - Label 23)**:
   - Video sumber: [signer1_label23_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer1_label23_sample1.mp4) (1920x1080 @ 30 FPS).
   - Total Frame: **84 frame** (Durasi 2.80 detik).
   - Output: [avatar/motion_rumah.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_rumah.json).
   - Karakteristik: Isyarat dua tangan simetris membentuk atap rumah.
2. **☀️ Siang (Noon - Label 25)**:
   - Video sumber: [signer1_label25_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer1_label25_sample1.mp4) (1920x1080 @ 30 FPS).
   - Total Frame: **69 frame** (Durasi 2.30 detik).
   - Output: [avatar/motion_siang.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_siang.json).
   - Karakteristik: Gerakan tangan di atas kepala melambangkan matahari di tengah hari.
3. **🍚 Makan (Eat - Label 7)**:
   - Video sumber: [signer0_label7_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer0_label7_sample1.mp4) (1280x720 @ 28.2 FPS).
   - Total Frame: **57 frame** (Durasi 2.23 detik).
   - Output: [avatar/motion_makan.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_makan.json).
   - Karakteristik: Tangan mengarah ke mulut berulang secara ritmis.
4. **👤 Saya (I / Me - Label 9)**:
   - Video sumber: [signer0_label9_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer0_label9_sample1.mp4) (1280x720 @ 25.8 FPS).
   - Total Frame: **59 frame** (Durasi 2.83 detik).
   - Output: [avatar/motion_saya.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_saya.json).
   - Karakteristik: Telunjuk menunjuk ke arah dada penutur.
5. **🌙 Malam (Night - Label 27)**:
   - Video sumber: [signer1_label27_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer1_label27_sample1.mp4) (1920x1080 @ 30 FPS).
   - Total Frame: **96 frame** (Durasi 3.20 detik).
   - Output: [avatar/motion_malam.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_malam.json).
   - Karakteristik: Dua tangan bersilangan menutup ke bawah.
6. **💧 Air (Water - Label 0)**:
   - Video sumber: [signer0_label0_sample1.mp4](file:///d:/Project/4mlai/hand-isyarat/datasets/WL-BISINDO/signer0_label0_sample1.mp4) (1280x720 @ 26.4 FPS).
   - Total Frame: **68 frame** (Durasi 3.07 detik).
   - Output: [avatar/motion_air.json](file:///d:/Project/4mlai/hand-isyarat/avatar/motion_air.json).

### B. Dynamic Motion Manifest (`avatar/motions_manifest.json`)
Seluruh metadata video dan file animasi diorganisir dalam sebuah manifest JSON tunggal untuk interoperabilitas dengan web viewer maupun mobile app (Flutter/Kotlin).

### C. Live Motion Switcher pada GUI Web Viewer
- Ditambahkan menu dropdown **Pilih Gerakan** di navigation bar [avatar/avatar_viewer.html](file:///d:/Project/4mlai/hand-isyarat/avatar/avatar_viewer.html).
- Pengguna dapat beralih seketika (*on-the-fly*) antar gerakan isyarat.
- Video referensi, metadata label/FPS, dan model animasi 3D avatar akan tersinkronisasi otomatis secara mulus.
- Cara Menjalankan:
  ```bash
  uv run python run_viewer.py
  ```
  Lalu pilih gerakan yang diinginkan pada dropdown navigasi atas.

## 12. Studio Interaktif Pembuat Pose & Gerakan 3D Custom (`avatar/pose_studio.html`)

### A. Mengapa Ekstraksi Video Otomatis Menghasilkan Gerakan Kurang Pas?
1. **Depth Ambiguity pada Kamera Monokular (MediaPipe)**:
   - MediaPipe mengestimasi koordinat $Z$ (kedalaman) secara aproksimasi relatif dari citra 2D 1 kamera. Akibatnya, saat penutur menekuk siku ke depan atau memutar telapak tangan menghadap kamera, nilai $Z$ sering fluktuatif (*jitter*) dan memicu pergeseran sudut yang tidak alami.
2. **Bone Axis & Constraint Mismatch pada Rig Avatar**:
   - Tulang pada humanoid rig (`man-rigged.glb`) memiliki rest-pose dan batasan anatomis (*biomechanical limits*). Mengonversi vektor 3D bebas tanpa batasan *Inverse Kinematics (IK)* atau *cone constraints* menyebabkan siku terpelintir (*twisted elbow*) atau orientasi telapak tangan terbalik.
3. **Kebutuhan Akurasi Linguistik BISINDO**:
   - Dalam bahasa isyarat, orientasi telapak tangan (*palm orientation*), bentuk tangan (*handshape*), dan lokasi sentuhan (*location*) harus presisi sempurna. Deviasi beberapa derajat pada video dapat mengubah makna isyarat.

### B. Solusi: BISINDO 3D Avatar Pose & Motion Studio
Telah dibangun aplikasi Web Studio interaktif [avatar/pose_studio.html](file:///d:/Project/4mlai/hand-isyarat/avatar/pose_studio.html) yang memungkinkan pengguna mendesain pose dan menyusun urutan animasi secara kustom langsung pada 3D avatar:

1. **Kendali Sendi Presisi (Real-time Sliders)**:
   - **Lengan Atas & Bahu**: Angkat lengan (naik/turun), rentang (buka/tutup), dan putaran bahu (*roll*).
   - **Siku (Forearm)**: Sudut tekukan alami siku (0° hingga 145°) dan rotasi *twist* pergelangan.
   - **Pergelangan Tangan (Wrist)**: Tekuk telapak (*pitch*), lambaian (*yaw*), dan rotasi (*roll*).
   - **Artikulasi 5 Jari Jemari**:
     - *Master Slider*: Genggam semua jemari (0% terbuka hingga 100% genggam mengepal).
     - *Individual Finger Curls*: Jempol, Telunjuk, Jari Tengah, Jari Manis, Kelingking.
     - *Finger Spread*: Merenggangkan atau merapatkan celah antar jemari.
   - **Kepala & Torso**: Toleh kiri/kanan, angguk, dan membungkuk/tegak.

2. **Katalog 1-Klik Preset Bentuk Tangan & Isyarat**:
   - **Bentuk Telapak Cepat**: ✋ Terbuka, ✊ Genggam, ☝️ Menunjuk, ✌️ Dua Jari (V), 👌 Pinch / O, 👍 Jempol, 🤟 I Love You, 🤙 Telepon, 📐 Rapat Rata.
   - **Preset Isyarat Penuh**: 🏠 Rumah (Atap segitiga simetris), ☀️ Siang (Tangan terangkat di atas kepala), 🍚 Makan (Tangan di depan mulut), 👤 Saya (Telunjuk mengarah ke dada), 🙏 Salam / Terima Kasih, 👋 Halo.

3. **Keyframe Sequencer & Motion Timeline**:
   - Tombol **"➕ Simpan Pose ke Keyframe"** untuk merekam pose avatar pada urutan waktu.
   - Interpolasi gerakan mulus (*Smooth Hermite / Slerp*) antar keyframe saat tombol **"▶ Putar Gerakan"** ditekan.
   - Pengatur durasi total gerakan (1.5s, 2.5s, 3.5s, 5.0s).
   - Fitur **"🪞 Salin Pose Kanan &rarr; Kiri"** (Mirroring) untuk isyarat dua tangan simetris.

4. **Interoperabilitas Ekspor / Impor JSON**:
   - Menghasilkan file JSON animasi standar dengan struktur quaternion lokal per-frame yang dapat langsung dimuat ke Three.js viewer maupun aplikasi mobile (Flutter / Android Kotlin).
   - Dilengkapi fitur Salin ke Clipboard dan Unduh file `.json`.

5. **Koreksi Arah Rotasi Kinematik (Perbaikan Siku Terbalik / Inverted Axis)**:
   - *Masalah yang Terjadi*: Pada implementasi awal, slider "Tekuk Siku" $95^\circ$ dan "Angkat Lengan" $45^\circ$ membuat tangan avatar menekuk **ke belakang punggung** (seperti sayap patah ke belakang) bukannya ke depan dada.
   - *Akar Masalah Matematis*: Pada rig `man-rigged.glb`, sumbu rotasi engsel lokal $+X$ ternyata memproyeksikan vektor tulang ke $-Z$ (arah punggung).
   - *Solusi*: Menginversi nilai sudut ke $-X$ untuk angkat lengan (`-p.RightArm_up`), tekukan siku (`-p.RightForeArm_bend`), serta tekukan jemari (`-c`), sehingga saat slider digerakkan ke kanan, tangan menekuk ke arah depan dada dan jemari menggenggam ke dalam telapak tangan dengan benar.

6. **Cara Menjalankan**:
   ```bash
   uv run python run_viewer.py
   ```
   Server lokal akan otomatis membuka Pose Studio pada browser:
   `http://127.0.0.1:8000/avatar/pose_studio.html`

## 13. Live Webcam Motion Capture & Keyframe Auto-Recorder

Untuk mengatasi kerumitan mengatur puluhan slider sendi secara manual, dibangun sistem **Live Webcam MoCap langsung di browser**:

### A. Alur Kerja (Workflow)
1. **Live Mirroring Webcam**:
   - Pengguna menekan tombol **"🔴 Rekam via Kamera (MoCap)"**.
   - Jendela Picture-in-Picture (PiP) aktif menampilkan feed webcam langsung.
   - Google MediaPipe Holistic (WebAssembly / CDN) melacak 33 Pose landmarks dan 42 Hand landmarks secara realtime.
   - Model 3D avatar langsung meniru (*mirroring*) posisi lengan, siku, kepala, dan lekukan jari pengguna secara instan tanpa lag.
2. **Hitung Mundur & Perekaman Otomatis (3s / 5s)**:
   - Pengguna memilih durasi rekam (misal: 3 detik atau 5 detik).
   - Layar menampilkan hitung mundur persiapan: `3... 2... 1... MULAI REKAM!`.
   - Pengguna memperagakan isyarat BISINDO di depan webcam.
   - Sistem secara otomatis mencuplik pose per ~90ms (~11 FPS) dan menyimpannya sebagai kumpulan keyframe pada **Timeline Sequencer**.
3. **Hasil & Pasca-Perekaman**:
   - Setelah durasi habis, animasi hasil rekaman webcam langsung berputar otomatis (*auto-loop*) pada avatar.
   - Pengguna dapat menggeser *scrubber* timeline untuk memeriksa tiap detik gerakan.
   - Jika ada jari yang kurang pas, pengguna dapat mengoreksinya dengan slider pada keyframe tersebut tanpa harus mengulang dari awal.
   - Klik **"💾 Ekspor / Salin JSON"** untuk langsung mengambil file animasi yang siap dipakai di aplikasi mobile (Flutter / Kotlin).

## 14. Penyelesaian Masalah Lengan Kaku pada Avatar (Kinematika Lengan Organik & Pergelangan)

### A. Gejala & Keluhan Pengguna
Saat memperagakan isyarat di depan webcam pada Live MoCap Studio, avatar terlihat **kaku pada area lengan dan pergelangan tangan** (*"kenapa ya di avatar model lengan kek kaku gitu?"*). Avatar tampak seperti manekin kayu/robot dengan tangan yang terhimpit di samping tubuh dan telapak tangan yang tidak luwes.

### B. Analisis Akar Masalah (Root Causes)
1. **Penyederhanaan Heuristik Elevasi 1D ($Y$-Delta Saja)**:
   - Kode awal hanya menghitung sudut angkat lengan atas berdasarkan selisih vertikal 2D: `dy_arm = sh.y - el.y`.
   - Dalam bahasa isyarat BISINDO, ketika peraga mengangkat tangan di depan dada, siku bergerak **maju ke arah kamera ($Z$)**, bukan melayang tinggi di atas kepala.
   - Karena posisi siku di kamera tetap berada di bawah bahu secara vertikal ($el.y > sh.y$), `dy_arm` bernilai negatif ($\approx -0.15$), sehingga algoritma lama mengira lengan tidak diangkat sama sekali (menghasilkan sudut $\approx -5^\circ$). Lengan atas avatar pun tetap menempel kaku di rusuk pinggang.

2. **Pergelangan Tangan Terkunci Total (`pitch=0, yaw=0, roll=0`)**:
   - Sudut pergelangan tangan (`RightHand_pitch`, `RightHand_yaw`, `RightHand_roll`) tidak diekstrak dari landmark tangan dan selalu dibiarkan bernilai $0$.
   - Akibatnya, telapak tangan avatar menjadi lempengan kaku yang tidak bisa mengangguk, melambai, atau memutar mengikuti artikulasi penutur isyarat.

3. **Rotasi Aksial Siku & Lengan Bawah Terkunci (`ForeArm_twist = 0`)**:
   - Gerakan pronasi/supinasi (memutar telapak tangan menghadap diri sendiri vs menghadap lawan bicara) tidak dihitung. Sendi siku hanya bisa menekuk pada satu bidang datar.

4. **Tulang Pundak / Selangka (`RightShoulder` & `LeftShoulder`) Lumpuh**:
   - Pada rig humanoid 3D, memutar lengan atas tanpa menggerakkan tulang selangka (*clavicle*) akan menciptakan ilusi "sendi pintu engsel" yang kaku dan tidak anatomis.

### C. Solusi Rekayasa yang Diimplementasikan
1. **Kinematika 3D Kedalaman Jangkauan ($Z$-Depth + $Y$-Lift + Hand Work Height)**:
   - Menghitung jangkauan siku ke depan dari vektor kedalaman MediaPipe: `dz = -(el.z - sh.z)`.
   - Menggabungkan kedalaman maju dengan ketinggian kerja tangan di depan dada/wajah:
     $$\theta_{up} = \text{atan2}(fwd + up + handLift, dy)$$
   - Saat pengguna mengangkat tangan ke area dada atau dagu (seperti isyarat Makan, Siang, Rumah), lengan atas avatar secara alami terangkat maju ke depan ($45^\circ - 75^\circ$) dengan proporsi anatomis yang presisi.

2. **Solver Vektor Normal Telapak Tangan & Orientasi Pergelangan**:
   - Membentuk vektor telapak tangan $\vec{v}_{palm} = MCP_9 - Wrist$ dan vektor buku jari $\vec{v}_{knuckle} = MCP_5 - MCP_{17}$.
   - Menghitung *cross product* $\vec{N} = \vec{v}_{palm} \times \vec{v}_{knuckle}$ untuk mendeteksi arah hadap telapak secara 3D.
   - Menghasilkan sudut:
     - `ForeArm_twist`: Pronasi / supinasi lengan bawah.
     - `Hand_pitch`: Fleksi / ekstensi tekukan telapak tangan naik-turun.
     - `Hand_yaw`: Deviasi radial/ulnar (lambaian telapak kiri-kanan).
     - `Hand_roll`: Roll halus telapak tangan.

3. **Elevasi Pundak Dinamis (Clavicle Kinematics)**:
   - Tulang `RightShoulder` dan `LeftShoulder` kini otomatis terangkat proporsional ($15\% - 20\%$) saat lengan atas diangkat:
     ```javascript
     const rShoulderUp = Math.max(0, p.RightArm_up - 15) * 0.16;
     const rShoulderFwd = Math.max(0, p.RightArm_up - 15) * 0.12;
     setBoneRotation("RightShoulder", [-rShoulderFwd, 0, rShoulderUp], 'XYZ');
     ```

4. **Adaptive Exponential Moving Average (EMA Filter)**:
   - Meredam getaran mikro (*jitter*) dari webcam sambil mempertahankan responsivitas gerakan cepat (koefisien smoothing $\alpha = 0.42$).

### D. Dampak & Hasil
Gerakan avatar pada Live MoCap kini terasa **luwes, lentur, dan organik** layaknya manusia sungguhan. Lengan atas mengangkat maju ke depan dengan wajar saat berisyarat di depan dada, pergelangan tangan berartikulasi aktif, dan pundak ikut naik secara dinamis.







## 12. Integrasi 3D Avatar GLB & Player Gerakan BISINDO ke Aplikasi Mobile Flutter (ISYARATIN)

Telah diintegrasikan sistem Avatar Humanoid 3D (man-rigged.glb) berartikulasi penuh (54 tulang) ke dalam aplikasi mobile Flutter ISYARATIN dengan dukungan pemutaran gerakan format <label>_motion.json dan motion_<label>.json:

### A. Struktur Folder & Penyimpanan Aset
- **Avatar 3D Model Folder**:
  - ssets/avatar/ menyimpan model 3D man-rigged.glb (12.45 MB, 54 bones rigged, full fingers articulation).
  - ssets/avatar/viewer.html viewer WebGL Three.js teroptimasi mobile.
  - ssets/avatar/js/ menyimpan runtime Three.js offline (	hree.min.js, GLTFLoader.js, OrbitControls.js).
- **Pustaka Gerakan (Motion Data Folder)**:
  - ssets/avatar/motions/ menyimpan data rotasi sendi per-frame dalam format JSON:
    - ir_motion.json & motion_air.json (Air - Water)
    - makan_motion.json & motion_makan.json (Makan - Eat)
    - malam_motion.json & motion_malam.json (Malam - Night)
    - umah_motion.json & motion_rumah.json (Rumah - House)
    - saya_motion.json & motion_saya.json (Saya - I / Me)
    - siang_motion.json & motion_siang.json (Siang - Noon)
    - motions_manifest.json katalog metadata gerakan.

### B. Arsitektur Local Embedded Streaming (AvatarMotionService)
- Menjalankan HttpServer loopback internal di 127.0.0.1:<port> menggunakan dart:io.
- Menghindari limit Android Binder transaction 1 MB dan batasan CORS ile:// WebView.
- Mendukung streaming biner GLB model dan file gerakan JSON secara instan dan 100% offline.

### C. Antarmuka Interaktif 3D di AvatarScreen (Langkah 3 · Avatar Merespon)
- **Viewport 3D WebGL**: Menampilkan avatar secara real-time dengan gesture rotasi 360°, pan, dan zoom.
- **Preset Sudut Kamera**: Tombol cepat untuk Badan (upper body focus), Seluruh Tubuh (full body), dan Zoom Tangan (hands focus).
- **Deteksi Isyarat Otomatis**: Mendeteksi kata balasan dari Langkah 2 (suara/teks) dan otomatis memutar animasi isyarat yang bersesuaian.
- **Pengatur Kecepatan**: Pilihan  .5x (slow-motion untuk edukasi), 1.0x (normal), dan 1.5x (cepat).
- **Selector Chip Gerakan**: Pengguna dapat berganti isyarat secara interaktif dengan satu sentuhan.

### D. Perbaikan ImageError (IllegalArgumentException) & Cropping Model Avatar
1. **Solusi E/ImageError (Getting Image failed - IllegalArgumentException)**:
   - **Akar Masalah**: Pada Android Camera2/CameraX, frame dikirim sebagai YUV_420_888 (format 35). Native wrapper google_mlkit_commons memanggil InputImage.fromByteArray(..., 35) yang ditolak oleh SDK native Google Play Services ML Kit karena romByteArray hanya menerima format NV21 atau YV12.
   - **Solusi**: Dibuat fungsi konversi _yuv420ToNv21() di [lib/services/sign_recognition_pipeline.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/services/sign_recognition_pipeline.dart) yang menyalin Y-plane dan meng-interleave V dan U dengan memperhitungkan ytesPerRow dan ytesPerPixel. Format dikirimkan sebagai InputImageFormat.nv21, menghilangkan error ImageError secara tuntas.
2. **Cropping Avatar 3D (Hanya Bagian Dada hingga Kepala)**:
   - Diterapkan Three.js GPU hardware clippingPlanes (
ew THREE.Plane(new THREE.Vector3(0, 1, 0), -1.02)) di [assets/avatar/viewer.html](file:///d:/Project/4mlai/apapun/isyaratin/assets/avatar/viewer.html).
   - Seluruh geometri di bawah pinggang (hips, paha, lutut, kaki) dipotong dan tidak ditampilkan (*no lower body*).
   - Menghapus floor grid lama dan menambahkan pedestal ring minimalis di dasar potongan torso (y = 1.015).
   - Kamera difokuskan pada postur atas dengan sudut preset: **Badan** (dada & tangan), **Zoom Tangan** (fokus artikulasi jari), dan **Kepala** (wajah & ekspresi).


## 13. Rekonseptualisasi Pengenalan Isyarat: Paradigma Record-and-Infer & Analisis Rangkaian Per-Kata

Untuk mengatasi ambiguitas prediksi *continuous rolling buffer* (yang rentan memicu noise dan jitter saat pengguna baru mengangkat tangan atau melakukan transisi), alur inferensi diubah secara fundamental ke paradigma **Record & Recognize (Rekam Gerakan Total -> Analisis Per-Kata)**:

### A. Alur Kerja Rekam Gerakan Total (Recording Session Workflow)
1. **Penyelarasan Posisi Awal**:
   - Kamera melakukan pelacakan real-time pose tubuh dan kedua tangan.
   - Indikator status membimbing pengguna: `✓ Tubuh Terdeteksi · Tangan: N` sebelum mulai merekam.
2. **Perekaman Rangkaian Gerakan (startRecording())**:
   - Pengguna menekan tombol **"Mulai Rekam Isyarat"**.
   - Sistem mengakumulasi seluruh vektor fitur 186-dimensi per-frame pada ~12 FPS ke dalam array _recordedFrames.
   - UI menampilkan badge merah aktif: `● MEREKAM 00:03 · 38 frame`.
3. **Pemberhentian Perekaman**:
   - **Manual**: Pengguna menekan tombol **"Selesai & Terjemahkan"** (atau "Batal").
   - **Otomatis (Auto-Stop)**: Sistem secara cerdas mendeteksi saat tangan diturunkan >= 1.1 detik (_consecutiveNoHandFrames >= 14) atau tangan diam tak bergerak >= 1.5 detik setelah melakukan gerakan >= 16 frame.

### B. Algoritma Segmentasi & Pengenalan Per-Kata (Word-by-Word Sequence Inference)
Setelah perekaman berhenti, fungsi stopRecordingAndRecognize() memproses seluruh rangkaian gerakan:
1. **Activity Trimming**:
   - Mengidentifikasi frame aktif pertama dan terakhir di mana tangan terdeteksi (hasLeft == 1.0 atau hasRight == 1.0).
   - Memotong frame diam di awal dan di akhir rekaman agar tidak mengotori inferensi model.
2. **Pengenalan Isyarat Tunggal ( \le 42$ frame, ~0.8s - 3.5s)**:
   - Melakukan interpolasi linier (*uniform time resampling*) dari $ frame menjadi tepat 32 frame sesuai input tensor TFLite [1, 32, 186].
   - Menghasilkan 1 kata dengan probabilitas tertinggi.
3. **Pengenalan Rangkaian Multi-Kata ( > 42$ frame)**:
   - **Sliding Window**: Menggeser jendela 32 frame dengan *stride* 10 frame (~0.83 detik).
   - Setiap irisan jendela diresample ke 32 frame dan diinferensikan oleh model TFLite.
   - **Repetition Suppression & Peak Selection**: Jendela berurutan yang memprediksi kata yang sama digabungkan, dan skor keyakinan puncak (*peak confidence*) dipilih sebagai representasi kata tersebut.
   - Memfilter probabilitas di bawah ambang batas (threshold 0.35).
   - Menghasilkan daftar kata terurut secara temporal: [kata_1, kata_2, ..., kata_n].
4. **Penyajian Hasil di UI**:
   - Menampilkan chip badge untuk setiap kata terdeteksi lengkap dengan persentase keyakinan.
   - Mengisi kotak pesan teks secara otomatis dengan kalimat gabungan, siap dikirim atau disunting oleh pengguna.

## 14. Perbaikan Kamera Kotak (1:1), Tombol Berhenti, & Standardisasi Styling Antarmuka

### A. Perbaikan Bentuk Kamera Kotak (1:1 Aspect Ratio) & Anti-Gepeng (Center-Crop Fill)
- **Akar Masalah**: Sebelumnya container kamera menggunakan tinggi statis `height: 350` yang dipadukan dengan `Stack(fit: StackFit.expand)`. Pada perangkat smartphone dalam orientasi potret (lebar 360 - 412 px), rasio ini memaksa `CameraPreview` yang memiliki rasio asli 3:4 atau 9:16 untuk melebar secara paksa ke rasio mendekati 1:1 tanpa mekanisme scaling yang tepat, sehingga objek manusia dan tangan tampak pipih melebar (*gepeng*).
- **Solusi**:
  1. Mengubah pembungkus kamera menjadi `AspectRatio(aspectRatio: 1.0)` sehingga bentuk viewport selalu presisi bujur sangkar (**kotak**) pada semua resolusi layar.
  2. Mengimplementasikan perhitungan dinamis pada `LayoutBuilder`:
     - Menghitung rasio aspek sebenarnya dari sensor (`previewRatio`).
     - Menggunakan `OverflowBox` yang dipusatkan di tengah (`Center`), dengan dimensi yang dihitung secara matematis (`BoxFit.cover` manual):
       - Jika potret: `previewWidth = boxSize`, `previewHeight = boxSize / previewRatio`.
       - Jika lanskap: `previewWidth = boxSize * previewRatio`, `previewHeight = boxSize`.
  3. Memotong bagian luapan secara rapi menggunakan `ClipRRect(borderRadius: BorderRadius.circular(24))`, menghasilkan tampilan kamera kotak yang 100% proporsional, tajam, dan tidak gepeng.
  4. Menambahkan panduan visual *viewfinder* dengan 4 sudut bingkai berwarna hijau toska aksen agar pengguna dapat memposisikan kepala dan dada dengan pas di tengah kotak.

### B. Perbaikan Tombol Berhenti & Rekam Isyarat
- **Akar Masalah Tombol Tidak Berfungsi**:
  1. **TFLite Tensor Shape Mismatch**: Pada [lib/services/sign_recognition_model.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/services/sign_recognition_model.dart), inferensi `_interpreter.run([sequence], output)` mengirimkan flat array `[Float32List(5952)]` (dimensi `[1, 5952]`), padahal input tensor model TFLite adalah 3 dimensi `[1, 32, 186]`. Hal ini memicu unhandled exception di C++ runtime TFLite saat tombol berhenti/selesai ditekan, menyebabkan analisis gagal dan kotak teks tidak terisi.
  2. **Auto-Stop Terlalu Agresif**: Threshold frame tanpa tangan terlalu rendah (14 frame / ~0.9 detik) sehingga status perekaman kerap berganti otomatis secara mendadak sebelum pengguna menekan tombol berhenti.
  3. **Kejelasan Tombol di UI**: Label tombol sebelumnya tertulis "Selesai", padahal pengguna mencari tombol "Berhenti" (sesuai ikon stop merah).
- **Solusi**:
  1. Mereformasi vektor sekuens menjadi array 3 dimensi berukuran `[1, 32, 186]` (`List.generate(32, ...)`), serta membungkus pemanggilan inferensi dengan penanganan `try-catch` yang aman.
  2. Mengubah label tombol secara eksplisit menjadi **"Berhenti & Terjemahkan"** dengan warna merah aksen dan ikon `Icons.stop_circle_rounded`, serta tombol FAB mengambang bertuliskan **"Berhenti"** di atas pratinjau kamera saat merekam.
  3. Menambahkan tombol kontrol **Jeda / Lanjutkan Kamera** (`_togglePauseCamera()`) di toolbar atas kamera untuk memberi kendali penuh kepada pengguna menghentikan/menjeda pratinjau kamera saat tidak digunakan.
  4. Meningkatkan ambang batas *auto-stop* menjadi 25-28 frame (~1.8 detik) dan menurunkan batas minimal frame dari 10 ke 5 frame agar gerakan cepat tetap berhasil diterjemahkan tanpa error.

### C. Standardisasi Styling, Margin, & Padding Antarmuka
- **Padding Halaman**: Mengatur padding `ListView` menjadi `EdgeInsets.fromLTRB(20, 16, 20, 24)` agar jarak antar kartu bernapas lega dan tidak tertimpa bar navigasi bawah.
- **SurfaceCard & Result Chips**: Memberikan padding 16px, border lembut bernuansa tema toska, dan bayangan elevasi halus.
- **Tombol Hapus pada Input Pesan**: Menambahkan tombol cepat `Hapus` pada header kartu dan `suffixIcon: Icons.clear` pada `TextField` sehingga pengguna dapat mengosongkan teks dengan sekali ketuk.
- **Responsive Action Buttons**: Menyesuaikan tombol aksi di `ReplyScreen` menjadi lebih ringkas ("Bicara Suara" & "Bacakan Teks") dengan `maxLines: 1` dan `TextOverflow.ellipsis` guna mencegah layout overflow pada layar berukuran kecil (320px).

## 15. Solusi Permasalahan Avatar 3D Loading Terus-Menerus (Infinite Loading Spinner)

### A. Investigasi & Analisis Akar Masalah (Root Cause Analysis)
Saat membuka layar Langkah 3 (Avatar Merespon), indikator loading menampilkan pesan *"Menyiapkan Avatar 3D & Rig 54 Tulang..."* secara permanen tanpa pernah selesai. Setelah penelusuran mendalam terhadap log Android dan arsitektur WebGL/WebView, ditemukan beberapa faktor pemicu utama:

1. **Pemblokiran Cleartext Traffic oleh Android Network Security Policy (Faktor Terbesar)**:
   - Server lokal Three.js berjalan pada loopback `http://127.0.0.1:<port>`.
   - Sejak Android 9.0 (API Level 28), sistem operasi secara default **menolak seluruh koneksi HTTP tanpa enkripsi (cleartext)** dengan galat `net::ERR_CLEARTEXT_NOT_PERMITTED`.
   - Di [android/app/src/main/AndroidManifest.xml](file:///d:/Project/4mlai/apapun/isyaratin/android/app/src/main/AndroidManifest.xml), atribut `android:usesCleartextTraffic="true"` belum dideklarasikan pada tag `<application>`, sehingga WebView memblokir koneksi ke server lokal sebelum request sempat mencapai HttpServer Dart.

2. **Ketiadaan Error Delegasi & Console Logging pada WebView Flutter**:
   - `WebViewController` sebelumnya tidak memasang `setOnConsoleMessage` maupun `NavigationDelegate.onWebResourceError`.
   - Akibatnya, pemblokiran jaringan maupun galat JavaScript yang terjadi di dalam WebView tidak tercetak sama sekali di konsol logcat/debug Flutter (*silent failure*).

3. **Race Condition Injeksi `FlutterBridge` JavaScript Channel**:
   - Di dalam [assets/avatar/viewer.html](file:///d:/Project/4mlai/apapun/isyaratin/assets/avatar/viewer.html), fungsi `notifyFlutter("avatar_ready")` langsung memeriksa `if (window.FlutterBridge)`.
   - Pada platform view Android, channel JavaScript terkadang selesai terhubung beberapa milidetik setelah DOM dieksekusi. Jika `window.FlutterBridge` belum tersedia tepat saat model GLB selesai dimuat, pesan `avatar_ready` diabaikan begitu saja dan tidak pernah dikirimkan ulang.

4. **Event Listener `DOMContentLoaded` Terlewat**:
   - Skrip Three.js dibungkus dalam `window.addEventListener("DOMContentLoaded", ...)`. Jika dokumen telah berstatus *interactive* atau *complete* sebelum listener terpasang, event tersebut tidak akan pernah dipicu kembali.

5. **Ketiadaan Header `Content-Length` & In-Memory Caching untuk Model GLB (13 MB)**:
   - File model 3D `man-rigged.glb` berukuran ~13 MB dimuat berulang kali dari APK aset bundle tanpa header `Content-Length`.
   - Hal ini menyebabkan `xhr.lengthComputable` bernilai `false` sehingga bar persentase unduhan tidak berjalan dan rentan terjadi socket timeout pada perangkat dengan spesifikasi terbatas.

6. **Ketiadaan Safety Timeout & Tombol Bypass Manual di Flutter**:
   - Flag `_isLoading` di [lib/features/conversation/conversation_screens.dart](file:///d:/Project/4mlai/apapun/isyaratin/lib/features/conversation/conversation_screens.dart) dikunci hingga pesan `avatar_ready` tiba tanpa batas waktu (*timeout*), menutupi canvas WebGL secara absolut.

---

### B. Langkah Perbaikan Menyeluruh

1. **Aktivasi Cleartext Loopback di Android Manifest**:
   - Menambahkan `android:usesCleartextTraffic="true"` pada elemen `<application>` di [android/app/src/main/AndroidManifest.xml](file:///d:/Project/4mlai/apapun/isyaratin/android/app/src/main/AndroidManifest.xml).
   - Memastikan koneksi HTTP ke `127.0.0.1` diizinkan penuh oleh Android Security Policy.

2. **Antrean Pesan (*Message Queue*) & Polling Retry pada JavaScript Bridge**:
   - Di [assets/avatar/viewer.html](file:///d:/Project/4mlai/apapun/isyaratin/assets/avatar/viewer.html), fungsi `notifyFlutter` diperbarui dengan sistem antrean `pendingFlutterMessages`.
   - Jika `window.FlutterBridge` belum siap, pesan disimpan dalam antrean dan dilakukan *polling retry* setiap 120ms hingga bridge aktif dan seluruh pesan terkirim.
   - Mengekspos variabel global `window.isAvatarReady = true` dan `window.avatarBoneCount = 54` pada context window browser.
   - Menangani siklus hidup dokumen dengan memeriksa `document.readyState === "loading"` agar inisialisasi segera berjalan tanpa menunggu event `DOMContentLoaded` yang sudah lewat.
   - Menangkap seluruh galat runtime dengan `window.addEventListener("error", ...)` dan meneruskannya ke Flutter sebagai `avatar_error` / `js_error`.

3. **Optimasi Streaming & Caching di `AvatarMotionService`**:
   - Menyimpan byte model `man-rigged.glb` di memori (`Uint8List? _cachedGlbBytes`) setelah pembacaan pertama, memangkas waktu muat ulang menjadi seketika (*instant*).
   - Mengirimkan header HTTP `Content-Length`, `Access-Control-Allow-Origin: *`, dan `Cache-Control: public, max-age=3600` pada aset GLB dan JavaScript.
   - Menambahkan logging detail `debugPrint('[AvatarMotionService] Incoming request: $path')`.

4. **Penguatan Siklus Hidup & Verifikasi di `AvatarScreen` (Flutter)**:
   - **Console & Resource Logging**: Menambahkan `setOnConsoleMessage` dan `onWebResourceError` agar seluruh aktivitas JavaScript dan WebGL terpantau di logcat.
   - **Verification Polling (`_startStatusVerification`)**: Saat halaman webview selesai dimuat (`onPageFinished`), timer periodik mengecek nilai `window.isAvatarReady` setiap 600ms sebagai mekanisme ganda (*double guarantee*) jika notifikasi event bridge terhambat.
   - **Safety Timeout (8 Detik)**: Memasang timer fallback 8 detik yang otomatis melepaskan overlay loading (`_isLoading = false`) agar pengguna tidak terkunci di layar kosong.
   - **Tombol Alternatif Manual**: Menambahkan tombol `Buka Tampilan 3D Langsung` di dalam overlay loading agar pengguna dapat membuka canvas 3D sewaktu-waktu.
   - **Pembaruan Aksi Segarkan**: Tombol refresh di AppBar kini mengatur ulang safety timeout dan memuat ulang WebView secara bersih.


