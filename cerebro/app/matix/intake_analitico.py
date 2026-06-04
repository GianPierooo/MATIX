"""Intake analítico por parámetros para crear/entender un proyecto a fondo.

En vez de un cuestionario genérico, detecta el TIPO de proyecto y llena el
ESQUEMA de parámetros de ese tipo, analizando: una pregunta afilada a la vez,
detectando huecos e incoherencias. No deja planear hasta que la meta esté clara,
medible y con plazo y estén todos los parámetros REQUERIDOS (gate de
completitud). Luego se arma un plan EN CAPAS (visión → hitos → tareas finas del
bloque actual + corto plazo) sobre el árbol (Paso 2).

La parte PURA (esquema por tipo, detección de tipo y huecos, gate, capas del
plan) está separada y se testea sin BD. Lo impuro (leer/guardar parámetros) usa
`proyectos.parametros` (jsonb) y reusa `entrevistas_perfil` para el estado.
"""
from __future__ import annotations

from typing import Any

from ..db import Postgrest


def _p(clave: str, pregunta: str, analisis: str = "") -> dict[str, str]:
    return {"clave": clave, "pregunta": pregunta, "analisis": analisis}


# Parámetros comunes a TODO tipo (la meta medible con plazo + el porqué + los
# criterios de éxito + el tiempo disponible). El gate exige estos siempre.
_COMUNES = [
    _p("meta_plazo", "¿Cuál es la meta concreta y para cuándo? (con fecha o plazo real)",
       "Si es vaga o sin plazo, insiste: una meta sin fecha no se puede planear."),
    _p("criterio_exito", "¿Cómo sabrás que la meta está cumplida? (definición de «hecho», medible)",
       "Exige algo medible; si no, el avance no se puede evaluar honesto."),
    _p("tiempo_semanal", "¿Cuántas horas a la semana le puedes dedicar, de verdad?",
       "Contrasta con la meta: si la meta es grande y el tiempo poco, dilo."),
    _p("porque", "¿Por qué te importa esto? ¿Qué cambia en tu vida si lo logras?",
       "Captura SIEMPRE la motivación: alimenta los recordatorios de la mañana."),
]

# Esquema por tipo: requeridos (bloquean el plan) + opcionales (se ofrecen).
ESQUEMAS: dict[str, dict[str, list[dict[str, str]]]] = {
    "negocio": {
        "requeridos": [
            _p("que_vende", "¿Qué vendes EXACTAMENTE? (producto/servicio concreto)"),
            _p("propuesta_valor", "¿Cuál es tu diferenciador? ¿Por qué te comprarían a ti y no a otro?"),
            _p("cliente", "¿Quién es tu cliente objetivo, concreto? (no «todos»)"),
            _p("etapa", "¿En qué etapa estás hoy? (idea, diseños, stock, primeras ventas…)"),
            _p("canales", "¿Por dónde vendes o piensas vender? (canales)"),
            _p("precios_margenes", "¿Precios y márgenes? ¿Cuánto te queda por venta?",
               "Si quiere vender pero no sabe su margen, SEÑÁLALO: es un hueco crítico."),
            _p("cuello_botella", "¿Cuál es el cuello de botella REAL para vender más hoy?",
               "Cava hasta el freno real (no el síntoma)."),
            _p("horizonte_anios", "¿En qué horizonte lo ves? (meses/años)"),
            _p("presupuesto", "¿Con qué presupuesto cuentas para esto?"),
            *_COMUNES,
        ],
        "opcionales": [
            _p("competencia", "¿Quiénes son tu competencia?"),
            _p("identidad_marca", "¿Tienes identidad de marca definida (nombre, tono, visual)?"),
            _p("proveedores", "¿Tienes proveedores resueltos?"),
            _p("logistica", "¿Cómo es tu logística/envíos?"),
            _p("metricas", "¿Qué métricas sigues (ventas, conversión, etc.)?"),
            _p("ya_intento", "¿Qué ya intentaste y cómo te fue?"),
        ],
    },
    "skill": {
        "requeridos": [
            _p("nivel_actual", "¿Cuál es tu nivel REAL hoy? (sé honesto, con ejemplos)"),
            _p("materiales", "¿Qué materiales/recursos tienes o usarás?",
               "Engancha biblioteca_material si hay algo del tema (material_para_proyecto)."),
            _p("estilo_aprendizaje", "¿Cómo aprendes mejor? (práctica, teoría, conversación…)"),
            _p("hitos_examenes", "¿Hay hitos o exámenes que marquen el avance?"),
            *_COMUNES,
        ],
        "opcionales": [
            _p("obstaculos", "¿Qué te ha frenado antes con esto?"),
            _p("rendir_cuentas", "¿Algo o alguien que te ayude a rendir cuentas?"),
        ],
    },
    "construir": {
        "requeridos": [
            _p("que_construye", "¿Qué vas a construir, exactamente?"),
            _p("para_que", "¿Para qué/para quién? ¿Qué problema resuelve?"),
            _p("alcance", "¿Cuál es el alcance mínimo de la primera versión?"),
            _p("recursos_stack", "¿Con qué lo vas a construir? (herramientas, stack, recursos)"),
            _p("etapa", "¿En qué etapa estás hoy?"),
            *_COMUNES,
        ],
        "opcionales": [
            _p("referencias", "¿Tienes referencias o ejemplos que te gusten?"),
            _p("riesgos", "¿Qué riesgos o incógnitas ves?"),
        ],
    },
    "fisico": {
        "requeridos": [
            _p("objetivo_fisico", "¿Cuál es el objetivo físico concreto?"),
            _p("estado_actual", "¿Cuál es tu estado/punto de partida hoy?"),
            _p("frecuencia", "¿Con qué frecuencia puedes entrenar/dedicarle?"),
            _p("restricciones", "¿Lesiones, restricciones o condiciones a considerar?"),
            *_COMUNES,
        ],
        "opcionales": [
            _p("materiales", "¿Equipo/materiales disponibles?"),
            _p("metricas", "¿Cómo medirás el progreso?"),
        ],
    },
    "generico": {
        "requeridos": [
            _p("objetivo", "¿Cuál es el objetivo de fondo del proyecto?"),
            *_COMUNES,
        ],
        "opcionales": [
            _p("recursos", "¿Con qué recursos cuentas?"),
            _p("obstaculos", "¿Qué obstáculos prevés?"),
        ],
    },
}

