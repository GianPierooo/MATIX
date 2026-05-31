"""Selector del modelo del LLM de chat.

- `GET /modelos` — catálogo curado (los modelos principales de OpenAI y
  Anthropic) + cuál está seleccionado.
- `POST /modelos/seleccionar` — fija el modelo (se guarda en
  `config_matix.modelo_chat`).

El proveedor se infiere del id; `llm.py` rutea solo. Voz y RAG siguen
SIEMPRE en OpenAI, sea cual sea el modelo de chat.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..matix import modelos_llm
from ..schemas.modelos import ModelosEstado, SeleccionarModeloRequest
from ..security import require_api_key

router = APIRouter(
    prefix="/modelos",
    tags=["modelos"],
    dependencies=[Depends(require_api_key)],
)


@router.get("", response_model=ModelosEstado)
async def estado(db: Postgrest = Depends(get_db)) -> dict:
    return {
        "modelos": modelos_llm.listar(),
        "seleccionado": await modelos_llm.modelo_seleccionado(db),
    }


@router.post("/seleccionar", response_model=ModelosEstado)
async def seleccionar(
    body: SeleccionarModeloRequest, db: Postgrest = Depends(get_db)
) -> dict:
    try:
        await modelos_llm.set_modelo(db, body.modelo.strip())
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Modelo desconocido: «{body.modelo}».",
        )
    return {
        "modelos": modelos_llm.listar(),
        "seleccionado": await modelos_llm.modelo_seleccionado(db),
    }
