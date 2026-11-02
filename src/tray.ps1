# Claude Account Switcher - system tray app. Everything runs locally.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
[Windows.Forms.Application]::EnableVisualStyles()

$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\ClaudeAccountSwitcherTray', [ref]$created)
if (-not $created) { exit }

. (Join-Path $PSScriptRoot 'common.ps1')
$dswap = Join-Path $PSScriptRoot 'dswap.ps1'
$launcher = Join-Path $PSScriptRoot 'launcher.vbs'
$startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Account Switcher.vbs'
New-Item -ItemType Directory -Force $Store | Out-Null

$script:proc = $null
$script:then = $null
$script:what = ''
$script:addName = $null
$script:addOld = $null

$ni = New-Object Windows.Forms.NotifyIcon
$menu = New-Object Windows.Forms.ContextMenuStrip
$ni.ContextMenuStrip = $menu
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 600

function New-TrayIcon([string]$label) {
    $bmp = New-Object Drawing.Bitmap 32, 32
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(217, 119, 87))), 1, 1, 30, 30)
    $font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString($label, $font, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(0, 1, 32, 32)), $sf)
    $g.Dispose()
    [Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$script:iconKey = $null
function Update-Icon {
    $cur = Get-Current
    $key = "$cur"
    if ($key -eq $script:iconKey -and $ni.Icon) { return }   # unchanged: do not rebuild the icon
    $script:iconKey = $key
    $old = $ni.Icon
    $ni.Icon = New-TrayIcon $(if ($cur) { $cur.Substring(0, 1).ToUpper() } else { '?' })
    $ni.Text = ($(if ($cur) { "Claude: $cur" } else { 'Claude' }) + " (v$AppVersion)")
    if ($old) { $old.Dispose() }
}

# Accounts are identified by what the app is really signed in to, so signing in by hand is noticed too.
$iconTimer = New-Object Windows.Forms.Timer
$iconTimer.Interval = 5000
$iconTimer.add_Tick({ try { Update-Icon } catch {} })

# An account that is signed in but was never saved has to be named before it can be replaced.
function Get-SaveAsArgs {
    if ((Get-LiveInfo).LoggedIn -and -not (Get-Current)) {
        $n = Ask-Name (T 'p_save')
        if (-not $n) { return [pscustomobject]@{ Cancel = $true; Args = @() } }
        if ((Get-ProfileNames) -contains $n) { Show-Balloon (T 'exists' $n) 'Warning'; return [pscustomobject]@{ Cancel = $true; Args = @() } }
        return [pscustomobject]@{ Cancel = $false; Args = @('-SaveAs', $n); Name = $n }
    }
    return [pscustomobject]@{ Cancel = $false; Args = @() }
}

function Show-Balloon([string]$text, [string]$icon = 'Info', [int]$ms = 3000) { $ni.ShowBalloonTip($ms, (T 'title'), $text, $icon) }

function Show-Msg([string]$text, [string]$buttons = 'OKCancel') {
    $owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false; StartPosition = 'CenterScreen'; Opacity = 0 }
    $owner.Show()
    $r = [Windows.Forms.MessageBox]::Show($owner, $text, (T 'title'), $buttons, 'Question')
    $owner.Dispose()
    return "$r"
}

function Ask-Name([string]$prompt) {
    $n = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, (T 'title'), '').Trim()
    if (-not $n) { return $null }
    if ($n -notmatch '^[\w.-]{1,40}$') { Show-Balloon (T 'bad_name') 'Warning' 5000; return $null }
    return $n
}

