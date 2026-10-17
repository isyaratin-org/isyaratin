import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isyaratin/data/local_database.dart';
import 'package:isyaratin/data/models.dart';

void main() {
  late LocalDatabase database;
  final time = DateTime.utc(2026, 10, 17, 10);

  Conversation conversation({
    String owner = 'guest',
    bool pending = true,
    String title = 'Percakapan',
    DateTime? updatedAt,
  }) => Conversation(
    id: 'conversation-1',
    ownerId: owner,
    title: title,
    location: '',
    createdAt: time,
    updatedAt: updatedAt ?? time,
    pending: pending,
  );

  ChatMessage message({
    String id = 'message-1',
    String owner = 'guest',
    DateTime? createdAt,
  }) => ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    ownerId: owner,
    author: MessageAuthor.signer,
    source: MessageSource.typed,
    content: 'Saya ingin bertanya.',
    createdAt: createdAt ?? time,
  );

  setUp(() => database = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('persists a conversation and its message atomically', () async {
    await database.saveMessage(conversation(), message());
    expect(
      (await database.listConversations('guest')).single.title,
      'Percakapan',
    );
    expect(
      (await database.messages('guest', 'conversation-1')).single.content,
      'Saya ingin bertanya.',
    );
  });

  test('guest and account histories remain isolated', () async {
    await database.saveMessage(conversation(), message());
    expect(await database.listConversations('user-a'), isEmpty);
    expect(await database.messages('user-a', 'conversation-1'), isEmpty);
    expect(await database.conversation('user-a', 'conversation-1'), isNull);
    await database.editConversation('user-a', 'conversation-1', 'Changed', '');
    expect(
      (await database.listConversations('guest')).single.title,
      'Percakapan',
    );
  });

  test(
    'rejects mismatched owners without leaving a partial conversation',
    () async {
      await expectLater(
        database.saveMessage(conversation(), message(owner: 'other-user')),
        throwsArgumentError,
      );
      expect(await database.listConversations('guest'), isEmpty);
    },
  );

  test('a sync snapshot cannot mark newer edits as synchronized', () async {
    await database.saveMessage(conversation(), message());
    final snapshot = (await database.listConversations('guest')).single;
    await database.saveMessage(
      snapshot,
      message(id: 'message-2', createdAt: time.add(const Duration(minutes: 1))),
    );
    await database.markSynced(snapshot);
    expect((await database.listConversations('guest')).single.pending, isTrue);
    final latest = (await database.listConversations('guest')).single;
    await database.markSynced(latest);
    expect((await database.listConversations('guest')).single.pending, isFalse);
  });

  test('cloud import does not overwrite unsynchronized local edits', () async {
    await database.saveMessage(conversation(), message());
    await database.editConversation(
      'guest',
      'conversation-1',
      'Judul lokal',
      'Kantor',
    );
    await database.importCloud(
      conversation(title: 'Judul cloud', pending: false),
      [],
    );
    expect(
      (await database.listConversations('guest')).single.title,
      'Judul lokal',
    );
  });

  test('repeated cloud imports do not duplicate messages', () async {
    await database.importCloud(conversation(owner: 'user-a', pending: false), [
      message(owner: 'user-a'),
    ]);
    await database.importCloud(conversation(owner: 'user-a', pending: false), [
      message(owner: 'user-a'),
    ]);
    expect((await database.messages('user-a', 'conversation-1')).length, 1);
    expect(
      (await database.listConversations('user-a')).single.pending,
      isFalse,
    );
  });
}
