# Capa 6 — Agente de PC (6.0a/6.0b/6.1/6.2)

"PC y archivos": un agente local que corre en la computadora del usuario, un
transporte seguro nube↔local, y un framework de acciones tipadas y extensible.
Estado:
- **6.0a** — cimiento (conexión, registry, rails) + `listar_carpeta`.
- **6.0b** — lectura: `buscar_archivos`, `leer_archivo`, `resumir_documento`.
- **6.1** — organización con gate: `mover`, `renombrar`, `crear_carpeta`,
  `organizar`.
- **6.2** — abrir/cerrar apps de una allowlist dura y ejecutar tareas tipadas,
  todo con gate y sin shell (ver §1.1 y §2.1).

> Resumen en una línea: la PC abre una conexión saliente al cerebro, se
> autentica con un secreto, y solo deja que Matix vea lo que el usuario permitió,
> sin contenido, sin shell, con registro de cada acción.

---

## 1. Arquitectura

```
   ┌─────────────────┐        WebSocket sobre TLS         ┌──────────────────┐
   │  Agente local    │  ── conexión SALIENTE (la PC) ──▶ │     Cerebro       │
   │  (agente_pc/)    │   X-Agente-PC-Token (secreto)     │  (FastAPI/Railway)│
   │  en la PC        │ ◀── acciones ──   ── resultados ─▶│                   │
   └─────────────────┘                                    └──────────────────┘
            ▲                                                       ▲
            │ registry de acciones                                 │ tool del modelo
            │ + rails de seguridad                                 │ pc_listar_carpeta
            ▼                                                       ▼
     allowlist / denylist                                   chat de Matix ↔ app
     audit.log · sin shell
```

- **La PC siempre inicia.** El agente abre una conexión *saliente* al cerebro. El
  cerebro **nunca** inicia hacia la PC. No se abre ningún puerto en la máquina
  del usuario → nada que exponer ni escanear.
- **Un solo agente.** App de un solo usuario: el cerebro mantiene a lo sumo una
  conexión. Si llega una nueva (reconexión tras un corte), reemplaza a la vieja.
- **Reconexión automática.** Si la conexión se cae, el agente reintenta con
  backoff exponencial (1 s, 2 s, 4 s… hasta 60 s, con jitter).

### Piezas

| Pieza | Ubicación | Rol |
|---|---|---|
| Daemon / cliente WS | `agente_pc/agente_pc/cliente.py`, `daemon.py` | conexión saliente, reconexión, kill switch |
| Registry de acciones | `agente_pc/agente_pc/registro.py` | acciones tipadas con nivel de riesgo + gate `confirmado` |
| Acciones | `agente_pc/agente_pc/acciones.py` | catálogo (ver §1.1) |
| Rails de seguridad | `agente_pc/agente_pc/seguridad.py` | allowlist / denylist / ocultar secretos |
| Audit log | `agente_pc/agente_pc/auditoria.py` | una línea por acción en `agente_pc/audit.log` |
| Canal (cerebro) | `cerebro/app/agente/canal.py` | conexión viva + correlación + `confirmado` |
| Endpoint (cerebro) | `cerebro/app/routers/agente.py` | `WS /agente/ws` + `GET /agente/estado` + `POST /agente/ejecutar` |
| Tools del modelo | `cerebro/app/matix/tools.py` (`pc_*`) | el modelo enruta/propone acciones a la PC |
| Gate consecuente (app) | `app/lib/features/matix/presentation/dispositivo_confirmacion.dart` | reusa el sheet del teléfono (`pc_accion`) |
| Indicador (app) | `app/lib/screens/ajustes_screen.dart` (Ajustes → Conexión) | "PC: conectada / desconectada" |

### 1.1 Acciones disponibles

Cada acción se valida en el BORDE (en el agente): allowlist + denylist sobre la
ruta REAL resuelta (symlinks/`..`). Las **consecuentes** además exigen
`confirmado=true` (gate del lado agente) y NUNCA las dispara el modelo.