# Runs dswap.ps1 hidden; $then (optional scriptblock) runs after a successful exit.
function Start-Dswap([string[]]$dargs, [string]$what, [scriptblock]$then = $null) {
    if ($script:proc -and -not $script:proc.HasExited) { Show-Balloon (T 'b_busy'); return }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dswap`"") + $dargs
    Remove-Item $LogFile, "$LogFile.out", "$LogFile.err" -ErrorAction SilentlyContinue
    $env:DSWAP_RESULT = $LogFile   # dswap writes its messages here as UTF-8 (the console output is in the OEM code page)
    $script:proc = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru -RedirectStandardOutput "$LogFile.out" -RedirectStandardError "$LogFile.err"
    $null = $script:proc.Handle   # without this, ExitCode can come back empty for a fast-exiting process and a success looks like a failure
    $script:what = $what
    $script:then = $then
    $timer.Start()
}

$timer.add_Tick({
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        Update-Icon
        $then = $script:then; $script:then = $null
        $code = $script:proc.ExitCode
        if ($code -eq 0 -or $null -eq $code) {   # empty code = the process ended cleanly but we could not read it; failures always print an ERROR line (checked below)
            $errLine = @(Get-Content $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ERROR:' }) | Select-Object -Last 1
            if ($errLine) { Show-Balloon (T 'b_failed' ("$errLine" -replace '^ERROR:\s*', '')) 'Error' 8000; return }
            if ($script:what) { Show-Balloon $script:what }
            if ($then) { & $then }
        }
        else {
            $err = @(Get-Content $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '\S' }) | Select-Object -Last 1
            Show-Balloon (T 'b_failed' ("$err" -replace '^ERROR:\s*', '')) 'Error' 8000
        }
    }
})

# ---- add account: begin -> user signs in -> finish (or cancel -> back to the old account)
function Invoke-AddAccount {
    $name = Ask-Name (T 'p_add')
    if (-not $name) { return }
    if ((Get-ProfileNames) -contains $name) { Show-Balloon (T 'exists' $name) 'Warning'; return }
    if ((Show-Msg (T 'p_add_intro')) -ne 'OK') { return }
    $sa = Get-SaveAsArgs
    if ($sa.Cancel) { return }
    $script:addName = $name
    $script:addOld = if ($sa.Name) { $sa.Name } else { Get-Current }   # $null when nothing was signed in
    Start-Dswap (@('add-begin', $name) + $sa.Args) '' {
        if ((Show-Msg (T 'p_add_wait')) -eq 'OK') {
            Start-Dswap @('add-finish', $script:addName) (T 'add_done' $script:addName)
        }
        elseif ($script:addOld) {
            Start-Dswap @('switch', $script:addOld) (T 'switched' $script:addOld)
        }
    }
}

function Set-StartWithWindows([bool]$on) {
    if ($on) { Copy-Item $launcher $startupLink -Force } elseif (Test-Path $startupLink) { Remove-Item $startupLink -Force }
}

$menu.add_Opening({
    $menu.Items.Clear()
    Update-Icon
    $cur = Get-Current
    $names = Get-ProfileNames
    $h = $menu.Items.Add((T 'm_switch')); $h.Enabled = $false
    foreach ($n in $names) {
        $it = $menu.Items.Add($n); $it.Tag = $n; $it.Checked = ($n -eq $cur)
        $it.add_Click({ param($s, $e)
            if ($s.Tag -eq (Get-Current)) { return }
            $sa = Get-SaveAsArgs
            if ($sa.Cancel) { return }
            Start-Dswap (@('switch', $s.Tag) + $sa.Args) (T 'switched' $s.Tag)
        })
    }
    if (-not $cur -and (Get-LiveInfo).LoggedIn) {
        $it = $menu.Items.Add((T 'm_save'))
        $it.add_Click({
            $n = Ask-Name (T 'p_save')
            if ($n) { Start-Dswap @('save', $n) (T 'saved' $n) }
        })
    }
    [void]$menu.Items.Add('-')
    $it = $menu.Items.Add((T 'm_add')); $it.add_Click({ Invoke-AddAccount })
    if ($names.Count -gt 0) {
        $sub = $menu.Items.Add((T 'm_remove'))
        foreach ($n in $names) {
            $si = $sub.DropDownItems.Add($n); $si.Tag = $n
            $si.add_Click({ param($s, $e)
                if ((Show-Msg (T 'p_remove' $s.Tag) 'YesNo') -eq 'Yes') { Start-Dswap @('remove', $s.Tag) (T 'removed' $s.Tag) }
            })
        }
    }
    [void]$menu.Items.Add('-')
    $it = $menu.Items.Add((T 'm_share')); $it.Checked = [bool](Get-Setting 'shareSessions' $true)
    $it.add_Click({ param($s, $e) Set-Setting 'shareSessions' (-not $s.Checked) })
    $it = $menu.Items.Add((T 'm_startup')); $it.Checked = (Test-Path $startupLink)
    $it.add_Click({ param($s, $e) Set-StartWithWindows (-not $s.Checked) })
    [void]$menu.Items.Add('-')
    $it = $menu.Items.Add((T 'm_exit'))
    $it.add_Click({ $ni.Visible = $false; [Windows.Forms.Application]::Exit() })
})

$ni.add_MouseClick({ param($s, $e)
    if ($e.Button -eq 'Left') {
        [Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($ni, $null)
    }
})

Update-Icon
$iconTimer.Start()
$ni.Visible = $true
if (-not $Data) { Show-Balloon (T 'no_claude') 'Error' 8000 }
elseif (-not (Get-ProfileNames)) { Show-Balloon ((T 'b_first_run') + ' ' + (T 'b_hint')) 'Info' 10000 }
[Windows.Forms.Application]::Run()
$ni.Dispose(); $mutex.ReleaseMutex()
