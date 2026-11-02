# Runs dswap.ps1 against a fake Claude data folder. Never touches the real app or your real accounts.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('dswap-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$data = Join-Path $root 'data'
$env:DSWAP_DATA = $data; $env:DSWAP_STORE = Join-Path $root 'store'; $env:DSWAP_LANG = 'en'
$dswap = (Resolve-Path (Join-Path $PSScriptRoot '..\src\dswap.ps1')).Path
$script:fail = 0

function Ds { $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dswap @args 2>&1 | Out-String; [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE } }
function Check([string]$name, [bool]$ok) { if ($ok) { Write-Host "  ok    $name" } else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:fail++ } }
function Login([string]$uuid, [string]$tag) {
    New-Item -ItemType Directory -Force "$data\Network", "$data\Local Storage" | Out-Null
    $cfg = [ordered]@{ theme = 'dark'; 'oauth:tokenCacheV2' = "tok-$tag"; lastKnownAccountUuid = $uuid; other = @{ keep = $true } }
    [IO.File]::WriteAllText("$data\config.json", ($cfg | ConvertTo-Json -Depth 5))
    Set-Content "$data\Network\Cookies" "cookie-$tag"; Set-Content "$data\Local Storage\x" "ls-$tag"
}
function LoginFree([string]$uuid) {   # signed in, but the account has no plan: the app stores no plan token
    New-Item -ItemType Directory -Force "$data\Network" | Out-Null
    [IO.File]::WriteAllText("$data\config.json", ([ordered]@{ theme = 'dark'; lastKnownAccountUuid = $uuid } | ConvertTo-Json))
    Set-Content "$data\Network\Cookies" "cookie-free"
}
function Logout { [IO.File]::WriteAllText("$data\config.json", ([ordered]@{ theme = 'dark' } | ConvertTo-Json)); Remove-Item "$data\Network\Cookies" -ErrorAction SilentlyContinue }
function Get-ProfileTok([string]$n) { (Get-Content "$env:DSWAP_STORE\profiles\$n\auth.json" -Raw | ConvertFrom-Json).'oauth:tokenCacheV2' }
function Session([string]$uuid, [string]$org, [string]$name, [datetime]$when) {
    $d = "$data\claude-code-sessions\$uuid\$org"; New-Item -ItemType Directory -Force $d | Out-Null
    Set-Content "$d\$name.json" $name; (Get-Item "$d\$name.json").LastWriteTime = $when
}
function Cfg { Get-Content "$data\config.json" -Raw | ConvertFrom-Json }
function Has([string]$uuid, [string]$name) { [bool](Get-ChildItem "$data\claude-code-sessions\$uuid" -Recurse -Filter "$name.json" -ErrorAction SilentlyContinue) }

