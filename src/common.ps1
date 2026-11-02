# common.ps1 - shared helpers, dot-sourced by dswap.ps1 and tray.ps1.
# Everything here is local: no network calls, nothing leaves this machine.
$ErrorActionPreference = 'Stop'

$TestMode = [bool]$env:DSWAP_DATA   # tests point DSWAP_DATA at a fake data folder; the real app is never touched
$Store    = if ($env:DSWAP_STORE) { $env:DSWAP_STORE } else { Join-Path $env:USERPROFILE '.claude-desktop-swap' }
$Profiles = Join-Path $Store 'profiles'
$Backups  = Join-Path $Store 'backups'
$SettingsFile = Join-Path $Store 'settings.json'
$LogFile      = Join-Path $Store 'tray.log'

# What counts as "login state" of the desktop app
$AuthKeys = @('oauth:tokenCache', 'oauth:tokenCacheV2', 'lastKnownAccountUuid')   # keys inside config.json
$AuthFiles = @('Network\Cookies', 'Network\Cookies-journal')
$AuthDirs  = @('Local Storage', 'Session Storage', 'IndexedDB')
$BackupsToKeep = 10

# ---------------------------------------------------------------- i18n
$Lang = if ($env:DSWAP_LANG) { $env:DSWAP_LANG } elseif ((Get-UICulture).TwoLetterISOLanguageName -eq 'pt') { 'pt' } else { 'en' }
$Strings = @{
    pt = @{
        title        = 'Claude - Trocar conta'
        no_claude    = 'Não encontrei o app Claude Desktop neste PC.'
        inside_app   = 'Este script está rodando dentro do app Claude; fechar o app mataria o próprio script. Rode num PowerShell externo (ou use o ícone da bandeja).'
        closing      = 'Fechando o app Claude...'
        no_close     = 'O app não fechou. Feche manualmente e tente de novo.'
        reopened     = 'App reaberto.'
        no_startapp  = 'Não achei o app no menu Iniciar; abra manualmente.'
        bad_name     = 'Nome inválido (use letras, números, ponto, _ e -; até 40 caracteres).'
        no_profile   = "Perfil '{0}' não existe."
        exists       = "Já existe um perfil chamado '{0}'."
        no_config    = 'config.json do Claude não encontrado em {0}'
        no_login     = 'Nenhum login encontrado. Termine de entrar na conta no app (mesmo que ela não tenha plano) e tente de novo.'
        same_account = "Essa é a mesma conta do perfil '{0}'. Entre com uma conta diferente."
        unnamed      = 'A conta atual ainda não tem nome. Salve primeiro (Salvar conta atual como...) para não perder o login.'
        saved        = "Conta salva como '{0}'."
        updated      = "Perfil '{0}' atualizado."
        switched     = "Trocado para '{0}'."
        removed      = "Perfil '{0}' removido (o login no app não foi alterado)."
        backup       = 'Backup: {0}'
        adding       = 'Entre com a conta nova no app.'
        add_done     = "Conta '{0}' adicionada."
        synced       = '{0} sessões sincronizadas entre as contas.'
        sync_wait    = 'Esta conta ainda não tem pasta de sessões. Abra a aba Code uma vez e troque de conta de novo para sincronizar.'
        share_on     = 'Compartilhar sessões entre contas: ligado.'
        share_off    = 'Compartilhar sessões entre contas: desligado.'
        no_profiles  = 'Nenhum perfil ainda.'
        current      = 'atual'
        # tray
        m_switch     = 'Trocar de conta'
        m_save       = 'Salvar conta atual como...'
        m_add        = 'Adicionar conta nova...'
        m_remove     = 'Remover conta'
        m_share      = 'Compartilhar sessões entre contas'
        m_startup    = 'Iniciar com o Windows'
        m_exit       = 'Sair'
        p_save       = 'Nome para a conta que está logada agora (ex.: pessoal):'
        p_add        = 'Nome da conta NOVA (ex.: trabalho):'
        p_add_intro  = "Vou fechar o Claude, guardar a conta atual e abrir o app deslogado para você entrar na conta nova. Continuar?"
        p_add_wait   = "Entre com a conta nova no app e espere carregar (se a conta tiver plano, abra a aba Code uma vez).`n`nQuando terminar, clique em OK. Cancelar volta para a conta anterior."
        p_remove     = "Remover o perfil '{0}'? O login dessa conta guardado aqui será apagado (você poderá adicionar de novo)."
        b_working    = 'Trabalhando...'
        b_busy       = 'Aguarde a operação anterior terminar.'
        b_failed     = 'Falhou: {0}'
        b_first_run  = 'Clique no ícone e escolha "Salvar conta atual como..." para começar.'
        b_hint       = 'O ícone fica na bandeja do relógio (setinha ^).'
    }
    en = @{
        title        = 'Claude - Account Switcher'
        no_claude    = 'Could not find the Claude Desktop app on this PC.'
        inside_app   = 'This script is running inside the Claude app; closing the app would kill the script. Run it from an external PowerShell (or use the tray icon).'
        closing      = 'Closing the Claude app...'
        no_close     = 'The app did not close. Close it manually and try again.'
        reopened     = 'App reopened.'
        no_startapp  = 'Could not find the app in the Start menu; please open it manually.'
        bad_name     = 'Invalid name (letters, digits, dot, _ and - only; up to 40 characters).'
        no_profile   = "Profile '{0}' does not exist."
        exists       = "A profile named '{0}' already exists."
        no_config    = 'Claude config.json not found in {0}'
        no_login     = 'No login found. Finish signing in to the account in the app (even if it has no plan) and try again.'
        same_account = "That is the same account as profile '{0}'. Sign in with a different account."
        unnamed      = 'The current account has no name yet. Save it first (Save current account as...) so the login is not lost.'
        saved        = "Account saved as '{0}'."
        updated      = "Profile '{0}' updated."
        switched     = "Switched to '{0}'."
        removed      = "Profile '{0}' removed (the app's current login was not changed)."
        backup       = 'Backup: {0}'
        adding       = 'Sign in with the new account in the app.'
        add_done     = "Account '{0}' added."
        synced       = '{0} sessions synced across accounts.'
        sync_wait    = 'This account has no sessions folder yet. Open the Code tab once, then switch accounts again to sync.'
        share_on     = 'Share sessions between accounts: on.'
        share_off    = 'Share sessions between accounts: off.'
        no_profiles  = 'No profiles yet.'
        current      = 'current'
        m_switch     = 'Switch account'
        m_save       = 'Save current account as...'
        m_add        = 'Add new account...'
        m_remove     = 'Remove account'
        m_share      = 'Share sessions between accounts'
        m_startup    = 'Start with Windows'
        m_exit       = 'Exit'
        p_save       = 'Name for the account that is signed in right now (e.g. personal):'
        p_add        = 'Name for the NEW account (e.g. work):'
        p_add_intro  = "I will close Claude, store the current account and reopen the app signed out so you can sign in with the new account. Continue?"
        p_add_wait   = "Sign in with the new account in the app and wait for it to load (if the account has a plan, open the Code tab once).`n`nWhen you are done, click OK. Cancel goes back to the previous account."
        p_remove     = "Remove profile '{0}'? The login stored here for that account will be deleted (you can add it again later)."
        b_working    = 'Working...'
        b_busy       = 'Please wait for the previous operation to finish.'
        b_failed     = 'Failed: {0}'
        b_first_run  = 'Click the icon and choose "Save current account as..." to get started.'
        b_hint       = 'The icon lives in the system tray (the ^ arrow near the clock).'
    }
}
function T([string]$key, $a) {
    $s = $Strings[$Lang][$key]
    if (-not $s) { $s = $Strings['en'][$key] }
    if (-not $s) { $s = $key }
    if ($null -ne $a) { return ($s -f @($a)) }
    return $s
}