TIPOS = tuple(ESQUEMAS.keys())

# Palabras clave para detectar el tipo desde el nombre/objetivo/descripción.
_ALIAS_TIPO: dict[str, list[str]] = {
    "negocio": ["vender", "venta", "negocio", "marca", "tienda", "emprend", "ecommerce",
                "producto", "ropa", "drop", "clientes", "startup", "monetiz", "ingresos"],
    "skill": ["aprender", "idioma", "ingles", "english", "guitarra", "tocar", "estudiar",
              "dominar", "nivel", "b1", "b2", "c1", "curso", "portugues", "trading"],
    "fisico": ["bajar de peso", "masa muscular", "gym", "gimnasio", "calistenia", "correr",
               "salud", "entrenar", "dieta", "fuerza", "fisico", "cuerpo"],
    "construir": ["app", "aplicacion", "software", "construir", "juego", "web", "sistema",
                  "programa", "plataforma", "herramienta", "codigo", "mvp"],
}


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def detectar_tipo(texto: str) -> str:
    """Detecta el tipo de proyecto desde su nombre/objetivo/descripción.
    Default 'generico' si no calza nada. PURO."""
    t = _norm(texto)
    if not t:
        return "generico"
    for tipo, alias in _ALIAS_TIPO.items():
        if any(a in t for a in alias):
            return tipo
    return "generico"


def esquema_de(tipo: str) -> dict[str, list[dict[str, str]]]:
    """El esquema (requeridos + opcionales) del tipo, o el genérico."""
    return ESQUEMAS.get(tipo, ESQUEMAS["generico"])


def _tiene(capturados: dict[str, Any], clave: str) -> bool:
    v = capturados.get(clave)
    return bool(v.strip()) if isinstance(v, str) else bool(v)


def siguiente_pregunta_intake(
    tipo: str, capturados: dict[str, Any], preguntados: list[str]
) -> dict[str, Any] | None:
    """La siguiente pregunta afilada del intake: primero los REQUERIDOS no
    capturados/ no preguntados; luego ofrece OPCIONALES. None = nada pendiente.
    Una pregunta a la vez. PURO."""
    esquema = esquema_de(tipo)
    ya = set(preguntados)
    for grupo, requerido in (("requeridos", True), ("opcionales", False)):
        for p in esquema[grupo]:
            clave = p["clave"]
            if clave in ya or _tiene(capturados, clave):
                continue
            return {**p, "requerido": requerido}
    return None


def huecos(tipo: str, capturados: dict[str, Any]) -> dict[str, list[str]]:
    """Qué falta: claves REQUERIDAS sin capturar (bloquean el plan) y opcionales
    pendientes (no bloquean). PURO."""
    esquema = esquema_de(tipo)
    req = [p["clave"] for p in esquema["requeridos"] if not _tiene(capturados, p["clave"])]
    opc = [p["clave"] for p in esquema["opcionales"] if not _tiene(capturados, p["clave"])]
    return {"requeridos_faltantes": req, "opcionales_pendientes": opc}


