# Claude Account Switcher

**🇧🇷 Português** · [🇬🇧 English below](#english)

Ícone na bandeja do Windows para trocar de conta no **app Claude Desktop** com um clique, quantas contas você quiser (pessoal, trabalho, estudo...). Tudo roda **localmente** no seu PC: nenhum servidor, nenhuma conta online, nenhum dado enviado a lugar nenhum.

> Projeto independente da comunidade. Não é afiliado nem endossado pela Anthropic. "Claude" é marca da Anthropic. Use apenas com contas suas e respeitando os termos de uso do serviço.

## O que faz

- **Troca de conta com um clique** no ícone da bandeja, sem digitar senha de novo.
- **Quantas contas quiser.** Adicionar é um passo guiado, sem terminal.
- **Compartilha as sessões da aba Code entre as contas** automaticamente a cada troca (dá para desligar no menu), então você não perde o histórico de conversas locais.
- **Sem perguntas a cada troca.** Troca, reabre o app, pronto.
- **Backup automático** antes de cada troca (guarda os 10 últimos).
- Abre junto com o Windows (opcional).

## Instalar

1. Baixe o repositório (**Code > Download ZIP**) e extraia.
2. Dê dois cliques em **`Install.cmd`**. Não precisa de administrador.
3. Procure o círculo laranja na bandeja, perto do relógio. No Windows 11 ele costuma ficar escondido na seta **^**; arraste para a barra para deixar sempre visível.

Requisitos: Windows 10/11 e o app Claude Desktop instalado. Usa só o PowerShell que já vem no Windows.

## Como usar

1. Com a conta que você já usa logada no app, clique no ícone > **Salvar conta atual como...** e dê um nome (ex.: `pessoal`).
2. Para adicionar outra: ícone > **Adicionar conta nova...**. O app fecha, reabre deslogado, você entra na conta nova, abre a aba **Code** uma vez e clica OK.
3. Pronto: clique no ícone e escolha a conta. O app fecha e reabre já logado nela.

Outros itens do menu: **Remover conta**, **Compartilhar sessões entre contas** e **Iniciar com o Windows**.

## Como funciona

O app guarda seu login em arquivos locais (`config.json`, cookies e armazenamento do navegador embutido). O Claude Account Switcher só **copia esses arquivos** para uma pasta de perfil (`%USERPROFILE%\.claude-desktop-swap`) e restaura o perfil escolhido quando você troca. Os tokens são criptografados pelo Windows (DPAPI) para o seu usuário, então só funcionam neste PC e neste usuário do Windows.

## O que NÃO é compartilhado

- **Chats do claude.ai, memória, preferências, estilos e projetos** ficam no servidor, presos a cada conta. Nada disso é copiado. (Para a memória, use o importador em Configurações > Capacidades.)
- As **sessões da aba Code** são sincronizadas (cópia do arquivo de lista; a transcrição em `~/.claude/projects` já é compartilhada). Sessões apagadas numa conta podem reaparecer na troca seguinte. Desligue o compartilhamento no menu se não quiser isso.
- Uma conta nova só passa a ter pasta de sessões depois que você abre a aba Code nela uma vez.

## Segurança e privacidade

- Nenhuma chamada de rede. Leia o código: são 3 scripts PowerShell em [`src/`](src).
- **Trate `%USERPROFILE%\.claude-desktop-swap` como senha.** Ela contém o login das suas contas. Não compartilhe, não suba para o Git, não mande em print.
- Se o app abrir deslogado após uma troca, o token expirou: entre de novo e use "Salvar conta atual como..." com o mesmo nome.

## Limitações conhecidas

- Testado com a versão da **Microsoft Store/MSIX** do Claude Desktop. O instalador clássico (`%APPDATA%\Claude`) é detectado, mas não foi testado.
- Só Windows. Uma atualização do app pode mudar onde/como o login é guardado e quebrar a ferramenta; abra uma issue se acontecer.
- A troca fecha o app (primeiro de forma educada, depois à força). Salve o que estiver fazendo antes.

## Linha de comando (opcional)

Em um PowerShell **fora** do app Claude, dentro de `%LOCALAPPDATA%\ClaudeAccountSwitcher`: `dswap.ps1 list | save <nome> | switch <nome> | add <nome> | remove <nome> | share on|off | restore-backup`.

## Desinstalar

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1              # mantém suas contas salvas
powershell -ExecutionPolicy Bypass -File uninstall.ps1 -RemoveData  # apaga tudo
```

## Testes

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Rodam contra uma pasta de dados falsa; nunca tocam no seu app nem nas suas contas.

---

## English

A Windows tray icon to switch accounts in the **Claude Desktop app** with one click, as many accounts as you like (personal, work, school...). Everything is **local**: no server, no online account, nothing is sent anywhere.

> Independent community project, not affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic. Use it only with your own accounts and within the service's terms.

**Features:** one-click switching from the tray · unlimited accounts · guided "add account" (no terminal) · Code-tab sessions shared across accounts on every switch (toggleable) · no prompts on switch · automatic backup before each switch (last 10 kept) · optional start with Windows.

**Install:** download the ZIP, extract, double-click `Install.cmd` (no admin). Look for the orange circle in the tray (Windows 11 hides it under the `^` arrow; drag it out to pin it).

**Use:** sign in with your current account → tray icon → *Save current account as...* → to add another: *Add new account...*, sign in with it, open the **Code** tab once, click OK → then just pick an account from the menu.

**How it works:** the app stores your login in local files (`config.json`, cookies, embedded-browser storage). This tool copies those files into per-account profiles under `%USERPROFILE%\.claude-desktop-swap` and restores the one you pick. Tokens are encrypted by Windows (DPAPI) for your user, so they only work on this PC and Windows user.

**Not shared:** claude.ai chats, memory, preferences, styles and projects live on the server and stay with each account. Code-tab session *lists* are synced (transcripts in `~/.claude/projects` are already shared); sessions deleted in one account may reappear on the next switch.

**Security:** no network calls; treat `%USERPROFILE%\.claude-desktop-swap` like a password.

**Limitations:** tested with the Microsoft Store (MSIX) build only; the classic installer path is detected but untested. Windows only. An app update may change how login is stored and break this.

**Uninstall:** `uninstall.ps1` (add `-RemoveData` to also delete saved accounts). **Tests:** `tests\run-tests.ps1` (uses a fake data folder).

## License

[MIT](LICENSE)
