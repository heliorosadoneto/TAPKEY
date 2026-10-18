// Valores padrão de conexão. Nada secreto fica no código: o IP e o token reais
// vêm de `config.local.json` (ignorado pelo git) via --dart-define-from-file,
// ou são digitados em Configurações dentro do app.
//
//   flutter run --dart-define-from-file=config.local.json
//
// Sem esse arquivo o app compila normalmente com os valores abaixo.
const String kDefaultHost = String.fromEnvironment(
  'TAPKEY_HOST',
  defaultValue: '192.168.0.100',
);
const int kDefaultPort = int.fromEnvironment('TAPKEY_PORT', defaultValue: 8765);
const String kDefaultToken = String.fromEnvironment('TAPKEY_TOKEN');
const String kDefaultFp = String.fromEnvironment('TAPKEY_FP');
