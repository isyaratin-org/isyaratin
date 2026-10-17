import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Speech service wrapping Text-To-Speech (TTS) and Speech-To-Text (STT).
class SpeechService {
  SpeechService() {
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
  }

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();

  bool _speaking = false;
  bool _ttsInitialized = false;
  bool _sttInitialized = false;
  bool _sttAvailable = false;

  bool get isSpeaking => _speaking;
  bool get isListening => _stt.isListening;
  bool get isSttAvailable => _sttAvailable;

  // --- Text-To-Speech (TTS) ---

  Future<void> _ensureTtsReady() async {
    if (_ttsInitialized) return;
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _ttsInitialized = true;
  }

  /// Speaks [text] aloud. Returns `false` if the engine is unavailable.
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _ensureTtsReady();
      _speaking = true;
      await _tts.speak(trimmed);
      return true;
    } catch (_) {
      _speaking = false;
      return false;
    }
  }

  /// Stops any ongoing speech.
  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore
    }
  }

  // --- Speech-To-Text (STT) ---

  /// Initializes the speech recognition engine.
  Future<bool> initStt({
    Function(String status)? onStatus,
    Function(String errorMsg)? onError,
  }) async {
    if (_sttInitialized) return _sttAvailable;
    try {
      _sttAvailable = await _stt.initialize(
        onStatus: (status) {
          debugPrint('STT status: $status');
          onStatus?.call(status);
        },
        onError: (errorNotification) {
          debugPrint('STT error: ${errorNotification.errorMsg}');
          onError?.call(errorNotification.errorMsg);
        },
      );
      _sttInitialized = true;
      return _sttAvailable;
    } catch (e) {
      debugPrint('Failed to initialize STT: $e');
      _sttInitialized = true;
      _sttAvailable = false;
      return false;
    }
  }

  /// Starts listening to voice input and returns words transcribed.
  Future<bool> startListening({
    required Function(String words) onResult,
    VoidCallback? onDone,
  }) async {
    if (!_sttInitialized) {
      final ready = await initStt();
      if (!ready) return false;
    }
    if (!_sttAvailable) return false;

    if (_speaking) {
      await stop();
    }

    try {
      await _stt.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
          if (result.finalResult) {
            onDone?.call();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: 'id_ID',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Error starting STT listen: $e');
      return false;
    }
  }

  /// Stops listening to voice input.
  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  void dispose() {
    _speaking = false;
    _tts.stop();
    _stt.stop();
  }
}
