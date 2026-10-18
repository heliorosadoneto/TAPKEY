import 'package:flutter/material.dart';

import '../state.dart';
import '../theme.dart';
import 'scan_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _host = TextEditingController(text: widget.state.host);
  late final TextEditingController _port = TextEditingController(text: widget.state.port.toString());
  late final TextEditingController _token = TextEditingController(text: widget.state.token);
  bool _obscure = true;
  bool _busy = false;

  Future<void> _scan() async {
    final data = await Navigator.push<PairData>(
        context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (data == null || !mounted) return;
    _host.text = data.host;
    _port.text = data.port.toString();
    _token.text = data.token;
    await _save();
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim());
    final m = ScaffoldMessenger.of(context);
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      m.showSnackBar(const SnackBar(content: Text('Informe um IP e uma porta válidos.')));
      return;
    }
    setState(() => _busy = true);
    await widget.state.saveSettings(_host.text, port, _token.text);
    if (!mounted) return;
    setState(() => _busy = false);
    m.showSnackBar(SnackBar(
        content: Text(widget.state.connected
            ? 'Salvo. Notebook conectado!'
            : 'Salvo, mas não consegui conectar ao notebook.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Configurações',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text('Conexão com o notebook',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kAccent)),
        const SizedBox(height: 4),
        const Text('Abra o TAPKEY Desktop no notebook e escaneie o QR, ou digite os dados abaixo.',
            style: TextStyle(color: kMuted)),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Escanear QR'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _host,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'IP do notebook', prefixIcon: Icon(Icons.laptop)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Porta', prefixIcon: Icon(Icons.numbers)),
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
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: const Text('Salvar e testar'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 28),
        const Text('Protetor de tela',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kAccent)),
        const SizedBox(height: 4),
        const Text('Mostra o Tapi dormindo depois de um tempo sem tocar no app. Toque para acordar.',
            style: TextStyle(color: kMuted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in const [(0, 'Desligado'), (30, '30 s'), (60, '1 min'), (120, '2 min'), (300, '5 min')])
            ChoiceChip(
              label: Text(o.$2),
              selected: widget.state.screensaverSeconds == o.$1,
              onSelected: (_) => widget.state.setScreensaver(o.$1),
            ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }
}
