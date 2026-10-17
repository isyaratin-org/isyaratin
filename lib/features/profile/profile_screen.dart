import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editAccount(BuildContext context, WidgetRef ref) async {
    final client = ref.read(supabaseProvider);
    final user = ref.read(sessionProvider).user;
    if (client == null || user == null) {
      showNotice(context, 'Masuk ke akun untuk mengubah informasi profil.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AccountDialog(client),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Column(
      children: [
        const SectionHeader(
          'Profil',
          subtitle: 'Kelola akun dan pengaturan aplikasi Anda.',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE6F5F7), Color(0xFFF0F9FA)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.guest ? 'Pengguna lokal' : session.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.user?.email ??
                          'Riwayat tersimpan di perangkat ini.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1F2F5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const DesignIcon('9d65c', size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              session.guest
                                  ? 'Mode lokal'
                                  : session.user?.emailConfirmedAt != null
                                  ? 'Email Terverifikasi'
                                  : 'Email Belum Terverifikasi',
                              style: const TextStyle(
                                color: Color(0xFF0E636B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Akun', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsTile(
                      'Pengaturan Akun',
                      'Informasi akun nama dan email.',
                      'f3c08',
                      onTap: () => _editAccount(context, ref),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    _SettingsTile(
                      'Ubah sandi',
                      'Ganti kata sandi akun.',
                      'b09b2',
                      onTap: () {
                        final client = ref.read(supabaseProvider);
                        if (client == null || session.user == null) {
                          showNotice(
                            context,
                            'Masuk ke akun untuk mengubah kata sandi.',
                          );
                          return;
                        }
                        showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _AccountDialog(client, passwordMode: true),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Tentang', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsTile(
                      'Tentang Aplikasi',
                      'Cari tahu tentang aplikasi',
                      'd1634',
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'ISYARATIN',
                        applicationVersion: '0.1.0',
                        applicationIcon: const BrandLogo(),
                        children: [
                          const Text(
                            'Menjembatani Komunikasi, Mewujudkan Inklusi.\n\n'
                            'Fondasi asisten komunikasi dua arah. Pengenalan isyarat, rekam suara, '
                            'dan animasi avatar masih dalam pengembangan.',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    const _SettingsTile('Versi Aplikasi', 'v0.1.0', '27ddc'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(sessionProvider.notifier).signOut();
                  } catch (_) {
                    if (context.mounted) {
                      showNotice(context, 'Belum bisa keluar. Coba lagi.');
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: session.guest
                      ? AppColors.primary
                      : Colors.red,
                  side: BorderSide(
                    color: session.guest ? AppColors.primary : Colors.red,
                  ),
                ),
                icon: DesignIcon(
                  '587c8',
                  size: 18,
                  color: session.guest ? AppColors.primary : Colors.red,
                ),
                label: Text(
                  session.guest ? 'Masuk atau Daftar' : 'Keluar dari Akun',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile(this.title, this.subtitle, this.asset, {this.onTap});
  final String title, subtitle, asset;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.pale,
        shape: BoxShape.circle,
      ),
      child: DesignIcon(asset, size: 18),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 12, color: AppColors.muted),
    ),
    trailing: onTap == null ? null : const DesignIcon('9b74c', size: 18),
    onTap: onTap,
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog(this.client, {this.passwordMode = false});
  final SupabaseClient client;
  final bool passwordMode;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _form = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: widget.passwordMode
        ? ''
        : widget.client.auth.currentUser?.userMetadata?['full_name']
                  as String? ??
              '',
  );
  final _confirmation = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.passwordMode) {
        await widget.client.auth.updateUser(
          UserAttributes(password: _value.text),
        );
      } else {
        final user = widget.client.auth.currentUser!;
        await widget.client
            .from('profiles')
            .update({
              'full_name': _value.text.trim(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', user.id);
        await widget.client.auth.updateUser(
          UserAttributes(data: {'full_name': _value.text.trim()}),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Perubahan belum berhasil. Periksa koneksi dan coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.passwordMode ? 'Ubah kata sandi' : 'Informasi akun'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.passwordMode) ...[
              Text(widget.client.auth.currentUser?.email ?? ''),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _value,
              enabled: !_saving,
              obscureText: widget.passwordMode,
              maxLength: widget.passwordMode ? 128 : 120,
              decoration: InputDecoration(
                labelText: widget.passwordMode
                    ? 'Kata sandi baru'
                    : 'Nama lengkap',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Wajib diisi.'
                  : widget.passwordMode && value.length < 8
                  ? 'Minimal 8 karakter.'
                  : null,
            ),
            if (widget.passwordMode) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmation,
                enabled: !_saving,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Konfirmasi kata sandi',
                ),
                validator: (value) =>
                    value != _value.text ? 'Kata sandi belum sama.' : null,
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      TextButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
      ),
    ],
  );
}
