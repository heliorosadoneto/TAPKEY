#!/bin/sh
# Roda o app no celular usando config.local.json (se existir).
# Uso: ./run.sh -d <id-do-dispositivo>
cd "$(dirname "$0")"
if [ -f config.local.json ]; then
  exec flutter run --dart-define-from-file=config.local.json "$@"
else
  echo "Aviso: config.local.json não encontrado (copie config.local.example.json)."
  exec flutter run "$@"
fi
