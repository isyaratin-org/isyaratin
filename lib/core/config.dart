import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({this.supabaseUrl = '', this.publishableKey = ''});

  static const environment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String supabaseUrl;
  final String publishableKey;

  bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  String? get validationError {
    if (supabaseUrl.isEmpty && publishableKey.isEmpty) return null;
    if (!isConfigured) {
      return 'Isi URL dan publishable key Supabase bersama-sama.';
    }
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme)) {
      return 'URL Supabase belum valid.';
    }
    if (publishableKey.startsWith('sb_secret_')) {
      return 'Gunakan publishable key, bukan secret key.';
    }
    return null;
  }

  static String get authRedirect => kIsWeb
      ? '${Uri.base.origin}/auth/callback'
      : 'id.isyaratin.app://auth-callback';
}
