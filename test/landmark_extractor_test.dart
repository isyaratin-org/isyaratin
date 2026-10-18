import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isyaratin/services/landmark_extractor.dart';

void main() {
  group('LandmarkExtractor.extendSequence', () {
    test('builds the exact 400-dimensional model layout', () {
      final base = Float32List(2 * LandmarkExtractor.featureDim);
      for (var i = 0; i < 183; i++) {
        base[LandmarkExtractor.featureDim + i] = 1.0;
      }
      for (var frame = 0; frame < 2; frame++) {
        final flags = frame * LandmarkExtractor.featureDim + 183;
        base[flags] = 1.0;
        base[flags + 1] = 1.0;
        base[flags + 2] = 1.0;
      }

      final extended = LandmarkExtractor.extendSequence(base, 2);

      expect(extended, hasLength(2 * LandmarkExtractor.extendedFeatureDim));
      expect(
        extended.sublist(0, LandmarkExtractor.featureDim),
        base.sublist(0, LandmarkExtractor.featureDim),
      );
      expect(
        extended.sublist(
          LandmarkExtractor.extendedFeatureDim,
          LandmarkExtractor.extendedFeatureDim + LandmarkExtractor.featureDim,
        ),
        base.sublist(LandmarkExtractor.featureDim),
      );

      // Python copies frame 1 velocity into frame 0. Both frames therefore
      // contain +1 for every coordinate in this synthetic sequence.
      expect(
        extended.sublist(
          LandmarkExtractor.featureDim,
          LandmarkExtractor.featureDim + 183,
        ),
        everyElement(1.0),
      );
      expect(
        extended.sublist(
          LandmarkExtractor.extendedFeatureDim + LandmarkExtractor.featureDim,
          LandmarkExtractor.extendedFeatureDim +
              LandmarkExtractor.featureDim +
              183,
        ),
        everyElement(1.0),
      );
    });

    test('masks velocity when a component first appears', () {
      final base = Float32List(2 * LandmarkExtractor.featureDim);
      for (var i = 0; i < 183; i++) {
        base[LandmarkExtractor.featureDim + i] = 5.0;
      }
      final secondFlags = LandmarkExtractor.featureDim + 183;
      base[secondFlags] = 1.0;
      base[secondFlags + 1] = 1.0;
      base[secondFlags + 2] = 1.0;

      final extended = LandmarkExtractor.extendSequence(base, 2);

      expect(
        extended.sublist(
          LandmarkExtractor.featureDim,
          LandmarkExtractor.featureDim + 183,
        ),
        everyElement(0.0),
      );
      expect(
        extended.sublist(
          LandmarkExtractor.extendedFeatureDim + LandmarkExtractor.featureDim,
          LandmarkExtractor.extendedFeatureDim +
              LandmarkExtractor.featureDim +
              183,
        ),
        everyElement(0.0),
      );
    });
  });
}