# ---------------------------------------------------------------- helpers
# Status lines go to the console and, when DSWAP_RESULT is set (the tray does that), to a UTF-8 file the tray reads back,
# so accented text survives regardless of the console code page.
function Say([string]$msg, [string]$color) {
    if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
    if ($env:DSWAP_RESULT) { try { [IO.File]::AppendAllText($env:DSWAP_RESULT, "$msg`r`n", (New-Object Text.UTF8Encoding $false)) } catch {} }
}
function Die([string]$msg) { throw $msg }
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false)) }
function Read-Json([string]$path) { Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }

function Get-Setting([string]$name, $default) {
    if (Test-Path $SettingsFile) {
        $s = Read-Json $SettingsFile
        if ($s.PSObject.Properties[$name]) { return $s.$name }
    }
    return $default
}
function Set-Setting([string]$name, $value) {
    New-Item -ItemType Directory -Force $Store | Out-Null
    $s = if (Test-Path $SettingsFile) { Read-Json $SettingsFile } else { New-Object PSObject }
    $s | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    Write-Utf8 $SettingsFile ($s | ConvertTo-Json)
}

# Where does the Claude desktop app keep its data?
function Find-ClaudeData {
    if ($TestMode) { return $env:DSWAP_DATA }
    $cands = @()
    $pkg = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $cands += Join-Path $env:LOCALAPPDATA "Claude-Data\$($pkg.PackageFamilyName)"
        $cands += Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalCache\Roaming\Claude"
    }
    $cands += Join-Path $env:APPDATA 'Claude'
    foreach ($c in $cands) { if (Test-Path (Join-Path $c 'config.json')) { return $c } }
    return $null
}
$Data = Find-ClaudeData
$Config = if ($Data) { Join-Path $Data 'config.json' } else { $null }
function Assert-Claude { if (-not $Data) { Die (T 'no_claude') } }

