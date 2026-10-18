# TAPKEY — agente (Linux Mint)

Programa em Python (somente biblioteca padrão) que roda no notebook e recebe os toques do app do celular.

## Rodar manualmente
```bash
cd ~/projetos/meu_notebook/agent
python3 agent.py
```
Na primeira execução é gerado um token em `~/.config/tapkey/token`.
O agente serve **HTTPS** com um certificado autoassinado gerado na primeira execução (`~/.config/tapkey/tls/`); o terminal mostra o endereço (ex.: `https://192.168.3.133:8765`), o *fingerprint* SHA-256 e o link de pareamento `tapkey://pair?...&fp=...`. Para HTTP legado (não recomendado): `{"legacy_http": true}` em `settings.json`. Coloque o endereço e o token — coloque os dois em
**Configurações** no app do celular.

Em segundo plano:
```bash
nohup python3 agent.py > /tmp/meu_notebook_agent.log 2>&1 &
```
Parar: `pkill -f "python3 .*agent.py"`

## Iniciar automaticamente (systemd de usuário)
```bash
mkdir -p ~/.config/systemd/user
cp meu-notebook-agent.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now meu-notebook-agent.service
systemctl --user status meu-notebook-agent.service
```

## API (cabeçalho `X-Token` obrigatório)
- `GET /ping`
- `GET /apps` → `[{id, name, icon}]` (lido dos `.desktop` em /usr/share/applications, ~/.local/share/applications, flatpak e snap)
- `GET /icon/<id>` → PNG do ícone (404 se não houver)
- `POST /launch` com `{"id": "firefox"}` → abre o app

## Segurança
- Só abre aplicativos que estão na lista de `.desktop` escaneada; nunca comandos arbitrários.
- TLS com certificado fixado pelo app (via QR). Use em rede Wi-Fi confiável.
- Se usar firewall (ufw): `sudo ufw allow 8765/tcp`

## Bloquear / desbloquear

| Rota | Descrição |
|---|---|
| `GET /session` | `{locked, unlock_allowed}` |
| `POST /lock` | Bloqueia a sessão (`loginctl lock-session`, reserva: `cinnamon-screensaver-command --lock`) |
| `GET /challenge` | Nonce de uso único (20 s, preso ao IP) |
| `POST /unlock` | `{nonce, proof}` com `proof = HMAC-SHA256(token, nonce)`; `403` se desativado, `429` acima de 5/min por IP, `400` se o desafio for inválido |

O desbloqueio fica desligado até `~/.config/tapkey/settings.json` ter `{"allow_unlock": true}` (o TAPKEY Desktop grava isso em "Permitir desbloqueio pelo celular"). Todo bloqueio/desbloqueio é registrado em `~/.config/tapkey/events.log` e em `clients.json` (campo `events`).

## Integração com o Cursor (opcional)

Arquivos: `cursor_bridge.py` (estado, aprovações, fila, CLI), `tapkey_cursor_hook.py` (relay dos hooks e instalador). Tudo desligado por padrão (`cursor_integration`, `cursor_approvals`, `allow_instructions` em `settings.json`, controlados pelo TAPKEY Desktop). Rotas: `GET /cursor/state`, `GET /cursor/events` (SSE), `POST /cursor/approval`, `/cursor/instruction`, `/cursor/instruction/cancel`, `/cursor/cli/cancel`, `/cursor/open`. O relay fala com `127.0.0.1:8766` (`POST /hook`, segredo em `~/.config/tapkey/hook_secret`).

```bash
python3 tapkey_cursor_hook.py diff --home /tmp/copia     # mostra o que mudaria
python3 tapkey_cursor_hook.py install --home /tmp/copia  # instala (backup + mescla)
python3 tapkey_cursor_hook.py uninstall --home /tmp/copia
python3 -W ignore -m unittest discover -s tests          # testes
```
