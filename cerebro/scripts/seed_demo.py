"""Pre-poblar Matix con los datos reales del Documento Maestro.

Carga, en orden:
- 7 cursos universitarios.
- Horario semanal exacto de clases (13 sesiones).
- 3 proyectos activos (Matix, OnExotic, Shadows Games) +
  3 aparcados (Peyo, Idiomas, Automatizaciones).
- 3 categorías generales (Personal, Trabajo, Ideas).

Idempotente por nombre: si ya existe una fila con ese nombre, no se
duplica. Pensado para correrse en una BD nueva o casi nueva. Si hay
proyectos activos pre-existentes y se alcanza el tope de 3, los
nuevos se crean como aparcados y se avisa.

Uso:
    cd cerebro
    uv run python -m scripts.seed_demo

Necesita el cerebro arrancado en `http://127.0.0.1:8000` y la
`MATIX_API_KEY` en `cerebro/.env`.
"""
from __future__ import annotations

import asyncio
import os

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

BASE = "http://127.0.0.1:8000/api/v1"
KEY = os.environ.get("MATIX_API_KEY", "")
if not KEY:
    raise SystemExit("Falta MATIX_API_KEY en cerebro/.env")

HEADERS = {"X-Matix-Key": KEY, "Content-Type": "application/json"}


CURSOS = [
    ("Inteligencia de Negocios", "#2D7FF9", "—"),
    ("Calidad de Software", "#21D07A", "—"),
    ("Gestión de la Continuidad del Negocio", "#FF4D5E", "—"),
    ("Diseño e Implementación de Arquitectura Empresarial", "#E0A33A", "—"),
    ("Gobierno de TIC", "#9B7BFF", "—"),
    ("Herramientas para la Comunicación Efectiva", "#F06EA9", "—"),
    ("Taller de Investigación", "#3CCFCF", "Zoom"),
]

# (dia 0=L..6=D, curso, hora_inicio, hora_fin, ubicacion)
HORARIO = [
    (0, "Inteligencia de Negocios", "18:30:00", "20:00:00", None),
    (0, "Diseño e Implementación de Arquitectura Empresarial",
     "20:15:00", "21:45:00", None),
    (1, "Gobierno de TIC", "08:30:00", "10:00:00", None),
    (1, "Gestión de la Continuidad del Negocio",
     "18:30:00", "20:00:00", None),
    (2, "Inteligencia de Negocios", "18:30:00", "20:00:00", None),
    (2, "Diseño e Implementación de Arquitectura Empresarial",
     "20:15:00", "21:45:00", None),
    (3, "Gobierno de TIC", "08:30:00", "10:00:00", None),
    (3, "Gestión de la Continuidad del Negocio",
     "18:30:00", "20:00:00", None),
    (3, "Herramientas para la Comunicación Efectiva",
     "20:15:00", "22:30:00", None),
    (4, "Calidad de Software", "18:30:00", "20:00:00", None),
    (5, "Calidad de Software", "18:30:00", "20:00:00", None),
    (5, "Taller de Investigación", "21:00:00", "22:30:00", "Zoom"),
    (6, "Taller de Investigación", "13:15:00", "14:45:00", "Zoom"),
]

PROYECTOS = [
    {
        "nombre": "Matix",
        "estado": "activo",
        "prioridad": 1,
        "linea_meta": "Cerrar la Capa 1: armazón del hub funcionando y "
                      "probado (6 secciones, CRUD manual, notificaciones).",
        "descripcion": "La app que sostiene todo lo demás. Cerebro "
                       "externo + centro de mando de la vida.",
        "color": "#2D7FF9",
    },
    {
        "nombre": "OnExotic",
        "estado": "activo",
        "prioridad": 2,
        "linea_meta": "Canal de venta online publicado y las primeras 5 "
                      "ventas reales cerradas.",
        "descripcion": "Mi marca de ropa.",
        "color": "#9B7BFF",
    },
    {
        "nombre": "Shadows Games",
        "estado": "activo",
        "prioridad": 3,
        "linea_meta": "Terminar y publicar el juego de la próxima jam "
                      "(por confirmar con Leo).",
        "descripcion": "Negocio de videojuegos con Leo. Game jams.",
        "color": "#21D07A",
    },
    {
        "nombre": "Peyo (personaje virtual)",
        "estado": "aparcado",
        "descripcion": "Personaje virtual de contenido. En pausa "
                       "consciente, esperando su turno.",
        "color": "#F06EA9",
    },
    {
        "nombre": "Inglés / Portugués",
        "estado": "aparcado",
        "descripcion": "Aparcado hasta cerrar Matix. Elegir idioma al "
                       "reactivar.",
        "color": "#3CCFCF",
    },
    {
        "nombre": "Startup de automatizaciones",
        "estado": "aparcado",
        "descripcion": "Aparcado. Explorar tras cerrar OnExotic.",
        "color": "#E0A33A",
    },
]

