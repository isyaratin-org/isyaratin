import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});
  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  final _text = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .send(_text.text, MessageAuthor.signer);
      if (mounted) {
        _text.clear();
        context.go('/reply');
      }
    } catch (_) {
      if (mounted) showNotice(context, 'Pesan belum tersimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const StepHeader('Langkah 1 · Kirim Isyarat'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Terjemahan Isyarat',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Container(
              height: 350,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFE0EBED),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const DesignIcon('66bd1', size: 40, color: AppColors.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Pengenalan isyarat belum tersedia',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Kamu bisa memulai percakapan dengan mengetik pesan di bawah.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      DesignIcon('a20f6', size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Pesan ketik',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _text,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 5000,
                    enabled: !_saving,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Tulis pesan yang ingin disampaikan...',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving || _text.text.trim().isEmpty ? null : _send,
              icon: const DesignIcon('65602', color: Colors.white),
              label: Text(_saving ? 'Menyimpan...' : 'Tampilkan Pesan'),
            ),
          ],
        ),
      ),
    ],
  );
}

class ReplyScreen extends ConsumerStatefulWidget {
  const ReplyScreen({super.key});
  @override
  ConsumerState<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends ConsumerState<ReplyScreen> {
  final _text = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .send(_text.text, MessageAuthor.partner);
      if (mounted) {
        _text.clear();
        context.push('/avatar');
      }
    } catch (_) {
      if (mounted) showNotice(context, 'Balasan belum tersimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Column(
      children: [
        const StepHeader('Langkah 2 · Balas Pesan'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Voice Note',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.pale,
                            ),
                            child: const DesignIcon('00290', size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Pesan sebelumnya',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        session.signerText ??
                            'Belum ada pesan. Kamu bisa langsung mengetik balasan.',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      DesignIcon('86761', size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ketik balasan untuk ditampilkan sebagai teks. Pemutaran isyarat akan tersedia setelah animasi ditambahkan.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    DesignIcon('8593f', size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Pesan',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 5000,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Ketik balasan di sini...',
                  ),
                ),
                const SizedBox(height: 40),
                OutlinedButton.icon(
                  onPressed: () => showNotice(
                    context,
                    'Rekam suara belum tersedia. Gunakan kolom pesan untuk membalas.',
                  ),
                  icon: const DesignIcon('05f46'),
                  label: const Text('Rekam Voice Note'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving || _text.text.trim().isEmpty
                      ? null
                      : _send,
                  icon: const DesignIcon('65602', color: Colors.white),
                  label: Text(_saving ? 'Menyimpan...' : 'Kirim Balasan'),
                ),
                const SizedBox(height: 40),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DesignIcon('11a6f', size: 16),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Balasan selalu ditampilkan sebagai teks.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF287A57),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AvatarScreen extends ConsumerWidget {
  const AvatarScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reply = ref.watch(sessionProvider.select((s) => s.replyText));
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Langkah 3 · Avatar Merespon',
          style: TextStyle(fontSize: 14),
        ),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const DesignIcon('83c29'),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/reply'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Respon Avatar Isyarat',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Container(
              height: 330,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const RadialGradient(
                  radius: 0.9,
                  colors: [Colors.white, Color(0xFFCDE4E7)],
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DesignIcon('a6ca7', size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Pratinjau avatar · gambar statis',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Image.asset(
                      'assets/figma/58f2b.png',
                      width: 270,
                      fit: BoxFit.contain,
                      semanticLabel: 'Ilustrasi avatar dari desain ISYARATIN',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      DesignIcon('a20f6', size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Teks balasan',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    reply ?? 'Belum ada balasan.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => showNotice(
                context,
                'Animasi isyarat belum tersedia. Balasan saat ini ditampilkan sebagai teks.',
              ),
              icon: const DesignIcon('7916b'),
              label: const Text('Putar Ulang'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => context.go('/camera'),
              icon: const DesignIcon('b6576', color: Colors.white),
              label: const Text('Lanjutkan Percakapan'),
            ),
          ],
        ),
      ),
    );
  }
}