| Acción (agente) | Fase | Riesgo | Tool del cerebro | Qué hace |
|---|---|---|---|---|
| `listar_carpeta` | 6.0a | segura | `pc_listar_carpeta` | nombres de una carpeta (sin contenido) |
| `buscar_archivos` | 6.0b | segura | `pc_buscar_archivos` | busca por nombre/glob → ruta, tamaño, fecha |
| `leer_archivo` | 6.0b | segura | `pc_leer_archivo` | contenido de TEXTO (binarios: no) con tope |
| `leer_bytes` | 6.0b | segura | (interna de `pc_resumir_documento`) | bytes de un PDF/DOCX/TXT/MD (≤5 MB) |
| `planificar_organizacion` | 6.1 | segura | (preview de `pc_organizar_carpeta`) | calcula el plan SIN ejecutar |
| `mover_archivo` | 6.1 | **consecuente** | `pc_mover_archivo` | mueve (sin sobreescribir) |
| `renombrar_archivo` | 6.1 | **consecuente** | `pc_renombrar_archivo` | renombra (nombre simple) |
| `crear_carpeta` | 6.1 | **consecuente** | `pc_crear_carpeta` | crea una carpeta |
| `organizar_aplicar` | 6.1 | **consecuente** | `pc_organizar_carpeta` | ejecuta el plan paso a paso |
| `abrir_app` | 6.2 | **consecuente** | `pc_abrir_app` | abre una app de la allowlist de apps (sin shell) |
| `cerrar_app` | 6.2 | **consecuente** | `pc_cerrar_app` | cierra (graceful) las instancias que el agente abrió esta sesión |
| `ejecutar_tarea` | 6.2 | **consecuente** | `pc_ejecutar_tarea` | ejecuta una tarea PREDEFINIDA y tipada (no comandos) |

`resumir_documento` (tool `pc_resumir_documento`): el agente manda los bytes
(`leer_bytes`), el cerebro **reutiliza** el extractor `app/matix/
extraccion_documentos.py` (PDF/DOCX/TXT/MD) y resume con el modelo **mini**
(`gpt-4o-mini`). El texto del documento es DATO, no instrucciones.

**Sin borrado.** Eliminar es irreversible y queda fuera; irá en una acción
propia con confirmación reforzada.

#### 6.2 — Abrir apps y ejecutar tareas tipadas

Las acciones 6.2 pueden **lanzar procesos** en la PC, así que el modelo de
seguridad es más estricto (ver §2.1):

- `abrir_app(nombre)` — abre un programa de la **allowlist de apps**
  configurable (`AGENTE_PC_APPS_ALLOWLIST`, ver §3.3). Solo apps de la lista; la
  **denylist dura** (shells, instaladores, herramientas de sistema, gestor de
  credenciales) gana siempre. Se lanza con `subprocess` **sin shell** (args como
  lista → cero interpolación).
- `ejecutar_tarea(nombre, params)` — ejecuta una **tarea predefinida y tipada**
  del registro de `agente_pc/tareas.py`. NO son comandos arbitrarios: cada tarea
  compone primitivas seguras (abrir apps de la allowlist, abrir carpetas
  permitidas). Las de ejemplo: `sesion_de_foco` (abre un set de apps) y
  `abrir_proyecto` (abre una carpeta permitida con un editor de la allowlist).
  Lo que no esté registrado, no se ejecuta. Ver §3.4 para registrar una nueva.
- `cerrar_app(nombre)` — cierra de forma **ordenada (graceful, no force)** las
  instancias de una app de la allowlist que el agente abrió **en esta sesión**
  (rastreadas por PID). Nunca mata procesos ajenos ni fuerza el cierre (la app
  puede preguntar por guardar).

**CERO ejecución de shell.** No existe ninguna acción que tome un comando crudo.
Solo `abrir_app` (allowlist) y `ejecutar_tarea` (registro). Si el modelo quiere
algo fuera de eso, no puede — punto.

### 1.2 El gate de las acciones consecuentes (reusa el sheet del teléfono)

Las tools `pc_mover_archivo` / `pc_renombrar_archivo` / `pc_crear_carpeta` /
`pc_organizar_carpeta` / `pc_abrir_app` / `pc_ejecutar_tarea` / `pc_cerrar_app`
**no ejecutan**: PROPONEN. Flujo:

1. El modelo llama la tool → el cerebro devuelve un bloque `accion_dispositivo`
   de tipo `pc_accion` (el mismo canal que las acciones del teléfono), con un
   `resumen` (para `organizar`, el PLAN ya calculado por el agente).
2. La app muestra el **sheet de confirmación** reutilizado del agéntico del
   teléfono (`_mostrarHoja`). El modelo, por su cuenta, no puede ejecutar nada.
