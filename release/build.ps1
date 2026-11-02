# Builds dist\Claude-Account-Switcher.zip (the file people download from the GitHub release).
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ver = (Select-String -Path (Join-Path $root 'src\common.ps1') -Pattern "AppVersion = '([\d.]+)'").Matches.Groups[1].Value
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'Claude-Account-Switcher'
Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $stage 'src') | Out-Null

$files = @{
    'Install.cmd' = 'Install.cmd'; 'Uninstall.cmd' = 'Uninstall.cmd'
    'install.ps1' = 'install.ps1'; 'uninstall.ps1' = 'uninstall.ps1'
    'LICENSE' = 'LICENSE'; 'release\LEIA-ME.txt' = 'LEIA-ME.txt'
    'src\common.ps1' = 'src\common.ps1'; 'src\dswap.ps1' = 'src\dswap.ps1'; 'src\tray.ps1' = 'src\tray.ps1'
}
foreach ($k in $files.Keys) {
    $text = [IO.File]::ReadAllText((Join-Path $root $k)) -replace "`r?`n", "`r`n"   # Windows line endings, whatever git checked out
    $bom = $k -match '\.ps1$|\.txt$'                                                  # BOM so PowerShell and Notepad read accents right
    [IO.File]::WriteAllText((Join-Path $stage $files[$k]), $text, (New-Object Text.UTF8Encoding $bom))
}
$zip = Join-Path $dist 'Claude-Account-Switcher.zip'
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Built $zip (v$ver, $([Math]::Round((Get-Item $zip).Length / 1KB)) KB)"