# ---------------------------------------------------------------- app process control
function Get-AppProcs {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $p = $_.Path; $p -and ($p -like '*\WindowsApps\Claude_*' -or $p -like '*\AnthropicClaude\*' -or ($Data -and $p -like "$Data\claude-code\*")) } catch { $false }
    }
}

function Assert-NotInsideApp {
    if ($TestMode) { return }
    $appPids = @((Get-AppProcs).Id)
    if (-not $appPids) { return }
    $id = $PID
    for ($i = 0; $i -lt 20 -and $id; $i++) {
        if ($appPids -contains $id) { Die (T 'inside_app') }
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        $id = if ($p) { $p.ParentProcessId } else { $null }
    }
}

function Stop-App {
    if ($TestMode) { return }
    $procs = @(Get-AppProcs)
    if (-not $procs) { return }
    Say (T 'closing')
    foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch {} }   # polite first, so the app can flush its data
    for ($i = 0; $i -lt 16; $i++) { Start-Sleep -Milliseconds 250; if (-not @(Get-AppProcs)) { break } }
    @(Get-AppProcs) | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 40; $i++) {
        if (-not @(Get-AppProcs)) { Start-Sleep -Milliseconds 800; return }
        Start-Sleep -Milliseconds 250
    }
    Die (T 'no_close')
}

function Start-App {
    if ($TestMode -or $NoLaunch) { return }
    $app = Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1
    if (-not $app) { Say (T 'no_startapp'); return }
    Start-Process explorer.exe "shell:AppsFolder\$($app.AppID)"   # launched via explorer so the app is not our child
    Say (T 'reopened')
}

# ---------------------------------------------------------------- profiles
function Get-ProfileNames {
    if (-not (Test-Path $Profiles)) { return @() }
    @(Get-ChildItem $Profiles -Directory | Where-Object { $_.Name -notlike '*.tmp' } | Sort-Object Name | ForEach-Object Name)
}
function Get-ProfilePath([string]$n) {
    if ($n -notmatch '^[\w.-]{1,40}$') { Die (T 'bad_name') }
    Join-Path $Profiles $n
}
function Get-ProfileUuid([string]$n) {
    $f = Join-Path (Join-Path $Profiles $n) 'auth.json'
    if (Test-Path $f) { return (Read-Json $f).lastKnownAccountUuid }
    return $null
}
# What is signed in to the app right now? Read from the app's own config, never from our own bookkeeping,
# so signing in/out by hand (outside this tool) is always noticed. A free account has no plan token, only the uuid.
function Get-LiveInfo {
    $r = [pscustomobject]@{ LoggedIn = $false; Uuid = $null }
    if (-not $Config -or -not (Test-Path $Config)) { return $r }
    try { $cfg = Read-Json $Config } catch { return $r }
    $r.Uuid = $cfg.lastKnownAccountUuid
    $r.LoggedIn = [bool]($r.Uuid -or $cfg.'oauth:tokenCacheV2' -or $cfg.'oauth:tokenCache')
    return $r
}
function Get-LiveUuid { (Get-LiveInfo).Uuid }
# Name of the saved profile that matches the signed-in account, or $null (signed out, or an account not saved yet).
function Get-Current {
    $u = (Get-LiveInfo).Uuid
    if (-not $u) { return $null }
    foreach ($n in Get-ProfileNames) { if ((Get-ProfileUuid $n) -eq $u) { return $n } }
    return $null
}

function Copy-Dir([string]$src, [string]$dst) {
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    New-Item -ItemType Directory -Force $dst | Out-Null
    robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { Die "robocopy failed on $src (code $LASTEXITCODE)" }
}

