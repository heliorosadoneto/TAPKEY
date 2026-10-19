import 'dart:io' show Platform;

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

  Widget _sw(String title, String sub, bool v, ValueChanged<bool>? on, {bool danger = false}) => SwitchListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    title: Text(title, style: TextStyle(fontSize: 13, color: danger && v ? kErr : null)),
    subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: kMuted)),
    value: v,
    onChanged: on,
  );

  Widget _security() {
    final secure = a.tls;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // TAPKEY_EXPAND_SECURITY=1 abre o painel já expandido (usado para gerar capturas de tela)
        initiallyExpanded: Platform.environment['TAPKEY_EXPAND_SECURITY'] == '1',
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(secure ? Icons.lock_outline : Icons.warning_amber_rounded, size: 18, color: secure ? kOk : kErr),
        title: const Text('Segurança e Cursor', style: TextStyle(fontSize: 13)),
        subtitle: Text(
          secure ? 'TLS com certificado fixado no celular' : 'HTTP legado: sem criptografia',
          style: TextStyle(fontSize: 11, color: secure ? kMuted : kErr),
        ),
        children: [
          _sw(
            'Permitir desbloqueio pelo celular',
            'Token, desafio de uso único e biometria/PIN',
            a.allowUnlock,
            (v) => a.setAllowUnlock(v),
          ),
          _sw(
            'Integrar com o Cursor',
            'Instala hooks em ~/.cursor/hooks.json (mostra o diff antes)',
            a.cursorHooksInstalled,
            (v) => _toggleCursor(v),
          ),
          _sw(
            'Aprovar comandos pelo celular',
            'Shell/MCP esperam sua decisão (60 s, depois pergunta no Cursor)',
            a.cursorApprovals,
            a.cursorHooksInstalled ? (v) => a.setCursorApprovals(v) : null,
          ),
          _sw(
            'Permitir enviar instruções do celular',
            'Próxima instrução no mesmo chat e Cursor CLI (pastas já vistas)',
            a.allowInstructions,
            a.cursorHooksInstalled ? (v) => a.setAllowInstructions(v) : null,
          ),
          _sw(
            'Escutar em todas as interfaces',
            'Avançado: inclui VPN/túneis. Padrão: só Wi‑Fi/Ethernet da rede local',
            a.listenAll,
            (v) => _toggleListenAll(v),
            danger: true,
          ),
          _sw(
            'Modo HTTP legado',
            'Desliga a criptografia (só em rede confiável)',
            a.legacyHttp,
            (v) => _toggleLegacy(v),
            danger: true,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _revoke,
              icon: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('Revogar todos os celulares', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCursor(bool on) async {
    if (on) {
      final diff = await a.cursorDiff();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Integrar com o Cursor?', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 330,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Será feito um backup do hooks.json e acrescentadas entradas do TAPKEY (marcadas, removíveis). Suas entradas atuais não mudam.',
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF0B0B0C), borderRadius: BorderRadius.circular(8)),
                    child: SingleChildScrollView(
                      child: SelectableText(diff, style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Instalar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final done = await a.setCursorIntegration(on);
    _toast(done ? (on ? 'Integração com o Cursor ativada' : 'Integração removida') : a.cursorMsg);
  }

  Future<void> _toggleListenAll(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Escutar em todas as interfaces?', style: TextStyle(fontSize: 16)),
          content: const Text(
            'O agente passa a aceitar conexões também por VPN, túneis e outras interfaces (ainda só de IPs privados e com token por aparelho). Deixe desligado se você só usa o celular no Wi‑Fi de casa.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ativar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await a.setListenAll(on);
  }

  Future<void> _revokeDevice(ClientInfo c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Revogar este aparelho?', style: TextStyle(fontSize: 16)),
        content: Text(
          '"${c.name.isEmpty ? 'Celular' : c.name}" deixa de conseguir usar o notebook na hora. Para voltar, ele precisa escanear o QR de novo. Os outros celulares continuam funcionando.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revogar')),
        ],
      ),
    );
    if (ok != true) return;
    await a.revokeDevice(c.deviceId);
    _toast('Aparelho revogado');
  }

  Future<void> _toggleLegacy(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Ativar modo HTTP legado?', style: TextStyle(fontSize: 16)),
          content: const Text(
            'O tráfego (inclusive o token) deixa de ser criptografado e o celular não verifica o notebook. Use só em uma rede em que você confia. O celular precisa escanear o QR de novo.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ativar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await a.setLegacyHttp(on);
  }

  Future<void> _revoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Revogar todos os celulares?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Gera novo token e novo certificado. Todos os celulares precisam escanear o QR de novo.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revogar')),
        ],
      ),
    );
    if (ok == true) {
      await a.revokeAll();
      _toast('Acesso revogado. Escaneie o novo QR.');
    }
  }

  Future<void> _regen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Gerar novo token?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'O celular atual para de funcionar até escanear o novo QR.',
          style: TextStyle(fontSize: 13),
        ),
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
            Row(
              children: [
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
              ],
            ),
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
            _security(),
          ].animate(interval: 60.ms).fadeIn(duration: 350.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _header(bool up) => Row(
    children: [
      Mascot(connected: up, size: 40),
      const SizedBox(width: 10),
      const Text(
        'TAPKEY',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 3.5, color: kAccent),
      ),
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
      Text(
        up ? 'Rodando' : 'Parado',
        style: TextStyle(color: up ? kOk : kErr, fontSize: 12, fontWeight: FontWeight.w500),
      ),
      IconButton(
        tooltip: 'Sair',
        visualDensity: VisualDensity.compact,
        onPressed: widget.onQuit,
        icon: const Icon(Icons.power_settings_new, size: 18, color: kMuted),
      ),
    ],
  );

  Widget _pair(bool up) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorder),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kCardTop, kCard],
      ),
    ),
    child: Column(
      children: [
        // (capturas de tela com TAPKEY_EXPAND_SECURITY=1 omitem o QR)
        if (Platform.environment['TAPKEY_EXPAND_SECURITY'] != '1')
          Opacity(
            opacity: up ? 1 : 0.35,
            child:
                Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: QrImageView(
                        data: a.pairUri,
                        size: 156,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0C)),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF0B0B0C),
                        ),
                      ),
                    )
                    .animate(key: ValueKey(a.token))
                    .fadeIn()
                    .scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack),
          ),
        const SizedBox(height: 6),
        const Text('No celular: Configurações > Escanear QR', style: TextStyle(color: kMuted, fontSize: 11)),
      ],
    ),
  );

  Widget _field(String label, String value, bool isToken) => Container(
    height: 38,
    padding: const EdgeInsets.only(left: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF111114),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kBorder),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          ),
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
      ],
    ),
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
    final live = a.clients.where((c) => c.online).length;
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _showClients = !_showClients),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
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
              ],
            ),
          ),
        ),
        if (_showClients)
          for (final c in a.clients.take(5))
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 2, 4, 2),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.online ? kOk : kMuted),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: '${c.requests} requisições · último IP ${c.ip}',
                      child: Text(
                        [c.name.isEmpty ? 'Celular' : c.name, c.ip, if (c.lastApp.isNotEmpty) c.lastApp].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Text(
                    c.online ? 'online' : _ago(c.lastSeen),
                    style: TextStyle(color: c.online ? kOk : kMuted, fontSize: 11),
                  ),
                  IconButton(
                    tooltip: 'Revogar este aparelho',
                    visualDensity: VisualDensity.compact,
                    iconSize: 15,
                    onPressed: () => _revokeDevice(c),
                    icon: const Icon(Icons.block, color: kMuted),
                  ),
                ],
              ),
            ),
        if (_showClients)
          for (final e in a.events.take(5))
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 2, 4, 2),
              child: Row(
                children: [
                  Icon(
                    e.event.contains('Desbloq') ? Icons.lock_open : Icons.lock_outline,
                    size: 12,
                    color: e.ok ? kMuted : kErr,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${e.event} · ${e.ip}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: e.ok ? Colors.white : kErr),
                    ),
                  ),
                  Text(_ago(e.time), style: const TextStyle(color: kMuted, fontSize: 11)),
                ],
              ),
            ),
      ],
    );
  }
}
