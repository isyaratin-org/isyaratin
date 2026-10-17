import 'package:flutter_test/flutter_test.dart';
import 'package:isyaratin/core/config.dart';

void main() {
  test('empty configuration allows local mode', () {
    const config = AppConfig();
    expect(config.isConfigured, isFalse);
    expect(config.validationError, isNull);
  });
  test('incomplete configuration is explained', () {
    expect(
      const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
      ).validationError,
      isNotNull,
    );
  });
  test('rejects invalid URLs and secret keys', () {
    expect(
      const AppConfig(
        supabaseUrl: 'invalid',
        publishableKey: 'test',
      ).validationError,
      isNotNull,
    );
    expect(
      const AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        publishableKey: 'sb_secret_test',
      ).validationError,
      isNotNull,
    );
  });
}
