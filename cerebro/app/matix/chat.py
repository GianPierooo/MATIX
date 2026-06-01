"""Orquestador de conversación con Matix.

Recibe un mensaje del usuario + historial previo y devuelve la
respuesta. Arma el system prompt en este orden:

1. Reglas + tono + descripción de las herramientas (fijos).
2. Documento Maestro literal (fijo).
3. Contexto vivo del hub (proyectos activos con ids, tareas próximas
   con ids, eventos, cursos con ids…).

(1) y (2) se mantienen idénticos entre turnos → OpenAI los cachea
automáticamente. (3) varía cada turno pero va al final, así no rompe
el prefijo cacheado.

A partir de Capa 2 Paso 2, este módulo también maneja el **loop de
tool calling**: si el modelo pide ejecutar una herramienta, la
corremos, le devolvemos el resultado, y volvemos a llamar al modelo
para que narre lo que hizo (o encadene la siguiente acción). El
loop está acotado por `_MAX_VUELTAS` para evitar que un modelo
descalibrado dispare herramientas en bucle.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import enrutador, estado, llm, memoria, modelos_llm, modos
from .contexto import contexto_vivo
from .system_prompt import system_prompt_fijo
from .tools import TABLAS_AFECTADAS, TOOL_DEFINITIONS, ejecutar_tool

# Tope de iteraciones del loop modelo↔tools. Generoso pero finito:
# 6 cubre el caso "ejecutar 3 tools, ver resultado, narrar" con
# margen. Si se alcanza, devolvemos lo último que dijo el modelo y
# cortamos.
_MAX_VUELTAS = 6

_LIMA = ZoneInfo("America/Lima")
_DIAS_ES = [
    "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo",
]
_MESES_ES = [
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
    "septiembre", "octubre", "noviembre", "diciembre",
]


def _ahora_lima_es() -> str:
    """Fecha y hora actuales en Lima, en español y 12h (ej.
    'lunes 9 de febrero de 2026, 9:03 a. m.'). El cerebro la calcula
    explícita — no asume el reloj del sistema."""
    a = datetime.now(timezone.utc).astimezone(_LIMA)
    h12 = a.hour % 12 or 12
    ampm = "a. m." if a.hour < 12 else "p. m."
    return (
        f"{_DIAS_ES[a.weekday()]} {a.day} de {_MESES_ES[a.month - 1]} "
        f"de {a.year}, {h12}:{a.minute:02d} {ampm}"
    )


# Tope de imágenes por mensaje: varias ayudan (un recibo de dos páginas, dos
# capturas), pero cada una infla tokens. 5 es un techo razonable.
_MAX_IMAGENES = 5


async def conversar(
    db: Postgrest,
    *,
    historial: list[dict],
    mensaje: str,
    imagen: str | None = None,
    imagenes: list[str] | None = None,
    documento: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Genera la respuesta de Matix a `mensaje`, considerando
    `historial` (lista de `{rol, contenido}` con `rol` en
    `user`/`assistant`).

    Devuelve un dict:

        {
            "respuesta": "<texto final para mostrarle al usuario>",
            "tools_usadas": ["crear_tarea", ...],   # nombres
            "tablas_cambiadas": ["tareas", ...],    # para invalidar UI
        }

    Si el modelo devuelve texto sin tools, `tools_usadas` y
    `tablas_cambiadas` son listas vacías.
    """
    fijo = system_prompt_fijo()
    contexto = await contexto_vivo(db)

    mensajes: list[dict] = [
        {"role": "system", "content": fijo},
        {"role": "system", "content": contexto},
    ]

    # Conciencia temporal: la hora y fecha actuales en Lima, explícitas y en
    # español, para que Matix las use en la conversación (no solo para las
    # notificaciones). Ej.: notar que piden el "cierre del día" en la mañana.
    mensajes.append(
        {
            "role": "system",
            "content": (
                f"Hora y fecha actuales (America/Lima): {_ahora_lima_es()}. "
                "Tenlas presentes y úsalas: si algo no cuadra con la hora "
                "(p. ej. pedir el «cierre del día» en plena mañana), nótalo "
                "con tino y ofrece lo apropiado."
            ),
        }
    )

    # Memoria personal (Capa Memoria): el bloque compacto "lo que sé de ti"
    # con los hechos esenciales del usuario, junto al contexto vivo. Si no
    # hay nada, no inyecta nada. Lo extenso se recupera con `buscar_memoria`.
    bloque_mem = await memoria.bloque_memoria(db)
    if bloque_mem:
        mensajes.append({"role": "system", "content": bloque_mem})

    # Modo activo (Capa Modos): si hay uno, entra como `system` ADICIONAL,
    # encima del prompt base. Las reglas base e identidad de Matix mandan
    # siempre — el envoltorio se lo recuerda al modelo. El modo activo al
    # ARRANCAR el turno es el que se inyecta; si el modelo lo cambia con
    # `activar_modo`/`desactivar_modo`, aplica desde el próximo turno (y ya
    # avisó al usuario).
    modo = await modos.modo_activo(db)
    if modo:
        contenido_modo = modos.cargar_modo(modo)
        if contenido_modo:
            mensajes.append(
                {
                    "role": "system",
                    "content": modos.envoltura_modo(modo, contenido_modo),
                }
            )
    # Documento adjunto (PDF/DOCX/TXT/MD): el texto ya extraído por el cerebro
    # entra como contexto `system` de ESTE turno (no va al historial, igual que
    # la imagen). Matix lo lee para responder lo que el usuario le pida
    # (resumir, analizar, sacar tareas…). Si pide guardarlo, usa crear_apunte.
    doc_nombre = (documento or {}).get("nombre", "").strip()
    doc_texto = (documento or {}).get("texto", "").strip()
    if doc_texto:
        titulo = doc_nombre or "documento"
        mensajes.append(
            {
                "role": "system",
                "content": (
                    f"DOCUMENTO ADJUNTO por el usuario («{titulo}»). Léelo y "
                    "úsalo para responder lo que te pida en este turno "
                    "(resumir, analizar, explicar, sacar tareas…). Si te pide "
                    "guardarlo, usa crear_apunte con su contenido. Contenido:\n\n"
                    f"{doc_texto}"
                ),
            }
        )

    # Imágenes del turno. `imagen` (singular) se mantiene por compatibilidad;
    # `imagenes` permite varias. Se normaliza a UNA lista, se quitan vacías y
    # se capa a `_MAX_IMAGENES` (no inflar tokens). Solo viajan en ESTE turno.
    imgs = list(imagenes or [])
    if imagen:
        imgs.insert(0, imagen)
    imgs = [u for u in imgs if u][:_MAX_IMAGENES]

    # Modelo (y por ende proveedor) del CHAT: se resuelve UNA sola vez al
    # arrancar el turno y se usa en TODAS las vueltas del loop. Crítico: si el
    # usuario cambia de modelo a mitad de conversación, el cambio aplica desde
    # el PRÓXIMO turno; dentro de un turno el proveedor no cambia, así el
    # `raw` (formato nativo del proveedor) que se re-inyecta siempre encaja.
    # El historial entre turnos se reconstruye desde los campos NEUTROS
    # ({rol, contenido} de texto) — nunca se reusa el `raw` de otro proveedor.
    #
    # Modo Automático: si la selección es "auto", el enrutador por reglas
    # elige el modelo SEGÚN ESTE MENSAJE (sin llamada extra a ningún modelo).
    # Se decide acá, una vez, así que el turno entero —incluido su loop de
    # tools— se queda en el modelo elegido; el ruteo solo cambia entre turnos,
    # que es exactamente donde la reconstrucción de historial lo soporta.
    seleccion = await modelos_llm.seleccion_guardada(db)
    auto = seleccion == modelos_llm.AUTO
    if auto:
        barato, fuerte = await modelos_llm.par_barato_fuerte(db)
        # Con un documento O una imagen adjunta vamos al modelo FUERTE: el
        # enrutador solo ve el mensaje (corto: «resúmelo» / «anota los gastos»),
        # pero leer/analizar un documento o una captura (Yape/banco) merece el
        # modelo a fondo — mejor lectura, menos errores de clasificación. Sube
        # algo el costo en mensajes con adjunto, pero la precisión lo vale.
        if doc_texto or imgs:
            modelo = fuerte
        else:
            decision = enrutador.elegir(
                mensaje, modo_activo=modo, barato=barato, fuerte=fuerte
            )
            modelo = decision.modelo
    else:
        modelo = seleccion

    # ESTADO DE MATIX + el modelo REAL de este turno (id + nombre amigable),
    # como contexto `system`. Así Matix reporta con precisión en qué modelo
    # está (incluido Automático, que resuelve por mensaje) y qué puede hacer,
    # sin depender de cómo se autoidentifique el modelo subyacente.
    mensajes.append(
        {
            "role": "system",
            "content": estado.bloque_estado(
                modelo_id=modelo,
                modelo_etiqueta=modelos_llm.etiqueta_de(modelo),
                auto=auto,
            ),
        }
    )

    # Historial entre turnos: SIEMPRE desde los campos NEUTROS ({rol,
    # contenido} de texto), nunca el `raw` de otro proveedor. Un turno
    # solo-imagen/solo-documento se guardó con texto vacío: OpenAI lo tolera,
    # pero Anthropic RECHAZA contenido vacío y rompería el hilo al cambiar a
    # Claude. Le ponemos un placeholder neutro para no perder el turno ni el
    # orden de la conversación.
    for m in historial:
        rol = m.get("rol") or m.get("role")
        if rol not in ("user", "assistant"):
            continue
        contenido = (m.get("contenido") or "").strip() or "(adjunto)"
        mensajes.append({"role": rol, "content": contenido})

    # El turno actual: si trae imágenes, el `content` es una lista multimodal
    # [texto, imagen, imagen…] que el modelo de visión entiende (OpenAI y
    # Anthropic aceptan varios bloques de imagen). Las imágenes solo viajan en
    # ESTE turno — no entran al historial, así no se re-mandan después.
    if imgs:
        contenido_usuario: Any = [{"type": "text", "text": mensaje}]
        for url in imgs:
            contenido_usuario.append(
                {"type": "image_url", "image_url": {"url": url}}
            )
    else:
        contenido_usuario = mensaje
    mensajes.append({"role": "user", "content": contenido_usuario})

    tools_usadas: list[str] = []
    tablas_cambiadas: list[str] = []
    # Sección a la que llevar al usuario si pidió navegar ("llévame a
    # Universidad"). Gana la última llamada a `navegar` del turno.
    navegacion: str | None = None

    ultima_respuesta = ""

    for _ in range(_MAX_VUELTAS):
        salida = await llm.responder_con_tools(
            mensajes, TOOL_DEFINITIONS, model=modelo
        )

        if salida["tipo"] == "texto":
            ultima_respuesta = salida["contenido"]
            break

        # tipo == "tool_calls": metemos el mensaje del modelo (con
        # los tool_call_id) y a continuación una respuesta `tool`
        # por cada call. Luego volvemos a llamar al modelo.
        mensajes.append(salida["raw"])

        for call in salida["tool_calls"]:
            nombre = call["nombre"]
            args = call["args"]
            tools_usadas.append(nombre)

            resultado = await ejecutar_tool(db, nombre, args)

            if resultado.get("ok"):
                for tabla in TABLAS_AFECTADAS.get(nombre, []):
                    if tabla not in tablas_cambiadas:
                        tablas_cambiadas.append(tabla)
                # `navegar` no cambia datos: solo emite la sección a abrir.
                if nombre == "navegar":
                    navegacion = resultado.get("datos", {}).get("seccion")

            mensajes.append(
                {
                    "role": "tool",
                    "tool_call_id": call["id"],
                    "content": json.dumps(
                        resultado, ensure_ascii=False
                    ),
                }
            )
    else:
        # Se agotaron las vueltas sin que el modelo cerrara con
        # texto. Damos algo razonable.
        ultima_respuesta = (
            ultima_respuesta
            or "Hice varias acciones pero me enredé al narrarlas. "
            "Revisá el hub: lo último debería estar reflejado."
        )

    # Modo activo DESPUÉS del turno (el modelo pudo cambiarlo con
    # activar_modo/desactivar_modo). La app lo usa para el indicador.
    modo_final = await modos.modo_activo(db)

    return {
        "respuesta": ultima_respuesta,
        "tools_usadas": tools_usadas,
        "tablas_cambiadas": tablas_cambiadas,
        "navegacion": navegacion,
        "modo_activo": modo_final,
        # Transparencia: qué modelo respondió este turno y si lo eligió el
        # modo Automático. La app lo muestra (sobre todo en auto) para que
        # el usuario vea qué se usó y pueda ajustar el par.
        "modelo_usado": modelo,
        "auto": auto,
    }


