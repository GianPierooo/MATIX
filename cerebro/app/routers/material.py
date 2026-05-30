"""Router de la biblioteca de material de aprendizaje (Fase 1).

`POST /material/ingestar` sube el material de un documento (troceado) a
la biblioteca, etiquetado por skill+bloque, reemplazando lo previo de ese
par (idempotente). Es lo que usa `scripts/ingestar_documentos.py`.

La búsqueda del material NO es un endpoint REST: la hace Matix con la
tool `buscar_material` (ver tools.py), igual que `buscar_apuntes`.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..matix.biblioteca import ingestar_material
from ..schemas.material import IngestarMaterialRequest, IngestarMaterialResponse
from ..security import require_api_key

router = APIRouter(
    prefix="/material",
    tags=["material"],
    dependencies=[Depends(require_api_key)],
)


@router.post("/ingestar", response_model=IngestarMaterialResponse)
async def ingestar(
    body: IngestarMaterialRequest, db: Postgrest = Depends(get_db)
) -> dict:
    try:
        resultado = await ingestar_material(
            db,
            skill=body.skill,
            bloque=body.bloque,
            fuente=body.fuente,
            piezas=body.piezas,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)
        ) from e
    except RuntimeError as e:
        # OPENAI_API_KEY ausente, o el modelo de embeddings no respondió.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error ingestando material: {e}",
        ) from e
    return {
        "skill": body.skill.strip(),
        "bloque": body.bloque.strip(),
        **resultado,
    }
