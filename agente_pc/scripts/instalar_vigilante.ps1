# Instala el VIGILANTE del agente Matix en el Programador de tareas: corre
# vigilar_agente.ps1 cada 5 minutos (solo con sesion iniciada, sin admin).
# Capa 2 del autoarranque: el .lnk de la carpeta de Inicio lanza al logon
# (instalar_autostart.ps1) y el vigilante cubre los casos en que el Startup
# no dispara o el agente muere a mitad de sesion. Idempotente. ASCII puro.
#
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\instalar_vigilante.ps1
# Quitar: schtasks /Delete /F /TN MatixAgenteVigilante

$ErrorActionPreference = "Stop"
$Nombre = "MatixAgenteVigilante"
$vigilante = Join-Path $PSScriptRoot "vigilar_agente.ps1"
if (-not (Test-Path $vigilante)) {
    Write-Error "No encuentro $vigilante"
    exit 1
}

$accion = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$vigilante`""
schtasks /Create /F /TN $Nombre /SC MINUTE /MO 5 /TR $accion | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "schtasks fallo (codigo $LASTEXITCODE)"
    exit 1
}
Write-Host "Tarea '$Nombre' instalada: revisa cada 5 min y relanza el agente si murio."
Write-Host "Probarla ya: schtasks /Run /TN $Nombre"
