"""Tests del bloque inyectado de memoria personal.

`bloque_memoria` es la pieza clave (lo que Matix ve en cada turno). Lo
probamos con un fake de `db.list` — sin BD ni embeddings. El RAG y el
CRUD reales van por el dispatcher de tools / a mano contra prod.
"""
from __future__ import annotations

from typing import Any

from app.matix import memoria


class _FakeDB:
    """Stub mínimo: `list` devuelve filas predefinidas."""

    def __init__(self, filas: list[dict[str, Any]]):
        self._filas = filas
        self.ultimo_raw_filters: dict | None = None

    async def list(self, table: str, **kwargs: Any) -> list[dict[str, Any]]:
        self.ultimo_raw_filters = kwargs.get("raw_filters")
        return self._filas


async def test_bloque_agrupa_por_categoria() -> None:
    db = _FakeDB(
        [
            {"contenido": "Mi meta del semestre es aprobar Cálculo III",
             "categoria": "metas"},
            {"contenido": "Tengo un perro llamado Toby", "categoria": "personas"},
            {"contenido": "Estudio mejor de noche", "categoria": "preferencias"},
            {"contenido": "Un hecho sin categoría", "categoria": None},
        ]
    )
    bloque = await memoria.bloque_memoria(db)
    assert "LO QUE SÉ DE TI" in bloque
    assert "metas:" in bloque
    assert "Mi meta del semestre es aprobar Cálculo III" in bloque
    # categoría None cae en "general".
    assert "general:" in bloque
    # Solo pide los esenciales.
    assert db.ultimo_raw_filters == {"esencial": "is.true"}


async def test_bloque_vacio_cuando_no_hay_memoria() -> None:
    assert await memoria.bloque_memoria(_FakeDB([])) == ""


async def test_bloque_ignora_contenido_vacio() -> None:
    db = _FakeDB([{"contenido": "   ", "categoria": "metas"}])
    # Si el único hecho está vacío, no hay bloque que inyectar.
    assert await memoria.bloque_memoria(db) == ""
