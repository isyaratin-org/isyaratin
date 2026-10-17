import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/email_verification.dart';

enum AuthMode { login, register, forgot, reset, verify }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.mode = AuthMode.login});
  final AuthMode mode;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _register => widget.mode == AuthMode.register;
  bool get _forgot => widget.mode == AuthMode.forgot;
  bool get _reset => widget.mode == AuthMode.reset;
  bool get _verify => widget.mode == AuthMode.verify;

  String get _title => switch (widget.mode) {
    AuthMode.login => 'Selamat Datang',
    AuthMode.register => 'Daftar Akun',
    AuthMode.forgot => 'Lupa Kata Sandi',
    AuthMode.reset => 'Kata Sandi Baru',
    AuthMode.verify => 'Verifikasi Email',
  };
  String get _action => switch (widget.mode) {
    AuthMode.login => 'Masuk',
    AuthMode.register => 'Daftar',
    AuthMode.forgot => 'Kirim Tautan Pemulihan',
    AuthMode.reset => 'Simpan Kata Sandi',
    AuthMode.verify => 'Verifikasi',
  };

  Future<void> _resendVerification() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await EmailVerificationService(
        client,
      ).resendVerificationEmail(_email.text.trim());
      if (mounted) {
        setState(
          () =>
              _success = 'Email verifikasi telah dikirim ulang. Periksa kotak masuk.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'over_email_send_rate_limit' || 'over_request_rate_limit' =>
              'Terlalu banyak percobaan. Coba beberapa saat lagi.',
            _ => 'Belum bisa mengirim ulang. Periksa data dan coba lagi.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Tidak dapat terhubung. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      switch (widget.mode) {
        case AuthMode.login:
          await client.auth.signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
        case AuthMode.register:
          final result = await client.auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            data: {'full_name': _name.text.trim()},
            emailRedirectTo: AppConfig.authRedirect,
          );
          if (result.session == null && mounted) {
            setState(
              () => _success =
                  'Periksa email untuk memverifikasi akun, lalu masuk.',
            );
          }
        case AuthMode.forgot:
          await client.auth.resetPasswordForEmail(
            _email.text.trim(),
            redirectTo: AppConfig.authRedirect,
          );
          if (mounted) {
            setState(
              () => _success =
                  'Jika email terdaftar, tautan pemulihan akan dikirim.',
            );
          }
        case AuthMode.reset:
          await client.auth.updateUser(
            UserAttributes(password: _password.text),
          );
          ref.read(sessionProvider.notifier).finishRecovery();
        case AuthMode.verify:
          final result = await EmailVerificationService(
            client,
          ).verifyEmailOtp(_email.text.trim(), _code.text);
          if (mounted) {
            setState(() {
              switch (result) {
                case EmailVerificationResult.verified:
                  _success = 'Email berhasil diverifikasi. Silakan masuk.';
                case EmailVerificationResult.alreadyVerified:
                  _success = 'Email sudah diverifikasi. Silakan masuk.';
                case EmailVerificationResult.invalidCode:
                  _error =
                      'Kode verifikasi tidak valid atau sudah kedaluwarsa.';
                case EmailVerificationResult.failure:
                  _error =
                      'Verifikasi belum berhasil. Periksa koneksi lalu coba lagi.';
              }
            });
          }
      }
    } on AuthException catch (error) {
      debugPrint('AuthException [${error.code}]: ${error.message}');
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            'invalid_credentials' => 'Email atau kata sandi belum sesuai.',
            'email_not_confirmed' => 'Verifikasi email terlebih dahulu.',
            'over_email_send_rate_limit' || 'over_request_rate_limit' =>
              'Terlalu banyak percobaan. Coba beberapa saat lagi.',
            'weak_password' => 'Gunakan kata sandi yang lebih kuat.',
            _ => error.message.isNotEmpty
                ? error.message
                : 'Permintaan belum berhasil. Periksa data dan coba lagi.',
          },
        );
      }
    } catch (e) {
      debugPrint('General auth error: $e');
      if (mounted) {
        setState(
          () =>
              _error = 'Tidak dapat terhubung. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint,
    String icon, {
    bool password = false,
    bool email = false,
    bool confirm = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        obscureText: password && _obscure,
        enabled: !_loading,
        maxLength: email
            ? 254
            : password
            ? 128
            : 120,
        keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
        autofillHints: email
            ? const [AutofillHints.email]
            : password
            ? [
                _register || _reset
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ]
            : const [AutofillHints.name],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          prefixIcon: Padding(
            padding: const EdgeInsets.all(14),
            child: DesignIcon(icon, size: 18),
          ),
          suffixIcon: password
              ? IconButton(
                  tooltip: _obscure
                      ? 'Tampilkan kata sandi'
                      : 'Sembunyikan kata sandi',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: const DesignIcon('61f1d', size: 18),
                )
              : null,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return '$label wajib diisi.';
          }
          if (email &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
            return 'Masukkan email yang valid.';
          }
          if (password && (_register || _reset) && value.length < 8) {
            return 'Minimal 8 karakter.';
          }
          if (confirm && value != _password.text) {
            return 'Kata sandi belum sama.';
          }
          return null;
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(supabaseProvider) != null;
    final startupNotice = ref.watch(startupNoticeProvider);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final top = MediaQuery.paddingOf(context).top;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  SizedBox(
                    height:
                        306 +
                        top +
                        (MediaQuery.textScalerOf(context).scale(14) / 14 - 1) *
                            160,
                    child: BrandBackground(
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: EdgeInsets.only(top: top + 64),
                          child: Column(
                            children: [
                              const BrandLogo(),
                              const SizedBox(height: 16),
                              const Text(
                                'ISYARATIN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'Menjembatani Komunikasi, Mewujudkan Inklusi',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xB3FFFFFF),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Text(
                                    _title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Stack(
                    children: [
                      const SizedBox(
                        height: 114,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0xFF208E98)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: SurfaceCard(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _form,
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_register) ...[
                                    _field(
                                      'Nama lengkap',
                                      _name,
                                      'Masukkan nama lengkap',
                                      '4b72d',
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (!_reset) ...[
                                    _field(
                                      'Email',
                                      _email,
                                      'Masukkan email',
                                      '7b130',
                                      email: true,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_verify) ...[
                                    _field(
                                      'Kode verifikasi',
                                      _code,
                                      'Masukkan kode dari email',
                                      'c2efd',
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _loading
                                            ? null
                                            : _resendVerification,
                                        child: const Text(
                                          'Kirim ulang kode',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (!_forgot && !_verify) ...[
                                    _field(
                                      'Password',
                                      _password,
                                      _register || _reset
                                          ? 'Minimal 8 karakter'
                                          : 'Masukkan Password',
                                      '7a418',
                                      password: true,
                                    ),
                                  ],
                                  if (_register || _reset) ...[
                                    const SizedBox(height: 16),
                                    _field(
                                      'Konfirmasi password',
                                      _confirmation,
                                      'Ulangi kata sandi',
                                      '7a418',
                                      password: true,
                                      confirm: true,
                                    ),
                                  ],
                                  if (widget.mode == AuthMode.login)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () => context.go(
                                                '/forgot-password',
                                              ),
                                        child: const Text(
                                          'Lupa Kata Sandi?',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  if (!configured)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        startupNotice ??
                                            'Login akan tersedia setelah Supabase dihubungkan. Kamu tetap bisa mencoba mode lokal.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  if (_error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  if (_success != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        _success!,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  FilledButton.icon(
                                    onPressed: configured && !_loading
                                        ? _submit
                                        : null,
                                    icon: _loading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : DesignIcon(
                                            _register ? 'bfe62' : 'c2efd',
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                    label: Text(_action),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!_reset)
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _register
                              ? 'Sudah punya akun?'
                              : _forgot
                              ? 'Sudah ingat kata sandi?'
                              : _verify
                              ? 'Sudah punya akun?'
                              : 'Belum punya akun?',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => context.go(
                                  _register || _forgot || _verify
                                      ? '/login'
                                      : '/register',
                                ),
                          child: Text(
                            _register || _forgot || _verify ? 'Masuk' : 'Daftar',
                          ),
                        ),
                      ],
                    ),
                  if (!_reset)
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () =>
                                ref.read(sessionProvider.notifier).enterGuest(),
                      child: const Text('Coba tanpa akun'),
                    ),
                  SizedBox(height: MediaQuery.paddingOf(context).bottom + 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