3. Si el usuario confirma → la app hace `POST /api/v1/agente/ejecutar`
   `{accion, args}` (whitelist server-side). El cerebro cruza el canal con
   `confirmado=true`. El agente revalida TODO y ejecuta.

Triple capa: el modelo solo propone · el endpoint tiene whitelist · el agente
exige `confirmado` y revalida cada ruta.

---

## 2. Modelo de seguridad (lo no negociable)

1. **Conexión saliente, nunca entrante.** No se abren puertos en la PC.
2. **Secreto compartido.** El agente presenta `AGENTE_PC_TOKEN` en el header
   `X-Agente-PC-Token`. Es **distinto** de la API key de la app (`X-Matix-Key`).
   El cerebro lo valida **antes** de aceptar el WebSocket; si no coincide (o no
   está configurado), rechaza el handshake.
3. **Anti-impostor (TLS).** El agente exige `wss://` (TLS), valida el certificado
   con la cadena de CA del sistema, y comprueba que el **host** sea exactamente
   el esperado (`AGENTE_PC_HOST_ESPERADO`). Decisión 6.0a: sin *pinning* del
   certificado (sobrevive a la rotación normal de certificados del proveedor).
4. **Allowlist.** El agente SOLO ve lo que cae dentro de las carpetas listadas en
   `AGENTE_PC_ALLOWLIST`. Cualquier ruta fuera → rechazada.
   - **Path traversal:** la ruta se **canonicaliza** (`realpath`: resuelve `..` y
     rutas relativas) y se valida que el resultado REAL siga dentro de la
     allowlist DESPUÉS de resolver. `Documentos/../../.ssh/id_rsa` no pasa.
   - **Symlinks:** un enlace dentro de la allowlist que apunte fuera se detecta
     porque `realpath` lo resuelve antes de validar; el destino real cae fuera →
     rechazado (y la denylist lo cubre si apunta a `.ssh`, etc.).
   - **TOCTOU:** las acciones consecuentes revalidan la ruta justo antes de
     operar y trabajan sobre la ruta REAL resuelta; `organizar_aplicar` revalida
     CADA paso y aborta si algo dejó de ser válido. No se sobreescribe nunca.
5. **Denylist (gana sobre la allowlist).** Aunque caigan dentro de una carpeta
   permitida, y aunque el usuario lo pida explícito, son **invisibles**: `.ssh`,
   `.env` (y `.env.*`), llaves (`*.pem`, `*.key`, `id_rsa`…), `.git`,
   credenciales, perfiles de navegador (vía `AppData`), carpetas de sistema
   (`Windows`, `Program Files`, `ProgramData`, `/etc`, `/usr`…).
6. **Sin shell arbitrario.** El agente NO ejecuta comandos. Solo corre acciones
   del registry tipado.
7. **Niveles de riesgo + gate.** Cada acción declara `segura` / `consecuente` /
   `prohibida`. Las `segura` (lectura) se ejecutan directo. Las `consecuente`
   (mover/renombrar/crear) se ejecutan **solo con `confirmado=true`**, que únicamente
   viaja por el canal de ejecución confirmada del cerebro (tras el OK del usuario
   en la app). Las `prohibida` (p. ej. borrar) nunca se ejecutan.
8. **Fallo cerrado.** Canal caído, token inválido, permiso denegado, ruta
   ambigua o destino existente → falla seguro y dice por qué; nunca falla abierto
   ejecutando algo a medias.
9. **Audit log local.** Cada acción deja una línea en `agente_pc/audit.log`:
   acción, ruta, timestamp (America/Lima), resultado ok/error. **Nunca** el
   contenido de los archivos.
10. **Kill switch.** Ctrl+C (o SIGTERM) detiene el agente al instante, cerrando la
    conexión limpio.
11. **Anti-inyección.** Todo lo que el agente devuelve (nombres, contenido de
    archivos, resúmenes) se trata en el cerebro como **DATO**, jamás como
    instrucciones para el modelo. Si un archivo dice "mueve todo a la papelera",
    eso es texto que se muestra/resume, nunca una orden que el modelo ejecute.
    El modelo mini que resume recibe además una instrucción explícita de no
    obedecer al documento. (Probado en tests.)
