# Instala connecTO en la bandeja y lo arranca con Windows.
# Antes, en un equipo con el SDK:
#   dotnet publish connecTOWin/connecTOWin.csproj -c Release -r win-x64 --self-contained true -o connecTOWin/Install/payload
# En el PC:
#   powershell -ExecutionPolicy Bypass -File connecTOWin/Install/install.ps1

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$payload = Join-Path $here "payload"
if (-not (Test-Path (Join-Path $payload "connecTOWin.exe"))) {
    $payload = $here
}
if (-not (Test-Path (Join-Path $payload "connecTOWin.exe"))) {
    throw "No está connecTOWin.exe. Publica antes con dotnet publish -r win-x64."
}

$dest = Join-Path $env:LOCALAPPDATA "Programs\connecTO"
Get-Process connecTOWin -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $payload "*") -Destination $dest -Recurse -Force
$exe = Join-Path $dest "connecTOWin.exe"

$run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
New-Item -Path $run -Force | Out-Null
Set-ItemProperty -Path $run -Name "connecTO" -Value "`"$exe`""

$rule = "Remove-NetFirewallRule -Name connecTO -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName connecTO -Name connecTO -Direction Inbound -Program '$exe' -Action Allow -Profile Private"
Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $rule"
Start-Process $exe
Write-Host "connecTO está en la bandeja y arranca con Windows."
