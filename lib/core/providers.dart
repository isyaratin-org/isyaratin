import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';
import '../data/models.dart';
import '../data/sync_repository.dart';

final databaseProvider = Provider<LocalDatabase>(
  (ref) => throw UnimplementedError(),
);
final supabaseProvider = Provider<SupabaseClient?>((ref) => null);
final startupNoticeProvider = Provider<String?>((ref) => null);

class AppSession {
  const AppSession({
    this.user,
    this.guest = false,
    this.recovering = false,
    this.conversationId,
    this.signerText,
    this.replyText,
    this.syncing = false,
  });

  final User? user;
  final bool guest;
  final bool recovering;
  final String? conversationId;
  final String? signerText;
  final String? replyText;
  final bool syncing;

  String get ownerId => user?.id ?? 'guest';
  bool get canEnter => guest || user != null;
  String get displayName {
    final name = user?.userMetadata?['full_name'] as String?;
    return name == null || name.trim().isEmpty ? 'Teman' : name.trim();
  }

  AppSession withConversation(String? id, String? signer, String? reply) =>
      AppSession(
        user: user,
        guest: guest,
        recovering: recovering,
        conversationId: id,
        signerText: signer,
        replyText: reply,
        syncing: syncing,
      );

  AppSession withSyncing(bool value) => AppSession(
    user: user,
    guest: guest,
    recovering: recovering,
    conversationId: conversationId,
    signerText: signerText,
    replyText: replyText,
    syncing: value,
  );
}

final sessionProvider = NotifierProvider<SessionController, AppSession>(
  SessionController.new,
);

final historyProvider = FutureProvider.family<List<Conversation>, String>(
  (ref, ownerId) => ref.watch(databaseProvider).listConversations(ownerId),
);

final messagesProvider =
    FutureProvider.family<List<ChatMessage>, (String, String)>((ref, args) {
      final (ownerId, id) = args;
      return ref.watch(databaseProvider).messages(ownerId, id);
    });

class SessionController extends Notifier<AppSession> {
  static const _uuid = Uuid();

  @override
  AppSession build() {
    final client = ref.watch(supabaseProvider);
    final subscription = client?.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user;
      if (user?.id != state.user?.id ||
          event.event == AuthChangeEvent.signedOut) {
        state = AppSession(user: user);
      } else {
        state = AppSession(
          user: user,
          guest: state.guest,
          recovering:
              state.recovering ||
              event.event == AuthChangeEvent.passwordRecovery,
          conversationId: state.conversationId,
          signerText: state.signerText,
          replyText: state.replyText,
          syncing: state.syncing,
        );
      }
      if (event.event == AuthChangeEvent.passwordRecovery) {
        state = AppSession(user: user, recovering: true);
      }
      // Auto-sync history whenever a session becomes available: on app start
      // with a persisted session (initialSession) and right after sign-in.
      if (user != null &&
          (event.event == AuthChangeEvent.initialSession ||
              event.event == AuthChangeEvent.signedIn)) {
        _autoSync(user);
      }
    });
    final currentUser = client?.auth.currentUser;
    if (currentUser != null) {
      // Schedule after build so state assignment does not happen mid-build.
      Future.microtask(() => _autoSync(currentUser));
    }
    ref.onDispose(() => subscription?.cancel());
    return AppSession(user: currentUser);
  }

  /// Best-effort background sync of history for [user]. Never throws; failures
  /// are silent so the manual sync button on the history page remains the
  /// explicit fallback.
  Future<void> _autoSync(User user) async {
    final client = ref.read(supabaseProvider);
    if (client == null || state.syncing) return;
    final ownerId = user.id;
    state = AppSession(user: user, syncing: true);
    try {
      await SyncRepository(
        ref.read(databaseProvider),
        client,
      ).synchronize(ownerId);
      if (ref.mounted) refreshHistory(state.conversationId);
    } catch (_) {
      // Ignore — auto-sync is best-effort.
    } finally {
      if (ref.mounted && state.ownerId == ownerId) {
        state = state.withSyncing(false);
      }
    }
  }

  void enterGuest() => state = const AppSession(guest: true);

  Future<void> signOut() async {
    final client = ref.read(supabaseProvider);
    if (state.user != null && client != null) {
      await client.auth.signOut(scope: SignOutScope.local);
    }
    state = const AppSession();
  }

  void finishRecovery() => state = AppSession(user: state.user);

  void newConversation() => state = state.withConversation(null, null, null);

  Future<void> openConversation(String id) async {
    final ownerId = state.ownerId;
    final database = ref.read(databaseProvider);
    if (await database.conversation(ownerId, id) == null) {
      throw StateError('Percakapan tidak ditemukan.');
    }
    final messages = await database.messages(ownerId, id);
    if (state.ownerId != ownerId) return;
    String? signer;
    String? reply;
    for (final message in messages) {
      if (message.author == MessageAuthor.signer) {
        signer = message.content;
      } else {
        reply = message.content;
      }
    }
    state = state.withConversation(id, signer, reply);
  }

  Future<void> send(String value, MessageAuthor author) async {
    final content = value.trim();
    if (content.isEmpty || content.length > 5000) {
      throw ArgumentError('Isi pesan harus 1–5000 karakter.');
    }
    if (!state.canEnter) throw StateError('Silakan masuk terlebih dahulu.');
    final ownerId = state.ownerId;
    final now = DateTime.now().toUtc();
    final database = ref.read(databaseProvider);
    final id = state.conversationId ?? _uuid.v4();
    final existing = await database.conversation(ownerId, id);
    final conversation =
        existing ??
        Conversation(
          id: id,
          ownerId: ownerId,
          title:
              'Percakapan ${DateFormat('dd MMM, HH.mm', 'id_ID').format(now.toLocal())}',
          location: '',
          createdAt: now,
          updatedAt: now,
        );
    await database.saveMessage(
      conversation,
      ChatMessage(
        id: _uuid.v4(),
        conversationId: id,
        ownerId: ownerId,
        author: author,
        source: MessageSource.typed,
        content: content,
        createdAt: now,
      ),
    );
    if (state.ownerId != ownerId) return;
    state = state.withConversation(
      id,
      author == MessageAuthor.signer ? content : state.signerText,
      author == MessageAuthor.partner ? content : state.replyText,
    );
    refreshHistory(id);
  }

  void refreshHistory([String? id]) {
    final ownerId = state.ownerId;
    ref.invalidate(historyProvider(ownerId));
    if (id != null) ref.invalidate(messagesProvider((ownerId, id)));
  }

  Future<void> editConversation(
    String id,
    String title,
    String location,
  ) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty ||
        trimmedTitle.length > 160 ||
        location.trim().length > 240) {
      throw ArgumentError('Periksa judul dan lokasi percakapan.');
    }
    await ref
        .read(databaseProvider)
        .editConversation(state.ownerId, id, trimmedTitle, location.trim());
    refreshHistory(id);
  }

  Future<int> sync() async {
    if (state.syncing) return 0;
    final client = ref.read(supabaseProvider);
    final user = state.user;
    if (client == null || user == null) {
      throw StateError('Masuk ke akun untuk menyinkronkan riwayat.');
    }
    final ownerId = user.id;
    state = state.withSyncing(true);
    try {
      final count = await SyncRepository(
        ref.read(databaseProvider),
        client,
      ).synchronize(ownerId);
      if (ref.mounted) refreshHistory(state.conversationId);
      return count;
    } finally {
      if (ref.mounted && state.ownerId == ownerId) {
        state = state.withSyncing(false);
      }
    }
  }
}
