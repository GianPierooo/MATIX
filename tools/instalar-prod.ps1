<#
.SYNOPSIS
  Compila el APK release de Matix con la config de PROD e instala al
  dispositivo conectado por USB. Para iterar rápido en device sin pasar por el
  OTA.

.DESCRIPTION
  Reproduce los mismos --dart-define que inyecta el CI (.github/workflows/
  release.yml) en el build de producción:
    MATIX_API_URL   URL del cerebro en Railway (pública)
    MATIX_API_KEY   token X-Matix-Key (SECRETO — no va al repo)
    MATIX_ENV=prod
    MATIX_BUILD_NUMBER

  La API key se lee de (en orden):
    1) la variable de entorno  $env:MATIX_API_KEY
    2) el archivo  tools/.env.prod.local  (NO versionado; ver el .example)
  Si no está en ninguno, el script falla con instrucciones claras.

  NO toca el flujo del CI: es solo para desarrollo local. El APK local va
  firmado con la debug keystore (no la de release del CI), por eso se
  desinstala la versión previa antes de instalar (firmas distintas).

.EXAMPLE
  powershell -File tools/instalar-prod.ps1
#>
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repo 'app'
$envFile = Join-Path $PSScriptRoot '.env.prod.local'

# --- 1) Cargar config local (no versionada) -------------------------------
$cfg = @{}
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -and -not $t.StartsWith('#') -and $t.Contains('=')) {
      $parts = $t -split '=', 2
      $cfg[$parts[0].Trim()] = $parts[1].Trim()
    }
  }
}

# La env var pisa al archivo.
$apiKey = $env:MATIX_API_KEY
if (-not $apiKey) { $apiKey = $cfg['MATIX_API_KEY'] }

$apiUrl = $env:MATIX_API_URL
if (-not $apiUrl) { $apiUrl = $cfg['MATIX_API_URL'] }
if (-not $apiUrl) { $apiUrl = 'https://matix-production.up.railway.app' }

if (-not $apiKey) {
  Write-Host ''
  Write-Host 'ERROR: falta MATIX_API_KEY (la config de prod necesita la API key).' -ForegroundColor Red
  Write-Host ''
  Write-Host 'Ponla de UNA de estas dos formas (NO se sube al repo):'
  Write-Host '  1) Variable de entorno, en esta terminal:'
  Write-Host "       `$env:MATIX_API_KEY = '<la key>'"
  Write-Host '  2) Archivo  tools/.env.prod.local  con la linea:'
  Write-Host '       MATIX_API_KEY=<la key>'
  Write-Host '     (plantilla:  copy tools\.env.prod.local.example tools\.env.prod.local)'
  Write-Host ''
  Write-Host 'Es la MISMA MATIX_API_KEY que esta en cerebro/.env.' -ForegroundColor Yellow
  exit 1
}

# Build number alto: en dev no queremos que el chequeo de update crea que el
# APK del OTA (build ~70) es "mas nuevo" y nos ofrezca bajarlo.
$buildNum = 900000

# --- 2) Compilar release arm64 con config de prod -------------------------
Write-Host "Compilando release arm64 con config PROD (env=prod, url=$apiUrl)..." -ForegroundColor Cyan
Push-Location $appDir
try {
  # OJO: la API key viaja como argumento de --dart-define; no la imprimimos.
  & flutter build apk --release --target-platform android-arm64 `
    --build-number=$buildNum `
    --dart-define=MATIX_API_URL=$apiUrl `
    --dart-define=MATIX_API_KEY=$apiKey `
    --dart-define=MATIX_ENV=prod `
    --dart-define=MATIX_BUILD_NUMBER=$buildNum
  if ($LASTEXITCODE -ne 0) { throw "flutter build fallo (exit $LASTEXITCODE)" }
} finally {
  Pop-Location
}

$apk = Join-Path $appDir 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path $apk)) { Write-Host "No se encontro el APK: $apk" -ForegroundColor Red; exit 1 }

# --- 3) Localizar adb -----------------------------------------------------
$candidatos = @()
if ($env:ANDROID_HOME) { $candidatos += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') }
if ($env:ANDROID_SDK_ROOT) { $candidatos += (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe') }
$candidatos += (Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe')

$adb = $null
foreach ($c in $candidatos) {
  if ($c -and (Test-Path $c)) { $adb = $c; break }
}
if (-not $adb) {
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) { $adb = $cmd.Source }
}
if (-not $adb) { Write-Host 'No encontre adb (instala platform-tools o agrega adb al PATH).' -ForegroundColor Red; exit 1 }

$conectados = (& $adb devices) | Select-String -Pattern "device$"
if (-not $conectados) {
  Write-Host 'No hay device conectado/autorizado. Revisa USB + depuracion USB.' -ForegroundColor Red
  exit 1
}

# --- 4) Reinstalar (desinstala primero: firma debug != release del OTA) ----
Write-Host 'Desinstalando version previa (si la hay)...' -ForegroundColor Cyan
& $adb uninstall dev.matix.matix 2>$null | Out-Null

Write-Host 'Instalando...' -ForegroundColor Cyan
& $adb install $apk
if ($LASTEXITCODE -ne 0) { Write-Host 'adb install fallo.' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host 'OK: instalado con config PROD.' -ForegroundColor Green
Write-Host 'Abre Matix > Ajustes: "Entorno" debe decir prod y la URL apuntar a Railway.'
