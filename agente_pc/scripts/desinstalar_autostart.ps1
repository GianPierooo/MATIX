<#
.SYNOPSIS
  Quita el autostart del agente local de Matix (lo que instalo instalar_autostart.ps1).

.DESCRIPTION
  Borra el acceso directo de la carpeta de Inicio (y, por si quedo de versiones
  viejas, tambien una Tarea Programada 'MatixAgentePC'). Tras esto el agente YA
  NO arranca solo al iniciar sesion; podras seguir corriendolo a mano con:
    cd agente_pc
    uv run python -m agente_pc

  NO toca el .env, el .venv ni el codigo: solo quita el arranque automatico.
  Si hay un proceso del agente AUN corriendo, intenta cerrarlo.

.NOTES
  No requiere admin. Si ExecutionPolicy lo bloquea:
    powershell -ExecutionPolicy Bypass -File scripts\desinstalar_autostart.ps1
#>

$ErrorActionPreference = "Stop"
$NombreAcceso = "MatixAgentePC"
$TareaVieja   = "MatixAgentePC"

$algo = $false

# 1) Acceso directo en la carpeta de Inicio.
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup "$NombreAcceso.lnk"
if (Test-Path $lnk) {
    Remove-Item $lnk -Force
    Write-Host "Acceso directo de Inicio eliminado: $lnk"
    $algo = $true
}

# 2) Tarea Programada vieja (por si quedo de instalaciones previas).
$tarea = Get-ScheduledTask -TaskName $TareaVieja -ErrorAction SilentlyContinue
if ($tarea) {
    try { Stop-ScheduledTask -TaskName $TareaVieja -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName $TareaVieja -Confirm:$false
    Write-Host "Tarea Programada vieja '$TareaVieja' eliminada."
    $algo = $true
}

if (-not $algo) {
    Write-Host "No habia autostart instalado. Nada que quitar."
}

# 3) Cierra el proceso del agente si sigue vivo.
$vivos = Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like '*arrancar.py*' -or $_.CommandLine -like '*agente_pc*' }
foreach ($p in $vivos) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "Proceso del agente detenido (PID $($p.ProcessId))."
}

Write-Host "Listo. El agente ya no arranca solo."
