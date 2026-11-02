# Removes Claude Account Switcher. Your saved accounts are kept unless you pass -RemoveData.
param([switch]$RemoveData)
$ErrorActionPreference = 'Stop'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '-File\s+"[^"]*tray\.ps1"' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500

Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Account Switcher.vbs') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude Account Switcher.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher') -Recurse -Force -ErrorAction SilentlyContinue

$store = Join-Path $env:USERPROFILE '.claude-desktop-swap'
if ($RemoveData) { Remove-Item $store -Recurse -Force -ErrorAction SilentlyContinue; Write-Host 'Removed the app and all saved accounts.' }
else { Write-Host "Removed the app. Saved accounts are still in $store (run with -RemoveData to delete them)." }
