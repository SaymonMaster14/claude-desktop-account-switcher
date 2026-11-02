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

    Write-Host 'safety'
    Ds switch a | Out-Null
    [IO.File]::WriteAllText("$env:DSWAP_STORE\state.json", '{"current":null}')
    Check 'switch refused while current account is unnamed' ((Ds switch b).Code -ne 0)
    Check 'switch with -Force works' ((Ds switch b -Force).Code -eq 0)
    1..12 | ForEach-Object { Ds switch a | Out-Null; Ds switch b | Out-Null }
    Check 'backups are pruned to 10' ((Get-ChildItem "$env:DSWAP_STORE\backups" -Directory).Count -le 10)

    Write-Host 'remove'
    Check 'remove c' ((Ds remove c).Code -eq 0)
    Check 'c is gone' (-not (Test-Path "$env:DSWAP_STORE\profiles\c"))
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:fail) { Write-Host "`n$script:fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed."
