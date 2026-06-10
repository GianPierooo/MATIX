<#
.SYNOPSIS
  Deja el agente local de Matix arrancando solo al iniciar sesion en Windows.

.DESCRIPTION
  Crea un acceso directo en la carpeta de INICIO (Startup) del usuario que lanza
  el agente con pythonw.exe (ventana oculta) a traves del lanzador scripts/arrancar.py.

  Por que la carpeta de Inicio y NO una Tarea Programada: bajo Task Scheduler,
  pythonw.exe se cuelga en el arranque del interprete (hereda handles de stdio
  invalidos en esa sesion); el proceso queda vivo pero nunca conecta. La carpeta
  de Inicio lanza en la sesion interactiva real, que es donde el agente conecta
  sin problemas. Sin admin, sin ventana, sin elevacion.

  Es idempotente: re-ejecutarlo reemplaza el acceso directo. Tambien limpia una
  Tarea Programada vieja (MatixAgentePC) si quedo de instalaciones previas.

  Diagnostico: el arranque crudo queda en agente_pc/agente_autostart.log y el log
  estructurado del daemon en agente_pc/agente_runtime.log.

  Para quitarlo: scripts/desinstalar_autostart.ps1

.NOTES
  NO requiere admin. Si ExecutionPolicy lo bloquea:
    powershell -ExecutionPolicy Bypass -File scripts\instalar_autostart.ps1
#>

$ErrorActionPreference = "Stop"
$NombreAcceso = "MatixAgentePC"
$TareaVieja   = "MatixAgentePC"   # de intentos previos con Task Scheduler

# Raiz del agente = carpeta padre de scripts/
$Raiz = Split-Path -Parent $PSScriptRoot

# Interprete: pythonw.exe (sin consola) preferido; python.exe como respaldo.
$pythonw = Join-Path $Raiz ".venv\Scripts\pythonw.exe"
$python  = Join-Path $Raiz ".venv\Scripts\python.exe"
if (Test-Path $pythonw) {
    $exe = $pythonw
} elseif (Test-Path $python) {
    $exe = $python
} else {
    Write-Error "No encuentro el .venv del agente ($Raiz\.venv). Corre 'uv sync' en esa carpeta y reintenta."
    exit 1
}

$launcher = Join-Path $PSScriptRoot "arrancar.py"
if (-not (Test-Path $launcher)) {
    Write-Error "No encuentro el lanzador: $launcher"
    exit 1
}

Write-Host "Agente:     $Raiz"
Write-Host "Interprete: $exe"
Write-Host "Lanzador:   $launcher"

# Aviso si la sesion esta elevada (el agente debe correr con permisos minimos).
$idActual = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$prActual = New-Object System.Security.Principal.WindowsPrincipal($idActual)
if ($prActual.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Estas en una sesion ELEVADA. Corre este script en una sesion NORMAL: el agente debe correr con permisos minimos."
}

# Limpia una Tarea Programada vieja, si quedo de instalaciones anteriores.
$tareaVieja = Get-ScheduledTask -TaskName $TareaVieja -ErrorAction SilentlyContinue
if ($tareaVieja) {
    Write-Host "Quito una Tarea Programada vieja (migramos a carpeta de Inicio)."
    try { Stop-ScheduledTask -TaskName $TareaVieja -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName $TareaVieja -Confirm:$false -ErrorAction SilentlyContinue
}

# Crea el acceso directo en la carpeta de Inicio del usuario.
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup "$NombreAcceso.lnk"

$sh = New-Object -ComObject WScript.Shell
$acceso = $sh.CreateShortcut($lnk)
$acceso.TargetPath       = $exe
$acceso.Arguments        = '"' + $launcher + '"'
$acceso.WorkingDirectory = $Raiz
$acceso.WindowStyle      = 7   # minimizado (pythonw no muestra ventana igual)
$acceso.Description      = "Agente local de Matix (Capa 6). Arranca al iniciar sesion, oculto."
$acceso.Save()

Write-Host "Acceso directo creado en Inicio:"
Write-Host "  $lnk"

# Lanzarlo ya (no hace falta esperar al proximo login).
Start-Process -FilePath $exe -ArgumentList ('"' + $launcher + '"') -WorkingDirectory $Raiz | Out-Null
Start-Sleep -Seconds 6

# Verifica que el proceso quedo vivo.
$vivo = Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like '*arrancar.py*' } | Select-Object -First 1
Write-Host ""
if ($vivo) {
    Write-Host "Agente corriendo (PID $($vivo.ProcessId))."
} else {
    Write-Warning "No veo el proceso del agente; revisa agente_pc\agente_autostart.log"
}
Write-Host "Diagnostico:    $Raiz\agente_autostart.log"
Write-Host "Log de runtime: $Raiz\agente_runtime.log"
Write-Host ""
Write-Host "Listo. El agente arrancara solo cada vez que inicies sesion en Windows."
Write-Host "Para quitarlo: scripts\desinstalar_autostart.ps1"