# Forzamos esta tool concreta: la captura rápida de Inicio no es una
# conversación, su único trabajo es guardar el apunte clasificado.
_TOOL_CHOICE_CREAR_APUNTE = {
    "type": "function",
    "function": {"name": "crear_apunte"},
}


async def capturar_apunte(db: Postgrest, *, texto: str) -> dict[str, Any]:
    """Captura rápida de un apunte dictado desde Inicio.

    Reusa las piezas del Paso C: el system prompt fijo (que ya lleva
    las reglas de clasificación), el contexto vivo (proyectos/cursos
    EXISTENTES con sus ids) y la tool `crear_apunte` (que indexa para
    el RAG y reporta dónde quedó archivado). No es conversación: una
    sola llamada forzada a `crear_apunte`, sin narración ni loop.

    Devuelve el resultado crudo de la tool:
    `{"ok": True, "datos": {...}}` o `{"ok": False, ...}`. El router
    lo traduce a la respuesta HTTP.
    """
    fijo = system_prompt_fijo()
    contexto = await contexto_vivo(db)

    instruccion = (
        "El usuario acaba de dictar una idea para anotar (captura "
        "rápida desde la pantalla Inicio — NO es una conversación). "
        "Tu única tarea es guardarla llamando `crear_apunte` una vez: "
        "un título corto, el contenido con la idea, y la clasificación "
        "a un proyecto activo o curso que YA exista en el contexto "
        "vivo solo si encaja claro; ante la duda, déjalo general. No "
        "inventes proyectos ni cursos.\n\nIdea dictada:\n" + texto
    )

    mensajes: list[dict] = [
        {"role": "system", "content": fijo},
        {"role": "system", "content": contexto},
        {"role": "user", "content": instruccion},
    ]

    salida = await llm.responder_con_tools(
        mensajes,
        TOOL_DEFINITIONS,
        model=await modelos_llm.modelo_seleccionado(db),
        tool_choice=_TOOL_CHOICE_CREAR_APUNTE,
    )

    if salida["tipo"] != "tool_calls":
        # Forzamos la tool, así que esto no debería pasar; si el modelo
        # devolvió texto igual, lo tratamos como fallo claro.
        raise RuntimeError("El modelo no generó la captura del apunte.")

    call = next(
        (c for c in salida["tool_calls"] if c["nombre"] == "crear_apunte"),
        None,
    )
    if call is None:
        raise RuntimeError("El modelo no llamó a crear_apunte.")

    return await ejecutar_tool(db, "crear_apunte", call["args"])
