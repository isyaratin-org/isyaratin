import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../services/speech_service.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _query = '';
  Future<void> _sync() async {
    try {
      await ref.read(sessionProvider.notifier).sync();
      if (mounted) showNotice(context, 'Riwayat berhasil disinkronkan.');
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Sinkronisasi belum berhasil. Riwayat lokal tetap tersimpan.',
        );
      }
    }
  }

  Future<bool> _confirmDeleteConversationDialog(
    BuildContext context,
    Conversation conversation,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Hapus Percakapan?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            content: Text(
              'Percakapan "${conversation.title}" dan seluruh pesannya akan dihapus secara permanen.',
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _clearAll(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Hapus Semua Riwayat?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            content: const Text(
              'Semua riwayat percakapan akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.',
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Hapus Semua'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await ref.read(sessionProvider.notifier).clearHistory();
      if (context.mounted) {
        showNotice(context, 'Semua riwayat percakapan berhasil dihapus.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final history = ref.watch(historyProvider(session.ownerId));
    final hasHistory = history.asData?.value.isNotEmpty ?? false;
    return Column(
      children: [
        SectionHeader(
          'Riwayat',
          subtitle: session.syncing
              ? 'Menyinkronkan riwayat...'
              : 'Semua percakapan yang pernah diterjemahkan',
          trailing: (session.user != null || hasHistory)
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (session.user != null)
                      IconButton(
                        tooltip: 'Sinkronkan riwayat',
                        visualDensity: VisualDensity.compact,
                        onPressed: session.syncing ? null : _sync,
                        icon: session.syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync, size: 20),
                      ),
                    if (hasHistory)
                      IconButton(
                        tooltip: 'Hapus semua riwayat',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _clearAll(context),
                        icon: const Icon(
                          Icons.delete_sweep_outlined,
                          size: 22,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                )
              : null,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (session.user != null) {
                await _sync();
              }
              ref.invalidate(historyProvider(session.ownerId));
              await ref.read(historyProvider(session.ownerId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                TextField(
                  onChanged: (text) =>
                      setState(() => _query = text.toLowerCase().trim()),
                  decoration: const InputDecoration(
                    hintText: 'Cari riwayat percakapan...',
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(14),
                      child: DesignIcon('ef544', size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (session.guest)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Mode lokal · Percakapan tamu tidak diunggah ke akun.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                history.when(
                  data: (items) {
                    final filtered = items
                        .where(
                          (c) => '${c.title} ${c.location}'
                              .toLowerCase()
                              .contains(_query),
                        )
                        .toList();
                    if (filtered.isEmpty) {
                      return EmptyState(
                        items.isEmpty
                            ? 'Belum ada percakapan'
                            : 'Tidak ditemukan',
                        items.isEmpty
                            ? 'Mulai percakapan dari menu Kamera atau Voice Note.'
                            : 'Coba kata kunci lain.',
                      );
                    }
                    final today = DateUtils.dateOnly(DateTime.now());
                    final todayItems = filtered
                        .where(
                          (c) =>
                              DateUtils.isSameDay(c.updatedAt.toLocal(), today),
                        )
                        .toList();
                    final olderItems = filtered
                        .where(
                          (c) => !DateUtils.isSameDay(
                            c.updatedAt.toLocal(),
                            today,
                          ),
                        )
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final group in [
                          (label: 'Hari Ini', items: todayItems),
                          (label: 'Sebelumnya', items: olderItems),
                        ])
                          if (group.items.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                group.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            for (final conversation in group.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Dismissible(
                                  key: Key('conv_${conversation.id}'),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) =>
                                      _confirmDeleteConversationDialog(
                                        context,
                                        conversation,
                                      ),
                                  onDismissed: (_) async {
                                    await ref
                                        .read(sessionProvider.notifier)
                                        .deleteConversation(conversation.id);
                                    if (context.mounted) {
                                      showNotice(
                                        context,
                                        'Percakapan berhasil dihapus.',
                                      );
                                    }
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                      size: 24,
                                    ),
                                  ),
                                  child: ConversationTile(
                                    conversation,
                                    onDelete: () async {
                                      final confirmed =
                                          await _confirmDeleteConversationDialog(
                                            context,
                                            conversation,
                                          );
                                      if (confirmed) {
                                        await ref
                                            .read(sessionProvider.notifier)
                                            .deleteConversation(
                                              conversation.id,
                                            );
                                        if (context.mounted) {
                                          showNotice(
                                            context,
                                            'Percakapan berhasil dihapus.',
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                          ],
                      ],
                    );
                  },
                  error: (_, _) => EmptyState(
                    'Riwayat belum bisa dibaca',
                    'Coba muat kembali.',
                    action: OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(historyProvider(session.ownerId)),
                      child: const Text('Coba Lagi'),
                    ),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ConversationTile extends StatelessWidget {
  const ConversationTile(
    this.conversation, {
    super.key,
    this.dark = false,
    this.onDelete,
  });
  final Conversation conversation;
  final bool dark;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: dark ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: dark ? null : Border.all(color: const Color(0xFFE2EBF0)),
      boxShadow: [
        BoxShadow(
          color: dark
              ? AppColors.primary.withValues(alpha: 0.2)
              : const Color(0x06000000),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/history/${conversation.id}'),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.pale,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const DesignIcon('26c8a'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: dark ? Colors.white : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        DesignIcon(dark ? 'd58da' : '75a3c', size: 12),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${DateFormat('dd MMM, HH.mm', 'id_ID').format(conversation.updatedAt.toLocal())} · ${conversation.location.isEmpty ? 'Lokasi belum diisi' : conversation.location}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: dark ? Colors.white : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'Pilihan',
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: dark ? Colors.white70 : AppColors.muted,
                  ),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (val) {
                    if (val == 'delete') {
                      onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.error,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Hapus',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                DesignIcon(dark ? 'f05bc' : 'f900d', size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

class ConversationDetailScreen extends ConsumerWidget {
  const ConversationDetailScreen(this.id, {super.key});
  final String id;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Conversation item,
  ) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditConversationSheet(item),
    );
    if (result == null) return;
    try {
      await ref
          .read(sessionProvider.notifier)
          .editConversation(id, result.$1, result.$2);
    } catch (_) {
      if (context.mounted) {
        showNotice(context, 'Informasi belum tersimpan. Coba lagi.');
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Conversation item,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Hapus Percakapan?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            content: Text(
              'Percakapan "${item.title}" dan seluruh pesan di dalamnya akan dihapus secara permanen.',
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Batal',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await ref.read(sessionProvider.notifier).deleteConversation(id);
      if (context.mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/history');
        }
        showNotice(context, 'Percakapan berhasil dihapus.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerId = ref.watch(sessionProvider.select((s) => s.ownerId));
    final history = ref.watch(historyProvider(ownerId));
    final messages = ref.watch(messagesProvider((ownerId, id)));
    final item = history.asData?.value.where((c) => c.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const DesignIcon('194f4'),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/history'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item?.title ?? 'Percakapan',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (item != null)
              Text(
                item.location.isEmpty ? 'Lokasi belum diisi' : item.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (item != null) ...[
            IconButton(
              tooltip: 'Edit info percakapan',
              onPressed: () => _edit(context, ref, item),
              icon: const DesignIcon('01bcf', size: 17),
            ),
            IconButton(
              tooltip: 'Hapus percakapan',
              onPressed: () => _delete(context, ref, item),
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.when(
                data: (items) => items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: EmptyState(
                          'Tidak ada pesan',
                          'Percakapan ini belum memiliki pesan.',
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          for (final message in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _MessageBubble(message),
                            ),
                        ],
                      ),
                error: (_, _) =>
                    const Center(child: Text('Pesan belum bisa dibaca.')),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: Column(
                children: [
                  FilledButton.icon(
                    onPressed: item == null
                        ? null
                        : () async {
                            try {
                              await ref
                                  .read(sessionProvider.notifier)
                                  .openConversation(id);
                              if (context.mounted) context.go('/camera');
                            } catch (_) {
                              if (context.mounted) {
                                showNotice(
                                  context,
                                  'Percakapan belum bisa dibuka.',
                                );
                              }
                            }
                          },
                    icon: const DesignIcon('b8c3c', size: 18),
                    label: const Text('Lanjutkan Percakapan'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: messages.asData?.value.isNotEmpty != true
                        ? null
                        : () async {
                            final transcript = messages.requireValue
                                .map(
                                  (m) =>
                                      '${m.author == MessageAuthor.signer ? 'Pengguna' : 'Lawan Bicara'}: ${m.content}',
                                )
                                .join('\n\n');
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    '${item?.title ?? 'Percakapan ISYARATIN'}\n\n$transcript',
                              ),
                            );
                            if (context.mounted) {
                              showNotice(
                                context,
                                'Transkrip disalin. Kamu bisa membagikannya lewat aplikasi lain.',
                              );
                            }
                          },
                    icon: const DesignIcon('61a9b', size: 16),
                    label: const Text('Salin Transkrip'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble(this.message);
  final ChatMessage message;
  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final _speech = SpeechService();
  bool _speaking = false;

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  Future<void> _toggleSpeech() async {
    if (_speaking) {
      await _speech.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final started = await _speech.speak(widget.message.content);
    if (mounted) setState(() => _speaking = started);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final signer = message.author == MessageAuthor.signer;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: signer ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: signer ? AppColors.primary : Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!signer)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Lawan Bicara',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              Text(
                message.content,
                style: TextStyle(color: signer ? Colors.white : AppColors.text),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('HH:mm').format(message.createdAt.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      color: signer ? const Color(0xFFD9ECEC) : AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    switch (message.source) {
                      MessageSource.sign => 'Isyarat',
                      MessageSource.voice => 'Voice',
                      MessageSource.typed => 'Teks',
                    },
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: signer ? const Color(0xFFD9ECEC) : AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _speaking ? 'Hentikan pembacaan' : 'Bacakan pesan',
                    onPressed: _toggleSpeech,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: DesignIcon(signer ? 'a3259' : '8c3e3', size: 15),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditConversationSheet extends StatefulWidget {
  const _EditConversationSheet(this.item);
  final Conversation item;
  @override
  State<_EditConversationSheet> createState() => _EditConversationSheetState();
}

class _EditConversationSheetState extends State<_EditConversationSheet> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item.title);
  late final _location = TextEditingController(text: widget.item.location);
  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Info Percakapan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Beri judul dan lokasi supaya percakapan ini mudah dicari nanti.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Judul percakapan'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Judul wajib diisi.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              maxLength: 240,
              decoration: const InputDecoration(labelText: 'Lokasi'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, (_title.text, _location.text));
                }
              },
              child: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    ),
  );
}
