"""Modos de Matix: bundles que ajustan tono + conocimiento + prioridades.

Un modo es un archivo `.md` en `app/matix/modos/`. La lista es
*file-driven*: agregar un `.md` = agregar un modo (sin tocar código). Cada
`.md` arranca con `# Etiqueta` y una línea `> descripción`, seguido de las
secciones (Tono, Conocimiento, Prioridades/comportamiento).

Este módulo:
- carga el contenido y la metadata de los `.md` (puro, sin BD),
- lee/escribe el modo ACTIVO en `config_matix` (singleton).

El modo activo entra al prompt como contenido `system` ADICIONAL, encima
del prompt base; las reglas base e identidad de Matix mandan siempre (ver
`envoltura_modo`).
"""
from __future__ import annotations

from pathlib import Path

from ..db import Postgrest

_DIR = Path(__file__).parent / "modos"


def _ruta(nombre: str) -> Path:
    # `Path(nombre).name` evita traversal (../, rutas absolutas).
    return _DIR / f"{Path(nombre).name}.md"


def existe_modo(nombre: str | None) -> bool:
    return bool(nombre) and _ruta(nombre).is_file()


def cargar_modo(nombre: str) -> str | None:
    """Contenido `.md` del modo, o `None` si no existe."""
    p = _ruta(nombre)
    return p.read_text(encoding="utf-8") if p.is_file() else None


def _meta_de_texto(nombre: str, texto: str) -> dict[str, str]:
    etiqueta: str | None = None
    descripcion: str | None = None
    for linea in texto.splitlines():
        s = linea.strip()
        if etiqueta is None and s.startswith("# "):
            etiqueta = s[2:].strip()
        elif descripcion is None and s.startswith("> "):
            descripcion = s[2:].strip()
    return {
        "nombre": nombre,
        "etiqueta": etiqueta or nombre.capitalize(),
        "descripcion": descripcion or "",
    }


def listar_modos() -> list[dict[str, str]]:
    """Modos disponibles (alfabético) con etiqueta + descripción del `.md`."""
    out: list[dict[str, str]] = []
    if not _DIR.is_dir():
        return out
    for p in sorted(_DIR.glob("*.md")):
        out.append(_meta_de_texto(p.stem, p.read_text(encoding="utf-8")))
    return out


def meta_modo(nombre: str) -> dict[str, str] | None:
    texto = cargar_modo(nombre)
    return _meta_de_texto(nombre, texto) if texto is not None else None


def envoltura_modo(nombre: str, contenido: str) -> str:
    """Envuelve el `.md` con el encuadre: el modo AJUSTA dentro de las
    reglas base, nunca las reemplaza."""
    etiqueta = (meta_modo(nombre) or {}).get("etiqueta", nombre)
    return (
        f"MODO ACTIVO: {etiqueta}.\n"
        "Ajusta tu tono, tu conocimiento y tus prioridades según lo de "
        "abajo. PERO tus reglas base y tu identidad de Matix mandan SIEMPRE: "
        "el modo afina dentro de eso, nunca lo reemplaza ni lo contradice. Si "
        "algo del modo choca con una regla base (seguridad, confirmaciones, no "
        "inventar datos), gana la regla base.\n\n"
        f"{contenido}"
    )


# ── Modo activo (persistido en config_matix, singleton) ─────────────


async def _fila(db: Postgrest) -> dict | None:
    filas = await db.list("config_matix", limit=1)
    return filas[0] if filas else None


async def modo_activo(db: Postgrest) -> str | None:
    """El modo activo, o `None` (normal). Si el modo guardado ya no existe
    como `.md` (se quitó del repo), devuelve `None`: degradación limpia."""
    fila = await _fila(db)
    if not fila:
        return None
    nombre = fila.get("modo_activo")
    return nombre if existe_modo(nombre) else None


async def set_modo_activo(db: Postgrest, nombre: str | None) -> None:
    """Fija (o limpia, con `None`) el modo activo en `config_matix`."""
    fila = await _fila(db)
    if fila is None:
        await db.insert("config_matix", {"modo_activo": nombre})
    else:
        await db.update("config_matix", fila["id"], {"modo_activo": nombre})
