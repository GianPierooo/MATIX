"""Acciones concretas del agente local.

Fases:
  - 6.0a: listar_carpeta (SEGURA).
  - 6.0b (lectura · SEGURA): buscar_archivos, leer_archivo, leer_bytes
    (soporte de resumir_documento), planificar_organizacion (preview).
  - 6.1 (organización · CONSECUENTE, exigen confirmado=true): mover_archivo,
    renombrar_archivo, crear_carpeta, organizar_aplicar.

Sin borrado en esta fase (eliminar es irreversible; va en una acción propia con
confirmación reforzada más adelante).

SEGURIDAD — todo se valida en el BORDE de cada acción, aquí en el agente, jamás
confiando en el modelo:
  - `seguridad.ruta_permitida` resuelve symlinks/`..` (realpath) ANTES de decidir
    y aplica denylist (gana) + allowlist. Path traversal y symlinks que escapan
    quedan bloqueados.
  - Las acciones consecuentes revalidan origen Y destino, no sobreescriben, y
    operan sobre la ruta REAL resuelta.
  - El contenido leído es DATO: el agente nunca lo interpreta como instrucción.
"""
from __future__ import annotations

import base64
import fnmatch
import os
import shutil
from datetime import datetime, timedelta, timezone
from typing import Any

from .registro import AccionDef, Contexto, NivelRiesgo, Param, Registro
from .seguridad import entrada_oculta, ruta_permitida

# Topes (evitan payloads gigantes / DoS accidental / barridos infinitos).
MAX_ENTRADAS = 1000
MAX_RESULTADOS = 500
MAX_BARRIDO = 20000
MAX_DOC_BYTES = 5 * 1024 * 1024  # 5 MB para resumir_documento

_LIMA = timezone(timedelta(hours=-5))  # Perú: UTC-5 fijo, sin tzdata.

# Extensiones de texto que leer_archivo acepta. Además se hace sniff de bytes
# nulos por si una extensión "de texto" trae binario.
_EXT_TEXTO = frozenset(
    {
        ".txt", ".md", ".markdown", ".csv", ".tsv", ".json", ".jsonl", ".yaml",
        ".yml", ".xml", ".html", ".htm", ".css", ".js", ".ts", ".tsx", ".jsx",
        ".py", ".dart", ".java", ".kt", ".kts", ".c", ".h", ".cpp", ".hpp",
        ".cc", ".rs", ".go", ".rb", ".php", ".sh", ".bash", ".ps1", ".bat",
        ".sql", ".toml", ".ini", ".cfg", ".conf", ".env_example", ".log",
        ".tex", ".rst", ".gradle", ".properties", ".gitignore", ".dockerfile",
    }
)
# Documentos que resumir_documento soporta (los extrae el cerebro reutilizando
# app/matix/extraccion_documentos.py).
_EXT_DOC = frozenset({".pdf", ".docx", ".txt", ".md"})

# Categorías por tipo de archivo (criterio "por tipo" de organizar).
_CATEGORIAS = {
    "Imágenes": {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".svg", ".heic", ".tiff"},
    "Documentos": {".pdf", ".doc", ".docx", ".txt", ".md", ".rtf", ".odt", ".tex"},
    "Hojas de cálculo": {".xls", ".xlsx", ".csv", ".tsv", ".ods"},
    "Presentaciones": {".ppt", ".pptx", ".odp", ".key"},
    "Comprimidos": {".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz"},
    "Audio": {".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a"},
    "Video": {".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv"},
    "Código": {".py", ".js", ".ts", ".dart", ".java", ".kt", ".c", ".cpp", ".rs",
               ".go", ".rb", ".php", ".html", ".css", ".json", ".sh"},
    "Instaladores": {".exe", ".msi", ".dmg", ".apk", ".deb", ".rpm"},
}

_CARPETAS_COMUNES = {
    "documentos": "~/Documents", "documents": "~/Documents",
    "escritorio": "~/Desktop", "desktop": "~/Desktop",
    "descargas": "~/Downloads", "downloads": "~/Downloads",
}


# ── Helpers de ruta ──────────────────────────────────────────────────────────


