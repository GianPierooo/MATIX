"""Único punto de entrada al modelo de lenguaje.

**Ningún otro módulo del cerebro importa `openai` ni `anthropic`.** Esto
es por diseño: el proveedor del LLM de chat es intercambiable por env, y
toda la lógica vive acá. Los demás módulos reciben `dict`s simples —
incluso los tool calls se devuelven en formato neutro para no acoplar
`chat.py` a ninguna SDK.

Proveedores del CHAT (env `MATIX_LLM_PROVIDER`, default `openai`):
- `openai`  → modelos GPT (function calling + visión + JSON nativo).
- `anthropic` → modelos Claude (tool use + visión; JSON por prefill).
`MATIX_LLM_MODEL` fija el modelo del proveedor elegido (default el
`gpt-4o-mini` de siempre).

SIEMPRE OpenAI, sin importar el proveedor del chat (Anthropic no tiene
equivalentes): transcripción (Whisper), TTS y los embeddings del RAG.

Las API keys se leen SOLO de variables de entorno (`OPENAI_API_KEY`,
`ANTHROPIC_API_KEY`); nunca del código ni del repo.
"""
from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from datetime import date
from typing import Any, TypeVar

from openai import AsyncOpenAI

from ..config import settings
from . import modelos_llm
from .uso import medidor

logger = logging.getLogger("matix.llm")

# Tope de tokens de salida para Anthropic (OpenAI no lo exige). Holgado
# para una respuesta de chat o un lote de tool calls.
_MAX_TOKENS_ANTHROPIC = 4096


def _es_error_de_proveedor(e: Exception) -> bool:
    """¿El fallo es del PROVEEDOR (transitorio/operativo) y amerita failover?

    SÍ: timeout, caída de conexión, rate limit (429), saturación (529) y
    errores 5xx del servidor del proveedor.
    NO: bad request (400), content filter, auth (401/403), not found (404),
    validación (422) — esos son legítimos y se devuelven tal cual.

    Funciona para ambos SDKs (OpenAI y Anthropic comparten la jerarquía
    httpx/APIError): primero miramos `status_code`; si no hay (timeout/
    conexión), caemos al nombre de la clase.
    """
    code = getattr(e, "status_code", None)
    if isinstance(code, int):
        return code in (408, 409, 425, 429) or code >= 500
    nombre = type(e).__name__
    return nombre in {
        "APITimeoutError",
        "APIConnectionError",
        "APIConnectionTimeoutError",
        "RateLimitError",
        "InternalServerError",
        "ServiceUnavailableError",
        "OverloadedError",
        "Timeout",
        "ConnectError",
        "ReadTimeout",
    }


def _es_auth_o_credito(e: Exception) -> bool:
    """¿El fallo es por AUTH (key inválida) o CRÉDITO/CUOTA agotada?

    Para el FAILOVER entre proveedores esto SÍ amerita saltar al otro: si la
    key de OpenAI no tiene crédito (401 / 403 / 429 insufficient_quota), no
    sirve reintentar con OpenAI — hay que usar Anthropic. (Distinto del retry
    en el MISMO proveedor, que sí excluye estos: reintentar una key muerta es
    inútil.)
    """
    code = getattr(e, "status_code", None)
    if code in (401, 403):
        return True
    # 429 puede ser rate-limit (transitorio) o insufficient_quota (sin saldo).
    texto = f"{getattr(e, 'code', '')} {e}".lower()
    pistas = ("insufficient_quota", "billing", "credit", "quota", "exceeded your", "payment")
    if code == 429 and any(p in texto for p in pistas):
        return True
    nombre = type(e).__name__
    if nombre in ("AuthenticationError", "PermissionDeniedError"):
        return True
    return any(p in texto for p in ("insufficient_quota", "exceeded your current quota"))


def _amerita_failover(e: Exception) -> bool:
    """Para CAMBIAR de proveedor: transitorio (timeout/5xx/429) O auth/crédito.
    Lo legítimo (400 bad request, content filter, 404, 422) NO cae al otro."""
    return _es_error_de_proveedor(e) or _es_auth_o_credito(e)


_T = TypeVar("_T")


def _modelo_efectivo(model: str | None) -> str:
    """Modelo a intentar PRIMERO, respetando el proveedor preferido.

    - Si la preferencia es 'auto' (o no hay), usa el modelo tal cual.
    - Si la preferencia fuerza un proveedor distinto al del modelo, salta al
      modelo COMPARABLE de ese proveedor (p. ej. preferencia=anthropic y
      modelo=gpt-4o-mini → claude-haiku-4-5). El failover luego cae al otro.
    """
    m = _modelo_chat(model)
    pref = modelos_llm.proveedor_preferido()
    if pref in ("openai", "anthropic") and modelos_llm.proveedor_de_id(m) != pref:
        alt = modelos_llm.modelo_fallback(m)
        if alt and modelos_llm.proveedor_de_id(alt) == pref:
            return alt
    return m


async def _con_failover(
    model: str, intento: Callable[[str], Awaitable[_T]]
) -> tuple[_T, str, bool]:
    """Ejecuta `intento(model)`; si falla por error de proveedor o por
    auth/crédito, reintenta UNA vez con el modelo comparable del OTRO
    proveedor. Devuelve (resultado, modelo_efectivo, hubo_failover).
    Errores legítimos se relanzan sin failover."""
    try:
        return await intento(model), model, False
    except Exception as e:  # noqa: BLE001
        if not _amerita_failover(e):
            raise
        fallback = modelos_llm.modelo_fallback(model)
        if not fallback or fallback == model:
            raise
        logger.warning(
            "failover LLM: «%s» (%s) falló por %s → reintento con «%s» (%s)",
            model, modelos_llm.proveedor_de_id(model), type(e).__name__,
            fallback, modelos_llm.proveedor_de_id(fallback),
        )
        return await intento(fallback), fallback, True


async def _con_reintentos(
    hacer: Callable[[], Awaitable[_T]],
    *,
    intentos: int = 3,
    base_delay: float = 0.4,
    etiqueta: str = "llm",
) -> _T:
    """Ejecuta `hacer()` reintentando SOLO ante errores TRANSITORIOS de proveedor
    (timeout / 5xx / 429), con backoff exponencial (base_delay·2^i). Tras agotar
    los intentos, relanza el último error. Los errores legítimos (400/401/422…)
    se relanzan de inmediato (no son transitorios). Sirve para utilidades como
    el TTS y la narración de cámara, que antes no reintentaban y morían ante un
    502 pasajero de OpenAI."""
    for i in range(intentos):
        try:
            return await hacer()
        except Exception as e:  # noqa: BLE001
            if not _es_error_de_proveedor(e) or i == intentos - 1:
                raise
            logger.warning(
                "%s: error transitorio (%s); reintento %d/%d",
                etiqueta, type(e).__name__, i + 1, intentos - 1,
            )
            await asyncio.sleep(base_delay * (2 ** i))
    # Inalcanzable (el loop siempre retorna o relanza), pero deja el tipo claro.
    raise RuntimeError("reintentos agotados")  # pragma: no cover


_openai_client: AsyncOpenAI | None = None
_anthropic_client: Any = None


def _get_openai_client() -> AsyncOpenAI:
    """Cliente OpenAI lazy. Lo usan el chat (proveedor openai) y SIEMPRE
    Whisper/TTS/embeddings. Falla claro si falta la key."""
    global _openai_client
    if _openai_client is None:
        if not settings.openai_api_key:
            raise RuntimeError(
                "OPENAI_API_KEY no está configurada en cerebro/.env"
            )
        _openai_client = AsyncOpenAI(api_key=settings.openai_api_key)
    return _openai_client


