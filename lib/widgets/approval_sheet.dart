import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../cursor.dart';
import '../state.dart';
import '../theme.dart';
import 'island.dart';
import 'mascot.dart';

bool _sheetOpen = false;

/// Abre (uma vez) a folha de aprovação para um pedido do Cursor.
Future<void> showApprovalSheet(
  BuildContext context,
  AppState state,
  CursorApproval a,
) async {
  if (_sheetOpen) return;
  _sheetOpen = true;
  try {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: const Color(0xFF131316),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ApprovalCard(state: state, approval: a, sheet: true),
    );
  } finally {
    _sheetOpen = false;
  }
}

/// Cartão de aprovação: comando completo, contagem regressiva, Permitir (com biometria/PIN) e Negar.
class ApprovalCard extends StatefulWidget {
  final AppState state;
  final CursorApproval approval;
  final bool sheet;
  const ApprovalCard({
    super.key,
    required this.state,
    required this.approval,
    this.sheet = false,
  });

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  Timer? _t;
  bool _busy = false;
  CursorApproval get a => widget.approval;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => mounted ? setState(() {}) : null,
    );
    widget.state.cursor.addListener(_gone);
  }

  @override
  void dispose() {
    _t?.cancel();
    widget.state.cursor.removeListener(_gone);
    super.dispose();
  }

  // some quando a aprovação já foi resolvida (aqui, no Cursor ou por tempo)
  void _gone() {
    if (!mounted) return;
    if (!widget.state.cursor.approvals.any((x) => x.id == a.id) &&
        widget.sheet) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _decide(bool allow) async {
    if (_busy) return;
    if (allow) {
      var ok = false;
      try {
        ok = await LocalAuthentication().authenticate(
          localizedReason:
              'Confirme que é você para permitir esta ação no notebook',
          biometricOnly: false,
        );
      } catch (_) {}
      if (!ok) {
        HapticFeedback.heavyImpact();
        island.show('Autenticação cancelada', kind: IslandKind.error);
        mascotController.error();
        return;
      }
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final (ok, msg) = await widget.state.cursor.decide(a, allow);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      island.show(msg, kind: allow ? IslandKind.success : IslandKind.lock);
      allow ? mascotController.happy() : mascotController.wink();
    } else {
      island.show(
        msg,
        kind: IslandKind.error,
        duration: const Duration(seconds: 4),
      );
      mascotController.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = (a.expires - DateTime.now().millisecondsSinceEpoch / 1000)
        .clamp(0, 600)
        .toDouble();
    final total = (a.expires - a.created).clamp(1, 600).toDouble();
    final card = Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, widget.sheet ? 18 : 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                a.kind == 'shell'
                    ? Icons.terminal_rounded
                    : Icons.extension_outlined,
                color: kAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cursor pede aprovação',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${left.ceil()} s',
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${a.folder} · ${a.title}',
            style: const TextStyle(color: kMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: left / total,
              minHeight: 3,
              backgroundColor: kBorder,
              color: kAccent,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B0C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                a.command,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (a.denyOnly) ...[
            const SizedBox(height: 8),
            const Text(
              'Comando longo demais: por segurança só é possível negar aqui. Para permitir, confirme no Cursor.',
              style: TextStyle(color: kErr, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _decide(false),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Negar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: kErr,
                    side: const BorderSide(color: kErr),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || a.denyOnly ? null : () => _decide(true),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Permitir'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Sem resposta, o Cursor volta a perguntar na tela do notebook.',
            style: TextStyle(color: kMuted, fontSize: 11),
          ),
        ],
      ),
    );
    if (widget.sheet) return SafeArea(child: card);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAccent.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(color: kAccent.withValues(alpha: .08), blurRadius: 18),
        ],
      ),
      child: card,
    );
  }
}
