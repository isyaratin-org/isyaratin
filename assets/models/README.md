# Model isyarat (sign recognition)

Letakkan model TensorFlow Lite di folder ini:

- `sign_model.tflite` — model pengenalan isyarat sequence (wajib untuk pengenalan otomatis)
- `labels.txt` — satu label per baris, opsional (jika tidak ada, prediksi memakai indeks)

## Kontrak input/output (sequence landmark)

Model ini mengikuti arsitektur BiLSTM/MGN dari `train-new.py`:

- **Input**: `[1, 32, 186]` float32
  - 32 frame (sequence window ~2.67 detik pada 12 fps)
  - 186 dimensi per frame:
    - Left Hand : 21 landmark x 3 = 63
    - Right Hand : 21 landmark x 3 = 63
    - Pose : 19 landmark x 3 = 57 (11 head + 6 arm + 2 torso)
    - Flags : `[has_left_hand, has_right_hand, has_pose]` = 3
- **Output**: `[1, numLabels]` float32 (logits/softmax)

### Normalisasi (harus sama dengan training)

Body-centric normalization:

- Origin = titik tengah antara bahu kiri dan kanan (`torso_center`)
- Scale = jarak Euclidean antara kedua bahu (`torso_scale`)
- Semua koordinat ditranslasi ke origin dan dibagi scale

### Urutan landmark pose (19)

```
0=nose, 1=eye_inner_l, 2=eye_l, 3=eye_outer_l, 4=eye_inner_r, 5=eye_r,
6=eye_outer_r, 7=ear_l, 8=ear_r, 9=mouth_l, 10=mouth_r,
11=shoulder_l, 12=shoulder_r, 13=elbow_l, 14=elbow_r, 15=wrist_l, 16=wrist_r,
17=hip_l, 18=hip_r
```

## Konversi ONNX → TFLite

Model training menghasilkan `bisindo_lstm.onnx` (input `[1, 32, 186]`). Konversi ke TFLite:

```bash
# Opsi 1: onnx2tf
pip install onnx2tf
onnx2tf -i bisindo_lstm.onnx -o tflite_output

# Opsi 2: ai-edge-torch (rekomendasi untuk LSTM/RNN)
pip install ai-edge-torch
# (lihat dokumentasi ai-edge-torch untuk ekspor PyTorch -> TFLite)
```

Setelah konversi, salin hasilnya:

```bash
cp tflite_output/bisindo_lstm_float32.tflite assets/models/sign_model.tflite
```

## Pipeline di aplikasi

1. Kamera → `hand_landmarker` (MediaPipe, Android) stream 21 landmark tangan
2. Kamera → `google_mlkit_pose_detection` → 19 landmark pose
3. [`LandmarkExtractor`](../lib/services/landmark_extractor.dart) → 186-dim per frame
4. [`SequenceBuffer`](../lib/services/sequence_buffer.dart) → buffer 32 frame
5. [`SignRecognitionModel`](../lib/services/sign_recognition_model.dart) → inferensi

Jika model tidak ada, aplikasi tetap berjalan normal dengan input ketik.