def _get_anthropic_client() -> Any:
    """Cliente Anthropic lazy. Solo se importa/crea si el proveedor de
    chat es `anthropic` — así el camino default (OpenAI) no depende de
    que la SDK esté presente en runtime."""
    global _anthropic_client
    if _anthropic_client is None:
        if not settings.anthropic_api_key:
            raise RuntimeError(
                "ANTHROPIC_API_KEY no está configurada (necesaria con "
                "MATIX_LLM_PROVIDER=anthropic)."
            )
        from anthropic import AsyncAnthropic

        _anthropic_client = AsyncAnthropic(api_key=settings.anthropic_api_key)
    return _anthropic_client


# ─────────────────────────────────────────────────────────────────────
# Capa de proveedor: selección + traducción de formatos
# ─────────────────────────────────────────────────────────────────────


def _es_anthropic(model: str) -> bool:
    """Proveedor del modelo: se INFIERE del id (claude-* → anthropic;
    gpt-*/o* → openai), con el env como último fallback."""
    return modelos_llm.proveedor_de_id(model) == "anthropic"


def _modelo_chat(model: str | None) -> str:
    """El modelo del chat: el explícito si se pasó, si no el de env."""
    return model or settings.matix_llm_model or "gpt-4o-mini"


def _registrar_chat_openai(usage: Any, model: str) -> None:
    """Registra el uso de un chat OpenAI con el precio del MODELO usado."""
    precios = modelos_llm.precios_de(model)
    if precios:
        medidor.registrar_chat(
            usage, precio_input_por_m=precios[0], precio_output_por_m=precios[1],
            proveedor="openai",
        )
    else:
        medidor.registrar_chat(usage, proveedor="openai")


def _registrar_uso_anthropic(usage: Any, model: str) -> None:
    """Normaliza el `usage` de Anthropic (input/output/cache) al shape que
    espera `medidor.registrar_chat`, con el precio del MODELO usado."""
    if usage is None:
        return
    inp = getattr(usage, "input_tokens", 0) or 0
    out = getattr(usage, "output_tokens", 0) or 0
    cache_read = getattr(usage, "cache_read_input_tokens", 0) or 0
    normalizado = {
        "prompt_tokens": inp + cache_read,
        "completion_tokens": out,
        "prompt_tokens_details": {"cached_tokens": cache_read},
    }
    precios = modelos_llm.precios_de(model)
    if precios:
        medidor.registrar_chat(
            normalizado, precio_input_por_m=precios[0], precio_output_por_m=precios[1],
            proveedor="anthropic",
        )
    else:
        medidor.registrar_chat(normalizado, proveedor="anthropic")


def _imagen_a_anthropic(url: str) -> dict[str, Any]:
    """Convierte un `data:image/...;base64,...` (formato OpenAI/visión) a un
    bloque `image` de Anthropic."""
    cabecera, _, datos = url.partition(",")
    media = "image/jpeg"
    if cabecera.startswith("data:") and ";" in cabecera:
        media = cabecera[len("data:"):].split(";", 1)[0] or "image/jpeg"
    return {
        "type": "image",
        "source": {"type": "base64", "media_type": media, "data": datos},
    }


def _contenido_usuario_anthropic(content: Any) -> Any:
    """Contenido de un mensaje de usuario: texto plano tal cual, o lista
    multimodal [texto, imagen] traducida a bloques de Anthropic."""
    # Anthropic RECHAZA contenido de usuario vacío (rompería el hilo). Nunca
    # devolvemos cadena/lista vacía: un placeholder neutro mantiene el turno.
    if isinstance(content, str):
        return content if content.strip() else "(adjunto)"
    if isinstance(content, list):
        bloques: list[dict[str, Any]] = []
        for parte in content:
            if not isinstance(parte, dict):
                continue
            if parte.get("type") == "text":
                texto = parte.get("text", "")
                if texto.strip():
                    bloques.append({"type": "text", "text": texto})
            elif parte.get("type") == "image_url":
                url = (parte.get("image_url") or {}).get("url", "")
                if url:
                    bloques.append(_imagen_a_anthropic(url))
        return bloques or "(adjunto)"
    return content or "(adjunto)"


def _a_anthropic(messages: list[dict]) -> tuple[str, list[dict]]:
    """Traduce la conversación NEUTRA (lo que arma `chat.py`) a
    (system, messages) de Anthropic:

    - los `system` se concatenan en el parámetro `system` aparte,
    - el assistant NEUTRO (`{contenido, tool_calls:[{id,nombre,args}]}`) se
      serializa a bloques `text` + `tool_use` de Anthropic,
    - los resultados de tool (`role:tool`) se agrupan en UN mensaje `user`
      con bloques `tool_result` (Anthropic lo exige así),
    - las imágenes de un user multimodal se traducen a bloques `image`.

    NUNCA recibe bloques crudos de OTRO proveedor: la representación es neutra,
    así el failover a mitad de turno y manos libres con tools funcionan.
    """
    system_partes: list[str] = []
    out: list[dict] = []
    tool_results: list[dict] = []

    def _flush() -> None:
        nonlocal tool_results
        if tool_results:
            out.append({"role": "user", "content": tool_results})
            tool_results = []

    for m in messages:
        rol = m.get("role")
        if rol == "system":
            c = m.get("content")
            if isinstance(c, str) and c.strip():
                system_partes.append(c)
            continue
        if rol == "tool":
            contenido = m.get("content")
            if not isinstance(contenido, str):
                contenido = json.dumps(contenido, ensure_ascii=False)
            tool_results.append(
                {
                    "type": "tool_result",
                    "tool_use_id": m.get("tool_call_id"),
                    "content": contenido,
                }
            )
            continue
        _flush()
        if rol == "assistant":
            # Si el assistant YA viene con `content` en bloques (el `raw` de un
            # turno Anthropic previo, re-inyectado por el loop de tools), pásalo
            # TAL CUAL: reconstruirlo perdía los tool_use y rompía el pairing con
            # los tool_result del siguiente turno (multi-turno con Claude).
            contenido_raw = m.get("content")
            if isinstance(contenido_raw, list):
                out.append({"role": "assistant", "content": contenido_raw})
                continue
            texto = m.get("contenido")
            if not isinstance(texto, str):
                texto = contenido_raw if isinstance(contenido_raw, str) else ""
            bloques: list[dict[str, Any]] = []
            if texto and texto.strip():
                bloques.append({"type": "text", "text": texto})
            for c in m.get("tool_calls") or []:
                bloques.append(
                    {
                        "type": "tool_use",
                        "id": c.get("id"),
                        "name": c.get("nombre"),
                        "input": c.get("args") or {},
                    }
                )
            # Anthropic rechaza assistant vacío; placeholder si no hay nada.
            out.append({"role": "assistant", "content": bloques or (texto or "(ok)")})
        else:  # user
            out.append(
                {"role": "user", "content": _contenido_usuario_anthropic(m.get("content"))}
            )
    _flush()
    return "\n\n".join(system_partes), out


def _a_openai(messages: list[dict]) -> list[dict]:
    """Serializa la conversación NEUTRA al formato de OpenAI Chat Completions.

    system/user/tool ya vienen con el shape de OpenAI; el assistant NEUTRO
    (`{contenido, tool_calls:[{id,nombre,args}]}`) se traduce a
    `{role:assistant, content, tool_calls:[{id,type:function,function:{name,
    arguments}}]}`. NUNCA filtra bloques `tool_use` de Anthropic a OpenAI.
    """
    out: list[dict] = []
    for m in messages:
        if m.get("role") == "assistant" and ("tool_calls" in m or "contenido" in m):
            tcs = m.get("tool_calls") or []
            texto = m.get("contenido")
            if not isinstance(texto, str):
                texto = ""
            if tcs:
                out.append(
                    {
                        "role": "assistant",
                        "content": texto or None,
                        "tool_calls": [
                            {
                                "id": c.get("id"),
                                "type": "function",
                                "function": {
                                    "name": c.get("nombre"),
                                    "arguments": json.dumps(
                                        c.get("args") or {}, ensure_ascii=False
                                    ),
                                },
                            }
                            for c in tcs
                        ],
                    }
                )
            else:
                out.append({"role": "assistant", "content": texto})
        else:
            out.append(m)
    return out


