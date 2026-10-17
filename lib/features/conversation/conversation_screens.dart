import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../services/avatar_motion_service.dart';
import '../../services/sign_recognition_model.dart';
import '../../services/sign_recognition_pipeline.dart';
import '../../services/speech_service.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});
  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  final _text = TextEditingController();
  bool _saving = false;
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  bool _cameraUnavailable = false;
  bool _switchingCamera = false;
  SignRecognitionModel? _model;
  SignRecognitionPipeline? _pipeline;
  final ValueNotifier<LiveSignPrediction?> _livePrediction =
      ValueNotifier<LiveSignPrediction?>(null);
  StreamSubscription<LiveSignPrediction>? _predictionSub;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  RecordedSignResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      final model = await SignRecognitionModel.load();
      if (!mounted) {
        model?.close();
        return;
      }
      setState(() {
        _model = model;
      });
      if (model != null) _startPipeline();
    } catch (e, stack) {
      debugPrint('Error in _initModel: $e\n$stack');
    }
  }

  Future<void> _startPipeline() async {
    final controller = _controller;
    final model = _model;
    if (controller == null ||
        model == null ||
        !controller.value.isInitialized ||
        _pipeline != null) {
      return;
    }
    try {
      debugPrint('Starting SignRecognitionPipeline stream...');
      final pipeline = SignRecognitionPipeline(
        cameraController: controller,
        model: model,
      );
      pipeline.onAutoStop = _onAutoStopDetected;
      _predictionSub = pipeline.predictions.listen((prediction) {
        _livePrediction.value = prediction;
      });
      setState(() => _pipeline = pipeline);
      await controller.startImageStream((image) {
        pipeline.processFrame(image, controller.description.sensorOrientation);
      });
      debugPrint('SignRecognitionPipeline stream running.');
    } catch (e, stack) {
      debugPrint('Pipeline start error: $e\n$stack');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || !mounted) {
        setState(() => _cameraUnavailable = true);
        return;
      }
      _cameras = cameras;
      // Default to front camera if available, otherwise first camera
      int initialIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (initialIndex == -1) initialIndex = 0;
      _selectedCameraIndex = initialIndex;

      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (e, stack) {
      debugPrint('Camera init error: $e\n$stack');
      if (mounted) setState(() => _cameraUnavailable = true);
    }
  }

  Future<void> _setupCameraController(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _switchingCamera = false;
    });
    if (_model != null) {
      _startPipeline();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switchingCamera) {
      if (_cameras.length < 2 && mounted) {
        showNotice(context, 'Hanya ada 1 kamera yang terdeteksi di perangkat.');
      }
      return;
    }
    setState(() => _switchingCamera = true);

    await _predictionSub?.cancel();
    _predictionSub = null;
    _pipeline?.dispose();
    _pipeline = null;

    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}
      await oldController.dispose();
    }

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;

    try {
      await _setupCameraController(_cameras[_selectedCameraIndex]);
      if (mounted) {
        final isFront =
            _cameras[_selectedCameraIndex].lensDirection ==
            CameraLensDirection.front;
        showNotice(
          context,
          isFront ? 'Beralih ke Kamera Depan' : 'Beralih ke Kamera Belakang',
        );
      }
    } catch (e, stack) {
      debugPrint('Error switching camera: $e\n$stack');
      if (mounted) {
        setState(() => _switchingCamera = false);
        showNotice(context, 'Gagal mengganti kamera. Coba lagi.');
      }
    }
  }

  @override
  void dispose() {
    _predictionSub?.cancel();
    _pipeline?.dispose();
    _livePrediction.dispose();
    _text.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .send(_text.text, MessageAuthor.signer);
      if (mounted) {
        _text.clear();
        context.go('/reply');
      }
    } catch (_) {
      if (mounted) showNotice(context, 'Pesan belum tersimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onAutoStopDetected() {
    if (!_isRecording || _isAnalyzing) return;
    if (mounted) {
      showNotice(
        context,
        'Gerakan selesai terdeteksi. Menerjemahkan kata demi kata...',
      );
    }
    _stopAndRecognize();
  }

  void _startRecording() {
    if (_pipeline == null || _model == null) {
      showNotice(context, 'Model isyarat belum siap.');
      return;
    }
    _pipeline?.startRecording();
    setState(() {
      _isRecording = true;
      _lastResult = null;
    });
  }

  void _cancelRecording() {
    _pipeline?.cancelRecording();
    setState(() {
      _isRecording = false;
    });
    showNotice(context, 'Perekaman gerakan dibatalkan.');
  }

  Future<void> _stopAndRecognize() async {
    if (!_isRecording || _isAnalyzing) return;
    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    try {
      final result = await _pipeline?.stopRecordingAndRecognize();
      if (!mounted) return;

      setState(() {
        _isAnalyzing = false;
        _lastResult = result;
      });

      if (result != null) {
        if (result.errorMessage != null) {
          showNotice(context, result.errorMessage!);
        } else if (result.sentence.isNotEmpty) {
          setState(() {
            if (_text.text.trim().isEmpty) {
              _text.text = result.sentence;
            } else {
              _text.text = '${_text.text.trim()} ${result.sentence}';
            }
          });
          showNotice(
            context,
            'Berhasil menerjemahkan ${result.words.length} kata.',
          );
        } else {
          showNotice(
            context,
            'Tidak ada kata yang terdeteksi dengan yakin. Coba ulangi gerakannya.',
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error recognizing recording: $e\n$stack');
      if (mounted) {
        setState(() => _isAnalyzing = false);
        showNotice(context, 'Terjadi kendala analisis isyarat. Coba lagi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const StepHeader('Langkah 1 · Kirim Isyarat'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Terjemahan Isyarat',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Container(
              height: 350,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFE0EBED),
                borderRadius: BorderRadius.circular(24),
              ),
              child: _controller != null && _controller!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        if (_switchingCamera)
                          Container(
                            color: Colors.black45,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (_isAnalyzing)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Menerjemahkan kata demi kata...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: ValueListenableBuilder<LiveSignPrediction?>(
                            valueListenable: _livePrediction,
                            builder: (context, prediction, _) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _isRecording
                                      ? Colors.red.shade700
                                      : Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isRecording) ...[
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'MEREKAM ${(prediction?.recordedDurationSeconds ?? 0.0).toStringAsFixed(1)}s · ${prediction?.recordedFrames ?? 0} frame',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ] else ...[
                                      Icon(
                                        prediction?.hasPose == true
                                            ? Icons.check_circle
                                            : Icons.accessibility_new,
                                        color: prediction?.hasPose == true
                                            ? const Color(0xFF4ADE80)
                                            : Colors.white70,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        prediction?.hasPose == true
                                            ? 'Tubuh Terdeteksi · Tangan: ${prediction?.handCount ?? 0}'
                                            : 'Arahkan kamera ke dada & kepala',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'camera-switch',
                            tooltip: 'Ganti Kamera Depan/Belakang',
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.9,
                            ),
                            foregroundColor: AppColors.primary,
                            onPressed: _switchingCamera || _isRecording
                                ? null
                                : _switchCamera,
                            child: const Icon(Icons.flip_camera_android),
                          ),
                        ),
                        if (_isRecording)
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: FloatingActionButton(
                              heroTag: 'camera-stop',
                              tooltip: 'Selesai & Terjemahkan',
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              onPressed: _isAnalyzing
                                  ? null
                                  : _stopAndRecognize,
                              child: _isAnalyzing
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.stop_rounded, size: 28),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const DesignIcon(
                          '66bd1',
                          size: 40,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _cameraUnavailable
                              ? 'Kamera tidak tersedia'
                              : 'Menyiapkan kamera...',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Kamu bisa memulai percakapan dengan mengetik pesan di bawah.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isRecording) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _stopAndRecognize,
                            icon: const Icon(
                              Icons.stop_circle_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Selesai & Terjemahkan',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _cancelRecording,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Batal'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Peragakan satu atau rangkaian kata isyarat. Tekan Selesai atau turunkan tangan untuk menerjemahkan.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ] else if (_isAnalyzing) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Memproses terjemahan kata demi kata...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed:
                          _model == null ||
                              _controller == null ||
                              !_controller!.value.isInitialized
                          ? null
                          : _startRecording,
                      icon: const Icon(
                        Icons.fiber_manual_record,
                        color: Colors.red,
                        size: 20,
                      ),
                      label: const Text(
                        'Mulai Rekam Isyarat',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF146C74),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rekam gerakan total terlebih dahulu. Setelah berhenti atau menekan selesai, model akan menganalisis gerakan perkata.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            if (_lastResult != null && _lastResult!.words.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F5F7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF146C74).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Hasil Terjemahan (${_lastResult!.words.length} Kata):',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_lastResult!.durationSeconds.toStringAsFixed(1)}s · ${_lastResult!.totalFrames} frame',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final word in _lastResult!.words)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(
                                  0xFF146C74,
                                ).withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  word.word,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${(word.confidence * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      DesignIcon('a20f6', size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Pesan terjemahan / ketik',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _text,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 5000,
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText:
                          'Tulis pesan atau hasil terjemahan akan masuk di sini...',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving || _text.text.trim().isEmpty ? null : _send,
              icon: const DesignIcon('65602', color: Colors.white),
              label: Text(_saving ? 'Menyimpan...' : 'Tampilkan Pesan'),
            ),
          ],
        ),
      ),
    ],
  );
}

class ReplyScreen extends ConsumerStatefulWidget {
  const ReplyScreen({super.key});
  @override
  ConsumerState<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends ConsumerState<ReplyScreen> {
  final _text = TextEditingController();
  final _speech = SpeechService();
  bool _saving = false;
  bool _speaking = false;
  bool _listening = false;

  @override
  void dispose() {
    _text.dispose();
    _speech.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (_speaking) {
      await _speech.stop();
      if (mounted) setState(() => _speaking = false);
    }

    setState(() => _listening = true);

    final success = await _speech.startListening(
      onResult: (words) {
        if (!mounted) return;
        setState(() {
          _text.text = words;
          _text.selection = TextSelection.fromPosition(
            TextPosition(offset: _text.text.length),
          );
        });
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );

    if (!success && mounted) {
      setState(() => _listening = false);
      showNotice(
        context,
        'Pengenalan suara tidak tersedia atau izin mikrofon belum diberikan.',
      );
    }
  }

  Future<void> _toggleSpeech() async {
    if (_speaking) {
      await _speech.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    if (_listening) {
      await _speech.stopListening();
      if (mounted) setState(() => _listening = false);
    }
    final started = await _speech.speak(_text.text);
    if (mounted) setState(() => _speaking = started);
  }

  Future<void> _send() async {
    if (_listening) {
      await _speech.stopListening();
      if (mounted) setState(() => _listening = false);
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .send(_text.text, MessageAuthor.partner);
      if (mounted) {
        _text.clear();
        context.push('/avatar');
      }
    } catch (_) {
      if (mounted) showNotice(context, 'Balasan belum tersimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Column(
      children: [
        const StepHeader('Langkah 2 · Balas Pesan'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Voice Note',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.pale,
                            ),
                            child: const DesignIcon('00290', size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Pesan sebelumnya',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        session.signerText ??
                            'Belum ada pesan. Kamu bisa langsung mengetik balasan.',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      DesignIcon('86761', size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bicara dengan tombol mikrofon atau ketik balasan untuk ditampilkan sebagai teks.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    DesignIcon('8593f', size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Pesan',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 5000,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Ketik atau rekam balasan suara di sini...',
                  ),
                ),
                if (_listening) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Sedang mendengarkan... Silakan bicara.',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _toggleListening,
                          child: const Text(
                            'Selesai',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _saving ? null : _toggleListening,
                        icon: Icon(
                          _listening ? Icons.mic_off : Icons.mic,
                          color: _listening
                              ? Colors.redAccent
                              : AppColors.primary,
                        ),
                        label: Text(
                          _listening
                              ? 'Berhenti Bicara'
                              : 'Bicara (Voice Note)',
                          style: TextStyle(
                            color: _listening ? Colors.redAccent : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: _listening
                            ? FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFDADA),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (!_speaking && _text.text.trim().isEmpty)
                            ? null
                            : _toggleSpeech,
                        icon: Icon(
                          _speaking ? Icons.stop : Icons.volume_up,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        label: Text(_speaking ? 'Hentikan' : 'Bacakan Balasan'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving || _text.text.trim().isEmpty
                      ? null
                      : _send,
                  icon: const DesignIcon('65602', color: Colors.white),
                  label: Text(_saving ? 'Menyimpan...' : 'Kirim Balasan'),
                ),
                const SizedBox(height: 40),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DesignIcon('11a6f', size: 16),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Balasan selalu ditampilkan sebagai teks.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF287A57),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AvatarScreen extends ConsumerStatefulWidget {
  const AvatarScreen({super.key});

  @override
  ConsumerState<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends ConsumerState<AvatarScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _avatarReady = false;
  String _selectedMotionId = 'rumah';
  String _activeGloss = 'Rumah';
  double _currentSpeed = 1.0;
  bool _isPlaying = true;
  String? _detectedGestureName;

  @override
  void initState() {
    super.initState();
    _initAvatarViewer();
  }

  @override
  void dispose() {
    // Hentikan server HTTP lokal agar tidak ada timer/port yang bocor
    // saat layar avatar ditutup (penting untuk test & kebersihan resource).
    AvatarMotionService.instance.stopServer();
    super.dispose();
  }

  Future<void> _initAvatarViewer() async {
    try {
      final serverUrl = await AvatarMotionService.instance.startServer();

      // Cek apakah ada balasan dari langkah 2 yang cocok dengan kata isyarat
      final reply = ref.read(sessionProvider).replyText;
      if (reply != null && reply.trim().isNotEmpty) {
        final match = AvatarMotionService.instance.findMotionForText(reply);
        if (match != null) {
          _selectedMotionId = match.id;
          _activeGloss = match.gloss;
          _detectedGestureName = match.gloss;
        }
      }

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF090D16))
        ..addJavaScriptChannel(
          'FlutterBridge',
          onMessageReceived: (JavaScriptMessage msg) {
            _handleJsMessage(msg.message);
          },
        )
        ..loadRequest(Uri.parse(serverUrl));

      if (mounted) {
        setState(() {
          _controller = controller;
        });
      }
    } catch (e) {
      debugPrint('[AvatarScreen] Error init avatar: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleJsMessage(String message) {
    try {
      debugPrint('[AvatarScreen JS]: $message');
      if (message.contains('avatar_ready')) {
        if (mounted) {
          setState(() {
            _avatarReady = true;
            _isLoading = false;
          });
          // Muat gerakan terpilih
          _controller?.runJavaScript("loadMotion('$_selectedMotionId')");
        }
      } else if (message.contains('motion_loaded')) {
        if (mounted) {
          setState(() {
            _isPlaying = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[AvatarScreen] Error parsing JS msg: $e');
    }
  }

  void _switchMotion(String motionId, String gloss) {
    setState(() {
      _selectedMotionId = motionId;
      _activeGloss = gloss;
      _isPlaying = true;
    });
    _controller?.runJavaScript("loadMotion('$motionId')");
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    _controller?.runJavaScript("togglePlay()");
  }

  void _replay() {
    setState(() {
      _isPlaying = true;
    });
    _controller?.runJavaScript("replay()");
  }

  void _setSpeed(double speed) {
    setState(() {
      _currentSpeed = speed;
    });
    _controller?.runJavaScript("setSpeed($speed)");
  }

  void _setCameraPreset(String mode) {
    _controller?.runJavaScript("setCameraPreset('$mode')");
  }

  @override
  Widget build(BuildContext context) {
    final reply = ref.watch(sessionProvider.select((s) => s.replyText));
    final motions = AvatarMotionService.instance.motions;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Langkah 3 · Avatar Merespon',
          style: TextStyle(fontSize: 14),
        ),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const DesignIcon('83c29'),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/reply'),
        ),
        actions: [
          IconButton(
            tooltip: 'Segarkan Avatar',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _avatarReady = false;
              });
              _controller?.reload();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Respon Avatar Isyarat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _avatarReady
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _avatarReady ? '3D Active' : 'Loading',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D9488),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Viewport 3D GLB Model Container
            Container(
              height: 380,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF090D16),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!)
                  else
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),

                  // Overlay badge atas
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.accessibility_new,
                            size: 14,
                            color: Color(0xFF14B8A6),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Gerakan: $_activeGloss',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Indikator Loading awal
                  if (_isLoading)
                    Container(
                      color: const Color(0xFF090D16),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF14B8A6)),
                            SizedBox(height: 14),
                            Text(
                              'Menyiapkan Avatar 3D & Rig 54 Tulang...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Camera Angle Presets Row
            Row(
              children: [
                const Text(
                  'Sudut Kamera:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildPresetChip('Badan', 'upper'),
                        const SizedBox(width: 6),
                        _buildPresetChip('Zoom Tangan', 'hands'),
                        const SizedBox(width: 6),
                        _buildPresetChip('Kepala', 'head'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Playback and Speed Controls
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            onPressed: _togglePlay,
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: AppColors.primary,
                            ),
                            tooltip: _isPlaying ? 'Jeda' : 'Putar',
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: _replay,
                            icon: const Icon(Icons.replay, size: 20),
                            tooltip: 'Putar Ulang Gerakan',
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Kecepatan:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildSpeedButton(0.5, '0.5x'),
                          const SizedBox(width: 4),
                          _buildSpeedButton(1.0, '1.0x'),
                          const SizedBox(width: 4),
                          _buildSpeedButton(1.5, '1.5x'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Motion Switcher Selection
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.swipe_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Pustaka Gerakan Isyarat BISINDO',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: motions.map((m) {
                      final isSelected = m.id == _selectedMotionId;
                      return ChoiceChip(
                        label: Text('${m.gloss} (${m.english})'),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) _switchMotion(m.id, m.gloss);
                        },
                        selectedColor: const Color(0xFF0D9488),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? Colors.white : AppColors.text,
                        ),
                        avatar: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Teks Balasan Card
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const DesignIcon('a20f6', size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Teks balasan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_detectedGestureName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Sesuai: $_detectedGestureName',
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (reply != null && reply.trim().isNotEmpty)
                        ? reply
                        : 'Belum ada balasan suara/teks.',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: () => context.go('/camera'),
              icon: const DesignIcon('b6576', color: Colors.white),
              label: const Text('Lanjutkan Percakapan Kamera'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, String mode) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _setCameraPreset(mode),
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildSpeedButton(double speed, String label) {
    final isSelected = (_currentSpeed - speed).abs() < 0.01;
    return InkWell(
      onTap: () => _setSpeed(speed),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
