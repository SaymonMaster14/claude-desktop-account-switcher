<#
  dswap - command line for Claude Account Switcher (Claude Desktop, Windows).
  Most people never need this: use the tray icon. Run from an external PowerShell, not from inside the Claude app.

    dswap list                       accounts you saved ('*' = the one signed in right now)
    dswap save <name>                save the account that is signed in right now
    dswap switch <name>              switch to a saved account (-SaveAs <n> names an unsaved current account first)
    dswap add <name>                 guided: store current, sign in with a new account, store it
    dswap remove <name>              forget a saved account (does not sign out of the app)
    dswap sync                       share Code-tab sessions between accounts now
    dswap share on|off               auto-share sessions on every switch (default: on)
    dswap restore-backup [folder]    list backups, or restore one

  Flags: -NoLaunch (do not reopen the app)   -SaveAs <name>
#>
param(
    [Parameter(Position = 0)][string]$Cmd = 'help',
    [Parameter(Position = 1)][string]$Name,
    [string]$SaveAs,
    [switch]$NoLaunch
)
. (Join-Path $PSScriptRoot 'common.ps1')

function Do-Sync {
    $n = Sync-Sessions
    if ($n -gt 0) { Say (T 'synced' $n) }
}

# Make sure whatever is signed in right now is stored before we replace it.
#  - signed out                 -> nothing to store
#  - matches a saved profile    -> refresh that profile
#  - an account we never saved  -> needs -SaveAs, otherwise refuse (it would be lost)
function Store-Current {
    $live = Get-LiveInfo
    if (-not $live.LoggedIn) { return $null }
    $cur = Get-Current
    if ($cur) { Save-Profile $cur; Say (T 'updated' $cur); return $cur }
    if (-not $SaveAs) { Die (T 'unnamed') }
    [void](Get-ProfilePath $SaveAs)
    if (Test-Path (Get-ProfilePath $SaveAs)) { Die (T 'exists' $SaveAs) }
    Save-Profile $SaveAs; Say (T 'saved' $SaveAs)
    return $SaveAs
}

try {
    switch ($Cmd) {
        'list' {
            $cur = Get-Current
            $names = Get-ProfileNames
            if (-not $names) { Say (T 'no_profiles'); break }
            foreach ($n in $names) {
                $u = Get-ProfileUuid $n
                Say ('{0} {1}   {2}' -f $(if ($n -eq $cur) { '*' } else { ' ' }), $n, $(if ($u) { $u.Substring(0, [Math]::Min(8, $u.Length)) } else { '' }))
            }
        }
        'save' {
            if (-not $Name) { Die 'Usage: dswap save <name>' }
            [void](Get-ProfilePath $Name)
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try { Assert-NotDuplicate $Name; Save-Profile $Name; Say (T 'saved' $Name) }
            finally { Start-App }
        }
        'switch' {
            if (-not $Name) { Die 'Usage: dswap switch <name>' }
            if (-not (Test-Path (Get-ProfilePath $Name))) { Die (T 'no_profile' $Name) }
            Assert-Claude; Assert-NotInsideApp
            if ((Get-LiveInfo).LoggedIn -and -not (Get-Current) -and -not $SaveAs) { Die (T 'unnamed') }   # check before closing the app
            Stop-App
            try {
                Backup-Now
                $stored = Store-Current
                if ($stored -eq $Name) { Say (T 'switched' $Name); break }   # already that account
                Import-Login (Get-ProfilePath $Name)
                Do-Sync
                Say (T 'switched' $Name)
            }
            finally { Start-App }
        }
        # 'add' is split in two so the tray can show its own dialogs in between.
        'add-begin' {
            if (-not $Name) { Die 'Usage: dswap add-begin <name>' }
            if (Test-Path (Get-ProfilePath $Name)) { Die (T 'exists' $Name) }
            Assert-Claude; Assert-NotInsideApp
            if ((Get-LiveInfo).LoggedIn -and -not (Get-Current) -and -not $SaveAs) { Die (T 'unnamed') }
            Stop-App
            try {
                Backup-Now
                [void](Store-Current)
                Clear-Login
                Say (T 'adding')
            }
            finally { Start-App }
        }
        'add-finish' {
            if (-not $Name) { Die 'Usage: dswap add-finish <name>' }
            Assert-Claude; Assert-NotInsideApp
            [void](Get-ProfilePath $Name)
            if (-not (Get-LiveInfo).LoggedIn) { Die (T 'no_login') }   # check before closing the app
            Stop-App
            try {
                Assert-NotDuplicate $Name
                Save-Profile $Name
                Do-Sync
                Say (T 'add_done' $Name)
            }
            finally { Start-App }
        }
        'add' {
            if (-not $Name) { Die 'Usage: dswap add <name>' }
            $NoLaunch = $false
            & $PSCommandPath add-begin $Name
            if ($LASTEXITCODE -ne 0) { exit 1 }
            Read-Host "`n$(T 'p_add_wait')`nENTER" | Out-Null
            & $PSCommandPath add-finish $Name
            if ($LASTEXITCODE -ne 0) { exit 1 }
        }
        'remove' {
            if (-not $Name) { Die 'Usage: dswap remove <name>' }
            $p = Get-ProfilePath $Name
            if (-not (Test-Path $p)) { Die (T 'no_profile' $Name) }
            Remove-Item $p -Recurse -Force
            Say (T 'removed' $Name)
        }
        'sync' {
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try { Do-Sync } finally { Start-App }
        }
        'share' {
            if ($Name -notin 'on', 'off') { Die 'Usage: dswap share on|off' }
            Set-Setting 'shareSessions' ($Name -eq 'on')
            Say (T $(if ($Name -eq 'on') { 'share_on' } else { 'share_off' }))
        }
        'restore-backup' {
            if (-not $Name) { if (Test-Path $Backups) { Get-ChildItem $Backups -Directory | Sort-Object Name | ForEach-Object Name }; break }
            $b = Join-Path $Backups $Name
            if (-not (Test-Path $b)) { Die 'Backup not found.' }
            Assert-Claude; Assert-NotInsideApp; Stop-App
            try { Import-Login $b; Say "Backup '$Name' restored." } finally { Start-App }
        }
        default { Get-Content $PSCommandPath -TotalCount 17 | Select-Object -Skip 1 | Write-Host }
    }
}
catch {
    Say ('ERROR: ' + $_.Exception.Message) 'Red'
    exit 1
}
