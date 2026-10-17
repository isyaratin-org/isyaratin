import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

class IsyaratinApp extends ConsumerWidget {
  const IsyaratinApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'ISYARATIN',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: ref.watch(routerProvider),
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => ColoredBox(
      color: const Color(0xFFE0EBED),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: child,
        ),
      ),
    ),
  );
}