def _raw_neutral(contenido: str, calls: list[dict]) -> dict[str, Any]:
    """Mensaje del asistente en representación NEUTRA, para re-inyectar en el
    historial sin atarlo a ningún proveedor."""
    return {"role": "assistant", "contenido": contenido or "", "tool_calls": calls}


def _tools_a_anthropic(tools: list[dict]) -> list[dict]:
    """Traduce las definiciones de tools de OpenAI (`function`/`parameters`)
    al formato de Anthropic (`input_schema`).

    Marca `cache_control` en la ÚLTIMA tool: Anthropic cachea todo el prefijo
    hasta el último breakpoint, así que esto cachea el bloque entero de tools
    (grande) junto con el system (que ya se cachea). En turnos siguientes de la
    misma conversación, las tools se leen del cache (~10% del costo) en vez de
    re-procesarse. Si el set de tools del turno cambia (filtrado distinto), el
    cache se rehace solo — sigue siendo correcto."""
    out: list[dict] = []
    for t in tools:
        f = t.get("function", t)
        out.append(
            {
                "name": f["name"],
                "description": f.get("description", ""),
                "input_schema": f.get("parameters")
                or {"type": "object", "properties": {}},
            }
        )
    if out:
        out[-1] = {**out[-1], "cache_control": {"type": "ephemeral"}}
    return out


def _tool_choice_a_anthropic(tool_choice: Any) -> dict[str, Any]:
    if isinstance(tool_choice, dict):
        nombre = (tool_choice.get("function") or {}).get("name")
        if nombre:
            return {"type": "tool", "name": nombre}
    return {"type": "auto"}


def _texto_de_anthropic(content: Any) -> str:
    partes = []
    for b in content or []:
        if getattr(b, "type", None) == "text":
            partes.append(b.text or "")
        elif isinstance(b, dict) and b.get("type") == "text":
            partes.append(b.get("text", ""))
    return "".join(partes)


async def _texto_en(model: str, messages: list[dict], *, temperature: float) -> str:
    """Un intento de texto contra UN modelo (rutea por proveedor)."""
    if _es_anthropic(model):
        return await _anthropic_texto(messages, model=model, temperature=temperature)
    return await _openai_texto(messages, model=model, temperature=temperature)


async def responder(
    messages: list[dict],
    *,
    model: str | None = None,
    temperature: float = 0.6,
) -> str:
    """Versión simple sin tools (resumen de documentos, utilidades). Respeta el
    proveedor preferido y cae al otro proveedor ante error/crédito agotado."""
    model = _modelo_efectivo(model)
    texto, _, _ = await _con_failover(
        model, lambda m: _texto_en(m, messages, temperature=temperature)
    )
    return texto


async def responder_con_tools(
    messages: list[dict],
    tools: list[dict],
    *,
    model: str | None = None,
    temperature: float = 0.6,
    tool_choice: Any = "auto",
) -> dict[str, Any]:
    """Llama al modelo del CHAT con acceso a `tools` (definiciones en el
    formato de OpenAI; el proveedor las traduce). Devuelve un dict NEUTRO
    que `chat.py` consume sin saber del proveedor:

        {"tipo": "texto", "contenido": "...", "raw": <opaco>}
    o
        {"tipo": "tool_calls",
         "tool_calls": [{"id", "nombre", "args"}...],
         "raw": <opaco>}

    `tool_choice` por defecto `"auto"`. Para forzar una herramienta:
    `{"type": "function", "function": {"name": "crear_apunte"}}` (formato
    OpenAI; el proveedor Anthropic lo traduce a `{"type":"tool","name":…}`).

    `raw` es el mensaje del asistente en el formato NATIVO del proveedor
    activo; `chat.py` lo re-inyecta tal cual en el siguiente turno (opaco
    para él). Como `chat.py` fija el modelo del turno y lo pasa en cada vuelta,
    si el primario cae TODAS las vueltas caen al MISMO fallback → el `raw`
    siempre es del mismo proveedor dentro del turno.

    FAILOVER (patrón barato y legítimo): si el proveedor del modelo primario
    falla por un error de PROVEEDOR (timeout/rate limit/5xx/caída), reintenta
    UNA sola vez con el modelo comparable del OTRO proveedor. En errores
    legítimos (bad request, content filter, auth) NO reintenta: los relanza.
    Si hubo failover, el dict trae `modelo_efectivo` y `failover=True` para que
    `chat.py` lo surfacee con transparencia.

    FAILOVER: respeta el proveedor preferido (lo intenta primero) y, si falla
    por error de proveedor O por auth/crédito agotado, cae UNA vez al modelo
    comparable del OTRO proveedor. Errores legítimos (400/404/422) se relanzan.
    """
    model = _modelo_efectivo(model)
    resultado, efectivo, hubo = await _con_failover(
        model,
        lambda m: _con_tools_en(
            m, messages, tools, temperature=temperature, tool_choice=tool_choice
        ),
    )
    # SIEMPRE reportamos el modelo REAL que respondió: puede diferir del pedido
    # por el proveedor preferido (swap) o por failover. `failover` solo cuando
    # hubo caída del primario (para la nota "respondiendo con … (respaldo)").
    resultado["modelo_efectivo"] = efectivo
    resultado["failover"] = hubo
    return resultado


async def _con_tools_en(
    model: str,
    messages: list[dict],
    tools: list[dict],
    *,
    temperature: float,
    tool_choice: Any,
) -> dict[str, Any]:
    """Un intento contra UN modelo concreto (rutea por proveedor)."""
    if _es_anthropic(model):
        return await _anthropic_con_tools(
            messages, tools, model=model, temperature=temperature, tool_choice=tool_choice
        )
    return await _openai_con_tools(
        messages, tools, model=model, temperature=temperature, tool_choice=tool_choice
    )


async def _json_en(model: str, messages: list[dict], *, temperature: float) -> str:
    """Un intento de JSON contra UN modelo (rutea por proveedor)."""
    if _es_anthropic(model):
        return await _anthropic_json(messages, model=model, temperature=temperature)
    return await _openai_json(messages, model=model, temperature=temperature)


async def _chat_json(
    messages: list[dict], *, model: str | None, temperature: float
) -> str:
    """Pide al modelo del chat una respuesta JSON y devuelve el string
    crudo. OpenAI usa su modo JSON; Anthropic, prefill con `{`. Respeta el
    proveedor preferido y cae al otro ante error/crédito agotado."""
    model = _modelo_efectivo(model)
    texto, _, _ = await _con_failover(
        model, lambda m: _json_en(m, messages, temperature=temperature)
    )
    return texto


# ── Implementación OpenAI ───────────────────────────────────────────


async def _openai_texto(messages, *, model, temperature) -> str:
    client = _get_openai_client()
    resp = await _crear_openai(
        client, model=model, temperature=temperature,
        base_kwargs={"messages": _a_openai(messages)},
    )
    _registrar_chat_openai(resp.usage, model)
    return (resp.choices[0].message.content or "").strip()


