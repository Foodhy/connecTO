# Quita connecTO de la bandeja, del arranque y del firewall privado.

$ErrorActionPreference = "Stop"
Get-Process connecTOWin -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "connecTO" -ErrorAction SilentlyContinue
Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command Remove-NetFirewallRule -Name connecTO -ErrorAction SilentlyContinue"
$dest = Join-Path $env:LOCALAPPDATA "Programs\connecTO"
if (Test-Path $dest) {
    Remove-Item -Path $dest -Recurse -Force
}
Write-Host "connecTO se quitó de este PC."
