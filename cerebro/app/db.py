"""Cliente PostgREST para Supabase.

La Capa 1 no usa `supabase-py` porque arrastra dependencias nativas
(pyiceberg) que requieren MSVC en Windows. Hablamos directo con
PostgREST vía httpx usando el `service_role` key — mismo resultado
para CRUD de tablas, menos superficie.
"""
from __future__ import annotations

from typing import Any

import httpx

from .config import settings


def _headers() -> dict[str, str]:
    key = settings.supabase_service_role_key
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


class Postgrest:
    """Wrapper mínimo sobre el endpoint `/rest/v1` de Supabase.

    El `httpx.AsyncClient` se crea lazy en el primer uso (no en
    `__init__`) para evitar atarlo a un event loop equivocado — en
    Windows + pytest-asyncio cada test recibe un loop nuevo, y un
    cliente creado fuera lanza `Event loop is closed` al limpiar.
    """

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None

    @property
    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=f"{settings.supabase_url}/rest/v1",
                headers=_headers(),
                timeout=20.0,
            )
        return self._client

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def list(
        self,
        table: str,
        *,
        order: str | None = None,
        limit: int | None = None,
        filters: dict[str, str] | None = None,
        raw_filters: dict[str, str] | None = None,
        select: str | None = None,
    ) -> list[dict[str, Any]]:
        """Lista filas. `filters` se traduce a `col=eq.valor` en query
        params (igualdad estricta), para no obligar al caller a conocer
        la sintaxis de PostgREST.

        `raw_filters` permite operadores que no son `eq`: el valor se
        usa tal cual, e.g. `{"eliminado_en": "is.null"}` o
        `{"vence_en": "lt.2026-01-01"}`. Útil para la papelera
        (borrado suave) donde necesitamos `is.null` / `not.is.null`.

        `select` acota las columnas (e.g. `"id,contenido"`), útil para no
        traer columnas pesadas como un `embedding`. Default: todas (`*`).
        """
        params: dict[str, str] = {"select": select or "*"}
        if order:
            params["order"] = order
        if limit is not None:
            params["limit"] = str(limit)
        if filters:
            for col, val in filters.items():
                params[col] = f"eq.{val}"
        if raw_filters:
            for col, val in raw_filters.items():
                params[col] = val
        r = await self._http.get(f"/{table}", params=params)
        r.raise_for_status()
        return r.json()

    async def get(self, table: str, row_id: str) -> dict[str, Any] | None:
        r = await self._http.get(
            f"/{table}",
            params={"id": f"eq.{row_id}", "select": "*", "limit": "1"},
        )
        r.raise_for_status()
        data = r.json()
        return data[0] if data else None

    async def insert(self, table: str, payload: dict[str, Any]) -> dict[str, Any]:
        r = await self._http.post(
            f"/{table}",
            json=payload,
            headers={"Prefer": "return=representation"},
        )
        r.raise_for_status()
        return r.json()[0]

    async def update(
        self, table: str, row_id: str, payload: dict[str, Any]
    ) -> dict[str, Any] | None:
        if not payload:
            return await self.get(table, row_id)
        r = await self._http.patch(
            f"/{table}",
            params={"id": f"eq.{row_id}"},
            json=payload,
            headers={"Prefer": "return=representation"},
        )
        r.raise_for_status()
        data = r.json()
        return data[0] if data else None

    async def delete(self, table: str, row_id: str) -> bool:
        r = await self._http.delete(
            f"/{table}",
            params={"id": f"eq.{row_id}"},
            headers={"Prefer": "return=representation"},
        )
        r.raise_for_status()
        return bool(r.json())

    async def delete_where(
        self, table: str, *, filters: dict[str, str]
    ) -> int:
        """Borra todas las filas que matcheen `filters` (igualdad).
        Devuelve cuántas borró. Lo usa el indexador para purgar los
        chunks viejos de un apunte antes de insertar los nuevos."""
        params = {col: f"eq.{val}" for col, val in filters.items()}
        r = await self._http.delete(
            f"/{table}",
            params=params,
            headers={"Prefer": "return=representation"},
        )
        r.raise_for_status()
        return len(r.json())

    async def upsert(
        self, table: str, payload: dict[str, Any], *, on_conflict: str
    ) -> dict[str, Any]:
        """Inserta o reemplaza por la columna de conflicto (`on_conflict`).
        Reemplaza la fila completa con `payload` — el caller calcula los valores
        nuevos (p.ej. acumular el gasto del día) y pasa la fila final."""
        r = await self._http.post(
            f"/{table}",
            params={"on_conflict": on_conflict},
            json=payload,
            headers={"Prefer": "resolution=merge-duplicates,return=representation"},
        )
        r.raise_for_status()
        data = r.json()
        return data[0] if data else payload

    async def rpc(
        self, function: str, payload: dict[str, Any] | None = None
    ) -> Any:
        """Llama a una función SQL expuesta vía PostgREST (`/rpc/<name>`).
        Útil para queries que no se pueden expresar con select+filters
        — p.ej. la búsqueda por similitud vectorial."""
        r = await self._http.post(f"/rpc/{function}", json=payload or {})
        r.raise_for_status()
        return r.json()


db = Postgrest()


def get_db() -> Postgrest:
    return db