async def _crear_openai(client, *, model, base_kwargs, temperature):
    """Llama a OpenAI agregando `temperature` solo si el modelo la soporta. Si
    pese a eso un modelo nuevo la rechaza con 400, reintenta UNA vez sin ella
    (red de seguridad: el 400 no debe llegar al usuario como error genérico)."""
    kwargs = dict(base_kwargs)
    if modelos_llm.soporta_temperature(model):
        kwargs["temperature"] = temperature
    try:
        return await client.chat.completions.create(model=model, **kwargs)
    except Exception as e:  # noqa: BLE001
        code = getattr(e, "status_code", None)
        msj = str(e).lower()
        if code == 400 and "temperature" in msj:
            logger.warning(
                "modelo «%s» no acepta temperature; reintento sin el parámetro",
                model,
            )
            kwargs.pop("temperature", None)
            return await client.chat.completions.create(model=model, **kwargs)
        raise


async def _openai_con_tools(messages, tools, *, model, temperature, tool_choice) -> dict:
    client = _get_openai_client()
    resp = await _crear_openai(
        client,
        model=model,
        temperature=temperature,
        base_kwargs={
            "messages": _a_openai(messages),
            "tools": tools,
            "tool_choice": tool_choice,
        },
    )
    _registrar_chat_openai(resp.usage, model)
    msg = resp.choices[0].message
    if msg.tool_calls:
        calls = []
        for tc in msg.tool_calls:
            try:
                args = json.loads(tc.function.arguments or "{}")
            except json.JSONDecodeError:
                args = {}
            calls.append({"id": tc.id, "nombre": tc.function.name, "args": args})
        return {
            "tipo": "tool_calls",
            "tool_calls": calls,
            "raw": _raw_neutral((msg.content or "").strip(), calls),
        }
    return {
        "tipo": "texto",
        "contenido": (msg.content or "").strip(),
        "raw": _raw_neutral((msg.content or "").strip(), []),
    }


async def _openai_json(messages, *, model, temperature) -> str:
    client = _get_openai_client()
    resp = await _crear_openai(
        client, model=model, temperature=temperature,
        base_kwargs={
            "messages": _a_openai(messages),
            "response_format": {"type": "json_object"},
        },
    )
    _registrar_chat_openai(resp.usage, model)
    return resp.choices[0].message.content or "{}"


# ── Implementación Anthropic (Claude) ───────────────────────────────


async def _anthropic_texto(messages, *, model, temperature) -> str:
    client = _get_anthropic_client()
    system, msgs = _a_anthropic(messages)
    kwargs: dict[str, Any] = {
        "model": model,
        "max_tokens": _MAX_TOKENS_ANTHROPIC,
        "temperature": temperature,
        "messages": msgs,
    }
    if system:
        kwargs["system"] = system
    resp = await client.messages.create(**kwargs)
    _registrar_uso_anthropic(resp.usage, model)
    return _texto_de_anthropic(resp.content).strip()


def _system_anthropic(system: str) -> Any:
    """System de Anthropic con CACHÉ de prompt: el bloque grande y fijo (reglas
    + documento maestro + capacidades) se marca `cache_control` para que Claude
    lo cachee entre turnos. Baja latencia y costo en el camino del modelo fuerte.
    """
    return [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}]


async def _anthropic_con_tools(messages, tools, *, model, temperature, tool_choice) -> dict:
    client = _get_anthropic_client()
    system, msgs = _a_anthropic(messages)
    kwargs: dict[str, Any] = {
        "model": model,
        "max_tokens": _MAX_TOKENS_ANTHROPIC,
        "messages": msgs,
        "tools": _tools_a_anthropic(tools),
        "tool_choice": _tool_choice_a_anthropic(tool_choice),
    }
    if modelos_llm.soporta_temperature(model):
        kwargs["temperature"] = temperature
    if system:
        kwargs["system"] = _system_anthropic(system)
    resp = await client.messages.create(**kwargs)
    _registrar_uso_anthropic(resp.usage, model)

    calls: list[dict] = []
    textos: list[str] = []
    for b in resp.content:
        bloque = b.model_dump() if hasattr(b, "model_dump") else dict(b)
        if bloque.get("type") == "tool_use":
            calls.append(
                {
                    "id": bloque.get("id"),
                    "nombre": bloque.get("name"),
                    "args": bloque.get("input") or {},
                }
            )
        elif bloque.get("type") == "text":
            textos.append(bloque.get("text", ""))

    texto = "".join(textos).strip()
    raw = _raw_neutral(texto, calls)
    if calls:
        return {"tipo": "tool_calls", "tool_calls": calls, "raw": raw}
    return {"tipo": "texto", "contenido": texto, "raw": raw}


async def _anthropic_json(messages, *, model, temperature) -> str:
    client = _get_anthropic_client()
    system, msgs = _a_anthropic(messages)
    # Prefill con `{` para forzar una respuesta JSON: Claude continúa el
    # objeto. El resultado completo es "{" + lo que devolvió.
    msgs = [*msgs, {"role": "assistant", "content": "{"}]
    kwargs: dict[str, Any] = {
        "model": model,
        "max_tokens": _MAX_TOKENS_ANTHROPIC,
        "temperature": temperature,
        "messages": msgs,
    }
    if system:
        kwargs["system"] = system
    resp = await client.messages.create(**kwargs)
    _registrar_uso_anthropic(resp.usage, model)
    return "{" + _texto_de_anthropic(resp.content)


async def extraer_tareas_json(
    texto: str,
    *,
    hoy: str,
    model: str | None = None,
) -> list[dict]:
    """Extrae tareas accionables de un texto libre y las devuelve
    estructuradas (Capa 7-B). El texto suele venir del OCR de una foto
    (una lista escrita a mano, una pizarra, un post-it) ya corregido
    por el usuario, así que puede traer ruido y errores.

    Usa el **modo JSON** de OpenAI (`response_format=json_object`):
    el modelo está obligado a responder un objeto JSON válido, así no
    tenemos que rascar texto libre buscando el bloque.

    Devuelve una lista de dicts `{"titulo": str, "vence_en": str|None}`
    donde `vence_en` es una fecha `YYYY-MM-DD` o `None`. Reglas que
    fija el prompt:

    - Solo acciones concretas que la persona debe HACER. Prosa,
      definiciones, apuntes de estudio o ruido → no son tareas.
    - Si el texto no tiene tareas claras, devuelve lista vacía. NO
      inventa tareas ni fechas.
    - Resuelve fechas relativas ("el viernes", "mañana", "en dos
      semanas") a una fecha real usando `hoy` como referencia. Si una
      tarea no menciona fecha, `vence_en` es `null`.

    `hoy` se pasa como `YYYY-MM-DD` en hora de Lima (lo calcula el
    router). Esto mantiene la función pura y testeable: misma entrada,
    misma salida, sin depender del reloj del proceso.
    """
    system = (
        "Eres un extractor de tareas. Recibes un texto libre que puede "
        "venir del escaneo (OCR) de una foto: una lista escrita a mano, "
        "una pizarra, notas sueltas. Puede traer errores de OCR.\n\n"
        f"Hoy es {hoy} (zona horaria de Lima, Perú).\n\n"
        "Tu trabajo: identificar las ACCIONES CONCRETAS que la persona "
        "debe hacer y devolverlas como JSON. Reglas estrictas:\n"
        "- Solo tareas accionables (algo que se hace y se completa). La "
        "prosa, las definiciones, los apuntes de estudio o el ruido NO "
        "son tareas.\n"
        "- Si el texto no contiene tareas claras, devuelve la lista "
        "vacía. NO inventes tareas.\n"
        "- Cada tarea: un título corto y claro en infinitivo o imperativo "
        "('Comprar pan', 'Entregar informe').\n"
        "- Si la tarea menciona una fecha (relativa o absoluta), "
        "resuélvela a una fecha real en formato YYYY-MM-DD usando la "
        "fecha de hoy como referencia. Si no menciona fecha, usa null. "
        "NO inventes fechas.\n\n"
        'Responde SOLO un objeto JSON con esta forma exacta:\n'
        '{"tareas": [{"titulo": "...", "vence_en": "YYYY-MM-DD" | null}]}'
    )
    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": texto},
        ],
        model=model,
        temperature=0.2,
    )
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return []

    crudas = datos.get("tareas") if isinstance(datos, dict) else None
    if not isinstance(crudas, list):
        return []

    tareas: list[dict] = []
    for item in crudas:
        if not isinstance(item, dict):
            continue
        titulo = item.get("titulo")
        if not isinstance(titulo, str) or not titulo.strip():
            continue
        vence = item.get("vence_en")
        if not isinstance(vence, str) or not vence.strip():
            vence = None
        tareas.append({"titulo": titulo.strip(), "vence_en": vence})
    return tareas


