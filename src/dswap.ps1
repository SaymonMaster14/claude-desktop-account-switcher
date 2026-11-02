<#
  dswap - command line for Claude Account Switcher (Claude Desktop, Windows).
  Most people never need this: use the tray icon. Run from an external PowerShell, not from inside the Claude app.

    dswap list                       accounts you saved ('*' = current)
    dswap save <name>                save the account that is signed in right now
    dswap switch <name>              switch to a saved account
    dswap add <name>                 guided: store current, sign in with a new account, store it
    dswap remove <name>              forget a saved account (does not sign out of the app)
    dswap sync                       share Code-tab sessions between accounts now
    dswap share on|off               auto-share sessions on every switch (default: on)
    dswap restore-backup [folder]    list backups, or restore one

  Flags: -NoLaunch (do not reopen the app)   -Force (internal)
#>
param(
    [Parameter(Position = 0)][string]$Cmd = 'help',
    [Parameter(Position = 1)][string]$Name,
    [switch]$NoLaunch,
    [switch]$Force
)
. (Join-Path $PSScriptRoot 'common.ps1')

function Do-Sync {
    $n = Sync-Sessions
    if ($n -gt 0) { Write-Host (T 'synced' $n) } elseif ($n -lt 0) { Write-Host (T 'sync_wait') }
}

# Everything that must happen after the app is closed, to leave the current account safely stored.
function Save-CurrentIfNamed([bool]$allowUnnamed) {
    $cur = Get-Current
    if ($cur) { Save-Profile $cur; Write-Host (T 'updated' $cur) }
    elseif (-not $allowUnnamed) { Die (T 'unnamed') }
    return $cur
}

try {
    switch ($Cmd) {
        'list' {
            $cur = Get-Current
            $names = Get-ProfileNames
            if (-not $names) { Write-Host (T 'no_profiles'); break }
            foreach ($n in $names) {
                $u = Get-ProfileUuid $n
                '{0} {1}   {2}' -f $(if ($n -eq $cur) { '*' } else { ' ' }), $n, $(if ($u) { $u.Substring(0, [Math]::Min(8, $u.Length)) } else { '' })
            }
        }
        'save' {
            if (-not $Name) { Die 'Usage: dswap save <name>' }
            [void](Get-ProfilePath $Name)
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try { Assert-NotDuplicate $Name; Save-Profile $Name; Set-Current $Name; Write-Host (T 'saved' $Name) }
            finally { Start-App }
        }
        'switch' {
            if (-not $Name) { Die 'Usage: dswap switch <name>' }
            if (-not (Test-Path (Get-ProfilePath $Name))) { Die (T 'no_profile' $Name) }
            Assert-Claude; Assert-NotInsideApp
            if (-not (Get-Current) -and -not $Force) { Die (T 'unnamed') }
            Stop-App
            try {
                Backup-Now
                $cur = Get-Current
                if ($cur -and $cur -ne $Name) { Save-Profile $cur; Write-Host (T 'updated' $cur) }
                Import-Login (Get-ProfilePath $Name); Set-Current $Name
                Do-Sync
                Write-Host (T 'switched' $Name)
            }
            finally { Start-App }
        }
        # 'add' is split in two so the tray can show its own dialogs in between.
        'add-begin' {
            if (-not $Name) { Die 'Usage: dswap add-begin <name>' }
            if (Test-Path (Get-ProfilePath $Name)) { Die (T 'exists' $Name) }
            Assert-Claude; Assert-NotInsideApp
            if (-not (Get-Current)) { Die (T 'unnamed') }
            Stop-App
            try {
                Backup-Now
                [void](Save-CurrentIfNamed $false)
                Clear-Login; Set-Current $null
                Write-Host (T 'adding')
            }
            finally { Start-App }
        }
        'add-finish' {
            if (-not $Name) { Die 'Usage: dswap add-finish <name>' }
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try {
                [void](Get-ProfilePath $Name)
                Assert-NotDuplicate $Name
                Save-Profile $Name; Set-Current $Name
                Do-Sync
                Write-Host (T 'add_done' $Name)
            }
            finally { Start-App }
        }
        'add' {
            if (-not $Name) { Die 'Usage: dswap add <name>' }
            $NoLaunch = $false
            $old = Get-Current
            & $PSCommandPath add-begin $Name
            if ($LASTEXITCODE -ne 0) { exit 1 }
            Read-Host "`n$(T 'p_add_wait' $old)`nENTER" | Out-Null
            & $PSCommandPath add-finish $Name
            if ($LASTEXITCODE -ne 0) { exit 1 }
        }
        'remove' {
            if (-not $Name) { Die 'Usage: dswap remove <name>' }
            $p = Get-ProfilePath $Name
            if (-not (Test-Path $p)) { Die (T 'no_profile' $Name) }
            Remove-Item $p -Recurse -Force
            if ((Get-Current) -eq $Name) { Set-Current $null }
            Write-Host (T 'removed' $Name)
        }
        'sync' {
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try { Do-Sync } finally { Start-App }
        }
        'share' {
            if ($Name -notin 'on', 'off') { Die 'Usage: dswap share on|off' }
            Set-Setting 'shareSessions' ($Name -eq 'on')
            Write-Host (T $(if ($Name -eq 'on') { 'share_on' } else { 'share_off' }))
        }
        'restore-backup' {
            if (-not $Name) { if (Test-Path $Backups) { Get-ChildItem $Backups -Directory | Sort-Object Name | ForEach-Object Name }; break }
            $b = Join-Path $Backups $Name
            if (-not (Test-Path $b)) { Die 'Backup not found.' }
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try { Import-Login $b; Set-Current $null; Write-Host "Backup '$Name' restored." } finally { Start-App }
        }
        default { Get-Content $PSCommandPath -TotalCount 17 | Select-Object -Skip 1 | Write-Host }
    }
}
catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
