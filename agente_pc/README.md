# Agente local de Matix (Capa 6 · 6.0a)

Daemon que corre **en tu PC** y le deja a Matix ver/gestionar archivos dentro de
los límites que tú definas. Es el cimiento de la Capa 6. En 6.0a solo sabe hacer
**una** cosa de prueba: **listar los nombres** de archivos y carpetas de una ruta
permitida (sin leer contenido).

> ⚠️ **NUNCA lo corras como administrador.** El agente debe correr con los
> permisos mínimos de tu usuario normal. Si detecta que está elevado, se niega a
> arrancar. Correrlo elevado le daría acceso a todo el sistema — justo lo que los
> rails de seguridad quieren evitar.

## Cómo funciona (resumen de seguridad)

- **Conexión saliente, nunca entrante.** Tu PC abre una conexión WebSocket sobre
  TLS *hacia* el cerebro. El cerebro **nunca** inicia hacia tu PC. No se abre
  ningún puerto en tu máquina.
- **Token compartido.** El agente presenta `AGENTE_PC_TOKEN` al conectar; el
  cerebro lo valida. Si no coincide, la conexión se rechaza.
- **Anti-impostor.** El agente solo se conecta a `wss://` (TLS) y exige que el
  host sea exactamente el de la config. No se conecta a nada más.
- **Allowlist.** El agente SOLO ve lo que cae dentro de las carpetas que listes
  en `AGENTE_PC_ALLOWLIST`. Cualquier ruta fuera → rechazada.
- **Denylist (gana sobre la allowlist).** Aunque caigan dentro de una carpeta
  permitida, son invisibles: `.ssh`, `.env`, llaves (`*.pem`, `id_rsa`…),
  `.git`, credenciales, perfiles de navegador (AppData), carpetas de sistema
  (Windows, Program Files…).
- **Sin shell.** El agente NO ejecuta comandos arbitrarios. Solo corre acciones
  del registry tipado.
- **Audit log.** Cada acción queda en `agente_pc/audit.log` (acción, ruta,
  timestamp, ok/error) — nunca el contenido de los archivos.

## Requisitos

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (gestor de entorno/deps)

## Configuración

1. Copia el ejemplo y edítalo:

   ```bash
   cp agente_pc/.env.example agente_pc/.env
   ```

2. Pega en `agente_pc/.env` el **mismo** `AGENTE_PC_TOKEN` que tiene el cerebro
   (variable de entorno en Railway, y `cerebro/.env` si corres el cerebro
   local). Si aún no existe, genera uno:

   ```bash
   python -c "import secrets; print(secrets.token_urlsafe(48))"
   ```

   y ponlo en **ambos** lados (agente + cerebro/Railway).

3. Ajusta `AGENTE_PC_ALLOWLIST` a las carpetas que quieras exponer. Por defecto:
   `~/Documents;~/Desktop;~/Downloads`.

## Correr el agente

Desde la carpeta `agente_pc/`:

```bash
uv sync
uv run python -m agente_pc
```

Verás algo como:

```
[agente] acciones registradas: listar_carpeta
[agente] carpetas permitidas: 3
[agente] cerebro: wss://matix-production.up.railway.app/api/v1/agente/ws
[agente] corriendo. Ctrl+C para detener (kill switch).
[agente] conectado al cerebro
```

Si la conexión se cae, el agente reintenta solo con backoff (1s, 2s, 4s… hasta
60s). Apenas vuelve, Matix vuelve a ver tu PC como "conectada".

## Arranque automático (al iniciar sesión)

El agente solo conecta mientras corre. Para que arranque solo cada vez que
inicias sesión en Windows (sin abrir una terminal a mano):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\instalar_autostart.ps1
```

Esto crea un acceso directo en tu **carpeta de Inicio** que lanza el agente con
`pythonw.exe` (sin ventana), con tus permisos normales (nunca admin). Lo arranca
de una vez, así que no necesitas reiniciar.

Para quitarlo:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\desinstalar_autostart.ps1
```

Notas:

- Se usa la **carpeta de Inicio** y no una Tarea Programada a propósito: bajo
  Task Scheduler el `pythonw` del venv (de uv) se cuelga al arrancar por handles
  de stdio inválidos en esa sesión. La carpeta de Inicio lanza en tu sesión
  normal, donde conecta sin problemas.
- Verás **dos** procesos `pythonw` en el Administrador de tareas: es normal — el
  `pythonw` del venv es un "trampolín" de uv que re-ejecuta el intérprete base.
  Hay **un solo agente**: un guard de instancia única impide que corra un segundo
  si lo abres a mano (sale con código 6 en vez de pelear por el canal).
- Diagnóstico: el arranque crudo queda en `agente_autostart.log` y el log del
  daemon (conectado/desconectado, acciones) en `agente_runtime.log`.

## Kill switch (detenerlo al instante)

- **Ctrl+C** en la terminal donde corre. El agente cierra la conexión limpio y
  sale.
- O envíale `SIGTERM` (p. ej. cerrar el proceso desde el administrador de
  tareas). También cierra limpio.

Mientras el agente esté apagado, Matix simplemente responde "tu PC no está
conectada" — nunca se cuelga esperando.

## Editar qué puede ver

Edita `AGENTE_PC_ALLOWLIST` en `agente_pc/.env` y reinicia el agente. Recuerda:
la **denylist gana** — `.ssh`, `.env`, llaves, etc. siguen ocultos aunque los
metas dentro de una carpeta permitida.

## Probar desde la app

Con el agente corriendo, en el chat de Matix:

> lista mi carpeta Documentos

Matix enruta la acción a tu PC y te devuelve los nombres. En **Ajustes →
Conexión** verás el estado **PC: conectada / desconectada**.

## Qué NO hace (todavía)

6.0a es solo el cimiento. NO lee, mueve ni escribe archivos más allá de listar
nombres. Esas acciones (consecuentes) llegan en fases siguientes, con
confirmación explícita.
