import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'agent_service.dart';
import 'theme.dart';
import 'widgets/mascot.dart';

/// Janela compacta: status, QR de pareamento e poucos botões.
class HomePage extends StatefulWidget {
  final AgentService agent;
  final VoidCallback onQuit;
  const HomePage({super.key, required this.agent, required this.onQuit});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showToken = false;
  bool _showClients = false;
  AgentService get a => widget.agent;

  @override
  void initState() {
    super.initState();
    a.addListener(_rebuild);
  }

  @override
  void dispose() {
    a.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  Future<void> _regen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Gerar novo token?', style: TextStyle(fontSize: 16)),
        content: const Text('O celular atual para de funcionar até escanear o novo QR.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gerar')),
        ],
      ),
    );
    if (ok == true) {
      await a.regenerateToken();
      _toast('Novo token gerado. Escaneie o QR de novo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = a.running;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          children: [
            _header(up),
            const SizedBox(height: 8),
            _pair(up),
            const SizedBox(height: 8),
            _field('Endereço', a.address, false),
            const SizedBox(height: 6),
            _field('Token', _showToken ? a.token : '•' * 16, true),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: a.busy ? null : (up ? a.stopAgent : a.startAgent),
                  icon: a.busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(up ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                  label: Text(up ? 'Parar agente' : 'Iniciar agente'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _regen,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Novo token'),
                ),
              ),
            ]),
            if (a.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(a.error!, style: const TextStyle(color: kErr, fontSize: 11)),
              ),
            const SizedBox(height: 6),
            _clients(),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Iniciar com o sistema', style: TextStyle(fontSize: 13)),
              value: a.autostart,
              onChanged: (v) => a.setAutostart(v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Permitir desbloqueio pelo celular', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Exige token, desafio de uso único e biometria/PIN no celular',
                  style: TextStyle(fontSize: 11, color: kMuted)),
              value: a.allowUnlock,
              onChanged: (v) => a.setAllowUnlock(v),
            ),
          ]
              .animate(interval: 60.ms)
              .fadeIn(duration: 350.ms)
              .slideY(begin: 0.1, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _header(bool up) => Row(children: [
        Mascot(connected: up, size: 40),
        const SizedBox(width: 10),
        const Text('TAPKEY',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 3.5, color: kAccent)),
        const Spacer(),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: up ? kOk : kErr,
            boxShadow: [BoxShadow(color: (up ? kOk : kErr).withValues(alpha: 0.7), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 6),
        Text(up ? 'Rodando' : 'Parado',
            style: TextStyle(color: up ? kOk : kErr, fontSize: 12, fontWeight: FontWeight.w500)),
        IconButton(
          tooltip: 'Sair',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onQuit,
          icon: const Icon(Icons.power_settings_new, size: 18, color: kMuted),
        ),
      ]);

  Widget _pair(bool up) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kCardTop, kCard]),
        ),
        child: Column(children: [
          Opacity(
            opacity: up ? 1 : 0.35,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                data: a.pairUri,
                size: 156,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0C)),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B0B0C)),
              ),
            ).animate(key: ValueKey(a.token)).fadeIn().scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack),
          ),
          const SizedBox(height: 6),
          const Text('No celular: Configurações > Escanear QR',
              style: TextStyle(color: kMuted, fontSize: 11)),
        ]),
      );

  Widget _field(String label, String value, bool isToken) => Container(
        height: 38,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111114),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorder),
        ),
        child: Row(children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(color: kMuted, fontSize: 11))),
          Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
          ),
          if (isToken)
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: _showToken ? 'Ocultar' : 'Mostrar',
              onPressed: () => setState(() => _showToken = !_showToken),
              icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility, color: kMuted),
            ),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Copiar',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: isToken ? a.token : value));
              _toast('$label copiado');
            },
            icon: const Icon(Icons.copy, color: kMuted),
          ),
        ]),
      );

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 10) return 'agora';
    if (s < 60) return 'há $s s';
    if (s < 3600) return 'há ${s ~/ 60} min';
    if (s < 86400) return 'há ${s ~/ 3600} h';
    return 'há ${s ~/ 86400} d';
  }

  Widget _clients() {
    final n = a.clients.length;
    final live = a.clients.where((c) => DateTime.now().difference(c.lastSeen).inSeconds < 15).length;
    return Column(children: [
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _showClients = !_showClients),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(children: [
            Icon(Icons.smartphone, size: 16, color: live > 0 ? kOk : kMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                n == 0
                    ? 'Nenhum celular conectou ainda'
                    : '$n ${n == 1 ? 'celular' : 'celulares'} · $live online · ${a.totalLaunches} aberturas',
                style: const TextStyle(fontSize: 12.5, color: kMuted),
              ),
            ),
            Icon(_showClients ? Icons.expand_less : Icons.expand_more, size: 18, color: kMuted),
          ]),
        ),
      ),
      if (_showClients)
        for (final c in a.clients.take(5))
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 4, 2),
            child: Row(children: [
              Expanded(
                child: Text(
                    c.lastApp.isEmpty ? c.ip : '${c.ip} · ${c.lastApp}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ),
              Text(_ago(c.lastSeen), style: const TextStyle(color: kMuted, fontSize: 11)),
            ]),
          ),
      if (_showClients)
        for (final e in a.events.take(5))
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 4, 2),
            child: Row(children: [
              Icon(e.event.contains('Desbloq') ? Icons.lock_open : Icons.lock_outline,
                  size: 12, color: e.ok ? kMuted : kErr),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${e.event} · ${e.ip}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: e.ok ? Colors.white : kErr)),
              ),
              Text(_ago(e.time), style: const TextStyle(color: kMuted, fontSize: 11)),
            ]),
          ),
    ]);
  }
}