try {
    Write-Host 'scripts'
    foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot '..') -Recurse -Filter *.ps1) {
        $e = $null; [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e)
        Check "parses: $($f.Name)" ($e.Count -eq 0)
    }
    Check 'tray caches the process handle (fixes false "failed" notice)' ((Get-Content (Join-Path $PSScriptRoot '..\src\tray.ps1') -Raw) -match '\$script:proc\.Handle')
    $bad = Ds switch does-not-exist
    Check 'failures exit non-zero and print an ERROR: line for the tray' ($bad.Code -ne 0 -and $bad.Out -match 'ERROR:')

    Write-Host 'save two accounts'
    Login 'uuid-A' 'A'; Session 'uuid-A' 'orgA' 'local_a1' (Get-Date).AddDays(-2); Session 'uuid-A' 'orgA' 'local_a2' (Get-Date).AddDays(-2)
    Check 'save a' ((Ds save a).Code -eq 0)
    Login 'uuid-B' 'B'; Session 'uuid-B' 'orgB' 'local_b1' (Get-Date).AddDays(-1)
    Check 'save b' ((Ds save b).Code -eq 0)
    Check 'saving the same login under another name is refused' ((Ds save b-again).Code -ne 0)
    Check 'invalid name is refused' ((Ds save 'bad name!').Code -ne 0)

    Write-Host 'switch + session sharing'
    Check 'switch a' ((Ds switch a).Code -eq 0)
    Check 'config has account A token' ((Cfg).'oauth:tokenCacheV2' -eq 'tok-A')
    Check 'unrelated config keys preserved' ((Cfg).theme -eq 'dark' -and (Cfg).other.keep)
    Check 'cookies restored' ((Get-Content "$data\Network\Cookies") -eq 'cookie-A')
    Check "A now sees B's session" (Has 'uuid-A' 'local_b1')
    Check 'switch b' ((Ds switch b).Code -eq 0)
    Check 'config has account B token' ((Cfg).'oauth:tokenCacheV2' -eq 'tok-B')
    Check "B now sees A's sessions" ((Has 'uuid-B' 'local_a1') -and (Has 'uuid-B' 'local_a2'))

    Write-Host 'newest copy wins'
    (Get-Item "$data\claude-code-sessions\uuid-A\orgA\local_a1.json").LastWriteTime = Get-Date
    Set-Content "$data\claude-code-sessions\uuid-A\orgA\local_a1.json" 'edited-in-A'; (Get-Item "$data\claude-code-sessions\uuid-A\orgA\local_a1.json").LastWriteTime = (Get-Date).AddMinutes(5)
    Ds switch a | Out-Null; Ds switch b | Out-Null
    Check 'edited session propagated' ((Get-Content "$data\claude-code-sessions\uuid-B\orgB\local_a1.json") -eq 'edited-in-A')

    Write-Host 'sharing off'
    Check 'share off' ((Ds share off).Code -eq 0)
    Session 'uuid-A' 'orgA' 'local_a3' (Get-Date)
    Ds switch a | Out-Null; Ds switch b | Out-Null
    Check 'new session is NOT copied when sharing is off' (-not (Has 'uuid-B' 'local_a3'))
    Ds share on | Out-Null
    Ds switch a | Out-Null; Ds switch b | Out-Null
    Check 'copied again after turning sharing on' (Has 'uuid-B' 'local_a3')

    Write-Host 'guided add (begin/finish)'
    Check 'add-begin c' ((Ds add-begin c).Code -eq 0)
    Check 'login cleared' (-not (Cfg).'oauth:tokenCacheV2')
    Check 'add-finish without signing in fails' ((Ds add-finish c).Code -ne 0)
    Login 'uuid-C' 'C'; Session 'uuid-C' 'orgC' 'local_c1' (Get-Date)
    Check 'add-finish c' ((Ds add-finish c).Code -eq 0)
    Check 'c sees older sessions' (Has 'uuid-C' 'local_a1')
    Check 'list shows 3 accounts' (((Ds list).Out -split "`n" | Where-Object { $_ -match '\S' }).Count -eq 3)
    Check 'adding an account that already exists is refused' ((Ds add-begin a).Code -ne 0)

    Write-Host 'free account (no plan token, only the account id)'
    LoginFree 'uuid-F'
    Check 'save free account' ((Ds save f).Code -eq 0)
    Check 'free profile has no plan token' (-not (Get-Content "$env:DSWAP_STORE\profiles\f\auth.json" -Raw | ConvertFrom-Json).'oauth:tokenCacheV2')
    Check 'switch a (leaving the free account)' ((Ds switch a).Code -eq 0)
    Check 'switch back to the free account' ((Ds switch f).Code -eq 0)
    Check 'plan token is gone, account id is the free one' ((-not (Cfg).'oauth:tokenCacheV2') -and (Cfg).lastKnownAccountUuid -eq 'uuid-F')

    Write-Host 'signed out / signed in by hand'
    Logout
    Check 'list shows no current account while signed out' (-not ((Ds list).Out -match '\*'))
    Check 'switching works while signed out' ((Ds switch a).Code -eq 0)
    Check 'signed in as a' ((Cfg).'oauth:tokenCacheV2' -eq 'tok-A')
    Login 'uuid-B' 'B2'   # user signs in to b by hand, outside the tool
    Check 'current account is detected from the real login' ((Ds list).Out -match '\*\s+b\s')
    Logout
    Check 'saving while signed out fails' ((Ds save z).Code -ne 0)
    Check '...and leaves no .tmp folder behind' (-not (Get-ChildItem "$env:DSWAP_STORE\profiles" -Filter '*.tmp' -ErrorAction SilentlyContinue))

    Write-Host 'safety'
    Login 'uuid-X' 'X'   # an account that was never saved
    Check 'switch refused while the signed-in account is unsaved' ((Ds switch b).Code -ne 0)
    Check 'login untouched after the refusal' ((Cfg).'oauth:tokenCacheV2' -eq 'tok-X')
    Check 'switch with -SaveAs stores it first' ((Ds switch b -SaveAs x).Code -eq 0)
    Check 'x was saved' ((Get-ProfileTok 'x') -eq 'tok-X')
    Login 'uuid-Y' 'Y'
    Check '-SaveAs refuses a name that already exists' ((Ds switch b -SaveAs a).Code -ne 0)
    1..12 | ForEach-Object { Ds switch a | Out-Null; Ds switch b | Out-Null }
    Check 'backups are pruned to 10' ((Get-ChildItem "$env:DSWAP_STORE\backups" -Directory).Count -le 10)

    Write-Host 'messages reach the tray as UTF-8'
    Login 'uuid-X2' 'X2'
    $env:DSWAP_RESULT = Join-Path $root 'result.txt'; $env:DSWAP_LANG = 'pt'
    [void](Ds switch b)
    $txt = [IO.File]::ReadAllText($env:DSWAP_RESULT, [Text.Encoding]::UTF8)
    Remove-Item Env:\DSWAP_RESULT; $env:DSWAP_LANG = 'en'
    Check 'accented text is intact in the result file' ($txt -match 'não' -and $txt -match '^ERROR:' )

    Write-Host 'remove'
    Check 'remove c' ((Ds remove c).Code -eq 0)
    Check 'c is gone' (-not (Test-Path "$env:DSWAP_STORE\profiles\c"))
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:fail) { Write-Host "`n$script:fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed."
