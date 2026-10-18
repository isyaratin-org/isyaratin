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

class AvatarMotionSequence {
  const AvatarMotionSequence({
    required this.motions,
    required this.unmatchedWords,
    required this.normalizedText,
  });

  final List<AvatarMotionItem> motions;
  final List<String> unmatchedWords;
  final String normalizedText;
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
    if (_motions.isNotEmpty) return;
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/avatar/motions/motions_manifest.json',
      );
      final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
      _motions = list
          .map(
            (item) => AvatarMotionItem.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      debugPrint(
        '[AvatarMotionService] Dimuat ${_motions.length} gerakan BISINDO.',
      );
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

  /// Mencocokkan teks dengan gerakan isyarat terdekat.
  ///
  /// Mendukung kalimat bebas, misal "saya mau buat ktp" akan menemukan gerakan
  /// "ktp". Strategi skor:
  /// - Cocok penuh frasa gloss (mis. "buku rekening") = skor tertinggi.
  /// - Cocok per-kata gloss di dalam teks (mis. "ktp") = skor sedang.
  /// - Semakin banyak kata gloss yang cocok, semakin tinggi skor.
  AvatarMotionItem? findMotionForText(String text) {
    if (text.isEmpty || _motions.isEmpty) return null;
    final clean = text.toLowerCase().trim();

    // Token kata dari teks input (buang kata sambung umum)
    final stopWords = {
      'saya',
      'aku',
      'mau',
      'ingin',
      'buat',
      'untuk',
      'yang',
      'dan',
      'di',
      'ke',
      'dengan',
      'tolong',
      'bisa',
      'akan',
      'ini',
      'itu',
      'a',
      'the',
      'please',
      'want',
      'make',
      'i',
      'me',
    };
    final inputWords = clean
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty && !stopWords.contains(w))
        .toSet();

    AvatarMotionItem? best;
    var bestScore = 0.0;

    for (final item in _motions) {
      final id = item.id.toLowerCase();
      final gloss = item.gloss.toLowerCase();

      // 1. Cocok penuh frasa gloss / id di dalam teks
      if (clean.contains(gloss)) {
        final score = 100.0 + gloss.length;
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
        continue;
      }
      if (clean.contains(id)) {
        final score = 90.0 + id.length;
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
        continue;
      }

      // 2. Cocok per-kata gloss terhadap kata input
      final glossWords = gloss
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.isNotEmpty)
          .toList();
      var matched = 0;
      for (final gw in glossWords) {
        if (inputWords.contains(gw)) matched++;
      }
      if (matched > 0) {
        // Skor: proporsi kata gloss yang cocok + bonus kata tunggal
        final ratio = matched / glossWords.length;
        final score = 50.0 * ratio + matched;
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }
    }

    return best;
  }

  /// Mengubah kalimat bebas menjadi urutan motion sesuai urutan kata.
  ///
  /// Frasa terpanjang diprioritaskan (`buku rekening` sebelum `buku`), lalu
  /// kata tunggal dicocokkan melalui normalisasi dan stemming ringan bahasa
  /// Indonesia. Kata yang belum punya aset motion dikembalikan lewat
  /// [AvatarMotionSequence.unmatchedWords], bukan diganti dengan motion lain.
  AvatarMotionSequence findMotionSequence(String text) {
    final normalized = _normalizeText(text);
    final words = normalized.isEmpty ? <String>[] : normalized.split(' ');
    final matched = <AvatarMotionItem>[];
    final unmatched = <String>[];

    final entries = _motions
        .map(
          (motion) => (
            motion: motion,
            phrases: {
              _normalizeText(motion.gloss),
              _normalizeText(motion.id.replaceAll('_', ' ')),
              ...?_phraseAliases[motion.id],
            }.where((value) => value.isNotEmpty).toList(),
          ),
        )
        .toList();

    var index = 0;
    while (index < words.length) {
      AvatarMotionItem? best;
      var consumed = 0;

      // Longest exact phrase wins, so multi-word glosses remain one motion.
      for (final entry in entries) {
        for (final phrase in entry.phrases) {
          final phraseWords = phrase.split(' ');
          if (phraseWords.length <= consumed ||
              index + phraseWords.length > words.length) {
            continue;
          }
          var same = true;
          for (var offset = 0; offset < phraseWords.length; offset++) {
            if (words[index + offset] != phraseWords[offset]) {
              same = false;
              break;
            }
          }
          if (same) {
            best = entry.motion;
            consumed = phraseWords.length;
          }
        }
      }

      // Fallback untuk variasi umum seperti "ingin" -> "mau" dan
      // "dibawa" -> "membawa". Hanya motion satu kata yang dipakai agar
      // frasa tidak terpotong menjadi arti yang berbeda.
      if (best == null) {
        final inputRoot = _motionRoot(words[index]);
        for (final entry in entries) {
          final singleWords = entry.phrases
              .where((phrase) => !phrase.contains(' '))
              .toList();
          if (singleWords.any((word) => _motionRoot(word) == inputRoot)) {
            best = entry.motion;
            consumed = 1;
            break;
          }
        }
      }

      if (best != null) {
        matched.add(best);
        index += consumed;
      } else {
        if (!_ignoredGrammarWords.contains(words[index])) {
          unmatched.add(words[index]);
        }
        index++;
      }
    }

    return AvatarMotionSequence(
      motions: List.unmodifiable(matched),
      unmatchedWords: List.unmodifiable(unmatched),
      normalizedText: normalized,
    );
  }

  static String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const Map<String, List<String>> _phraseAliases = {
    'disini': ['di sini', 'sini'],
    'bantuannya': ['bantuan', 'membantu', 'bantu'],
  };

  static const Set<String> _ignoredGrammarWords = {
    'dan',
    'atau',
    'yang',
    'di',
    'ke',
    'dari',
    'untuk',
    'dengan',
  };

  static String _motionRoot(String value) {
    const aliases = {
      'ingin': 'mau',
      'hendak': 'mau',
      'pengin': 'mau',
      'pengen': 'mau',
      'tolong': 'bantuan',
      'membantu': 'bantuan',
      'bantu': 'bantuan',
    };
    var word = aliases[value] ?? value;

    for (final suffix in const [
      'lah',
      'kah',
      'tah',
      'pun',
      'ku',
      'mu',
      'nya',
    ]) {
      if (word.endsWith(suffix) && word.length - suffix.length >= 3) {
        word = word.substring(0, word.length - suffix.length);
        break;
      }
    }
    for (final suffix in const ['kan', 'an', 'i']) {
      if (word.endsWith(suffix) && word.length - suffix.length >= 4) {
        word = word.substring(0, word.length - suffix.length);
        break;
      }
    }
    for (final prefix in const [
      'meng',
      'meny',
      'peng',
      'peny',
      'mem',
      'men',
      'pem',
      'pen',
      'ber',
      'ter',
      'per',
      'di',
      'ke',
      'se',
    ]) {
      if (word.startsWith(prefix) && word.length - prefix.length >= 3) {
        word = word.substring(prefix.length);
        break;
      }
    }
    return word;
  }

  Uint8List? _cachedGlbBytes;

  Future<Uint8List> _loadGlbBytes() async {
    if (_cachedGlbBytes != null) return _cachedGlbBytes!;
    final byteData = await rootBundle.load('assets/avatar/man-rigged.glb');
    _cachedGlbBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return _cachedGlbBytes!;
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
      debugPrint('[AvatarMotionService] Incoming request: $path');
      try {
        if (path == '/' ||
            path == '/index.html' ||
            path == '/avatar_viewer.html' ||
            path == '/pose_studio.html') {
          final page = path == '/pose_studio.html'
              ? 'pose_studio.html'
              : path == '/avatar_viewer.html'
              ? 'avatar_viewer.html'
              : 'viewer.html';
          final data = await rootBundle.loadString('assets/avatar/$page');
          final bytes = utf8.encode(data);
          req.response
            ..headers.contentType = ContentType.html
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..headers.set(
              'Cache-Control',
              'no-cache, no-store, must-revalidate',
            )
            ..contentLength = bytes.length
            ..add(bytes);
          await req.response.close();
          return;
        }

        if (path == '/man-rigged.glb') {
          final bytes = await _loadGlbBytes();
          req.response
            ..headers.set('Content-Type', 'model/gltf-binary')
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..headers.set('Cache-Control', 'public, max-age=3600')
            ..contentLength = bytes.length
            ..add(bytes);
          await req.response.close();
          debugPrint(
            '[AvatarMotionService] Sent man-rigged.glb (${bytes.length} bytes)',
          );
          return;
        }

        if (path.startsWith('/js/')) {
          final jsName = path.substring(4);
          final byteData = await rootBundle.load('assets/avatar/js/$jsName');
          final bytes = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );
          req.response
            ..headers.set(
              'Content-Type',
              'application/javascript; charset=utf-8',
            )
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..headers.set('Cache-Control', 'public, max-age=3600')
            ..contentLength = bytes.length
            ..add(bytes);
          await req.response.close();
          return;
        }

        if (path.startsWith('/videos_manual/') && path.endsWith('.mp4')) {
          final filename = path.substring('/videos_manual/'.length);
          if (filename.contains('/') || filename.contains('\\')) {
            req.response.statusCode = HttpStatus.badRequest;
            await req.response.close();
            return;
          }
          final byteData = await rootBundle.load(
            'assets/avatar/videos_manual/$filename',
          );
          final bytes = byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          );
          final range = req.headers.value(HttpHeaders.rangeHeader);
          final match = range == null
              ? null
              : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
          final start = match == null ? 0 : int.parse(match.group(1)!);
          final requestedEnd = match?.group(2);
          final end = requestedEnd == null || requestedEnd.isEmpty
              ? bytes.length - 1
              : int.parse(requestedEnd);
          if (start >= bytes.length || end < start) {
            req.response
              ..statusCode = HttpStatus.requestedRangeNotSatisfiable
              ..headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes */${bytes.length}',
              );
            await req.response.close();
            return;
          }
          final last = end < bytes.length ? end : bytes.length - 1;
          req.response
            ..statusCode = match == null
                ? HttpStatus.ok
                : HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentTypeHeader, 'video/mp4')
            ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..headers.set('Access-Control-Allow-Origin', '*')
            ..contentLength = last - start + 1
            ..add(bytes.sublist(start, last + 1));
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
            if (!filename.contains('_motion.json') &&
                filename.endsWith('.json'))
              'assets/avatar/motions/${filename.replaceAll('.json', '')}_motion.json',
          ];

          for (final c in candidates) {
            try {
              byteData = await rootBundle.load(c);
              break;
            } catch (_) {}
          }

          if (byteData != null) {
            final bytes = byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            );
            req.response
              ..headers.contentType = ContentType.json
              ..headers.set('Access-Control-Allow-Origin', '*')
              ..headers.set('Cache-Control', 'no-cache')
              ..contentLength = bytes.length
              ..add(bytes);
            await req.response.close();
            return;
          }
        }

        debugPrint('[AvatarMotionService] 404 Not Found: $path');
        req.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.text
          ..headers.set('Access-Control-Allow-Origin', '*')
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
    final server = _server;
    _server = null;
    _port = 0;
    await server?.close(force: true);
  }
}
