import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/providers.dart';
import 'data/local_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await initializeDateFormatting('id_ID');
  const config = AppConfig.environment;
  SupabaseClient? client;
  String? notice = config.validationError;
  if (config.isConfigured && notice == null) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
      );
      client = Supabase.instance.client;
    } catch (_) {
      notice =
          'Layanan akun belum dapat dihubungkan. Kamu bisa mencoba mode lokal.';
    }
  }
  final database = LocalDatabase();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        supabaseProvider.overrideWithValue(client),
        startupNoticeProvider.overrideWithValue(notice),
      ],
      child: const IsyaratinApp(),
    ),
  );
}
