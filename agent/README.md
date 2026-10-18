# TAPKEY — agente (Linux Mint)

Programa em Python (somente biblioteca padrão) que roda no notebook e recebe os toques do app do celular.

## Rodar manualmente
```bash
cd ~/projetos/meu_notebook/agent
python3 agent.py
```
Na primeira execução é gerado um token em `~/.config/tapkey/token`.
O terminal mostra o endereço (ex.: `http://192.168.3.133:8765`) e o token — coloque os dois em
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
- Use apenas em rede Wi-Fi confiável; o tráfego é HTTP simples com token.
- Se usar firewall (ufw): `sudo ufw allow 8765/tcp`

## Bloquear / desbloquear

| Rota | Descrição |
|---|---|
| `GET /session` | `{locked, unlock_allowed}` |
| `POST /lock` | Bloqueia a sessão (`loginctl lock-session`, reserva: `cinnamon-screensaver-command --lock`) |
| `GET /challenge` | Nonce de uso único (20 s, preso ao IP) |
| `POST /unlock` | `{nonce, proof}` com `proof = HMAC-SHA256(token, nonce)`; `403` se desativado, `429` acima de 5/min por IP, `400` se o desafio for inválido |

O desbloqueio fica desligado até `~/.config/tapkey/settings.json` ter `{"allow_unlock": true}` (o TAPKEY Desktop grava isso em "Permitir desbloqueio pelo celular"). Todo bloqueio/desbloqueio é registrado em `~/.config/tapkey/events.log` e em `clients.json` (campo `events`).
