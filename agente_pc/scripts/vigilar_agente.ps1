# Vigilante del agente Matix (Capa 6). Lo corre el Programador de tareas cada
# 5 minutos: si el proceso del agente NO esta vivo, lo relanza oculto y deja
# rastro en agente_autostart.log. ASCII puro (sin acentos) a proposito: el
# Task Scheduler puede leer el .ps1 sin BOM como ANSI y un acento lo rompe.
#
# Por que existe: la carpeta de Inicio (Startup) es "mejor esfuerzo" y hubo un
# boot real (2026-06-12 11:10) en el que Windows NO lanzo el .lnk — cero rastro
# en logs y cero crash en el Visor de eventos. El vigilante garantiza ademas la
# RESURRECCION si el proceso muere por cualquier causa en medio de la sesion.
#
# Por que se lanza via cmd /c con stdio EXPLICITO (stdin desde NUL, stdout y
# stderr a archivo): bajo el Task Scheduler los handles de stdio son invalidos
# y el trampolin de pythonw (uv) se CUELGA en el arranque del interprete antes
# de ejecutar nada — se reprodujo incluso lanzando via Start-Process desde
# powershell (PID vivo, 0 CPU, sin log, sin conexion). Darle handles reales
# via cmd evita el cuelgue. Verificado en la PC real.

$ErrorActionPreference = "SilentlyContinue"

$Raiz = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $PSScriptRoot "arrancar.py"
$exe = Join-Path $Raiz ".venv\Scripts\pythonw.exe"
if (-not (Test-Path $exe)) { $exe = Join-Path $Raiz ".venv\Scripts\python.exe" }
if (-not (Test-Path $exe) -or -not (Test-Path $launcher)) { exit 0 }

$vivo = Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like '*arrancar.py*' } | Select-Object -First 1

if (-not $vivo) {
    # OJO: el stdio del proceso va a agente_vigilante.log, NO a
    # agente_autostart.log — arrancar.py abre ese ultimo para sus diagnosticos
    # y la redireccion de cmd lo dejaria bloqueado (PermissionError real).
    $logV = Join-Path $Raiz "agente_vigilante.log"
    $marca = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logV -Value "$marca vigilante: agente caido; relanzando"
    $linea = "/c """"$exe"" ""$launcher"" < NUL >> ""$logV"" 2>&1"""
    Start-Process -FilePath "cmd.exe" -ArgumentList $linea `
        -WorkingDirectory $Raiz -WindowStyle Hidden
}
