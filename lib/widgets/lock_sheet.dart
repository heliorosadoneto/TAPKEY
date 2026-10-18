import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../state.dart';
import '../theme.dart';
import 'island.dart';
import 'mascot.dart';

/// Bottom sheet com as ações Bloquear / Desbloquear o notebook.
Future<void> showLockSheet(BuildContext context, AppState state) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF131316),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _LockSheet(state: state),
  );
}

class _LockSheet extends StatefulWidget {
  final AppState state;
  const _LockSheet({required this.state});

  @override
  State<_LockSheet> createState() => _LockSheetState();
}

class _LockSheetState extends State<_LockSheet> {
  bool _busy = false;
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_r);
    s.refreshSession();
  }

  @override
  void dispose() {
    s.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  Future<void> _lock() async {
    setState(() => _busy = true);
    mascotController.working(true);
    final (ok, msg) = await s.lockNotebook();
    mascotController.working(false);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      mascotController.proud();
      island.show('Notebook bloqueado', kind: IslandKind.lock);
      Navigator.pop(context);
    } else {
      mascotController.error();
      island.show(msg, kind: IslandKind.error, duration: const Duration(seconds: 4));
    }
  }

  Future<void> _unlock() async {
    if (!s.unlockAllowed) {
      mascotController.error();
      island.show('Desbloqueio desativado no TAPKEY Desktop', kind: IslandKind.error, duration: const Duration(seconds: 4));
      return;
    }
    // Biometria ou PIN/padrão/senha do aparelho
    bool authed = false;
    try {
      authed = await LocalAuthentication().authenticate(
        localizedReason: 'Confirme que é você para desbloquear o notebook',
        biometricOnly: false,
      );
    } catch (_) {
      authed = false;
    }
    if (!authed) {
      mascotController.error();
      island.show('Autenticação cancelada', kind: IslandKind.error);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    mascotController.working(true);
    final (ok, msg) = await s.unlockNotebook();
    mascotController.working(false);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      mascotController.finished();
      island.show(msg, kind: IslandKind.success);
      Navigator.pop(context);
    } else {
      mascotController.error();
      island.show(msg, kind: IslandKind.error, duration: const Duration(seconds: 4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = s.locked;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            Icon(locked ? Icons.lock : Icons.lock_open, color: locked ? kAccent : kMuted),
            const SizedBox(width: 10),
            Text(locked ? 'Notebook bloqueado' : 'Notebook desbloqueado',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || !s.connected ? null : _lock,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Bloquear'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !s.connected ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Desbloquear'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            s.unlockAllowed
                ? 'Para desbloquear, o celular pede biometria ou PIN.'
                : 'Desbloqueio desativado. Ative "Permitir desbloqueio pelo celular" no TAPKEY Desktop.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}