def _resolver_nombre(ruta: str) -> str:
    bruto = (ruta or "").strip()
    clave = bruto.lower().strip("/\\")
    if not os.path.isabs(bruto) and clave in _CARPETAS_COMUNES:
        return _CARPETAS_COMUNES[clave]
    return bruto


def _real(ruta: str) -> str:
    return os.path.realpath(os.path.expanduser(_resolver_nombre(str(ruta))))


def _rechazo(motivo: str) -> dict[str, Any]:
    return {"ok": False, "tipo": "rechazada", "mensaje": "ruta no permitida", "motivo": motivo}


def _categoria_por_ext(ext: str) -> str:
    for cat, exts in _CATEGORIAS.items():
        if ext in exts:
            return cat
    return "Otros"


def _token_proyecto(nombre: str) -> str:
    base = os.path.splitext(nombre)[0]
    for sep in ("_", "-", " ", "."):
        base = base.replace(sep, " ")
    partes = [p for p in base.split() if p]
    return partes[0].capitalize() if partes else "Varios"


def _mtime_iso(ruta: str) -> str:
    try:
        return datetime.fromtimestamp(os.path.getmtime(ruta), _LIMA).isoformat(timespec="seconds")
    except OSError:
        return ""


# ── 6.0a: listar_carpeta ─────────────────────────────────────────────────────


