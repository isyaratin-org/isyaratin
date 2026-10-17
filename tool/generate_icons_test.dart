// Run explicitly: flutter test tool/generate_icons_test.dart
// Renders the existing Figma SVG without recreating its artwork.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render Figma brand into platform launcher icons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: Colors.white,
            child: Center(
              child: SvgPicture.asset(
                'assets/figma/24704.svg',
                width: 600,
                height: 600,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sizes = <String, int>{
      'web/favicon.png': 32,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
      for (final density in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries)
        'android/app/src/main/res/mipmap-${density.key}/ic_launcher.png':
            density.value,
    };
    final iconDirectory = Directory(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset',
    );
    final contents =
        jsonDecode(
              File('${iconDirectory.path}/Contents.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final entry in contents['images'] as List<dynamic>) {
      final image = entry as Map<String, dynamic>;
      final filename = image['filename'] as String?;
      if (filename == null) continue;
      final dimension = double.parse(
        (image['size'] as String).split('x').first,
      );
      final scale = double.parse(
        (image['scale'] as String).replaceAll('x', ''),
      );
      sizes['${iconDirectory.path}/$filename'] = (dimension * scale).round();
    }
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      for (final entry in sizes.entries) {
        final image = await boundary.toImage(pixelRatio: entry.value / 1024);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(entry.key).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      }
    });
  });
}
