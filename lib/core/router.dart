import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/conversation/conversation_screens.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import 'providers.dart';
import 'theme.dart';
import 'widgets.dart';

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(
    sessionProvider.select((s) => (s.canEnter, s.recovering)),
    (_, _) => refresh.refresh(),
  );
  final router = GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, route) {
      final session = ref.read(sessionProvider);
      final path = route.uri.path;
      final authPage = [
        '/login',
        '/register',
        '/forgot-password',
        '/reset-password',
        '/verify-email',
        '/auth/callback',
      ].contains(path);
      if (session.recovering) {
        return path == '/reset-password' ? null : '/reset-password';
      }
      if (!session.canEnter) {
        if (path == '/reset-password' || path == '/auth/callback') {
          return '/login';
        }
        return authPage ? null : '/login';
      }
      return authPage ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/register',
        builder: (_, _) => const AuthScreen(mode: AuthMode.register),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const AuthScreen(mode: AuthMode.forgot),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const AuthScreen(mode: AuthMode.reset),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, _) => const AuthScreen(mode: AuthMode.verify),
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      ShellRoute(
        builder: (_, state, child) =>
            AppShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/camera', builder: (_, _) => const CameraScreen()),
          GoRoute(path: '/reply', builder: (_, _) => const ReplyScreen()),
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
      GoRoute(path: '/avatar', builder: (_, _) => const AvatarScreen()),
      GoRoute(
        path: '/history/:id',
        builder: (_, state) =>
            ConversationDetailScreen(state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (context, _) => Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              'Halaman tidak ditemukan',
              'Kembali ke beranda untuk melanjutkan.',
              action: FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Ke Beranda'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  static const _items = [
    (path: '/home', label: 'Beranda', asset: '15405'),
    (path: '/camera', label: 'Kamera', asset: '66bd1'),
    (path: '/reply', label: 'Voice Note', asset: 'afa96'),
    (path: '/history', label: 'Riwayat', asset: 'c8a8d'),
    (path: '/profile', label: 'Profil', asset: 'd64c0'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(bottom: false, child: child),
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFD9E3E7))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SizedBox(
            height: 66 + (MediaQuery.textScalerOf(context).scale(11) - 11) * 4,
            child: Row(
              children: [
                for (final item in _items)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Semantics(
                        selected: path == item.path,
                        button: true,
                        label: item.label,
                        child: Tooltip(
                          message: item.label,
                          child: Material(
                            color: path == item.path
                                ? AppColors.primary
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => context.go(item.path),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DesignIcon(
                                        item.asset,
                                        size: 22,
                                        color: path == item.path
                                            ? Colors.white
                                            : AppColors.text,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.label,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.2,
                                          fontWeight: path == item.path
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: path == item.path
                                              ? Colors.white
                                              : AppColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
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
  );
}
