import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../history/history_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final history = ref.watch(historyProvider);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        BrandBackground(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    BrandLogo(),
                    SizedBox(width: 20),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ISYARATIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                SurfaceCard(
                  color: const Color(0xFFEEF8F8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Halo, ${session.displayName}!',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ada yang bisa dibantu hari ini?',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ActionCard(
                        title: 'Mulai Isyarat',
                        subtitle: 'Terjemahkan ke teks',
                        asset: 'cf6dd',
                        dark: true,
                        onTap: () {
                          ref.read(sessionProvider.notifier).newConversation();
                          context.go('/camera');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        title: 'Voice Note',
                        subtitle: 'Ucapan ke isyarat',
                        asset: '981be',
                        onTap: () {
                          ref.read(sessionProvider.notifier).newConversation();
                          context.go('/reply');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Riwayat Terbaru',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/history'),
                    child: const Text(
                      'Lihat Semua ›',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              history.when(
                data: (items) => items.isEmpty
                    ? EmptyState(
                        'Mulai percakapan pertamamu',
                        'Percakapan yang kamu simpan akan muncul di sini.',
                        action: OutlinedButton(
                          onPressed: () => context.go('/camera'),
                          child: const Text('Mulai Percakapan'),
                        ),
                      )
                    : Column(
                        children: [
                          for (final item in items.take(2))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ConversationTile(item, dark: true),
                            ),
                        ],
                      ),
                error: (_, _) => const EmptyState(
                  'Riwayat belum bisa dibuka',
                  'Coba buka kembali halaman ini.',
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
              if (session.guest)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Mode lokal · Riwayat tersimpan di perangkat ini.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.onTap,
    this.dark = false,
  });
  final String title, subtitle, asset;
  final VoidCallback onTap;
  final bool dark;
  @override
  Widget build(BuildContext context) => Material(
    color: dark ? AppColors.primary : Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? Colors.white : AppColors.pale,
                borderRadius: BorderRadius.circular(14),
              ),
              child: DesignIcon(asset),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: dark ? const Color(0xFFE6F6F7) : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
