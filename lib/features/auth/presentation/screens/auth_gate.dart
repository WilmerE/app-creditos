import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/network/supabase_delta_sync.dart';
import '../../../../core/notifications/local_system_notification_service.dart';
import '../../../../injection_container.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import 'login_screen.dart';

/// Blocks protected screens until Supabase has restored a local session.
/// Session restoration is performed from local secure storage by Supabase,
/// so this gate does not require network access for existing sessions.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _sync = getIt<SupabaseDeltaSync>();
  StreamSubscription? _authSubscription;
  String? _checkedUserId;
  bool? _accountAllowed;
  bool _checkingAccount = false;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_handleSyncChange);
    _authSubscription = _sync.authStateChanges?.listen((event) {
      if (event.session != null) {
        LocalSystemNotificationService.instance.requestAndroidPermission();
      }
      unawaited(_checkAccount());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sync.currentUser != null) {
        LocalSystemNotificationService.instance.requestAndroidPermission();
      }
      unawaited(_checkAccount());
    });
  }

  @override
  void dispose() {
    _sync.removeListener(_handleSyncChange);
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  void _handleSyncChange() {
    final userId = _sync.currentUser?.id;
    if (userId != _checkedUserId && !_checkingAccount) {
      unawaited(_checkAccount());
    }
  }

  Future<void> _checkAccount() async {
    final userId = _sync.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _checkedUserId = null;
        _accountAllowed = null;
        _checkingAccount = false;
      });
      return;
    }
    if (_checkingAccount || _checkedUserId == userId) return;
    setState(() {
      _checkingAccount = true;
      _accountAllowed = null;
    });
    final allowed = await _sync.isAccountAllowedLocally(userId);
    if (!mounted) return;
    final latestUserId = _sync.currentUser?.id;
    if (latestUserId != userId) {
      setState(() => _checkingAccount = false);
      if (latestUserId != null) unawaited(_checkAccount());
      return;
    }
    setState(() {
      _checkedUserId = userId;
      _accountAllowed = allowed;
      _checkingAccount = false;
    });
    if (allowed) unawaited(_sync.synchronize());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sync,
      builder: (context, _) {
        final user = _sync.currentUser;
        if (!_sync.isConfigured || user == null) {
          return LoginScreen(sync: _sync);
        }
        if (_checkingAccount || _checkedUserId != user.id) {
          return const _AuthLoadingScreen();
        }
        if (_accountAllowed != true) {
          return _AccountMismatchScreen(sync: _sync);
        }
        return const DashboardScreen();
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AccountMismatchScreen extends StatelessWidget {
  const _AccountMismatchScreen({required this.sync});

  final SupabaseDeltaSync sync;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 52,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Estos datos locales pertenecen a otra cuenta.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Cierra sesión e inicia con la cuenta vinculada a este dispositivo. '
                'Los datos locales se mantienen protegidos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: sync.signOut,
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
