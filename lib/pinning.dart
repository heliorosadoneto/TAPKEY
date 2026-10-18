import 'dart:io';

import 'package:crypto/crypto.dart';

import 'state.dart';

/// Fixação de certificado (pinning): o notebook usa um certificado autoassinado, então a
/// validação normal sempre falha. Aceitamos SOMENTE se o SHA-256 do certificado for o
/// fingerprint recebido no QR de pareamento, e só para o host/porta pareados.
class PinningOverrides extends HttpOverrides {
  final AppState state;
  PinningOverrides(this.state);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final c = super.createHttpClient(context);
    c.badCertificateCallback = (X509Certificate cert, String host, int port) =>
        pinMatches(state.fp, cert.der) &&
        host == state.host &&
        port == state.port;
    return c;
  }
}

bool pinMatches(String expectedHex, List<int> der) {
  if (expectedHex.isEmpty) return false;
  return sha256.convert(der).toString() == expectedHex.toLowerCase();
}
