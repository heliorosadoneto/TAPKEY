import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cursor.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/approval_sheet.dart';
import '../widgets/island.dart';
import '../widgets/mascot.dart';

/// Aba "Cursor": estado das sessões, aprovações pendentes, instruções e saída do CLI.
class CursorScreen extends StatelessWidget {
  final AppState state;
  const CursorScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final c = state.cursor;
    return ListenableBuilder(
      listenable: Listenable.merge([c, state]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text(
                'Cursor',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (!state.connected)
                _info(
                  Icons.link_off,
                  'Notebook desconectado',
                  'Conecte-se ao notebook para ver o Cursor.',
                )
              else if (c.disabledKnown == true)
                _info(
                  Icons.extension_off_outlined,
                  'Integração desativada',
                  'No notebook, abra o TAPKEY Desktop > Segurança e Cursor e ligue "Integrar com o Cursor". Nada é instalado no Cursor sem você confirmar o diff.',
                )
              else if (c.disabledKnown == null)
                _info(Icons.sync, 'Conectando…', 'Aguardando o notebook.')
              else ...[
                for (final a in c.approvals)
                  ApprovalCard(state: state, approval: a),
                _Sessions(state: state),
                if (c.queue.isNotEmpty) _Queue(c: c),
                if (c.cli['running'] == true || c.cliLines.isNotEmpty)
                  _CliPanel(c: c),
                if (c.workspaces.isNotEmpty) _Workspaces(state: state),
                const SizedBox(height: 8),
                Text(
                  c.approvalsEnabled
                      ? 'Aprovações pelo celular: ligadas. Mantenha este app aberto para receber os pedidos.'
                      : 'Aprovações pelo celular: desligadas no Desktop.',
                  style: const TextStyle(color: kMuted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _info(IconData i, String t, String s) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: kBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(i, color: kMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(s, style: const TextStyle(color: kMuted, fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Sessions extends StatelessWidget {
  final AppState state;
  const _Sessions({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = state.cursor;
    if (c.sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kBorder),
        ),
        child: const Row(
          children: [
            Icon(Icons.bedtime_outlined, color: kMuted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nenhuma sessão ativa. Abra um chat do agente no Cursor.',
                style: TextStyle(color: kMuted),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [for (final s in c.sessions) _SessionCard(state: state, s: s)],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final AppState state;
  final CursorSession s;
  const _SessionCard({required this.state, required this.s});

  Color get _color => switch (s.state) {
    'working' || 'thinking' => kAccent,
    'waiting' => const Color(0xFFFBBF24),
    'finished' => kOk,
    'error' => kErr,
    _ => kMuted,
  };

  @override
  Widget build(BuildContext context) {
    final c = state.cursor;
    final busy = s.state == 'working' || s.state == 'thinking';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _color.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pulse(color: _color, active: busy || s.state == 'waiting'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.folder,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                stateLabel(s.state),
                style: TextStyle(
                  color: _color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (s.lastTool.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Última ferramenta: ${s.lastTool}',
              style: const TextStyle(color: kMuted, fontSize: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (s.queued > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${s.queued} instrução(ões) na fila',
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (c.instructionsEnabled)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        showInstructionDialog(context, state, session: s),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Instrução'),
                  ),
                ),
              if (c.instructionsEnabled) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final (ok, msg) = await c.openWorkspace(s.workspaceId);
                    island.show(
                      msg,
                      kind: ok ? IslandKind.cursor : IslandKind.error,
                    );
                    ok ? mascotController.happy() : mascotController.error();
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Abrir no Cursor'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  final Color color;
  final bool active;
  const _Pulse({required this.color, required this.active});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.animateTo(0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: .35 + .4 * _c.value),
            blurRadius: 4 + 10 * _c.value,
          ),
        ],
      ),
    ),
  );
}

class _Queue extends StatelessWidget {
  final CursorService c;
  const _Queue({required this.c});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: kBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fila de instruções',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final q in c.queue)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${q.folder}: ${q.preview}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kMuted, fontSize: 12.5),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: kMuted),
                onPressed: () => c.cancelQueued(q.id),
              ),
            ],
          ),
        const Text(
          'Entregue quando o Cursor terminar a execução atual, no mesmo chat.',
          style: TextStyle(color: kMuted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _CliPanel extends StatelessWidget {
  final CursorService c;
  const _CliPanel({required this.c});

  @override
  Widget build(BuildContext context) {
    final running = c.cli['running'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  running
                      ? 'Cursor CLI rodando (${c.cli['folder'] ?? ''})'
                      : 'Cursor CLI terminou',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (running)
                TextButton(onPressed: c.cancelCli, child: const Text('Parar')),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B0C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                c.cliLines.isEmpty ? '…' : c.cliLines.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Workspaces extends StatelessWidget {
  final AppState state;
  const _Workspaces({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = state.cursor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Projetos vistos pelo Cursor',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in c.workspaces)
                ActionChip(
                  avatar: const Icon(Icons.folder_open, size: 16),
                  label: Text(w.name),
                  onPressed: () async {
                    final (ok, msg) = await c.openWorkspace(w.id);
                    island.show(
                      msg,
                      kind: ok ? IslandKind.cursor : IslandKind.error,
                    );
                    ok ? mascotController.happy() : mascotController.error();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Toque para abrir no Cursor. Só aparecem pastas que o Cursor já abriu neste notebook.',
            style: TextStyle(color: kMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Diálogo "Enviar instrução": na conversa do Cursor (hook stop) ou no Cursor CLI.
Future<void> showInstructionDialog(
  BuildContext context,
  AppState state, {
  required CursorSession session,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF131316),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _InstructionForm(state: state, session: session),
    ),
  );
}

class _InstructionForm extends StatefulWidget {
  final AppState state;
  final CursorSession session;
  const _InstructionForm({required this.state, required this.session});

  @override
  State<_InstructionForm> createState() => _InstructionFormState();
}

class _InstructionFormState extends State<_InstructionForm> {
  final _text = TextEditingController();
  bool _cli = false;
  bool _busy = false;

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    final (ok, msg) = await widget.state.cursor.sendInstruction(
      t,
      viaCli: _cli,
      sessionId: widget.session.id,
      workspaceId: widget.session.workspaceId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    island.show(
      msg,
      kind: ok ? IslandKind.cursor : IslandKind.error,
      duration: const Duration(seconds: 3),
    );
    ok ? mascotController.proud() : mascotController.error();
    HapticFeedback.mediumImpact();
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.state.cursor;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instrução para ${widget.session.folder}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 5,
              minLines: 3,
              maxLength: 4000,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'O que o Cursor deve fazer em seguida?',
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(
                  value: false,
                  label: Text('No chat do Cursor'),
                  icon: Icon(Icons.chat_bubble_outline, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: const Text('Cursor CLI'),
                  icon: const Icon(Icons.terminal, size: 16),
                  enabled: c.cliAvailable,
                ),
              ],
              selected: {_cli},
              onSelectionChanged: (v) => setState(() => _cli = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              _cli
                  ? 'Roda "agent -p" na pasta do projeto, sem --force: ações que exigem aprovação não são executadas. A saída aparece aqui.'
                  : 'Entra na fila e é enviada no MESMO chat quando o Cursor terminar a execução atual (hook stop).',
              style: const TextStyle(color: kMuted, fontSize: 11.5),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Enviar'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
