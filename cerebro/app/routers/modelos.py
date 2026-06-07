"""Selector del modelo del LLM de chat.

- `GET /modelos` — catálogo curado (los modelos principales de OpenAI y
  Anthropic) + cuál está seleccionado (un id o `"auto"`) + el par
  barato/fuerte del modo Automático.
- `POST /modelos/seleccionar` — fija el modelo o el modo `"auto"`
  (se guarda en `config_matix.modelo_chat`).
- `POST /modelos/par` — cambia el par barato/fuerte del modo Automático.

El proveedor se infiere del id; `llm.py` rutea solo. En modo Automático, el
cerebro elige el modelo por mensaje con reglas (`enrutador.py`). Voz y RAG
siguen SIEMPRE en OpenAI, sea cual sea el modelo de chat.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..matix import modelos_llm
from ..schemas.modelos import (
    ModelosEstado,
    ParRequest,
    ProveedorRequest,
    SeleccionarModeloRequest,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/modelos",
    tags=["modelos"],
    dependencies=[Depends(require_api_key)],
)


async def _estado(db: Postgrest) -> dict:
    barato, fuerte = await modelos_llm.par_barato_fuerte(db)
    return {
        "modelos": modelos_llm.listar(),
        "seleccionado": await modelos_llm.seleccion_guardada(db),
        "par": {"barato": barato, "fuerte": fuerte},
        "proveedor_preferido": await modelos_llm.cargar_preferido(db),
    }


@router.get("", response_model=ModelosEstado)
async def estado(db: Postgrest = Depends(get_db)) -> dict:
    return await _estado(db)


@router.post("/seleccionar", response_model=ModelosEstado)
async def seleccionar(
    body: SeleccionarModeloRequest, db: Postgrest = Depends(get_db)
) -> dict:
    try:
        await modelos_llm.set_seleccion(db, body.modelo.strip())
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Selección desconocida: «{body.modelo}».",
        )
    return await _estado(db)


@router.post("/proveedor", response_model=ModelosEstado)
async def fijar_proveedor(
    body: ProveedorRequest, db: Postgrest = Depends(get_db)
) -> dict:
    """Fija el proveedor de IA preferido: openai | anthropic | auto."""
    try:
        await modelos_llm.set_proveedor_preferido(db, body.proveedor.strip())
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return await _estado(db)


@router.post("/par", response_model=ModelosEstado)
async def fijar_par(
    body: ParRequest, db: Postgrest = Depends(get_db)
) -> dict:
    try:
        await modelos_llm.set_par(
            db,
            barato=body.barato.strip() if body.barato else None,
            fuerte=body.fuerte.strip() if body.fuerte else None,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e),
        )
    return await _estado(db)
