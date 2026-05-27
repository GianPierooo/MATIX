"""Seed v2 — datos vivos para llenar los vacíos visuales.

Asume que `seed_demo.py` ya corrió (cursos, sesiones, proyectos,
categorías). Añade:

- Tareas reales asociadas a cada proyecto activo + personales.
- Acción siguiente fijada en cada proyecto activo.
- Evaluaciones próximas (los exámenes mencionados en el Documento
  Maestro: miércoles y jueves).
- Apuntes asociados a proyectos.
- Un cierre del día previo (ayer) para que el histórico aparezca.

Idempotente por título / nombre / fecha — no duplica si ya existe.

Uso:
    cd cerebro
    $env:PYTHONIOENCODING="utf-8"
    uv run python scripts/seed_demo_v2.py
"""
from __future__ import annotations

import asyncio
import os
from datetime import date, datetime, timedelta, timezone

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

BASE = "http://127.0.0.1:8000/api/v1"
KEY = os.environ.get("MATIX_API_KEY", "")
if not KEY:
    raise SystemExit("Falta MATIX_API_KEY en cerebro/.env")
HEADERS = {"X-Matix-Key": KEY, "Content-Type": "application/json"}


def hoy_a_las(h: int, m: int = 0) -> str:
    ahora = datetime.now(timezone.utc).astimezone()
    fecha = ahora.replace(hour=h, minute=m, second=0, microsecond=0)
    return fecha.astimezone(timezone.utc).isoformat()


def en_dias(d: int, h: int = 23, m: int = 59) -> str:
    ahora = datetime.now(timezone.utc).astimezone()
    fecha = (ahora + timedelta(days=d)).replace(
        hour=h, minute=m, second=0, microsecond=0
    )
    return fecha.astimezone(timezone.utc).isoformat()


# ---------------------------------------------------------------------------


