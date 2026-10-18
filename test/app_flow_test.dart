import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:isyaratin/app.dart';
import 'package:isyaratin/core/providers.dart';
import 'package:isyaratin/data/local_database.dart';
import 'package:isyaratin/data/models.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    final fonts = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await fonts.load();
  });

  testWidgets(
    'local message, reply, history, and sign-out form a usable flow',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: const IsyaratinApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Coba tanpa akun'));
      await tester.tap(find.text('Coba tanpa akun'));
      await tester.pumpAndSettle();
      expect(find.text('Halo, Teman!'), findsOneWidget);
      await tester.tap(find.text('Mulai Isyarat'));
      await tester.pumpAndSettle();
      // Camera is unavailable in the test environment; the screen falls back
      // to the typed-input flow with a status message.
      expect(
        find.text('Kamera tidak tersedia').evaluate().isNotEmpty ||
            find.text('Menyiapkan kamera...').evaluate().isNotEmpty,
        isTrue,
      );
      await tester.enterText(
        find.byType(TextField),
        'Saya ingin mengurus KTP.',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Tampilkan Pesan'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tampilkan Pesan'));
      await pumpUntil(tester, find.text('Langkah 2 · Balas Pesan'));
      expect(find.text('Saya ingin mengurus KTP.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Silakan siapkan berkas.');
      await tester.pump();
      await tester.ensureVisible(find.text('Kirim Balasan'));
      await tester.tap(find.text('Kirim Balasan'));
      // The avatar screen renders its header immediately; avoid pumpAndSettle
      // because the 3D webview is unavailable in tests and keeps a spinner.
      for (
        var i = 0;
        i < 10 && find.text('Respon Avatar Isyarat').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Respon Avatar Isyarat'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Lanjutkan Percakapan Kamera'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      // Avoid pumpAndSettle: the 3D webview spinner never settles in tests.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Lanjutkan Percakapan Kamera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();
      expect((await database.listConversations('guest')).length, 1);
      final messages = await database.messages(
        'guest',
        (await database.listConversations('guest')).single.id,
      );
      expect(messages.map((m) => m.content), [
        'Saya ingin mengurus KTP.',
        'Silakan siapkan berkas.',
      ]);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Masuk atau Daftar'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masuk atau Daftar'));
      await tester.pumpAndSettle();
      expect(find.text('Selamat Datang'), findsOneWidget);
      // Signing out retains the local guest history for the next local session.
      expect((await database.listConversations('guest')).length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('small screens and large text keep primary navigation usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).enterGuest();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IsyaratinApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final tab in ['Kamera', 'Voice Note', 'Riwayat', 'Profil']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Overflow on $tab');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('history preserves whether a message came from voice or sign', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier);
    controller.enterGuest();

    await controller.send(
      'Gerakan kamera',
      MessageAuthor.signer,
      source: MessageSource.sign,
    );
    await controller.send(
      'Balasan suara',
      MessageAuthor.partner,
      source: MessageSource.voice,
    );

    final conversation = (await database.listConversations('guest')).single;
    final messages = await database.messages('guest', conversation.id);
    expect(messages.map((message) => message.source), [
      MessageSource.sign,
      MessageSource.voice,
    ]);
  });

  test('history can be deleted individually and cleared completely', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionProvider.notifier);
    controller.enterGuest();

    await controller.send('Pesan 1', MessageAuthor.signer);
    final conv1 = (await database.listConversations('guest')).single;

    controller.newConversation();
    await controller.send('Pesan 2', MessageAuthor.signer);
    expect((await database.listConversations('guest')).length, 2);

    await controller.deleteConversation(conv1.id);
    final remaining = await database.listConversations('guest');
    expect(remaining.length, 1);
    expect(remaining.single.id, isNot(conv1.id));
    expect(await database.messages('guest', conv1.id), isEmpty);

    await controller.clearHistory();
    expect(await database.listConversations('guest'), isEmpty);
  });

  testWidgets(
    'deleting conversation from detail screen removes it from history',
    (tester) async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionProvider.notifier);
      controller.enterGuest();
      await controller.send('Pesan hapus uji coba', MessageAuthor.signer);
      final conv = (await database.listConversations('guest')).single;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IsyaratinApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();
      expect(find.text(conv.title), findsOneWidget);

      await tester.tap(find.text(conv.title));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hapus percakapan'));
      await tester.pumpAndSettle();

      expect(find.text('Hapus Percakapan?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await tester.pumpAndSettle();

      expect(await database.listConversations('guest'), isEmpty);
      expect(find.text('Belum ada percakapan'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

// SQLite native-library initialization can finish between rendered frames.
// Wait for the resulting screen while allowing real I/O, rather than assuming
// that a quiet animation scheduler means the database operation has completed.
Future<void> pumpUntil(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump();
    if (target.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    target,
    findsWidgets,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' | '),
  );
}