def puede_planear(tipo: str, capturados: dict[str, Any]) -> dict[str, Any]:
    """GATE de completitud: solo se puede planear si NO falta ningún requerido
    (incluye meta_plazo y criterio_exito = meta clara, medible y con plazo).
    PURO."""
    faltan = huecos(tipo, capturados)["requeridos_faltantes"]
    if not faltan:
        return {"listo": True, "faltan": [], "motivo": "Tienes todo lo requerido; se puede planear."}
    return {
        "listo": False,
        "faltan": faltan,
        "motivo": "Aún falta lo requerido para un plan honesto: " + ", ".join(faltan),
    }


def horizonte_por_indice(indice_fase: int, total_fases: int) -> str:
    """Etiqueta de horizonte de una fase del plan en capas según su posición:
    la actual es 'corto', las del medio 'medio', las lejanas 'largo'. PURO."""
    if total_fases <= 1 or indice_fase == 0:
        return "corto"
    if indice_fase >= total_fases - 1 and total_fases > 2:
        return "largo"
    return "medio" if total_fases > 2 else "largo"


def armar_plan_capas(
    *, vision: str, hitos: list[dict[str, Any]], tareas_corto: list[str]
) -> dict[str, Any]:
    """Estructura el plan EN CAPAS para horizonte largo, sin aplanar:
    visión (años) → hitos por fase (con su horizonte y criterio) → tareas finas
    accionables YA del bloque actual. PURO."""
    n = len(hitos)
    capas_hitos = []
    for i, h in enumerate(hitos):
        capas_hitos.append({
            "titulo": h.get("titulo", ""),
            "horizonte": horizonte_por_indice(i, n),
            "criterio": h.get("criterio", ""),
        })
    return {
        "vision": vision,
        "hitos": capas_hitos,
        "tareas_corto": [{"titulo": t, "horizonte": "corto"} for t in tareas_corto if t],
    }


# ════════════════════════════════════════════════════════════════════════════
# Estado (impuro): parámetros en proyectos.parametros + preguntados
# ════════════════════════════════════════════════════════════════════════════

# Parámetros que también se reflejan en columnas del perfil (para que el árbol,
# el % de avance y el briefing los vean sin abrir el jsonb).
_ESPEJO_COLUMNAS = {"objetivo": "objetivo", "horizonte_anios": "horizonte"}


async def cargar_capturados(db: Postgrest, proyecto: dict[str, Any]) -> dict[str, Any]:
    return dict(proyecto.get("parametros") or {})


async def guardar_parametro(
    db: Postgrest, *, proyecto: dict[str, Any], clave: str, valor: str
) -> None:
    """Mergea el parámetro en proyectos.parametros (read-modify-write) y espeja
    los que tienen columna propia."""
    params = dict(proyecto.get("parametros") or {})
    params[clave] = valor
    payload: dict[str, Any] = {"parametros": params}
    if clave in _ESPEJO_COLUMNAS:
        payload[_ESPEJO_COLUMNAS[clave]] = valor
    await db.update("proyectos", proyecto["id"], payload)


async def set_tipo(db: Postgrest, *, proyecto_id: str, tipo: str) -> None:
    if tipo in ESQUEMAS:
        await db.update("proyectos", proyecto_id, {"tipo": tipo})


async def estado_intake(db: Postgrest, proyecto_id: str) -> dict[str, Any] | None:
    filas = await db.list("entrevistas_perfil", filters={"proyecto_id": proyecto_id}, limit=1)
    return filas[0] if filas else None


async def guardar_estado_intake(
    db: Postgrest, *, proyecto_id: str, estado: str, preguntados: list[str]
) -> None:
    await db.delete_where("entrevistas_perfil", filters={"proyecto_id": proyecto_id})
    await db.insert(
        "entrevistas_perfil",
        {"proyecto_id": proyecto_id, "estado": estado, "preguntados": preguntados},
    )


async def intake_en_curso(db: Postgrest) -> bool:
    """¿Hay un intake en curso? Lo usa el ruteo para mandar TODO el intake al
    modelo fuerte (no solo el turno que lo dispara)."""
    try:
        filas = await db.list(
            "entrevistas_perfil", filters={"estado": "en_curso"}, limit=1
        )
        return bool(filas)
    except Exception:  # noqa: BLE001
        return False


def _norm(s: Any) -> str:
    r = s.lower().strip() if isinstance(s, str) else ""
    con, sin = "áàäâãéèëêíìïîóòöôõúùüûñ", "aaaaaeeeeiiiiooooouuuun"
    for i in range(len(con)):
        r = r.replace(con[i], sin[i])
    return r