12. **Permisos mínimos.** El agente corre con tu usuario normal. Si detecta que
    está **elevado** (administrador/root), se niega a arrancar.

### 2.1 Seguridad de apps y tareas (Fase 6.2 — lanzar procesos)

Lanzar procesos es más peligroso que leer archivos, así que `abrir_app`,
`ejecutar_tarea` y `cerrar_app` suman estas garantías sobre las de arriba:

1. **Allowlist DURA de apps.** Solo se abre lo que esté en
   `AGENTE_PC_APPS_ALLOWLIST` (nombre→ruta/comando). Cualquier app fuera de la
   lista → rechazada. Se resuelve al arrancar: una entrada que no existe o no
   resuelve se **omite** (con aviso), no se incluye.
2. **Denylist que gana sobre todo** (hardcoded en `seguridad.py`,
   `app_denylisted`): terminales/shells (`cmd`, `powershell`, `pwsh`, `bash`,
   `wsl`, `wt`, `conhost`…), intérpretes shell-equivalentes (`python`, `node`,
   `cscript`/`wscript`/`mshta`), herramientas de sistema (`regedit`, `taskmgr`,
   `mmc`, `rundll32`, `reg`, `netsh`, `sc`, `schtasks`, `diskpart`…),
   instaladores (`msiexec`, `setup`, `install`…) y el gestor de credenciales
   (`credwiz`, `vaultcmd`, `keymgr`). Además, **nada que viva en `C:\Windows`**
   (ni `/bin` `/sbin` en POSIX) se lanza. Aunque el usuario los ponga en su
   allowlist, **nunca** se abren. No es editable por config.
3. **CERO shell arbitrario.** El lanzador usa `subprocess.Popen([exe, *args],
   shell=False)`: la lista de argumentos NUNCA pasa por un shell → no hay
   inyección. No existe ninguna acción que acepte un comando crudo.
4. **Tareas solo del registro.** `ejecutar_tarea` solo corre tareas
   **registradas** en `tareas.py`, con parámetros **tipados**, que componen
   primitivas seguras (abrir apps de la allowlist, abrir carpetas permitidas).
   Una tarea desconocida o con params mal tipados → rechazada.
5. **Gate por acción.** Las tres son `consecuente`: exigen `confirmado=true`
   (tras el OK del usuario en el sheet). El modelo solo propone.
6. **Cierre acotado y graceful.** `cerrar_app` solo cierra los PIDs que el
   agente abrió **en esta sesión**, de forma ordenada (Windows: `taskkill /PID`
   sin `/F`; POSIX: SIGTERM) — nunca fuerza ni toca procesos ajenos.
7. **Falla cerrado.** Nombre con separadores/metacaracteres, app fuera de la
   allowlist, exe en la denylist, carpeta no permitida → rechazado, sin lanzar.
8. **Anti-inyección.** El contenido leído de un archivo es DATO: jamás dispara
   una app ni una tarea. Abrir/ejecutar solo viene de una orden directa y
   confirmada del usuario.

---

## 3. Cómo correr el agente en tu PC