def _listar_carpeta(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    ruta = _resolver_nombre(args.get("ruta"))
    veredicto = ruta_permitida(ruta, ctx.allowlist)
    if not veredicto.permitida:
        return _rechazo(veredicto.motivo)
    real = _real(ruta)
    if not os.path.isdir(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no es una carpeta accesible"}
    entradas: list[dict[str, str]] = []
    truncado = False
    try:
        with os.scandir(real) as it:
            for entrada in it:
                if entrada_oculta(entrada.name):
                    continue
                try:
                    es_dir = entrada.is_dir()
                except OSError:
                    es_dir = False
                entradas.append({"nombre": entrada.name, "tipo": "carpeta" if es_dir else "archivo"})
                if len(entradas) >= MAX_ENTRADAS:
                    truncado = True
                    break
    except PermissionError:
        return {"ok": False, "tipo": "sin_permiso", "mensaje": "el sistema no me deja leer esa carpeta"}
    entradas.sort(key=lambda e: (e["tipo"] != "carpeta", e["nombre"].lower()))
    return {"ok": True, "ruta": real, "entradas": entradas, "total": len(entradas), "truncado": truncado}


# ── 6.0b: buscar_archivos ────────────────────────────────────────────────────


def _coincide(nombre: str, patron: str) -> bool:
    n, p = nombre.lower(), patron.lower()
    if any(c in p for c in "*?["):
        return fnmatch.fnmatch(n, p)
    return p in n


def _buscar_archivos(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    patron = (args.get("patron") or "").strip()
    if not patron:
        return {"ok": False, "tipo": "validacion", "mensaje": "necesito un patrón de búsqueda"}

    carpeta = args.get("carpeta")
    if carpeta:
        veredicto = ruta_permitida(_resolver_nombre(carpeta), ctx.allowlist)
        if not veredicto.permitida:
            return _rechazo(veredicto.motivo)
        raices = [_real(carpeta)]
    else:
        raices = [str(p) for p in ctx.allowlist]

    resultados: list[dict[str, Any]] = []
    vistos = 0
    truncado = False
    for raiz in raices:
        if not os.path.isdir(raiz):
            continue
        # followlinks=False: no seguimos symlinks de carpeta (anti-escape).
        for dirpath, dirnames, filenames in os.walk(raiz, followlinks=False):
            # Poda: no descendemos a carpetas ocultas/denylisted.
            dirnames[:] = [d for d in dirnames if not entrada_oculta(d)]
            for fn in filenames:
                vistos += 1
                if vistos > MAX_BARRIDO:
                    truncado = True
                    break
                if entrada_oculta(fn) or not _coincide(fn, patron):
                    continue
                completa = os.path.join(dirpath, fn)
                # Revalidar cada hit (un symlink-archivo podría escapar).
                if not ruta_permitida(completa, ctx.allowlist).permitida:
                    continue
                try:
                    tamano = os.path.getsize(completa)
                except OSError:
                    tamano = None
                resultados.append({
                    "ruta": os.path.realpath(completa),
                    "nombre": fn,
                    "tamano": tamano,
                    "modificado": _mtime_iso(completa),
                })
                if len(resultados) >= MAX_RESULTADOS:
                    truncado = True
                    break
            if truncado:
                break
        if truncado:
            break

    resultados.sort(key=lambda r: r["nombre"].lower())
    return {"ok": True, "patron": patron, "archivos": resultados, "total": len(resultados), "truncado": truncado}


# ── 6.0b: leer_archivo (texto) ───────────────────────────────────────────────


def _es_texto(real: str) -> bool:
    ext = os.path.splitext(real)[1].lower()
    if ext in _EXT_TEXTO:
        return True
    # Sin extensión conocida: sniff de bytes nulos (binario → False).
    try:
        with open(real, "rb") as f:
            muestra = f.read(8192)
    except OSError:
        return False
    if b"\x00" in muestra:
        return False
    # Si la extensión NO es de texto y no hay señal clara, lo tratamos como
    # binario para no volcar cosas raras.
    return ext == ""


def _leer_archivo(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    ruta = _resolver_nombre(args.get("ruta"))
    veredicto = ruta_permitida(ruta, ctx.allowlist)
    if not veredicto.permitida:
        return _rechazo(veredicto.motivo)
    real = _real(ruta)
    if not os.path.isfile(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no es un archivo accesible"}
    ext = os.path.splitext(real)[1].lower()
    if not _es_texto(real):
        return {
            "ok": False,
            "tipo": "no_texto",
            "mensaje": f"es un archivo binario o no soportado ({ext or 'sin extensión'}); no lo leo crudo",
            "extension": ext,
        }
    tope = max(1, int(ctx.max_lectura_bytes))
    try:
        tamano = os.path.getsize(real)
        with open(real, "rb") as f:
            crudo = f.read(tope)
    except PermissionError:
        return {"ok": False, "tipo": "sin_permiso", "mensaje": "el sistema no me deja leer ese archivo"}
    except OSError:
        return {"ok": False, "tipo": "error_lectura", "mensaje": "no pude leer ese archivo"}
    texto = crudo.decode("utf-8", errors="replace")
    return {
        "ok": True,
        "ruta": real,
        "texto": texto,
        "bytes": tamano,
        "truncado": tamano > len(crudo),
    }


# ── 6.0b: leer_bytes (soporte de resumir_documento) ──────────────────────────


def _leer_bytes(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    ruta = _resolver_nombre(args.get("ruta"))
    veredicto = ruta_permitida(ruta, ctx.allowlist)
    if not veredicto.permitida:
        return _rechazo(veredicto.motivo)
    real = _real(ruta)
    if not os.path.isfile(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no es un archivo accesible"}
    ext = os.path.splitext(real)[1].lower()
    if ext not in _EXT_DOC:
        return {"ok": False, "tipo": "no_documento",
                "mensaje": f"para resumir solo acepto PDF, DOCX, TXT o MD (no {ext or 'sin extensión'})"}
    try:
        tamano = os.path.getsize(real)
        if tamano > MAX_DOC_BYTES:
            return {"ok": False, "tipo": "muy_grande",
                    "mensaje": f"el documento pesa {tamano // (1024*1024)} MB; el tope para resumir es 5 MB"}
        with open(real, "rb") as f:
            datos = f.read()
    except PermissionError:
        return {"ok": False, "tipo": "sin_permiso", "mensaje": "el sistema no me deja leer ese archivo"}
    except OSError:
        return {"ok": False, "tipo": "error_lectura", "mensaje": "no pude leer ese archivo"}
    return {
        "ok": True,
        "nombre": os.path.basename(real),
        "base64": base64.b64encode(datos).decode("ascii"),
        "bytes": tamano,
    }


# ── Organización: planificador puro (preview = ejecución, determinista) ──────


def _normalizar_criterio(criterio: str) -> str | None:
    c = (criterio or "").strip().lower()
    if "tipo" in c:
        return "tipo"
    if "fecha" in c:
        return "fecha"
    if "proyecto" in c:
        return "proyecto"
    return None


def _plan_organizacion(real_carpeta: str, criterio: str) -> list[dict[str, str]]:
    """Plan determinista: qué archivo top-level va a qué subcarpeta. Solo
    archivos (no toca subcarpetas), oculta secretos. preview == ejecución."""
    archivos: list[tuple[str, str]] = []  # (nombre, ext)
    try:
        with os.scandir(real_carpeta) as it:
            for e in it:
                if entrada_oculta(e.name):
                    continue
                try:
                    if e.is_dir():
                        continue
                except OSError:
                    continue
                archivos.append((e.name, os.path.splitext(e.name)[1].lower()))
    except OSError:
        return []

    # Categoría por archivo
    cat_de: dict[str, str] = {}
    if criterio == "tipo":
        for nombre, ext in archivos:
            cat_de[nombre] = _categoria_por_ext(ext)
    elif criterio == "fecha":
        for nombre, _ in archivos:
            ruta = os.path.join(real_carpeta, nombre)
            try:
                cat_de[nombre] = datetime.fromtimestamp(os.path.getmtime(ruta), _LIMA).strftime("%Y-%m")
            except OSError:
                cat_de[nombre] = "sin-fecha"
    else:  # proyecto
        tokens = {nombre: _token_proyecto(nombre) for nombre, _ in archivos}
        conteo: dict[str, int] = {}
        for t in tokens.values():
            conteo[t] = conteo.get(t, 0) + 1
        for nombre, _ in archivos:
            t = tokens[nombre]
            cat_de[nombre] = t if conteo[t] > 1 else "Varios"

    plan: list[dict[str, str]] = []
    for nombre, _ in sorted(archivos):
        cat = cat_de[nombre]
        plan.append({
            "origen": os.path.join(real_carpeta, nombre),
            "destino": os.path.join(real_carpeta, cat, nombre),
            "categoria": cat,
        })
    return plan


def _planificar_organizacion(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    carpeta = _resolver_nombre(args.get("carpeta"))
    veredicto = ruta_permitida(carpeta, ctx.allowlist)
    if not veredicto.permitida:
        return _rechazo(veredicto.motivo)
    real = _real(carpeta)
    if not os.path.isdir(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no es una carpeta accesible"}
    criterio = _normalizar_criterio(args.get("criterio"))
    if criterio is None:
        return {"ok": False, "tipo": "criterio_invalido",
                "mensaje": "criterio no reconocido; usa «por tipo», «por fecha» o «por proyecto»"}
    plan = _plan_organizacion(real, criterio)
    por_categoria: dict[str, int] = {}
    for p in plan:
        por_categoria[p["categoria"]] = por_categoria.get(p["categoria"], 0) + 1
    return {
        "ok": True,
        "carpeta": real,
        "criterio": criterio,
        "plan": plan,
        "por_categoria": por_categoria,
        "total": len(plan),
    }


# ── 6.1: acciones CONSECUENTES (exigen confirmado=true en el registry) ───────


def _validar_destino_padre(real_destino: str, allowlist) -> str | None:
    """Devuelve un motivo de rechazo o None si el padre del destino es válido."""
    padre = os.path.dirname(real_destino)
    if not ruta_permitida(padre, allowlist).permitida:
        return "destino fuera de lo permitido"
    if not ruta_permitida(real_destino, allowlist).permitida:
        return "destino no permitido"
    return None


def _mover_archivo(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    origen = _resolver_nombre(args.get("origen"))
    destino_in = _resolver_nombre(args.get("destino"))
    if not origen or not destino_in:
        return {"ok": False, "tipo": "validacion", "mensaje": "necesito origen y destino"}
    if not ruta_permitida(origen, ctx.allowlist).permitida:
        return _rechazo("origen no permitido")
    real_origen = _real(origen)
    if not os.path.exists(real_origen):
        return {"ok": False, "tipo": "no_existe", "mensaje": "el origen no existe"}

    real_destino = _real(destino_in)
    # Si el destino es una carpeta existente, movemos DENTRO de ella.
    if os.path.isdir(real_destino):
        real_destino = os.path.join(real_destino, os.path.basename(real_origen))
    motivo = _validar_destino_padre(real_destino, ctx.allowlist)
    if motivo:
        return _rechazo(motivo)
    if os.path.normcase(real_destino) == os.path.normcase(real_origen):
        return {"ok": False, "tipo": "sin_cambio", "mensaje": "origen y destino son el mismo"}
    if os.path.exists(real_destino):
        return {"ok": False, "tipo": "destino_existe", "mensaje": "ya existe algo en el destino; no sobreescribo"}
    try:
        shutil.move(real_origen, real_destino)
    except OSError:
        return {"ok": False, "tipo": "error_mover", "mensaje": "no pude mover ese archivo"}
    return {"ok": True, "origen": real_origen, "destino": real_destino}


def _renombrar_archivo(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    ruta = _resolver_nombre(args.get("ruta"))
    nuevo = (args.get("nuevo_nombre") or "").strip()
    if not ruta or not nuevo:
        return {"ok": False, "tipo": "validacion", "mensaje": "necesito ruta y nuevo_nombre"}
    # nuevo_nombre debe ser un nombre simple (sin separadores ni '..').
    if os.sep in nuevo or (os.altsep and os.altsep in nuevo) or nuevo in (".", "..") or "/" in nuevo or "\\" in nuevo:
        return {"ok": False, "tipo": "nombre_invalido", "mensaje": "el nuevo nombre no puede tener carpetas ni «..»"}
    if not ruta_permitida(ruta, ctx.allowlist).permitida:
        return _rechazo("origen no permitido")
    real = _real(ruta)
    if not os.path.exists(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no existe lo que quieres renombrar"}
    real_destino = os.path.join(os.path.dirname(real), nuevo)
    if not ruta_permitida(real_destino, ctx.allowlist).permitida:
        return _rechazo("el nuevo nombre cae en algo no permitido")
    if os.path.exists(real_destino):
        return {"ok": False, "tipo": "destino_existe", "mensaje": "ya existe algo con ese nombre"}
    try:
        os.rename(real, real_destino)
    except OSError:
        return {"ok": False, "tipo": "error_renombrar", "mensaje": "no pude renombrar"}
    return {"ok": True, "origen": real, "destino": real_destino}


def _crear_carpeta(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    ruta = _resolver_nombre(args.get("ruta"))
    if not ruta:
        return {"ok": False, "tipo": "validacion", "mensaje": "necesito la ruta de la carpeta"}
    if not ruta_permitida(ruta, ctx.allowlist).permitida:
        return _rechazo("fuera de lo permitido")
    real = _real(ruta)
    if os.path.exists(real):
        return {"ok": False, "tipo": "ya_existe", "mensaje": "ya existe esa carpeta"}
    # El padre también debe ser válido (defensa extra).
    if not ruta_permitida(os.path.dirname(real), ctx.allowlist).permitida:
        return _rechazo("la carpeta padre no está permitida")
    try:
        os.makedirs(real, exist_ok=False)
    except OSError:
        return {"ok": False, "tipo": "error_crear", "mensaje": "no pude crear la carpeta"}
    return {"ok": True, "ruta": real}


def _organizar_aplicar(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    """Recalcula el plan determinista y lo ejecuta paso a paso, revalidando
    CADA movimiento (anti-TOCTOU) y abortando ante algo inesperado."""
    carpeta = _resolver_nombre(args.get("carpeta"))
    if not ruta_permitida(carpeta, ctx.allowlist).permitida:
        return _rechazo("carpeta no permitida")
    real = _real(carpeta)
    if not os.path.isdir(real):
        return {"ok": False, "tipo": "no_existe", "mensaje": "no es una carpeta accesible"}
    criterio = _normalizar_criterio(args.get("criterio"))
    if criterio is None:
        return {"ok": False, "tipo": "criterio_invalido", "mensaje": "criterio no reconocido"}

    plan = _plan_organizacion(real, criterio)  # recomputado al momento de aplicar
    movidos: list[dict[str, str]] = []
    omitidos: list[dict[str, str]] = []
    carpetas_creadas: list[str] = []

    for paso in plan:
        origen = paso["origen"]
        destino = paso["destino"]
        # Revalidación por paso (anti-TOCTOU). Fallo de seguridad → ABORTAR.
        if not ruta_permitida(origen, ctx.allowlist).permitida:
            return {"ok": False, "tipo": "abortado", "mensaje": "una ruta dejó de ser válida; aborté",
                    "movidos": movidos, "omitidos": omitidos, "carpetas_creadas": carpetas_creadas}
        if not ruta_permitida(destino, ctx.allowlist).permitida:
            return {"ok": False, "tipo": "abortado", "mensaje": "un destino dejó de ser válido; aborté",
                    "movidos": movidos, "omitidos": omitidos, "carpetas_creadas": carpetas_creadas}
        if not os.path.isfile(origen):
            omitidos.append({"origen": origen, "motivo": "ya no es un archivo"})
            continue
        if os.path.exists(destino):
            omitidos.append({"origen": origen, "motivo": "el destino ya existe"})
            continue
        subcarpeta = os.path.dirname(destino)
        try:
            if not os.path.isdir(subcarpeta):
                os.makedirs(subcarpeta, exist_ok=True)
                carpetas_creadas.append(subcarpeta)
            shutil.move(origen, destino)
            movidos.append({"origen": origen, "destino": destino})
        except OSError:
            omitidos.append({"origen": origen, "motivo": "el sistema no dejó moverlo"})
            continue

    return {
        "ok": True,
        "carpeta": real,
        "criterio": criterio,
        "movidos": movidos,
        "omitidos": omitidos,
        "carpetas_creadas": sorted(set(carpetas_creadas)),
        "total_movidos": len(movidos),
    }


# ── Definiciones + registro ──────────────────────────────────────────────────

_DEFS = [
    AccionDef("listar_carpeta",
              "Lista nombres de archivos y carpetas dentro de una ruta permitida. NO devuelve contenido.",
              (Param("ruta", str, requerido=True),), NivelRiesgo.SEGURA, _listar_carpeta),
    AccionDef("buscar_archivos",
              "Busca archivos por nombre o glob dentro de la allowlist. Devuelve ruta, tamaño y fecha.",
              (Param("patron", str, requerido=True), Param("carpeta", str, requerido=False)),
              NivelRiesgo.SEGURA, _buscar_archivos),
    AccionDef("leer_archivo",
              "Lee el contenido de texto de un archivo permitido (con tope de tamaño). Binarios: no.",
              (Param("ruta", str, requerido=True),), NivelRiesgo.SEGURA, _leer_archivo),
    AccionDef("leer_bytes",
              "Lee los bytes de un documento permitido (PDF/DOCX/TXT/MD) para que el cerebro lo resuma.",
              (Param("ruta", str, requerido=True),), NivelRiesgo.SEGURA, _leer_bytes),
    AccionDef("planificar_organizacion",
              "Calcula (sin ejecutar) el plan de organización de una carpeta según un criterio.",
              (Param("carpeta", str, requerido=True), Param("criterio", str, requerido=True)),
              NivelRiesgo.SEGURA, _planificar_organizacion),
    AccionDef("mover_archivo",
              "Mueve un archivo de origen a destino (ambos permitidos, sin sobreescribir).",
              (Param("origen", str, requerido=True), Param("destino", str, requerido=True)),
              NivelRiesgo.CONSECUENTE, _mover_archivo),
    AccionDef("renombrar_archivo",
              "Renombra un archivo/carpeta a un nombre simple (sin sobreescribir).",
              (Param("ruta", str, requerido=True), Param("nuevo_nombre", str, requerido=True)),
              NivelRiesgo.CONSECUENTE, _renombrar_archivo),
    AccionDef("crear_carpeta",
              "Crea una carpeta nueva dentro de la allowlist.",
              (Param("ruta", str, requerido=True),), NivelRiesgo.CONSECUENTE, _crear_carpeta),
    AccionDef("organizar_aplicar",
              "Ejecuta el plan de organización de una carpeta, paso a paso y revalidando cada movimiento.",
              (Param("carpeta", str, requerido=True), Param("criterio", str, requerido=True)),
              NivelRiesgo.CONSECUENTE, _organizar_aplicar),
]


def crear_registro() -> Registro:
    """Registro con todas las acciones de las fases 6.0a/6.0b/6.1."""
    reg = Registro()
    for d in _DEFS:
        reg.registrar(d)
    return reg