async def clasificar_captura_json(
    texto: str,
    *,
    model: str | None = None,
) -> str:
    """Clasifica el texto de una captura (OCR de una foto) en uno de los
    cuatro destinos de la cámara inteligente:

    - ``"tareas"``: una lista de pendientes / cosas por hacer.
    - ``"eventos"``: un horario, sílabo o calendario con clases, fechas
      o exámenes.
    - ``"recibo"``: una boleta, factura o ticket de compra (con monto a
      pagar, total, comercio) → se registra como gasto en Finanzas.
    - ``"apunte"``: una nota, idea, definición o cualquier otra cosa. Es
      el **catch-all**: ante la duda, todo cae aquí (siempre se puede
      guardar como apunte sin perder nada).

    SOLO viaja el texto: la imagen se quedó en el teléfono (OCR
    on-device). La app abre el flujo sugerido y el usuario puede
    corregir el tipo. Usa el **modo JSON** de OpenAI para forzar un
    objeto válido; cualquier respuesta inválida cae a ``"apunte"``.
    """
    system = (
        "Eres un clasificador de capturas. Recibes el texto que un OCR "
        "extrajo de una foto y decides a cuál de cuatro destinos "
        "pertenece. Puede traer errores de OCR.\n\n"
        "Destinos:\n"
        '- "tareas": una lista de cosas por hacer / pendientes '
        "(ej. 'comprar pan, llamar a Ana, entregar informe').\n"
        '- "eventos": un horario, sílabo o calendario con clases, fechas '
        "o exámenes (ej. 'Cálculo III lun y mié 10-12, parcial 15 "
        "abril').\n"
        '- "recibo": una boleta, factura o ticket de compra: tiene un '
        "total o monto a pagar, el nombre de un comercio, fecha de "
        "compra, items con precios (ej. 'SUPERMERCADO XYZ … TOTAL S/ "
        "45.90').\n"
        '- "apunte": una nota, idea, definición, resumen o cualquier '
        "texto que no sea claramente lo anterior. Es el destino por "
        "defecto cuando dudes.\n\n"
        "Elige UN solo destino, el más probable. Responde SOLO un objeto "
        'JSON con esta forma exacta:\n'
        '{"tipo": "tareas" | "eventos" | "recibo" | "apunte"}'
    )
    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": texto},
        ],
        model=model,
        temperature=0,
    )
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return "apunte"
    tipo = datos.get("tipo") if isinstance(datos, dict) else None
    if tipo in ("tareas", "eventos", "recibo", "apunte"):
        return tipo
    return "apunte"


async def extraer_recibo_json(
    texto: str,
    *,
    hoy: str,
    model: str | None = None,
) -> dict:
    """Extrae los datos de un recibo (OCR de una boleta/ticket, ya
    corregido) para proponer un GASTO en Finanzas (Finanzas-2).

    Devuelve un dict con:
    - ``monto``: el TOTAL pagado como número (float) o ``None`` si no hay
      un total claro. **No inventa cifras**: ante la duda, ``None`` y la
      app deja escribirlo a mano.
    - ``fecha``: la fecha de la compra en ``YYYY-MM-DD`` o ``None``.
    - ``comercio``: el nombre del comercio/tienda o ``None``.
    - ``categoria``: una categoría de gasto sugerida en español
      (Comida, Transporte, Hogar, Salud, Ocio, Estudios, Otros) o
      ``None``.

    `hoy` (``YYYY-MM-DD`, hora de Lima) se pasa como referencia para
    fechas relativas; la mayoría de recibos traen fecha absoluta.
    """
    system = (
        "Eres un extractor de recibos. Recibes el texto que un OCR sacó "
        "de la foto de una boleta, factura o ticket de compra. Puede "
        "traer errores de OCR.\n\n"
        f"Hoy es {hoy} (zona horaria de Lima, Perú).\n\n"
        "Extrae estos datos del recibo y devuélvelos como JSON:\n"
        "- monto: el TOTAL pagado, como número (sin símbolo de moneda, "
        "punto decimal). Si hay varias cifras, usa el TOTAL/IMPORTE a "
        "pagar, no un subtotal ni un item suelto. Si NO hay un total "
        "claro, usa null. NO inventes el monto.\n"
        "- fecha: la fecha de la compra en formato YYYY-MM-DD. Resuelve "
        "fechas relativas con la fecha de hoy. Si no hay fecha, null.\n"
        "- comercio: el nombre del comercio o tienda. Si no se ve, null.\n"
        "- categoria: UNA categoría de gasto en español, de esta lista: "
        "Comida, Transporte, Hogar, Salud, Ocio, Estudios, Otros. Elige "
        "la más probable según el comercio/los items. Si no puedes, "
        "null.\n\n"
        "Responde SOLO un objeto JSON con esta forma exacta:\n"
        '{"monto": number | null, "fecha": "YYYY-MM-DD" | null, '
        '"comercio": string | null, "categoria": string | null}'
    )
    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": texto},
        ],
        model=model,
        temperature=0,
    )
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return {"monto": None, "fecha": None, "comercio": None, "categoria": None}
    if not isinstance(datos, dict):
        return {"monto": None, "fecha": None, "comercio": None, "categoria": None}

    # monto: aceptar número o string numérico; nunca inventar.
    monto_crudo = datos.get("monto")
    monto: float | None = None
    if isinstance(monto_crudo, (int, float)):
        monto = float(monto_crudo)
    elif isinstance(monto_crudo, str):
        try:
            monto = float(monto_crudo.replace(",", "").strip())
        except ValueError:
            monto = None
    if monto is not None and monto <= 0:
        monto = None

    def _texto_o_none(v: object) -> str | None:
        return v.strip() if isinstance(v, str) and v.strip() else None

    return {
        "monto": monto,
        "fecha": _texto_o_none(datos.get("fecha")),
        "comercio": _texto_o_none(datos.get("comercio")),
        "categoria": _texto_o_none(datos.get("categoria")),
    }