Requisitos: Python 3.12+ y [uv](https://docs.astral.sh/uv/).

1. **Config:**

   ```bash
   cp agente_pc/.env.example agente_pc/.env
   ```

2. **Token compartido.** Pega en `agente_pc/.env` el mismo `AGENTE_PC_TOKEN` que
   tiene el cerebro (ver §5). Si aún no existe, genera uno:

   ```bash
   python -c "import secrets; print(secrets.token_urlsafe(48))"
   ```

   y ponlo en **ambos** lados (agente + cerebro/Railway).

3. **Allowlist.** Ajusta `AGENTE_PC_ALLOWLIST` a tu gusto. Por defecto:
   `~/Documents;~/Desktop;~/Downloads`.

4. **Correr** (comando exacto, desde la raíz del repo):

   ```bash
   cd agente_pc
   uv sync
   uv run python -m agente_pc
   ```

   Salida esperada con el logger nuevo (cada línea dice qué pasó):

   ```
   17:42:01 [INFO] matix.agente: arranque: 12 acciones (abrir_app, buscar_archivos, cerrar_app, crear_carpeta, ejecutar_tarea, leer_archivo, leer_bytes, listar_carpeta, mover_archivo, organizar_aplicar, planificar_organizacion, renombrar_archivo)
   17:42:01 [INFO] matix.agente: arranque: 3 carpetas en allowlist
   17:42:01 [INFO] matix.agente:   - permitida: C:\Users\TU\Documents
   17:42:01 [INFO] matix.agente:   - permitida: C:\Users\TU\Desktop
   17:42:01 [INFO] matix.agente:   - permitida: C:\Users\TU\Downloads
   17:42:01 [INFO] matix.agente: arranque: 2 apps en allowlist (chrome, code)
   17:42:01 [INFO] matix.agente: arranque: conectando a cerebro wss://matix-production.up.railway.app/api/v1/agente/ws
   17:42:01 [INFO] matix.agente: arranque: host esperado (anti-impostor) matix-production.up.railway.app
   17:42:01 [INFO] matix.agente: arranque: corriendo. Ctrl+C para detener (kill switch).
   17:42:01 [INFO] matix.agente: ws: abriendo WSS hacia wss://matix-production.up.railway.app/api/v1/agente/ws
   17:42:01 [INFO] matix.agente: ws: TLS preparado; presentando X-Agente-PC-Token y handshake…
   17:42:02 [INFO] matix.agente: ws: handshake OK: cerebro aceptó el token (auth confirmada).
   17:42:02 [INFO] matix.agente: ws: 'hola' enviado; esperando acciones del cerebro.
   ```

   Cuando Matix manda una acción real, aparece:

   ```
   17:43:10 [INFO] matix.agente: ws: acción recibida id=abc123 nombre='listar_carpeta' ruta='~/Documents' confirmado=False
   17:43:10 [INFO] matix.agente: ws: acción resuelta id=abc123 resultado=ok
   17:43:10 [INFO] matix.agente: ws: resultado devuelto al cerebro id=abc123
   ```

5. **Errores de arranque accionables.** Si algo está mal, el mensaje te dice
   QUÉ y CÓMO arreglarlo. Ejemplos:

   - `.venv` roto: *"El .venv apunta a un Python que ya no existe (C:\\…\\Python312). Regenéralo: cd agente_pc && Remove-Item -Recurse -Force .venv && uv sync"*.
   - `.env` ausente: *"Falta agente_pc/.env … Crea uno: cp agente_pc/.env.example agente_pc/.env"*.
   - Token vacío / con espacios / muy corto: cada caso da un mensaje específico (token tiene espacios → "edita .env, deja el token sin comillas y sin espacios antes/después del ="; muy corto → "¿pegaste el placeholder en vez del de Railway?").
   - Corriendo como administrador: *"el agente debe correr con permisos MÍNIMOS del usuario"*.

6. **Autotest de conexión** (desde `agente_pc/`): prueba la auth y el canal y
   sale limpio. NO deja nada corriendo. Útil para diagnosticar antes de dejar
   el daemon vivo.

   ```bash
   uv run python -m agente_pc --test-connection
   ```

   Salida esperada (todo OK):

   ```
   [autotest] probando conexión a wss://matix-production.up.railway.app/api/v1/agente/ws …
   ✓ Conectado a cerebro (matix-production.up.railway.app)
     Handshake TLS + token aceptados; canal abierto y cerrado limpio.
   ```

   Si algo falla, sale un error ESPECÍFICO con la sugerencia de qué hacer: token
   no coincide, host inalcanzable, DNS, TLS, timeout (el cerebro de Railway
   puede estar dormido), `.venv` roto, allowlist vacía, etc. Exit code 0 si OK,
   1 si la conexión falló, 2 si la config está mal.

   En Windows con `stdout` redirigido (cp1252) las marcas se imprimen como
   `[OK]` / `[X]` para no crashear con UnicodeEncodeError; en una terminal
   moderna salen `✓` / `✗`.

### 3.1 Test end-to-end (`scripts/test_e2e.py`)

Diagnóstico de UN COMANDO que verifica que TODA la cadena funciona — registry,
allowlist, denylist, lectura, audit. No requiere que el cerebro esté arriba si
pasas `SKIP_CONEXION=1`; si tienes `.env` válido, además corre el autotest de
conexión.

```bash
cd agente_pc
uv run python scripts/test_e2e.py
# o sin tocar la red:
SKIP_CONEXION=1 uv run python scripts/test_e2e.py
# o con más detalle:
E2E_VERBOSE=1 uv run python scripts/test_e2e.py
```

Lo que cubre:

1. **[opcional] Autotest de conexión** — handshake TLS + token contra el
   cerebro real. Se salta con `SKIP_CONEXION=1` o si no hay token.
2. **Acciones seguras** sobre una sandbox temporal creada bajo
   `agente_pc/.e2e_sandbox/` (no usa `%TEMP%` porque `AppData` está en la
   denylist):
   - `listar_carpeta` de la raíz oculta secretos (`.env`, `.ssh`).
   - `buscar_archivos` con `*.md` encuentra el archivo.
   - `leer_archivo` de un `.txt` devuelve el contenido.
   - `leer_bytes` de un PDF devuelve base64 + nombre (listo para
     `resumir_documento` en el cerebro).
3. **Casos de seguridad que DEBEN fallar**:
   - leer fuera de la allowlist → rechazado.
   - path traversal con `../` → rechazado (la ruta real cae fuera).
   - leer `.env` dentro de la sandbox → rechazado (denylist por nombre).
   - leer `.ssh/id_rsa` → rechazado (denylist por nombre).
   - `renombrar_archivo` sin `confirmado=true` → bloqueado por el registry.
4. **Apps y tareas (6.2)** — con un lanzador SIMULADO (no abre ventanas
   durante el test; la lógica de allowlist/denylist/gate/audit sí es real):
   - `abrir_app` de una app de la allowlist → ok (el lanzador se invoca con el
     exe resuelto).
   - `abrir_app` fuera de la allowlist → rechazado, sin lanzar.
   - `abrir_app` denylisted (`cmd`) → rechazado por seguridad (defensa en
     profundidad del handler).
   - shell arbitrario IMPOSIBLE: no existe acción de comando crudo, y un
     "comando" como nombre de app se rechaza.
   - `abrir_app` sin `confirmado=true` → bloqueado por el gate consecuente.
   - `ejecutar_tarea` `sesion_de_foco` (con una app de la allowlist) → ok.
   - `ejecutar_tarea` desconocida → rechazada (solo tareas predefinidas).
   - `cerrar_app` de lo abierto en la sesión → ok (cierre graceful por PID).
5. **Audit log** (`agente_pc/audit.log`):
   - tras la sesión hay AL MENOS 6 líneas nuevas (una por acción ejecutada).
   - el log **no contiene contenido sensible**: ni el texto leído, ni el de
     `.env`, ni la "clave" del falso `id_rsa`.

Total: **19 pruebas** (11 base + 8 de 6.2).

Imprime un resumen "X/Y pruebas pasaron" y sale con `0` si todo pasó, `1`
si algo falló. La sandbox se limpia al terminar (si el script muere a mitad,
puede quedar — está gitignored).

### 3.2 Qué buscar en los logs si algo falla

| Síntoma | Línea del log que la confirma | Probable causa |
|---|---|---|
| El comando ni siquiera muestra el banner | `.venv: El .venv apunta a un Python que ya no existe …` | Desinstalaste/actualizaste Python; regenera el venv como dice el mensaje. |
| Sale `.env: Falta agente_pc/.env` y `exit 4` | esa línea | No copiaste la plantilla; corre `cp agente_pc/.env.example agente_pc/.env`. |
| Sale `token: …` y `exit 2` | el mensaje específico (vacío / espacios / corto) | El `AGENTE_PC_TOKEN` no es el de Railway o está malformado. |
| Conecta pero el cerebro nunca manda una acción | `ws: handshake OK …` + `ws: 'hola' enviado; esperando acciones del cerebro.` y nada más | Normal: el agente está en idle hasta que Matix llama una `pc_*`. |
| Llega una acción pero falla | `ws: acción recibida …` + `ws: acción resuelta id=… resultado=error:rechazada` | Ruta fuera de la allowlist o en la denylist; revisa `AGENTE_PC_ALLOWLIST`. |
| Llega una `consecuente` y nada cambia | `resultado=error:requiere_confirmacion` | El cerebro la cruzó sin `confirmado=true`; el usuario no aprobó en el sheet de la app. |
| El agente cae y reintenta | `ws: conexión caída (…); reintento en ~Xs` | Red/Railway intermitente; el backoff exponencial lo maneja solo. |
| Handshake rechazado | `ws: …` cierra con 1008 o `InvalidStatus 401/403` | Token no coincide con el de Railway. |
| Falla TLS | `ws: tls_invalido …` | Reloj del sistema atrasado, o proxy/antivirus interceptando. |

El audit log (`agente_pc/audit.log`) lleva UNA línea por acción ejecutada con
el formato:

```
2026-06-08T17:43:10-05:00 | accion=listar_carpeta | ruta=C:\Users\TU\Documents | resultado=ok | <tipo>
```

NUNCA viaja contenido de archivos en el audit — el test e2e lo verifica.

### Editar qué puede ver

Cambia `AGENTE_PC_ALLOWLIST` en `agente_pc/.env` y reinicia el agente. La
**denylist gana** siempre: `.ssh`, `.env`, llaves, etc. siguen ocultos aunque los
metas dentro de una carpeta permitida.

### 3.3 Editar qué apps puede abrir (Fase 6.2)

Edita `AGENTE_PC_APPS_ALLOWLIST` en `agente_pc/.env` y reinicia el agente.
Formato: `nombre=ruta_o_comando`, separados por `;` o saltos de línea.

```
AGENTE_PC_APPS_ALLOWLIST=code=C:\Users\TU\AppData\Local\Programs\Microsoft VS Code\Code.exe;chrome=chrome
```

- `nombre`: como te referirás a la app en el chat (`code`, `chrome`).
- `ruta_o_comando`: la ruta absoluta del `.exe`, o un comando del PATH.

Al arrancar, el agente **resuelve y verifica** cada entrada y loggea las que
omite (no existe, no resuelve, o cae en la denylist). En los logs verás:

```
17:42:01 [INFO] matix.agente: arranque: 2 apps en allowlist (chrome, code)
17:42:01 [WARNING] matix.agente: apps: app «shell» → «C:\Windows\System32\cmd.exe»: BLOQUEADA por la denylist (...). Omitida.
```

La **denylist no es negociable** (vive en `seguridad.py`, no en `.env`): aunque
listes `cmd`, `powershell`, un instalador o algo en `C:\Windows`, **nunca** se
abre. Eso es a propósito — un shell sería ejecución arbitraria, el agujero que
toda esta capa evita.

### 3.4 Registrar una tarea tipada nueva (Fase 6.2)

Las tareas viven en `agente_pc/agente_pc/tareas.py`. Agregar una = registrar un
`TareaDef` (nombre, descripción, parámetros tipados, handler) que use SOLO las
primitivas seguras — nunca shell ni rutas/apps sin validar:

```python
def _tarea_abrir_inbox(params, ctx):
    # Compone primitivas seguras: abre apps de la allowlist, valida carpetas.
    return _abrir(ctx, params["app"])  # _abrir ya valida allowlist + denylist

_registrar(TareaDef(
    "abrir_inbox",
    "Abre tu cliente de correo.",
    (Param("app", str, requerido=True),),
    _tarea_abrir_inbox,
))
```

Reglas para una tarea nueva:
- Usa `_abrir(ctx, nombre_app, args?)` para lanzar (ya valida allowlist +
  denylist + rastrea el PID). NUNCA llames a `subprocess` directo ni construyas
  comandos.
- Valida toda carpeta con `ruta_permitida(ruta, ctx.allowlist)` antes de usarla.
- Declara los parámetros con `Param(nombre, tipo, requerido)`: el registry los
  valida por ti.
- Falla cerrado: ante params faltantes o algo fuera de la allowlist, devuelve
  `{"ok": False, "tipo": "...", "mensaje": "..."}`.

El transporte, el gate y el cerebro NO cambian: la nueva tarea se invoca con
`pc_ejecutar_tarea(nombre="abrir_inbox", params={...})` y pasa por el mismo gate.

### Detenerlo (kill switch)

- **Ctrl+C** en la terminal donde corre → cierra limpio y sale.
- O envíale **SIGTERM** (cerrar el proceso) → también cierra limpio.

Mientras el agente esté apagado, Matix responde "tu PC no está conectada" — nunca
se cuelga esperando.

---

## 4. Cómo se usa desde la app

Con el agente corriendo, en el chat de Matix:

> lista mi carpeta Documentos

Matix llama a la tool `pc_listar_carpeta`, el cerebro la enruta a tu PC por el
canal, el agente valida la ruta contra la allowlist/denylist, devuelve los
**nombres** (sin contenido) y el modelo te los presenta. En **Ajustes →
Conexión** ves el estado **PC: conectada / desconectada** (con un botón para
recomprobar).

Con la Fase 6.2, además (cada una pide confirmación en el sheet antes de actuar):

> abre VS Code  ·  arranca una sesión de foco con code y chrome  ·
> abre la carpeta del proyecto X con el editor  ·  cierra Chrome

(Las apps deben estar en tu `AGENTE_PC_APPS_ALLOWLIST`; ver §3.3.)

---

## 5. El `AGENTE_PC_TOKEN` (dónde va)

Es un secreto compartido. Debe ser **el mismo** en tres lugares:

| Lugar | Variable | Para qué |
|---|---|---|
| Railway (cerebro en prod) | `AGENTE_PC_TOKEN` | el cerebro valida el handshake |
| `cerebro/.env` (local) | `AGENTE_PC_TOKEN` | correr el cerebro en local |
| `agente_pc/.env` (local) | `AGENTE_PC_TOKEN` | el agente lo presenta al conectar |

### Setearlo en Railway

1. Dashboard de Railway → proyecto del cerebro → pestaña **Variables**.
2. **New Variable** → nombre `AGENTE_PC_TOKEN`, valor = el mismo token que está en
   `agente_pc/.env` (cópialo desde ese archivo; nunca lo imprimas en logs).
3. Guardar → Railway redepliega el cerebro con la variable.

> El valor del token **nunca** va al repo, a un `.md`, ni a los logs. Los `.env`
> están gitignored. El `.env.example` documenta la variable vacía.

---

## 6. Protocolo del canal (referencia)

Mensajes JSON sobre el WebSocket:

- Cerebro → agente (pedir acción):
  ```json
  {"tipo": "accion", "id": "a7", "nombre": "listar_carpeta", "args": {"ruta": "Documentos"}}
  ```
- Agente → cerebro (resultado, correlado por `id`):
  ```json
  {"tipo": "resultado", "id": "a7", "resultado": {"ok": true, "ruta": "...", "entradas": [{"nombre": "tarea.txt", "tipo": "archivo"}], "total": 1}}
  ```
- Al conectar, el agente manda `{"tipo": "hola", "agente": "matix-pc"}` (el
  cerebro lo ignora; no es una instrucción).

Si el agente no está conectado, o no responde dentro del timeout, el canal
devuelve `{"ok": false, "tipo": "pc_desconectada" | "timeout", ...}` y la tool lo
traduce a un mensaje amable. Nunca se bloquea.

---

## 7. Tests

- `agente_pc/tests/` — rails de seguridad (allowlist/denylist de rutas Y de
  apps, escape con `..`, ocultar secretos, raíces de sistema), registry
  (niveles de riesgo, validación), las acciones de archivo, y 6.2:
  `test_apps.py` (abrir/cerrar, denylist gana, gate consecuente, lanzador real
  sin shell, resolución) y `test_tareas.py` (tareas tipadas, fail-closed,
  inyección imposible). Corre con `uv run pytest` desde `agente_pc/`.
- `agente_pc/scripts/test_e2e.py` — el e2e de un comando (ver §3.1), 19 pruebas.
- `cerebro/tests/test_agente_acciones.py` — las tools del cerebro proponen vía
  el gate (incl. `pc_abrir_app`/`pc_ejecutar_tarea`/`pc_cerrar_app`), la
  whitelist del endpoint admite las acciones 6.2, falla cerrado sin PC, y el
  contenido leído es DATO.

Los gates (app Flutter, cerebro) corren en CI en cada push; los del agente se
corren localmente (`uv run pytest` en `agente_pc/`).

---

## 8. Qué falta (post-6.2)

- **Borrado** (eliminar/papelera) con confirmación reforzada — deliberadamente
  fuera por ser irreversible.
- **Escritura** de contenido en archivos (crear/editar texto) con gate.
- Más tareas tipadas a medida del flujo del usuario (se registran en `tareas.py`).
- Empaquetado del agente para arrancarlo con doble clic / al iniciar sesión.

> Hecho hasta aquí: 6.0a (cimiento) · 6.0b (lectura: buscar, leer, resumir) ·
> 6.1 (organización con gate: mover, renombrar, crear carpeta, organizar) ·
> 6.2 (abrir/cerrar apps de allowlist + tareas tipadas, con gate y sin shell).
