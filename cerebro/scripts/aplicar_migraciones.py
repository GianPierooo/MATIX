"""Aplica TODAS las migraciones SQL en orden vía la Management API de
Supabase, contra el proyecto que apunten las variables de entorno.

Uso típico — preparar el proyecto Supabase de TEST (Capa 7-B, Paso de
aislamiento de tests). Con `cerebro/.env.test` ya lleno:

    cd cerebro
    uv run --env-file .env.test python scripts/aplicar_migraciones.py

(También sirve para un proyecto nuevo de dev/prod: cambia `--env-file`.)

Lee `SUPABASE_PROJECT_REF` y `SUPABASE_ACCESS_TOKEN` del entorno y
recorre `supabase/migrations/*.sql` en orden alfabético (0001, 0002…),
aplicando cada uno. Para en el primer fallo e imprime el error.

Es seguro reaplicar sobre un proyecto recién creado. NO está pensado
para correr dos veces sobre el mismo proyecto: muchas migraciones no
son idempotentes (CREATE TABLE sin IF NOT EXISTS, etc.).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import httpx

_RAIZ = Path(__file__).resolve().parent.parent.parent
_MIGRACIONES = _RAIZ / "supabase" / "migrations"


def main() -> int:
    ref = os.environ.get("SUPABASE_PROJECT_REF")
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not ref or not token:
        print(
            "  [x] Faltan SUPABASE_PROJECT_REF / SUPABASE_ACCESS_TOKEN en el\n"
            "      entorno. Corre con: uv run --env-file .env.test python\n"
            "      scripts/aplicar_migraciones.py",
            file=sys.stderr,
        )
        return 2

    archivos = sorted(_MIGRACIONES.glob("*.sql"))
    if not archivos:
        print(f"  [x] No hay migraciones en {_MIGRACIONES}", file=sys.stderr)
        return 2

    url = f"https://api.supabase.com/v1/projects/{ref}/database/query"
    print(f"Aplicando {len(archivos)} migraciones al proyecto {ref}…\n")
    for sql_file in archivos:
        sql = sql_file.read_text(encoding="utf-8")
        r = httpx.post(
            url,
            headers={"Authorization": f"Bearer {token}"},
            json={"query": sql},
            timeout=60.0,
        )
        ok = r.status_code in (200, 201)
        print(f"  {'OK ' if ok else 'ERR'}  {sql_file.name}  ({r.status_code})")
        if not ok:
            print(f"\n  Detuve en {sql_file.name}:\n{r.text[:600]}", file=sys.stderr)
            return 1

    print("\nListo. El proyecto de test tiene el esquema completo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