async def estimar_duraciones_json(
    tareas: list[dict],
    *,
    model: str | None = None,
) -> dict[str, int]:
    """Estima cuántos minutos toma cada tarea, por su título (Urgencia-3).

    Se usa al planificar el día: el planificador necesita una duración
    por tarea para encajarla en los huecos reales. Si la app no la
    tiene, Matix la estima acá.

    `tareas` es una lista de dicts `{"id": str, "titulo": str}`. Devuelve
    un dict `{tarea_id: minutos}` con un entero de minutos por tarea
    (múltiplos de 15, entre 15 y 180). El que NO se pueda estimar se
    omite — el caller aplica un default razonable. Función pura respecto
    al reloj: misma entrada, misma salida (mockeable en tests).
    """
    items = [
        {"id": str(t["id"]), "titulo": str(t["titulo"]).strip()}
        for t in tareas
        if t.get("id") and str(t.get("titulo", "")).strip()
    ]
    if not items:
        return {}

    system = (
        "Eres un planificador. Recibes una lista de tareas (id + título) "
        "y estimas cuánto tiempo de trabajo enfocado toma cada una.\n\n"
        "Reglas:\n"
        "- Devuelve minutos como entero, múltiplo de 15, entre 15 y 180.\n"
        "- Sé realista: una tarea breve ('responder correo') ~15-30 min; "
        "una mediana ('redactar resumen') ~45-60; uno grande ('estudiar "
        "para el examen') ~90-120.\n"
        "- Estima por el título nomás; no inventes contexto.\n\n"
        'Responde SOLO un objeto JSON con esta forma exacta:\n'
        '{"duraciones": [{"tarea_id": "...", "minutos": 45}]}'
    )
    user = json.dumps({"tareas": items}, ensure_ascii=False)
    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        model=model,
        temperature=0.2,
    )
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return {}
    crudas = datos.get("duraciones") if isinstance(datos, dict) else None
    if not isinstance(crudas, list):
        return {}

    out: dict[str, int] = {}
    for item in crudas:
        if not isinstance(item, dict):
            continue
        tid = item.get("tarea_id")
        minutos = item.get("minutos")
        if not isinstance(tid, str) or not isinstance(minutos, int):
            continue
        # Acota al rango razonable y redondea a múltiplos de 15.
        m = max(15, min(180, minutos))
        m = round(m / 15) * 15
        out[tid] = m
    return out


_HORIZONTES = {"ahora", "pronto", "mas_adelante"}


async def desglosar_tarea_json(
    titulo: str,
    *,
    contexto: str | None = None,
    model: str | None = None,
) -> dict:
    """Parte una tarea en pasos accionables, en orden lógico, cada uno
    etiquetado por horizonte (Capa 7 · Desglose).

    Devuelve un dict:
        {"es_atomica": bool, "pasos": [{"titulo": str, "horizonte": str}]}

    `horizonte` es uno de `"ahora"`, `"pronto"`, `"mas_adelante"`.

    Honestidad: si la tarea YA es un paso concreto y atómico, el modelo
    devuelve `es_atomica=True` y `pasos=[]` — no infla pasos de relleno.
    """
    system = (
        "Eres un asistente que parte tareas en pasos accionables. "
        "Recibes el título de una tarea (y a veces una nota con "
        "contexto) y la desglosas en pasos CONCRETOS, en orden lógico.\n\n"
        "Reglas estrictas:\n"
        "- Cada paso es una acción concreta que se hace y se completa "
        "(empieza con un verbo). Nada de pasos vagos ni de relleno.\n"
        "- Si la tarea YA es atómica y accionable (no hay nada que "
        "desglosar), devuelve es_atomica=true y pasos=[]. NO inventes "
        "pasos para justificar el desglose.\n"
        "- Etiqueta cada paso por horizonte temporal: 'ahora' (lo "
        "primero, lo que se puede arrancar ya), 'pronto' (el siguiente "
        "tramo), 'mas_adelante' (lo que viene después). Ordena los pasos "
        "de 'ahora' a 'mas_adelante'.\n"
        "- Entre 2 y 8 pasos; títulos cortos.\n\n"
        "Responde SOLO un objeto JSON con esta forma exacta:\n"
        '{"es_atomica": false, "pasos": [{"titulo": "...", '
        '"horizonte": "ahora" | "pronto" | "mas_adelante"}]}'
    )
    user = titulo.strip()
    if contexto and contexto.strip():
        user += f"\n\nContexto: {contexto.strip()}"

    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        model=model,
        temperature=0.3,
    )
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return {"es_atomica": False, "pasos": []}
    if not isinstance(datos, dict):
        return {"es_atomica": False, "pasos": []}

    es_atomica = bool(datos.get("es_atomica", False))
    crudas = datos.get("pasos")
    pasos: list[dict] = []
    if isinstance(crudas, list):
        for item in crudas:
            if not isinstance(item, dict):
                continue
            t = item.get("titulo")
            if not isinstance(t, str) or not t.strip():
                continue
            h = item.get("horizonte")
            if h not in _HORIZONTES:
                h = "pronto"
            pasos.append({"titulo": t.strip(), "horizonte": h})

    # Si no hay pasos, lo tratamos como atómica (no hay nada que crear).
    if not pasos:
        es_atomica = True
    return {"es_atomica": es_atomica, "pasos": pasos}


_DIAS_VALIDOS = set(range(1, 8))


def _hhmm_valido(v: Any) -> str | None:
    """Devuelve 'HH:MM' si `v` parece una hora 24h válida, si no None."""
    if not isinstance(v, str):
        return None
    s = v.strip()
    parts = s.split(":")
    if len(parts) != 2:
        return None
    try:
        h, m = int(parts[0]), int(parts[1])
    except ValueError:
        return None
    if 0 <= h <= 23 and 0 <= m <= 59:
        return f"{h:02d}:{m:02d}"
    return None


async def extraer_eventos_json(
    texto: str,
    *,
    hoy: str,
    model: str | None = None,
) -> list[dict]:
    """Extrae eventos del texto de un SÍLABO u HORARIO (Cámara · sílabo).

    Distingue dos tipos:
    - `recurrente`: clases que se repiten cada semana → `dias_semana`
      (enteros ISO 1=lun…7=dom) + `hora_inicio`/`hora_fin` (HH:MM).
    - `unico`: una fecha puntual (parcial, entrega) → `fecha`
      (YYYY-MM-DD), `hora_inicio`/`hora_fin` opcionales.

    Solo devuelve lo DATABLE: un recurrente necesita días; un único
    necesita fecha. Si no hay nada datable, lista vacía — no inventa.
    `hoy` (YYYY-MM-DD, Lima) ancla las fechas relativas; lo pasa el
    router para que la función sea pura.
    """
    system = (
        "Eres un extractor de eventos académicos. Recibes el texto (a "
        "veces de un OCR) de un SÍLABO u HORARIO de curso, ya corregido "
        f"por el usuario. Hoy es {hoy} (zona horaria de Lima, Perú).\n\n"
        "Distingue DOS tipos de evento:\n"
        "- 'recurrente': clases o sesiones que se repiten cada semana "
        "(p.ej. 'lunes y miércoles 10:00–12:00'). Da `dias_semana` como "
        "lista de enteros ISO (1=lunes … 7=domingo) y `hora_inicio` en "
        "HH:MM (24h); `hora_fin` si aparece.\n"
        "- 'unico': una fecha puntual (un parcial, una entrega: 'parcial "
        "el 15 de abril'). Da `fecha` en YYYY-MM-DD resolviendo fechas "
        "relativas con la fecha de hoy; `hora_inicio`/`hora_fin` si "
        "aparecen.\n\n"
        "Reglas estrictas:\n"
        "- Solo lo DATABLE: un recurrente DEBE tener días; un único DEBE "
        "tener fecha. Si el texto no tiene nada datable, devuelve la "
        "lista vacía. NO inventes fechas, horas ni eventos.\n"
        "- Título corto y claro (nombre del curso o de la evaluación).\n\n"
        "Responde SOLO un objeto JSON con esta forma exacta:\n"
        '{"eventos": [{"tipo": "recurrente", "titulo": "...", '
        '"dias_semana": [1, 3], "hora_inicio": "10:00", '
        '"hora_fin": "12:00"}, {"tipo": "unico", "titulo": "...", '
        '"fecha": "YYYY-MM-DD", "hora_inicio": null, "hora_fin": null}]}'
    )
    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": texto},
        ],
        model=model,
        temperature=0.2,
    )
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return []
    crudos = datos.get("eventos") if isinstance(datos, dict) else None
    if not isinstance(crudos, list):
        return []

    eventos: list[dict] = []
    for item in crudos:
        if not isinstance(item, dict):
            continue
        tipo = item.get("tipo")
        titulo = item.get("titulo")
        if tipo not in ("recurrente", "unico"):
            continue
        if not isinstance(titulo, str) or not titulo.strip():
            continue
        hora_inicio = _hhmm_valido(item.get("hora_inicio"))
        hora_fin = _hhmm_valido(item.get("hora_fin"))
        if tipo == "recurrente":
            dias = item.get("dias_semana")
            if not isinstance(dias, list):
                continue
            dias = sorted(
                {d for d in dias if isinstance(d, int) and d in _DIAS_VALIDOS}
            )
            if not dias:
                continue  # recurrente sin días no es datable
            eventos.append(
                {
                    "tipo": "recurrente",
                    "titulo": titulo.strip(),
                    "dias_semana": dias,
                    "hora_inicio": hora_inicio,
                    "hora_fin": hora_fin,
                    "fecha": None,
                }
            )
        else:
            fecha = item.get("fecha")
            if not isinstance(fecha, str) or len(fecha.strip()) < 10:
                continue
            try:
                date.fromisoformat(fecha.strip()[:10])
            except ValueError:
                continue
            eventos.append(
                {
                    "tipo": "unico",
                    "titulo": titulo.strip(),
                    "dias_semana": [],
                    "hora_inicio": hora_inicio,
                    "hora_fin": hora_fin,
                    "fecha": fecha.strip()[:10],
                }
            )
    return eventos