CATEGORIAS = [
    ("Personal", "#9B7BFF"),
    ("Trabajo", "#2D7FF9"),
    ("Ideas", "#21D07A"),
]


async def main() -> None:
    async with httpx.AsyncClient(
        base_url=BASE, headers=HEADERS, timeout=30
    ) as c:
        # ─── Cursos ───────────────────────────────────────────────
        print("\n▸ Cursos")
        cursos_existentes = (await c.get("/cursos")).json()
        nombres_existentes = {x["nombre"]: x["id"] for x in cursos_existentes}
        cursos_map: dict[str, str] = {}
        for nombre, color, profesor in CURSOS:
            if nombre in nombres_existentes:
                cursos_map[nombre] = nombres_existentes[nombre]
                print(f"  ↻ {nombre}")
                continue
            body = {"nombre": nombre, "color": color}
            if profesor and profesor != "—":
                body["profesor"] = profesor
            r = await c.post("/cursos", json=body)
            r.raise_for_status()
            cursos_map[nombre] = r.json()["id"]
            print(f"  + {nombre}")

        # ─── Sesiones de clase ────────────────────────────────────
        print("\n▸ Horario semanal")
        ses_existentes = (await c.get("/sesiones-clase")).json()
        clave = lambda s: (s["curso_id"], s["dia_semana"], s["hora_inicio"])
        ya = {clave(s) for s in ses_existentes}
        for dia, curso, hi, hf, ubi in HORARIO:
            cid = cursos_map[curso]
            k = (cid, dia, hi)
            if k in ya:
                continue
            body = {
                "curso_id": cid,
                "dia_semana": dia,
                "hora_inicio": hi,
                "hora_fin": hf,
            }
            if ubi:
                body["ubicacion"] = ubi
            r = await c.post("/sesiones-clase", json=body)
            r.raise_for_status()
            print(
                f"  + {'LMXJVSD'[dia]} {hi[:5]}–{hf[:5]}  {curso}"
            )

        # ─── Categorías ───────────────────────────────────────────
        print("\n▸ Categorías")
        cats_existentes = (await c.get("/categorias")).json()
        nombres_cats = {x["nombre"] for x in cats_existentes}
        for nombre, color in CATEGORIAS:
            if nombre in nombres_cats:
                print(f"  ↻ {nombre}")
                continue
            r = await c.post(
                "/categorias", json={"nombre": nombre, "color": color}
            )
            r.raise_for_status()
            print(f"  + {nombre}")

        # ─── Proyectos ────────────────────────────────────────────
        print("\n▸ Proyectos")
        proy_existentes = (await c.get("/proyectos")).json()
        nombres_proy = {x["nombre"] for x in proy_existentes}
        for p in PROYECTOS:
            if p["nombre"] in nombres_proy:
                print(f"  ↻ {p['nombre']}  ({p['estado']})")
                continue
            r = await c.post("/proyectos", json=p)
            if r.status_code == 409:
                print(
                    f"  ! {p['nombre']}: tope de 3 activos alcanzado. "
                    "Lo creo como aparcado."
                )
                fallback = {**p, "estado": "aparcado"}
                fallback.pop("prioridad", None)
                r = await c.post("/proyectos", json=fallback)
            r.raise_for_status()
            print(f"  + {p['nombre']}  ({p['estado']})")

        print("\n✓ Seed completo.")


if __name__ == "__main__":
    asyncio.run(main())