# app -> folder
function Export-Login([string]$dest) {
    Assert-Claude
    New-Item -ItemType Directory -Force $dest | Out-Null
    $cfg = Read-Json $Config
    $auth = [ordered]@{}
    foreach ($k in $AuthKeys) { if ($cfg.PSObject.Properties[$k]) { $auth[$k] = $cfg.$k } }
    if (-not $auth['lastKnownAccountUuid'] -and -not $auth['oauth:tokenCacheV2'] -and -not $auth['oauth:tokenCache']) { Die (T 'no_login') }
    Write-Utf8 (Join-Path $dest 'auth.json') ($auth | ConvertTo-Json -Depth 5)
    foreach ($f in $AuthFiles) {
        $s = Join-Path $Data $f; $d = Join-Path $dest ('files\' + $f)
        if (Test-Path $s) { New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null; Copy-Item $s $d -Force }
    }
    foreach ($dir in $AuthDirs) {
        $s = Join-Path $Data $dir
        if (Test-Path $s) { Copy-Dir $s (Join-Path $dest ('dirs\' + $dir)) }
    }
}

# folder -> app
function Import-Login([string]$src) {
    Assert-Claude
    $auth = Read-Json (Join-Path $src 'auth.json')
    $cfg = Read-Json $Config
    foreach ($k in $AuthKeys) {
        if ($auth.PSObject.Properties[$k]) { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $auth.$k -Force }
        elseif ($cfg.PSObject.Properties[$k]) { $cfg.PSObject.Properties.Remove($k) }
    }
    Write-Utf8 $Config ($cfg | ConvertTo-Json -Depth 100)
    foreach ($f in $AuthFiles) {
        $t = Join-Path $Data $f; $s = Join-Path $src ('files\' + $f)
        if (Test-Path $s) { Copy-Item $s $t -Force } elseif (Test-Path $t) { Remove-Item $t -Force }
    }
    foreach ($dir in $AuthDirs) {
        $t = Join-Path $Data $dir; $s = Join-Path $src ('dirs\' + $dir)
        if (Test-Path $s) { Copy-Dir $s $t } elseif (Test-Path $t) { Remove-Item $t -Recurse -Force }
    }
}

function Clear-Login {
    Assert-Claude
    $cfg = Read-Json $Config
    foreach ($k in $AuthKeys) { if ($cfg.PSObject.Properties[$k]) { $cfg.PSObject.Properties.Remove($k) } }
    Write-Utf8 $Config ($cfg | ConvertTo-Json -Depth 100)
    foreach ($f in $AuthFiles) { $t = Join-Path $Data $f; if (Test-Path $t) { Remove-Item $t -Force } }
    foreach ($dir in $AuthDirs) { $t = Join-Path $Data $dir; if (Test-Path $t) { Remove-Item $t -Recurse -Force } }
}

function Save-Profile([string]$n) {
    $p = Get-ProfilePath $n
    $tmp = "$p.tmp"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    try { Export-Login $tmp }
    catch { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; throw }   # never leave half-written profiles behind
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    Move-Item $tmp $p
}

# Refuse to save the live login under a name if it is already stored under another one
function Assert-NotDuplicate([string]$n) {
    $live = Get-LiveUuid
    if (-not $live) { return }
    foreach ($other in (Get-ProfileNames | Where-Object { $_ -ne $n })) {
        if ((Get-ProfileUuid $other) -eq $live) { Die (T 'same_account' $other) }
    }
}

function Backup-Now {
    if (-not (Get-LiveInfo).LoggedIn) { return }   # signed out: nothing to protect
    $b = Join-Path $Backups (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    Export-Login $b
    Copy-Item $Config (Join-Path $b 'config.json.full') -Force
    Say (T 'backup' $b)
    Get-ChildItem $Backups -Directory | Sort-Object Name -Descending | Select-Object -Skip $BackupsToKeep |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# Make every account see the same Code-tab session list (newest copy of each session wins).
# Returns the number of files copied, or -1 when the logged-in account has no sessions folder yet.
function Sync-Sessions {
    if (-not (Get-Setting 'shareSessions' $true)) { return 0 }
    $root = Join-Path $Data 'claude-code-sessions'
    if (-not (Test-Path $root)) { return -1 }
    $me = Get-LiveUuid
    if (-not $me) { return 0 }
    $mine = Join-Path $root $me
    if (-not (Test-Path $mine)) { return -1 }
    $dest = Get-ChildItem $mine -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $dest) { return -1 }
    $n = 0
    foreach ($acct in Get-ChildItem $root -Directory | Where-Object { $_.Name -ne $me }) {
        foreach ($f in Get-ChildItem $acct.FullName -Directory | ForEach-Object { Get-ChildItem $_.FullName -File -Filter 'local_*.json' }) {
            $t = Join-Path $dest.FullName $f.Name
            if (-not (Test-Path $t) -or $f.LastWriteTimeUtc -gt (Get-Item $t).LastWriteTimeUtc) { Copy-Item $f.FullName $t -Force; $n++ }
        }
    }
    return $n
}