async def main() -> None:
    async with httpx.AsyncClient(
        base_url=BASE, headers=HEADERS, timeout=30
    ) as c:
        # ─── Mapas necesarios ─────────────────────────────────────
        proys = (await c.get("/proyectos")).json()
        proy_por_nombre = {p["nombre"]: p for p in proys}
        cursos = (await c.get("/cursos")).json()
        curso_por_nombre = {c["nombre"]: c for c in cursos}
        cats = (await c.get("/categorias")).json()
        cat_por_nombre = {x["nombre"]: x for x in cats}

        if not proy_por_nombre.get("Matix"):
            print(
                "⚠ Ejecuta primero seed_demo.py — faltan proyectos base."
            )
            return

        # ─── Tareas ───────────────────────────────────────────────
        print("\n▸ Tareas")
        existentes = (await c.get("/tareas")).json()
        titulos = {t["titulo"] for t in existentes}

        tareas_a_crear = [
            # Matix #1
            {
                "titulo": "Cerrar Capa 1 con visto bueno visual",
                "proyecto": "Matix",
                "prioridad": "alta",
                "vence_en": hoy_a_las(23, 59),
                "nota": "Recorrer cada pantalla en el Huawei y confirmar "
                        "que todo carga sin errores.",
            },
            {
                "titulo": "Arrancar Capa 2 (chat con Claude API)",
                "proyecto": "Matix",
                "prioridad": "media",
                "vence_en": en_dias(3),
            },
            {
                "titulo": "Configurar batería Huawei para Matix",
                "proyecto": "Matix",
                "prioridad": "media",
                "vence_en": hoy_a_las(22, 0),
                "nota": "Ajustes → Apps → Matix → Batería → Apertura de "
                        "apps → Gestión manual → activar todo. Sin esto "
                        "EMUI mata los recordatorios.",
            },
            # OnExotic #2
            {
                "titulo": "Subir fotos del último drop a la tienda",
                "proyecto": "OnExotic",
                "prioridad": "alta",
                "vence_en": hoy_a_las(18, 30),
            },
            {
                "titulo": "Cerrar pasarela de pago",
                "proyecto": "OnExotic",
                "prioridad": "alta",
                "vence_en": en_dias(5),
            },
            {
                "titulo": "Diseñar piezas del siguiente drop",
                "proyecto": "OnExotic",
                "prioridad": "media",
                "vence_en": en_dias(7),
            },
            # Shadows Games #3
            {
                "titulo": "Cerrar alcance del juego de la jam con Leo",
                "proyecto": "Shadows Games",
                "prioridad": "alta",
                "vence_en": en_dias(2, 20, 0),
            },
            {
                "titulo": "Definir el género del juego",
                "proyecto": "Shadows Games",
                "prioridad": "media",
            },
            # Personales
            {
                "titulo": "Calistenia matutina",
                "categoria": "Personal",
                "prioridad": "baja",
                "vence_en": hoy_a_las(7, 0),
                "repeticion": "diaria",
            },
            {
                "titulo": "Box en Vinces Fight",
                "categoria": "Personal",
                "prioridad": "baja",
                "vence_en": hoy_a_las(21, 0),
            },
        ]

        tareas_por_titulo: dict[str, dict] = {
            t["titulo"]: t for t in existentes
        }

        for t in tareas_a_crear:
            if t["titulo"] in titulos:
                print(f"  ↻ {t['titulo']}")
                continue
            body: dict = {
                "titulo": t["titulo"],
                "prioridad": t["prioridad"],
            }
            if "nota" in t:
                body["nota"] = t["nota"]
            if "vence_en" in t:
                body["vence_en"] = t["vence_en"]
            if "repeticion" in t:
                body["repeticion"] = t["repeticion"]
            if "proyecto" in t:
                body["proyecto_id"] = proy_por_nombre[t["proyecto"]]["id"]
            if "categoria" in t:
                body["categoria_id"] = cat_por_nombre[t["categoria"]]["id"]
            r = await c.post("/tareas", json=body)
            r.raise_for_status()
            tareas_por_titulo[t["titulo"]] = r.json()
            print(f"  + {t['titulo']}")

        # ─── Acción siguiente de cada proyecto activo ─────────────
        print("\n▸ Acción siguiente por proyecto")
        siguiente = {
            "Matix": "Cerrar Capa 1 con visto bueno visual",
            "OnExotic": "Subir fotos del último drop a la tienda",
            "Shadows Games":
                "Cerrar alcance del juego de la jam con Leo",
        }
        for proy_nombre, tarea_titulo in siguiente.items():
            proy = proy_por_nombre[proy_nombre]
            tar = tareas_por_titulo.get(tarea_titulo)
            if not tar:
                print(f"  ⚠ no encontré la tarea para {proy_nombre}")
                continue
            if proy.get("tarea_siguiente_id") == tar["id"]:
                print(f"  ↻ {proy_nombre} ya apunta a esa acción")
                continue
            r = await c.patch(
                f"/proyectos/{proy['id']}",
                json={"tarea_siguiente_id": tar["id"]},
            )
            r.raise_for_status()
            print(f"  + {proy_nombre} → «{tarea_titulo}»")

        # ─── Evaluaciones próximas ────────────────────────────────
        print("\n▸ Evaluaciones próximas")
        evs_existentes = (await c.get("/evaluaciones")).json()
        ev_titulos = {e["titulo"] for e in evs_existentes}
        evaluaciones = [
            {
                "curso": "Calidad de Software",
                "titulo": "Examen parcial",
                "tipo": "examen",
                "fecha": en_dias(1, 18, 30),  # miércoles 18:30 si hoy es martes
                "peso": 30,
            },
            {
                "curso": "Gobierno de TIC",
                "titulo": "Ensayo entrega 2",
                "tipo": "entrega",
                "fecha": en_dias(2, 23, 59),
                "peso": 20,
            },
            {
                "curso": "Gestión de la Continuidad del Negocio",
                "titulo": "Laboratorio 3",
                "tipo": "entrega",
                "fecha": en_dias(6, 23, 59),
                "peso": 15,
            },
        ]
        for ev in evaluaciones:
            if ev["titulo"] in ev_titulos:
                print(f"  ↻ {ev['titulo']}")
                continue
            body = {
                "curso_id": curso_por_nombre[ev["curso"]]["id"],
                "titulo": ev["titulo"],
                "tipo": ev["tipo"],
                "fecha": ev["fecha"],
                "peso": ev["peso"],
            }
            r = await c.post("/evaluaciones", json=body)
            r.raise_for_status()
            print(f"  + {ev['titulo']}  ({ev['curso']})")

        # ─── Bloque protegido del proyecto Matix ─────────────────
        print("\n▸ Bloque protegido")
        matix = proy_por_nombre["Matix"]
        if matix.get("bloque_protegido") is None:
            r = await c.patch(
                f"/proyectos/{matix['id']}",
                json={
                    "bloque_protegido": {
                        "dias_semana": [0, 2, 4],  # L, Mi, V
                        "hora_inicio": "06:00",
                        "hora_fin": "09:00",
                    },
                },
            )
            r.raise_for_status()
            print("  + Matix → L/Mi/V 06:00–09:00")
        else:
            print("  ↻ Matix ya tiene bloque protegido")

        # ─── Apuntes ──────────────────────────────────────────────
        print("\n▸ Apuntes")
        ap_existentes = (await c.get("/apuntes")).json()
        ap_titulos = {a["titulo"] for a in ap_existentes}
        apuntes = [
            {
                "titulo": "Plan de Capa 2 — chat con Claude",
                "contenido": "Endpoint /matix/chat con prompt caching del "
                             "Documento Maestro. Tools: crear_tarea, "
                             "completar_tarea, marcar_acc_siguiente_hecha, "
                             "registrar_cierre. STT con Whisper, TTS con "
                             "flutter_tts del sistema.",
                "proyecto": "Matix",
                "etiquetas": ["capa2", "ia"],
            },
            {
                "titulo": "Ideas para el drop de verano",
                "contenido": "Paleta neutra + amarillo fluo en un solo "
                             "drop limitado. Probar serigrafía vs DTF.",
                "proyecto": "OnExotic",
                "etiquetas": ["drop", "ideas"],
            },
            {
                "titulo": "Sketch del game loop",
                "contenido": "Personaje colecciona fragmentos en una "
                             "pantalla 2D con niebla de guerra. Loop: "
                             "explorar → conseguir 3 fragmentos → "
                             "desbloquear siguiente nivel.",
                "proyecto": "Shadows Games",
                "etiquetas": ["jam", "diseño"],
            },
            {
                "titulo": "Resumen del día martes",
                "contenido": "Empecé fuerte: cerré la Capa 1. Tarde "
                             "irregular. Pendiente: no postergar la "
                             "calistenia mañana.",
                "etiquetas": ["personal"],
            },
        ]
        for a in apuntes:
            if a["titulo"] in ap_titulos:
                print(f"  ↻ {a['titulo']}")
                continue
            body = {
                "titulo": a["titulo"],
                "contenido": a["contenido"],
                "etiquetas": a["etiquetas"],
            }
            if "proyecto" in a:
                body["proyecto_id"] = proy_por_nombre[a["proyecto"]]["id"]
            r = await c.post("/apuntes", json=body)
            r.raise_for_status()
            print(f"  + {a['titulo']}")

        # ─── Cierre del día de ayer ───────────────────────────────
        print("\n▸ Cierre del día (ayer)")
        ayer = (date.today() - timedelta(days=1)).isoformat()
        r = await c.post(
            "/cierres_dia",
            json={
                "fecha": ayer,
                "items": [
                    "Cerré la Capa 1 en código",
                    "Limpié dos bugs serios (INTERNET + cleartext)",
                    "Sembré los datos reales del Documento Maestro",
                ],
                "nota_extra": "Día denso pero satisfactorio. Mañana "
                              "valido visual y arranco Capa 2.",
            },
        )
        r.raise_for_status()
        print(f"  + Cierre de {ayer}")

        # ─── Un evento personal hoy ──────────────────────────────
        print("\n▸ Evento personal de hoy")
        evs_pers = (await c.get("/eventos")).json()
        titulos_evs = {e["titulo"] for e in evs_pers}
        evento_box = "Box · Vinces Fight SMP"
        if evento_box in titulos_evs:
            print(f"  ↻ {evento_box}")
        else:
            r = await c.post(
                "/eventos",
                json={
                    "titulo": evento_box,
                    "inicia_en": hoy_a_las(21, 0),
                    "termina_en": hoy_a_las(22, 0),
                    "ubicacion": "Av. Perú 3630, SMP",
                },
            )
            r.raise_for_status()
            print(f"  + {evento_box}")

        print("\n✓ Seed v2 completo.")


if __name__ == "__main__":
    asyncio.run(main())
