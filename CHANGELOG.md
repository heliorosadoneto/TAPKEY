# Histórico de mudanças

Marcos do projeto, do mais novo ao mais antigo. Os números de versão são marcos de funcionalidade; o pacote `.deb` e o `pubspec.yaml` ainda usam `0.1.0` / `1.0.0+1`. Formato inspirado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.4.0] — 2026-10-18 · Pacote de animações

### Adicionado
- **Tapi no palco** na Início: passeia, olha para o cartão tocado, pula/gira ao lançar, fica tonto com toques rápidos, curioso ao rolar, sonolento antes do protetor de tela e tem comportamentos ociosos (olhar em volta, pulinho, piscadinha, bocejo, espreguiçar, "coucou", corações e estrelas).
- Novas ações/emoções do mascote: pulinho, olhar em volta, espreguiçar, curioso, sonolento; encadeamento de controladores (`link`).
- **Ilha com morph**: nasce como bolinha com o Tapi, expande até o conteúdo (mola), texto palavra por palavra com fade + desfoque, recolhe ao fechar; saudação ao abrir o app; haptics por tipo de evento; medição respeitando a escala de fonte do sistema.
- **Cartões**: entrada escalonada, squash & stretch, tilt 3D com parallax do ícone, brilho radial no toque, anel + partículas ao lançar.
- **Modo edição**: jiggle, selo de remover, arrastar para reordenar com mola e sombra, rolagem automática, botão *Concluir*, folha de opções com `Hero` do ícone.
- **Fundo vivo** (pontos à deriva, brilho que respira, ondas no toque; pausa em segundo plano e no protetor de tela).
- **Transições** de eixo compartilhado entre telas e abas, `Hero` do botão "+" para *Adicionar atalho*, ícones animados (cadeado, abas, chips, favoritos), ponto de conexão com "sonar".
- Haptics nos principais toques; mensagens da ilha no lugar de *snackbars*.
- `StatusDot`, `LivingBackground`, `TapiStage`; `AppState.setOrder` para persistir a ordem.
- Desktop: janela maior (380×700); variável `TAPKEY_EXPAND_SECURITY=1` para gerar capturas do painel expandido sem QR.
- Novo GIF de demonstração e capturas gravadas no celular real; galeria no README.

### Alterado
- Temas/telas passam a ter fundo transparente para mostrar o fundo vivo; transições de página do Material substituídas pelas de eixo compartilhado.
- Testes de captura desativam o laço SSE do Cursor (evita timers pendentes).

## [0.3.0] — 2026-10-18 · TLS fixado e integração com o Cursor

### Adicionado
- **TLS** com certificado autoassinado por instalação (EC P‑256, `openssl`), **SHA‑256 no QR** (`tapkey://pair?host&port&fp&token&name`) e *pinning* no app (`HttpOverrides`); *modo HTTP legado* opcional; *Novo token* e *Revogar todos os celulares* no Desktop.
- **Integração com o Cursor** (tudo desligado por padrão): relay `tapkey_cursor_hook.py` com instalação segura em `~/.cursor/hooks.json` (diff, backup, remoção só das nossas entradas), status das sessões, **aprovação de comandos** no celular (Permitir com biometria/PIN, comandos longos só negar), **fila de instruções** entregue pelo hook `stop`, **Rodar no Cursor CLI** (sem `--force`/`--yolo`), **Abrir no Cursor**, eventos por SSE, limites e logs.
- Aba **Cursor** no app, folha de aprovação e reações do Tapi.
- Painel **Segurança e Cursor** no TAPKEY Desktop.
- 28 testes Python (`agent/tests`).

### Alterado
- O agente serve **HTTPS** por padrão; celulares antigos precisam escanear o QR de novo. `openssl` passa a ser dependência do `.deb`.

### Limitações
- Integração testada com simulações; comportamento real do Cursor IDE e do CLI autenticado **não verificado**.

## [0.2.0] — 2026-10-18 · Bloqueio, protetor de tela e mascote

### Adicionado
- **Bloquear/Desbloquear** pelo celular (desbloqueio opcional e desligado por padrão, biometria/PIN, desafio HMAC de uso único, 5 tentativas/min, registro de eventos).
- **Protetor de tela** (Tapi dormindo estilo DVD, relógio, tela sempre acesa, tempo configurável).
- **Ilha** (pílula de eventos no topo) e o mascote **Tapi** (motor de estados, olhos que seguem o toque, antena física, emoções e partículas).
- Ícone do app gerado por código; README com demonstração.

## [0.1.0] — 2026-10-17 · Primeira versão

### Adicionado
- App Android com **grade de favoritos**, **lista de aplicativos do notebook** com ícones, **adicionar atalhos**, paisagem em tela cheia e tema minimalista.
- **Agente Python** (somente biblioteca padrão) com token, `/apps`, `/icon`, `/launch`.
- **TAPKEY Desktop** (Flutter Linux) com status, QR de pareamento, token, bandeja e início com o sistema; pacote `.deb` e `install.sh`.
