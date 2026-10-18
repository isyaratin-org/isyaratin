import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';
import 'models.dart';

class SyncRepository {
  SyncRepository(this.database, this.client);
  final LocalDatabase database;
  final SupabaseClient client;

  void _requireOwner(String ownerId) {
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Silakan masuk kembali sebelum menyinkronkan.');
    }
  }

  Future<int> synchronize(String ownerId) async {
    _requireOwner(ownerId);
    final pending = (await database.listConversations(
      ownerId,
    )).where((c) => c.pending).toList();
    for (final item in pending) {
      _requireOwner(ownerId);
      final messages = await database.messages(ownerId, item.id);
      await client.from('conversations').upsert(item.toCloudJson());
      if (messages.isNotEmpty) {
        // Ignore duplicate IDs so retries remain safe with append-only cloud messages.
        await client
            .from('messages')
            .upsert(
              messages.map((m) => m.toCloudJson()).toList(),
              onConflict: 'id',
              ignoreDuplicates: true,
            );
      }
      _requireOwner(ownerId);
      await database.markSynced(item);
    }
    // Pagination avoids silently truncating history at the Data API row limit.
    const pageSize = 100;
    for (var offset = 0; ; offset += pageSize) {
      _requireOwner(ownerId);
      final rows = await client
          .from('conversations')
          .select()
          .eq('owner_id', ownerId)
          .order('id')
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        final conversation = Conversation.fromJson(row);
        final messages = <ChatMessage>[];
        for (var messageOffset = 0; ; messageOffset += pageSize) {
          final batch = await client
              .from('messages')
              .select()
              .eq('owner_id', ownerId)
              .eq('conversation_id', conversation.id)
              .order('created_at')
              .order('id')
              .range(messageOffset, messageOffset + pageSize - 1);
          messages.addAll(batch.map(ChatMessage.fromJson));
          if (batch.length < pageSize) break;
        }
        _requireOwner(ownerId);
        await database.importCloud(conversation, messages);
      }
      if (rows.length < pageSize) break;
    }
    return pending.length;
  }
}
