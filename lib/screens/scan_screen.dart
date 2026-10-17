import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';

/// Dados de pareamento lidos do QR do TAPKEY Desktop:
/// tapkey://pair?host=IP&port=8765&token=TOKEN
class PairData {
  final String host;
  final int port;
  final String token;
  const PairData(this.host, this.port, this.token);

  static PairData? parse(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || u.scheme != 'tapkey' || u.host != 'pair') return null;
    final host = u.queryParameters['host'];
    final port = int.tryParse(u.queryParameters['port'] ?? '');
    final token = u.queryParameters['token'];
    if (host == null || host.isEmpty || port == null || token == null || token.isEmpty) {
      return null;
    }
    return PairData(host, port, token);
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final data = PairData.parse(raw);
      if (data != null) {
        _done = true;
        Navigator.pop(context, data);
        return;
      }
      setState(() => _hint = 'Esse QR não é do TAPKEY Desktop.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Escanear QR')),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Não foi possível abrir a câmera.\nPermita o acesso à câmera nas configurações do Android.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: kAccent, width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Text(
            _hint ?? 'Aponte para o QR exibido no TAPKEY Desktop',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: kAccent),
          ),
        ),
      ]),
    );
  }
}
