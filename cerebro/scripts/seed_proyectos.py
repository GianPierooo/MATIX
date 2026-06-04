"""Carga de proyectos desde planes ya parseados, por el pipeline REAL del
import del chat (importar_plan.aplicar_importacion) — misma creación que la app,
sin inserts a mano ni estructura distinta.

Uso:
    cd cerebro
    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
      python scripts/seed_proyectos.py <ruta_estructuras.json>

El archivo de estructuras es una lista de
`{"nombre": str, "estructura": {objetivo, tipo, parametros, fases:[...]}}` — el
MISMO shape que produce el modelo al parsear un plan en el chat. NO se versiona
(lleelo de un archivo local/gitignored): puede contener data personal.

Reglas (idénticas al import del chat):
- Si al plan le faltan parámetros REQUERIDOS, NO se inventa: se PAUSA ese plan y
  se reporta qué falta; los demás siguen.
- Etiquetado por horizonte + elaboración progresiva (fase actual fina, lejanas
  gruesas) los aplica plan_a_nodos.
- Idempotente: si ya existe un proyecto con ese nombre, se omite.
"""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db import Postgrest  # noqa: E402
from app.matix import avance, importar_plan  # noqa: E402


async def main(ruta: str) -> None:
    data = json.loads(Path(ruta).read_text(encoding="utf-8"))
    db = Postgrest()
    try:
        for item in data:
            nombre = item["nombre"]
            estructura = item["estructura"]
            existe = await db.list("proyectos", filters={"nombre": nombre}, limit=1)
            if existe:
                print(f"[omitido] «{nombre}» ya existe.")
                continue
            plan = importar_plan.normalizar_plan(estructura)
            gate = importar_plan.huecos_plan(plan)
            if importar_plan.decidir_importacion(gate) == "preguntar":
                print(f"[PAUSADO] «{nombre}»: faltan requeridos → {gate['faltan']}")
                continue
            res = await importar_plan.aplicar_importacion(
                db, plan=plan, nombre=nombre, proyecto=None
            )
            nodos = await db.list("arbol_nodos", filters={"proyecto_id": res["proyecto"]["id"]})
            pct = avance.porcentaje(nodos)
            raices = sum(1 for n in nodos if not n.get("parent_id"))
            print(
                f"[OK] «{nombre}»: estado={res['estado']}, fases={raices}, "
                f"nodos={res['nodos_creados']}, avance={pct}%"
            )
    finally:
        await db.aclose()


if __name__ == "__main__":
    ruta = sys.argv[1] if len(sys.argv) > 1 else "backups/planes_seed.json"
    asyncio.run(main(ruta))