async def repaso_semanal_json(
    datos: dict,
    *,
    model: str | None = None,
) -> dict:
    """Sintetiza el repaso semanal a partir de un resumen de la semana
    (Capa 8 · Repaso). Tono: balance honesto y cercano, SIN reproche
    (como el cierre del día). Reconoce lo hecho, nombra lo que quedó sin
    drama, y sugiere 1–3 focos para la próxima semana.

    Recibe `datos` (dict ya agregado por el cerebro: cuántas completó,
    qué quedó, eventos, proyectos, apuntes) y devuelve
    `{"resumen": str, "focos": [str]}`. El encaje/lectura del hub lo
    hace el cerebro; esto solo redacta. Lanza RuntimeError si falta la
    API key (el caller cae a un resumen determinístico)."""
    system = (
        "Eres Matix haciendo el repaso semanal con el usuario. Tono: "
        "balance honesto y cercano, SIN reproche (como un cierre de "
        "semana amable). Reconoce lo que SÍ se hizo, nombra lo que quedó "
        "sin drama (no es culpa, es información) y sugiere de 1 a 3 focos "
        "concretos para la próxima semana. Hablas en tú (nunca voseo).\n\n"
        "Recibes un resumen en JSON de la semana. SINTETIZA en prosa "
        "breve (2 a 4 frases); NO listes los datos crudos ni inventes "
        "nada que no esté en los datos.\n\n"
        "Responde SOLO un objeto JSON con esta forma exacta:\n"
        '{"resumen": "...", "focos": ["...", "..."]}'
    )
    user = json.dumps(datos, ensure_ascii=False)
    contenido = await _chat_json(
        [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        model=model,
        temperature=0.4,
    )
    try:
        out = json.loads(contenido)
    except json.JSONDecodeError as e:
        raise RuntimeError("El modelo no devolvió un JSON válido.") from e
    if not isinstance(out, dict):
        raise RuntimeError("El modelo no devolvió el objeto esperado.")

    resumen = out.get("resumen")
    if not isinstance(resumen, str) or not resumen.strip():
        raise RuntimeError("El modelo no devolvió un resumen.")
    crudos = out.get("focos")
    focos: list[str] = []
    if isinstance(crudos, list):
        for f in crudos:
            if isinstance(f, str) and f.strip():
                focos.append(f.strip())
    return {"resumen": resumen.strip(), "focos": focos[:3]}


async def transcribir(
    audio_bytes: bytes,
    *,
    nombre_archivo: str = "audio.m4a",
    mime: str = "audio/mp4",
    idioma: str = "es",
    model: str = "whisper-1",
) -> str:
    """Transcribe audio a texto vía Whisper.

    La app NUNCA habla con OpenAI directo — solo el cerebro. La app
    sube los bytes a `POST /api/v1/matix/transcribir` y el router
    llama a esta función.

    - `audio_bytes` debe ser un formato soportado por Whisper
      (m4a, mp3, wav, webm, ogg, flac…). En Android usamos m4a/AAC
      por defecto: compacto y nativo.
    - `idioma` ayuda a Whisper a no confundir el acento — fijamos
      `"es"` siempre (Gian Piero habla en español, y Whisper puede
      llegar a transcribir a inglés si el audio es corto).
    - Devuelve el texto crudo, sin recortar. Si el usuario habló
      poco y Whisper devuelve vacío, devolvemos string vacío y el
      caller decide qué hacer.
    """
    client = _get_openai_client()
    # OpenAI SDK acepta `file=(filename, bytes, content_type)`.
    resp = await client.audio.transcriptions.create(
        model=model,
        file=(nombre_archivo, audio_bytes, mime),
        language=idioma,
    )
    # Whisper cobra por minuto de audio. Estimamos la duración usando
    # un ratio conservador: AAC mono 16 kHz ≈ 32 kbps = 4 KB/s.
    estimacion_seg = max(0.0, len(audio_bytes) / 4096.0)
    medidor.registrar_whisper(estimacion_seg)

    texto = (resp.text or "").strip()
    # Filtro de alucinaciones conocidas — Whisper tiende a inventar
    # estas frases cuando el audio es silencio o ruido sin habla.
    # Cuando vienen sueltas (sin más contenido), las descartamos.
    if _es_alucinacion_de_whisper(texto):
        return ""
    return texto


# Frases que Whisper inventa cuando el audio no tiene voz real.
# Vienen del corpus con el que se entrenó (subtítulos de YouTube,
# créditos de videos, etc.). Si la transcripción ES exactamente o
# CONTIENE solo una de estas (con poco más), la descartamos.
_ALUCINACIONES_WHISPER = (
    "subtítulos realizados por la comunidad de amara.org",
    "subtítulos por la comunidad de amara.org",
    "subtitulado por la comunidad de amara.org",
    "subtítulos por amara.org",
    "subtitles by the amara.org community",
    "subtítulos en español",
    "¡suscríbete!",
    "suscríbete al canal",
    "gracias por ver",
    "gracias por ver el video",
    "thanks for watching",
    "thank you for watching",
    "music",
    "[música]",
    "♪",
    "(música)",
    "transcrito por:",
)


async def embebir(
    textos: list[str],
    *,
    model: str = "text-embedding-3-small",
) -> list[list[float]]:
    """Convierte una lista de textos en vectores (1536 dims con
    `text-embedding-3-small`). Sigue siendo el único punto del
    cerebro que importa `openai` — esto es Capa 3 Paso 1 RAG.

    Hace una sola llamada para toda la lista (batching), que es
    mucho más barato que una llamada por texto. Registra el uso
    sumando todos los tokens del batch.

    No deduplica ni cachea: el caller decide qué textos pasar.
    Para apuntes, el caller embebe título+contenido juntos.
    """
    if not textos:
        return []
    client = _get_openai_client()
    resp = await client.embeddings.create(model=model, input=textos)
    medidor.registrar_embedding(resp.usage.total_tokens)
    # OpenAI devuelve los embeddings en el mismo orden del input.
    return [item.embedding for item in resp.data]


async def embebir_seguro(textos: list[str]) -> list[list[float]] | None:
    """Como `embebir` pero NUNCA tumba al caller: ante error de proveedor o
    crédito agotado devuelve None. Para BÚSQUEDA (degrada a sin-RAG) e INDEXADO
    best-effort (se salta el índice). La INGESTA usa `embebir` directo para poder
    mostrar el mensaje honesto «ingesta en pausa: sin crédito de embeddings»."""
    try:
        return await embebir(textos)
    except Exception as e:  # noqa: BLE001
        logger.warning("embeddings no disponibles (%s); degrado sin RAG", type(e).__name__)
        return None


async def _openai_tts(texto: str, voz: str, model: str, formato: str) -> bytes:
    client = _get_openai_client()
    resp = await client.audio.speech.create(
        model=model, voice=voz, input=texto, response_format=formato
    )
    return await resp.aread()


async def _eleven_tts(texto: str, formato: str) -> bytes:
    """TTS de ElevenLabs (solo si hay key). Devuelve bytes mp3."""
    import httpx

    voice_id = settings.elevenlabs_voice_id or "EXAVITQu4vr4xnSDxMaL"  # "Sarah" (default)
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    headers = {"xi-api-key": settings.elevenlabs_api_key, "accept": "audio/mpeg"}
    payload = {"text": texto, "model_id": "eleven_multilingual_v2"}
    async with httpx.AsyncClient(timeout=30) as cli:
        r = await cli.post(url, headers=headers, json=payload)
        r.raise_for_status()
        return r.content


async def hablar(
    texto: str,
    *,
    voz: str = "onyx",
    model: str = "tts-1",
    formato: str = "mp3",
) -> tuple[bytes, str]:
    """Convierte `texto` a audio. Cadena de respaldo CLOUD:
    ElevenLabs (si hay key) → OpenAI tts-1. Devuelve `(audio_bytes, proveedor)`.

    Si TODO el cloud falla, relanza `RuntimeError`: el caller (la app) cae a la
    voz NATIVA del dispositivo (flutter_tts). `voz` aplica a OpenAI; ElevenLabs
    usa el voice_id de config.
    """
    errores: list[str] = []

    if settings.elevenlabs_api_key:
        try:
            audio = await _con_reintentos(
                lambda: _eleven_tts(texto, formato), etiqueta="tts-eleven"
            )
            medidor.registrar_tts(len(texto))
            return audio, "elevenlabs"
        except Exception as e:  # noqa: BLE001
            errores.append(f"elevenlabs:{type(e).__name__}")
            logger.warning("TTS ElevenLabs falló (%s); caigo a OpenAI", type(e).__name__)

    try:
        audio = await _con_reintentos(
            lambda: _openai_tts(texto, voz, model, formato), etiqueta="tts-openai"
        )
        medidor.registrar_tts(len(texto))
        return audio, "openai"
    except Exception as e:  # noqa: BLE001
        errores.append(f"openai:{type(e).__name__}")
        raise RuntimeError(
            f"TTS en la nube no disponible ({', '.join(errores)}); usa la voz del dispositivo."
        ) from e


# ── Cámara en vivo: narración corta de un frame (visión, gpt-4o-mini) ─────────

_NARRACION_SYSTEM = (
    "Eres los OJOS de Matix en una sesión de cámara EN VIVO. En UNA sola frase "
    "corta (máximo ~14 palabras), natural y en español peruano, di lo más "
    "relevante que se ve AHORA. No saludes, no uses asteriscos, no inventes lo "
    "que no aparece, no describas la calidad de la imagen. Si la escena es "
    "esencialmente la MISMA que la narración previa, responde EXACTAMENTE: SIN CAMBIOS."
)


async def _openai_vision(
    model: str, system: str, pedido: str, imagen_data_url: str, *, max_tokens: int
) -> str:
    client = _get_openai_client()

    async def _pedir():
        return await client.chat.completions.create(
            model=model,
            max_tokens=max_tokens,
            messages=[
                {"role": "system", "content": system},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": pedido},
                        {"type": "image_url",
                         "image_url": {"url": imagen_data_url, "detail": "low"}},
                    ],
                },
            ],
        )

    resp = await _con_reintentos(_pedir, etiqueta="vision")
    _registrar_chat_openai(resp.usage, model)
    return (resp.choices[0].message.content or "").strip()


