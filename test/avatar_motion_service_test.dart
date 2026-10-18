import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isyaratin/services/avatar_motion_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = AvatarMotionService.instance;
  late Uri base;

  // flutter_test mengganti HttpClient bawaan; socket biasa menguji server lokal
  // tanpa bergantung pada implementasi plugin/platform.
  Future<(int, List<int>)> get(String path, {String? range}) async {
    final socket = await Socket.connect(base.host, base.port);
    socket.add(
      ascii.encode(
        'GET $path HTTP/1.0\r\n'
        'Host: ${base.host}\r\n'
        '${range == null ? '' : 'Range: $range\r\n'}'
        'Connection: close\r\n\r\n',
      ),
    );
    await socket.flush();
    final response = await socket.fold<BytesBuilder>(
      BytesBuilder(),
      (builder, chunk) => builder..add(chunk),
    );
    socket.destroy();
    final bytes = response.takeBytes();
    var boundary = -1;
    for (var i = 0; i < bytes.length - 3; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        boundary = i;
        break;
      }
    }
    if (boundary < 0) throw StateError('HTTP response has no headers');
    final header = ascii.decode(bytes.sublist(0, boundary));
    final status = int.parse(header.split(' ').elementAt(1));
    return (status, bytes.sublist(boundary + 4));
  }

  setUpAll(() async {
    base = Uri.parse(await service.startServer());
  });

  tearDownAll(() async {
    await service.stopServer();
  });

  test('viewer, studio, model, and manual motion assets are served', () async {
    for (final path in [
      '/index.html',
      '/avatar_viewer.html',
      '/pose_studio.html',
      '/js/three.min.js',
      '/man-rigged.glb',
      '/motions/motions_manifest.json',
      '/motions/motion_manual_membawa.json',
    ]) {
      final (status, body) = await get(path);
      expect(status, HttpStatus.ok, reason: path);
      expect(body, isNotEmpty, reason: path);
    }
    expect(service.motions.length, 55);
  });

  test('manual video supports browser range requests', () async {
    final (status, bytes) = await get(
      '/videos_manual/membawa.mp4',
      range: 'bytes=0-99',
    );
    expect(status, HttpStatus.partialContent);
    expect(bytes.length, 100);
  });

  test('manual motion contains playable quaternion frames', () async {
    final (status, bytes) = await get('/motions/motion_manual_membawa.json');
    expect(status, HttpStatus.ok);
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(data['retargeterVersion'], 5);
    expect((data['frames'] as List).isNotEmpty, isTrue);
    expect(data['coordinateSpace'], 'avatar_local_quaternion');
  });

  test('sentence is tokenized into ordered available motions', () {
    final sequence = service.findMotionSequence('Saya mau buat KTP.');
    expect(sequence.motions.map((motion) => motion.id), [
      'wl_saya',
      'mau',
      'ktp',
    ]);
    expect(sequence.unmatchedWords, ['buat']);
  });

  test('longest phrases and lightweight Indonesian stems are preserved', () {
    final sequence = service.findMotionSequence(
      'Silakan buka buku rekening dan dibawa ke sini',
    );
    expect(sequence.motions.map((motion) => motion.id), [
      'silakan',
      'buka',
      'buku_rekening',
      'membawa',
      'disini',
    ]);
    expect(sequence.unmatchedWords, isEmpty);
  });

  test(
    'mobile viewer keeps skinned avatar visible above cropped legs',
    () async {
      final (status, bytes) = await get('/index.html');
      expect(status, HttpStatus.ok);
      final html = utf8.decode(bytes);
      expect(html, contains('child.frustumCulled = false'));
      expect(html, contains('renderer.clippingPlanes = [clipPlane]'));
      expect(html, contains('notifyFlutter("motion_finished"'));
      expect(
        html,
        contains('async function loadMotion(motionIdOrFilename, once = false)'),
      );
    },
  );
}
