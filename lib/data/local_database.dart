import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'models.dart';

// Custom SQL keeps this small schema explicit and avoids generated build files.
class LocalDatabase extends GeneratedDatabase {
  LocalDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'isyaratin',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('/sqlite3.wasm'),
                driftWorker: Uri.parse('/drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY, owner_id TEXT NOT NULL,
          title TEXT NOT NULL, location TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          pending INTEGER NOT NULL DEFAULT 1,
          UNIQUE(id, owner_id)
        )
      ''');
      await customStatement('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL,
          owner_id TEXT NOT NULL, author TEXT NOT NULL, source TEXT NOT NULL,
          content TEXT NOT NULL, created_at TEXT NOT NULL,
          FOREIGN KEY(conversation_id, owner_id)
            REFERENCES conversations(id, owner_id) ON DELETE CASCADE
        )
      ''');
      await customStatement(
        'CREATE INDEX conversation_owner ON conversations(owner_id, updated_at DESC)',
      );
      await customStatement(
        'CREATE INDEX message_conversation ON messages(owner_id, conversation_id, created_at)',
      );
    },
    beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<List<Conversation>> listConversations(
    String ownerId,
  ) async => (await customSelect(
    'SELECT * FROM conversations WHERE owner_id = ? ORDER BY updated_at DESC, id',
    variables: [Variable(ownerId)],
  ).get()).map((row) => Conversation.fromJson(row.data)).toList();

  Future<Conversation?> conversation(String ownerId, String id) async {
    final row = await customSelect(
      'SELECT * FROM conversations WHERE owner_id = ? AND id = ?',
      variables: [Variable(ownerId), Variable(id)],
    ).getSingleOrNull();
    return row == null ? null : Conversation.fromJson(row.data);
  }

  Future<List<ChatMessage>> messages(
    String ownerId,
    String conversationId,
  ) async => (await customSelect(
    'SELECT * FROM messages WHERE owner_id = ? AND conversation_id = ? ORDER BY created_at, id',
    variables: [Variable(ownerId), Variable(conversationId)],
  ).get()).map((row) => ChatMessage.fromJson(row.data)).toList();

  Future<void> saveMessage(Conversation conversation, ChatMessage message) =>
      transaction(() async {
        if (message.ownerId != conversation.ownerId ||
            message.conversationId != conversation.id) {
          throw ArgumentError('Pemilik percakapan tidak sesuai.');
        }
        await customStatement(
          '''
      INSERT INTO conversations (id, owner_id, title, location, created_at, updated_at, pending)
      VALUES (?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, pending = 1
    ''',
          [
            conversation.id,
            conversation.ownerId,
            conversation.title,
            conversation.location,
            conversation.createdAt.toIso8601String(),
            message.createdAt.toIso8601String(),
          ],
        );
        await _insertMessage(message);
      });

  Future<void> _insertMessage(ChatMessage message) => customStatement(
    '''
    INSERT OR IGNORE INTO messages (id, conversation_id, owner_id, author, source, content, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ''',
    [
      message.id,
      message.conversationId,
      message.ownerId,
      message.author.name,
      message.source.name,
      message.content,
      message.createdAt.toIso8601String(),
    ],
  );

  Future<void> editConversation(
    String ownerId,
    String id,
    String title,
    String location,
  ) async {
    await customStatement(
      '''
      UPDATE conversations SET title = ?, location = ?, updated_at = ?, pending = 1
      WHERE owner_id = ? AND id = ?
    ''',
      [title, location, DateTime.now().toUtc().toIso8601String(), ownerId, id],
    );
  }

  Future<void> deleteConversation(String ownerId, String id) async {
    await customStatement(
      'DELETE FROM conversations WHERE owner_id = ? AND id = ?',
      [ownerId, id],
    );
  }

  Future<void> clearHistory(String ownerId) async {
    await customStatement(
      'DELETE FROM conversations WHERE owner_id = ?',
      [ownerId],
    );
  }

  Future<void> markSynced(Conversation snapshot) => customStatement(
    '''
    UPDATE conversations SET pending = 0 WHERE id = ? AND owner_id = ? AND updated_at = ?
  ''',
    [snapshot.id, snapshot.ownerId, snapshot.updatedAt.toIso8601String()],
  );

  Future<void> importCloud(Conversation remote, List<ChatMessage> incoming) =>
      transaction(() async {
        final local = await conversation(remote.ownerId, remote.id);
        if (local?.pending ?? false) return;
        if (local == null || !local.updatedAt.isAfter(remote.updatedAt)) {
          await customStatement(
            '''
        INSERT INTO conversations (id, owner_id, title, location, created_at, updated_at, pending)
        VALUES (?, ?, ?, ?, ?, ?, 0)
        ON CONFLICT(id) DO UPDATE SET title = excluded.title,
          location = excluded.location, updated_at = excluded.updated_at
      ''',
            [
              remote.id,
              remote.ownerId,
              remote.title,
              remote.location,
              remote.createdAt.toIso8601String(),
              remote.updatedAt.toIso8601String(),
            ],
          );
        }
        for (final message in incoming) {
          if (message.ownerId == remote.ownerId &&
              message.conversationId == remote.id) {
            await _insertMessage(message);
          }
        }
      });
}