async def _anthropic_vision(
    model: str, system: str, pedido: str, imagen_data_url: str, *, max_tokens: int
) -> str:
    client = _get_anthropic_client()

    async def _pedir():
        return await client.messages.create(
            model=model,
            max_tokens=max_tokens,
            system=system,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": pedido},
                        _imagen_a_anthropic(imagen_data_url),
                    ],
                }
            ],
        )

    resp = await _con_reintentos(_pedir, etiqueta="vision")
    _registrar_uso_anthropic(resp.usage, model)
    textos = [
        (b.text if hasattr(b, "text") else "")
        for b in resp.content
        if getattr(b, "type", None) == "text"
    ]
    return "".join(textos).strip()


async def _vision_en(
    model: str, system: str, pedido: str, imagen_data_url: str, *, max_tokens: int
) -> str:
    """Un intento de visión contra UN modelo (rutea por proveedor). Tanto
    gpt-4o-mini como Claude Haiku soportan imágenes."""
    if _es_anthropic(model):
        return await _anthropic_vision(model, system, pedido, imagen_data_url, max_tokens=max_tokens)
    return await _openai_vision(model, system, pedido, imagen_data_url, max_tokens=max_tokens)


async def narrar_frame(
    imagen_data_url: str, *, narracion_previa: str | None = None
) -> str:
    """Narra en una frase corta lo que se ve en un frame de la cámara en vivo.

    Visión por la MISMA abstracción de proveedor que el chat: respeta el
    proveedor preferido y, si el primario cae (incl. crédito agotado), hace
    failover a Claude (también ve imágenes). Así la cámara revive aunque OpenAI
    no esté. Devuelve '' si no hay nada nuevo (el caller no narra)."""
    previa = (narracion_previa or "").strip()
    pedido = (
        "¿Qué ves ahora?"
        if not previa
        else f"Narración previa: «{previa}». Di qué cambió o qué ves ahora."
    )
    # Modelo de visión barato del proveedor preferido; failover al otro.
    model = _modelo_efectivo("gpt-4o-mini")
    try:
        out, _efectivo, _hubo = await _con_failover(
            model,
            lambda m: _vision_en(m, _NARRACION_SYSTEM, pedido, imagen_data_url, max_tokens=60),
        )
    except Exception:  # noqa: BLE001 — la cámara sigue; este frame queda sin frase
        logger.warning("narrar_frame: visión no disponible en ningún proveedor")
        return ""
    out = out.strip()
    if out.upper().strip(" .!¡¿?\"'") == "SIN CAMBIOS":
        return ""
    return out


def _es_alucinacion_de_whisper(texto: str) -> bool:
    """True si `texto` es una alucinación conocida de Whisper sobre
    silencio/ruido. Comparación case-insensitive y robusta a signos
    de puntuación al borde."""
    if not texto:
        return False
    normalizado = texto.lower().strip(" .!?¡¿\"'·-—\n\t")
    if not normalizado:
        return True  # solo signos/espacios
    if normalizado in _ALUCINACIONES_WHISPER:
        return True
    # Caso "Subtítulos … Amara.org. Subtítulos … Amara.org." (Whisper
    # repite la misma frase varias veces). Si todo el texto es una
    # repetición de una alucinación, también la descartamos.
    for hal in _ALUCINACIONES_WHISPER:
        if hal and hal in normalizado:
            sin_hal = normalizado.replace(hal, "").strip(" .,;:·-")
            if not sin_hal:
                return True
    return False
