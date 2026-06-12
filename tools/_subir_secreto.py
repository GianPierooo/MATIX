"""Sube un secreto/config a secretos_runtime SIN imprimir valores sensibles.
Uso: python tools/_subir_secreto.py CLAVE VALOR  (lee Supabase de cerebro/.env)"""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent


def _env(ruta: Path) -> dict[str, str]:
    d: dict[str, str] = {}
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if linea and not linea.startswith("#") and "=" in linea:
            k, _, v = linea.partition("=")
            d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def main() -> int:
    clave, valor = sys.argv[1], sys.argv[2]
    env = _env(RAIZ / "cerebro" / ".env")
    url, srk = env.get("SUPABASE_URL"), env.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not srk:
        print("FALTA SUPABASE_URL/SERVICE_ROLE_KEY en cerebro/.env")
        return 1
    req = urllib.request.Request(
        f"{url}/rest/v1/secretos_runtime",
        data=json.dumps({"clave": clave, "valor": valor}).encode(),
        method="POST",
        headers={
            "apikey": srk,
            "Authorization": f"Bearer {srk}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
    )
    with urllib.request.urlopen(req) as resp:
        print(f"OK {clave} -> secretos_runtime (HTTP {resp.status})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
