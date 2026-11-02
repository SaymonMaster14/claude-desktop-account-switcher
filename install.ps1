# Installs Claude Account Switcher for the current Windows user (no admin needed).
# Copies the app to %LOCALAPPDATA%\ClaudeAccountSwitcher, starts it with Windows and launches it now.
param([switch]$NoStart)
$ErrorActionPreference = 'Stop'

$src  = Join-Path $PSScriptRoot 'src'
$dest = Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher'
$startupDir = [Environment]::GetFolderPath('Startup')
$startMenu  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

# stop a running tray (any version) so files can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '-File\s+"[^"]*tray\.ps1"' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $src '*.ps1') $dest -Force
Get-ChildItem $dest -Filter *.ps1 | Unblock-File

# hidden launcher: no console window flashes at login
$vbs = 'CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + (Join-Path $dest 'tray.ps1') + '""", 0, False'
$launcher = Join-Path $dest 'launcher.vbs'
[IO.File]::WriteAllText($launcher, $vbs)

Copy-Item $launcher (Join-Path $startupDir 'Claude Account Switcher.vbs') -Force

$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startMenu 'Claude Account Switcher.lnk'))
$lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$lnk.Arguments = "`"$launcher`""
$lnk.IconLocation = Join-Path $env:WINDIR 'System32\imageres.dll,109'
$lnk.Save()

Write-Host "Installed to $dest"
if (-not $NoStart) {
    Start-Process wscript.exe -ArgumentList "`"$launcher`""   # the launcher exits at once, so the tray outlives this window
    Write-Host 'Started. Look for the orange circle in the system tray (the ^ arrow near the clock).'
}
