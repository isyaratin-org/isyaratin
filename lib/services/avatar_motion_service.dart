import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AvatarMotionItem {
  final String id;
  final String gloss;
  final String english;
  final int label;
  final String motionFile;
  final double fps;
  final double durationMs;
  final int totalFrames;

  const AvatarMotionItem({
    required this.id,
    required this.gloss,
    required this.english,
    required this.label,
    required this.motionFile,
    required this.fps,
    required this.durationMs,
    required this.totalFrames,
  });

  factory AvatarMotionItem.fromJson(Map<String, dynamic> json) =>
      AvatarMotionItem(
        id: json['id'] as String? ?? '',
        gloss: json['gloss'] as String? ?? '',
        english: json['english'] as String? ?? '',
        label: json['label'] as int? ?? 0,
        motionFile: json['motionFile'] as String? ?? '',
        fps: (json['fps'] as num?)?.toDouble() ?? 30.0,
        durationMs: (json['durationMs'] as num?)?.toDouble() ?? 2800.0,
        totalFrames: json['totalFrames'] as int? ?? 0,
      );
}

class AvatarMotionService {
  AvatarMotionService._();
  static final AvatarMotionService instance = AvatarMotionService._();

  HttpServer? _server;
  int _port = 0;
  List<AvatarMotionItem> _motions = [];

  bool get isRunning => _server != null;
  String get viewerUrl => 'http://127.0.0.1:$_port/index.html';
  List<AvatarMotionItem> get motions => _motions;

  /// Inisialisasi daftar gerakan dari manifest
  Future<void> loadManifest() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/avatar/motions/motions_manifest.json',
      );
      final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
      _motions = list
          .map((item) => AvatarMotionItem.fromJson(item as Map<String, dynamic>))
          .toList();
      debugPrint('[AvatarMotionService] Dimuat ${_motions.length} gerakan BISINDO.');
    } catch (e) {
      debugPrint('[AvatarMotionService] Warning load manifest: $e');
      // Fallback default gerakan utama
      _motions = const [
        AvatarMotionItem(
          id: 'rumah',
          gloss: 'Rumah',
          english: 'House',
          label: 23,
          motionFile: 'motion_rumah.json',
          fps: 30.0,
          durationMs: 2800.0,
          totalFrames: 84,
        ),
        AvatarMotionItem(
          id: 'siang',
          gloss: 'Siang',
          english: 'Noon',
          label: 25,
          motionFile: 'motion_siang.json',
          fps: 30.0,
          durationMs: 2300.0,
          totalFrames: 69,
        ),
        AvatarMotionItem(
          id: 'makan',
          gloss: 'Makan',
          english: 'Eat',
          label: 7,
          motionFile: 'motion_makan.json',
          fps: 28.2,
          durationMs: 2233.0,
          totalFrames: 57,
        ),
        AvatarMotionItem(
          id: 'saya',
          gloss: 'Saya',
          english: 'I / Me',
          label: 9,
          motionFile: 'motion_saya.json',
          fps: 25.8,
          durationMs: 2833.0,
          totalFrames: 59,
        ),
        AvatarMotionItem(
          id: 'malam',
          gloss: 'Malam',
          english: 'Night',
          label: 27,
          motionFile: 'motion_malam.json',
          fps: 30.0,
          durationMs: 3200.0,
          totalFrames: 96,
        ),
        AvatarMotionItem(
          id: 'air',
          gloss: 'Air',
          english: 'Water',
          label: 0,
          motionFile: 'motion_air.json',
          fps: 26.4,
          durationMs: 3066.0,
          totalFrames: 68,
        ),
      ];
    }
  }

  /// Mencocokkan teks balasan dengan gerakan isyarat terdekat
  AvatarMotionItem? findMotionForText(String text) {
    if (text.isEmpty || _motions.isEmpty) return null;
    final clean = text.toLowerCase();
    for (final item in _motions) {
      if (clean.contains(item.id.toLowerCase()) ||
          clean.contains(item.gloss.toLowerCase())) {
        return item;
      }
    }
    return null;
  }

  /// Jalankan local embedded HTTP server untuk Three.js WebGL & GLB
  Future<String> startServer() async {
    if (_server != null) return viewerUrl;

    await loadManifest();

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[AvatarMotionService] Server aktif di $viewerUrl');

    _server!.listen((HttpRequest req) async {
      final path = req.uri.path;
      try {
        if (path == '/' || path == '/index.html') {
          final data = await rootBundle.loadString('assets/avatar/viewer.html');
          req.response
            ..headers.contentType = ContentType.html
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..write(data);
          await req.response.close();
          return;
        }

        if (path == '/man-rigged.glb') {
          final byteData =
              await rootBundle.load('assets/avatar/man-rigged.glb');
          req.response
            ..headers.set('Content-Type', 'model/gltf-binary')
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..add(byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ));
          await req.response.close();
          return;
        }

        if (path.startsWith('/js/')) {
          final jsName = path.substring(4);
          final byteData =
              await rootBundle.load('assets/avatar/js/$jsName');
          req.response
            ..headers.set('Content-Type', 'application/javascript')
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..add(byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ));
          await req.response.close();
          return;
        }

        if (path.startsWith('/motions/')) {
          final filename = path.substring(9);
          // Coba beberapa varian nama: filename langsung, motion_<name>, atau <name>_motion.json
          ByteData? byteData;
          final candidates = [
            'assets/avatar/motions/$filename',
            if (!filename.startsWith('motion_'))
              'assets/avatar/motions/motion_$filename',
            if (!filename.contains('_motion.json') && filename.endsWith('.json'))
              'assets/avatar/motions/${filename.replaceAll('.json', '')}_motion.json',
          ];

          for (final c in candidates) {
            try {
              byteData = await rootBundle.load(c);
              break;
            } catch (_) {}
          }

          if (byteData != null) {
            req.response
              ..headers.contentType = ContentType.json
              ..headers.set('Access-Control-Allow-Origin', '*')
              ..add(byteData.buffer.asUint8List(
                byteData.offsetInBytes,
                byteData.lengthInBytes,
              ));
            await req.response.close();
            return;
          }
        }

        req.response
          ..statusCode = HttpStatus.notFound
          ..write('File not found: $path');
        await req.response.close();
      } catch (e) {
        debugPrint('[AvatarMotionService] Error handling $path: $e');
        try {
          req.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Server error');
          await req.response.close();
        } catch (_) {}
      }
    });

    return viewerUrl;
  }

  /// Tutup server jika tidak diperlukan lagi
  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
