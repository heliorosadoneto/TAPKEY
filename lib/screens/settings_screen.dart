import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/island.dart';
import '../widgets/mascot.dart';
import 'scan_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _host = TextEditingController(
    text: widget.state.host,
  );
  late final TextEditingController _port = TextEditingController(
    text: widget.state.port.toString(),
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.state.token,
  );
  late final TextEditingController _fp = TextEditingController(
    text: widget.state.fp,
  );
  bool _obscure = true;
  bool _busy = false;

  Future<void> _scan() async {
    final data = await Navigator.push<PairData>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (data == null || !mounted) return;
    _host.text = data.host;
    _port.text = data.port.toString();
    _token.text = data.token;
    _fp.text = data.fp;
    await _save(name: data.name);
  }

  Future<void> _save({String? name}) async {
    final port = int.tryParse(_port.text.trim());
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      island.show('Informe um IP e uma porta válidos.', kind: IslandKind.error);
      mascotController.error();
      return;
    }
    final fpText = _fp.text.trim().toLowerCase().replaceAll(':', '');
    if (fpText.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(fpText)) {
      island.show(
        'Fingerprint inválido (64 caracteres hexadecimais).',
        kind: IslandKind.error,
      );
      mascotController.error();
      return;
    }
    setState(() => _busy = true);
    await widget.state.saveSettings(
      _host.text,
      port,
      _token.text,
      fingerprint: fpText,
      name: name,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.state.connected) {
      island.show('Salvo. Notebook conectado!', kind: IslandKind.success);
      mascotController.happy();
    } else {
      island.show(
        'Salvo, mas não consegui conectar ao notebook.',
        kind: IslandKind.error,
      );
      mascotController.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Configurações',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Conexão com o notebook',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kAccent,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Abra o TAPKEY Desktop no notebook e escaneie o QR, ou digite os dados abaixo.',
            style: TextStyle(color: kMuted),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear QR'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'IP do notebook',
              prefixIcon: Icon(Icons.laptop),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Porta',
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Token',
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fp,
            decoration: const InputDecoration(
              labelText: 'Fingerprint do certificado (SHA-256)',
              helperText:
                  'Preenchido pelo QR. Vazio = HTTP legado (sem criptografia).',
              prefixIcon: Icon(Icons.fingerprint),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 10),
          _SecurityBadge(secure: widget.state.secure),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Salvar e testar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Protetor de tela',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kAccent,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Mostra o Tapi dormindo depois de um tempo sem tocar no app. Toque para acordar.',
            style: TextStyle(color: kMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in const [
                (0, 'Desligado'),
                (30, '30 s'),
                (60, '1 min'),
                (120, '2 min'),
                (300, '5 min'),
              ])
                _chip(o.$1, o.$2),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

extension _SettingsChips on _SettingsScreenState {
  Widget _chip(int seconds, String label) {
    final selected = widget.state.screensaverSeconds == seconds;
    final chip = ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (selected) return;
        HapticFeedback.selectionClick();
        widget.state.setScreensaver(seconds);
        if (seconds == 0) {
          mascotController.wink();
          island.show('Protetor de tela desligado', kind: IslandKind.info, duration: const Duration(milliseconds: 1500));
        } else {
          mascotController.yawn();
          island.show('Protetor de tela: $label', kind: IslandKind.success, duration: const Duration(milliseconds: 1500));
        }
      },
    );
    return selected
        ? chip.animate(key: ValueKey('sel-$seconds')).scale(begin: const Offset(.85, .85), duration: 520.ms, curve: Curves.elasticOut)
        : chip;
  }
}

class _SecurityBadge extends StatelessWidget {
  final bool secure;
  const _SecurityBadge({required this.secure});

  @override
  Widget build(BuildContext context) {
    final c = secure ? kOk : kErr;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(
            secure ? Icons.lock_outline : Icons.warning_amber_rounded,
            size: 18,
            color: c,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              secure
                  ? 'Conexão criptografada (TLS) com certificado fixado.'
                  : 'HTTP legado: o tráfego e o token não são criptografados.',
              style: TextStyle(fontSize: 12.5, color: c),
            ),
          ),
        ],
      ),
    );
  }
}
