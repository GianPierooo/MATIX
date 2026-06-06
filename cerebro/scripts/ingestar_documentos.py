"""Ingesta documentos de una carpeta a la BIBLIOTECA de material de
aprendizaje de Matix (Fase 1).

OJO: el material NO va a los apuntes (tu inbox de ideas). Va a un store
SEPARADO (`material_chunks`), etiquetado por:

  - skill  = la CARPETA   (ej. 'calistenia')  → un track.
  - bloque = cada ARCHIVO (ej. 'bloque_3')    → una etapa del track.

Así Matix puede traer "el bloque 3 de calistenia" sin mezclarlo con la
búsqueda de apuntes. El cerebro trocea/embebe y guarda; el documento
original se queda en tu PC (solo viaja el texto).

Idempotente por skill+bloque: re-ingestar el mismo archivo REEMPLAZA su
material (no duplica).

────────────────────────────────────────────────────────────────────
USO
────────────────────────────────────────────────────────────────────

1) Instala las librerías para leer PDF y DOCX (los .txt/.md no necesitan
   nada extra):

       pip install pypdf python-docx

2) Dale la URL del cerebro y tu API key (variables de entorno o flags):

       # Windows (PowerShell)
       $env:MATIX_API_URL = "https://tu-cerebro.up.railway.app"
       $env:MATIX_API_KEY = "tu-token-secreto"
       python scripts/ingestar_documentos.py "C:/ruta/a/calistenia"

       # …o por argumento, sin tocar el entorno:
       python scripts/ingestar_documentos.py "C:/ruta/a/calistenia" \
         --api-url "https://tu-cerebro.up.railway.app" \
         --api-key "tu-token-secreto"

   El skill por defecto es el nombre de la carpeta ('calistenia').
   Cámbialo con --skill. El bloque sale del nombre de cada archivo
   (ej. "Bloque 3.pdf" → 'bloque_3').

Opciones:
   --dry-run         No sube nada; solo muestra qué haría (para probar).
   --skill TEXTO     Skill/track (default: nombre de la carpeta).
   --max-chars N     Corta archivos largos en piezas de ~N caracteres
                     (default 18000) para que TODO quede indexado.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path

EXTENSIONES = {".txt", ".md", ".pdf", ".docx"}


def slug_bloque(texto: str) -> str:
    """Normaliza el nombre de un archivo a un tag de bloque estable:
    sin acentos, minúsculas, separadores → '_'. Ej: 'Bloque 3' →
    'bloque_3', 'Día 1.pdf' (stem 'Día 1') → 'dia_1'."""
    t = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    t = re.sub(r"[^a-z0-9]+", "_", t.strip().lower()).strip("_")
    return t or "sin_nombre"


# ─── Extracción de texto por formato ──────────────────────────────────
def _texto_de_txt(ruta: Path) -> str:
    return ruta.read_text(encoding="utf-8", errors="ignore")


def _texto_de_pdf(ruta: Path) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as e:  # noqa: BLE001
        raise RuntimeError(
            "Falta 'pypdf' para leer PDFs. Instálalo con: pip install pypdf"
        ) from e
    lector = PdfReader(str(ruta))
    return "\n\n".join((p.extract_text() or "") for p in lector.pages)


def _texto_de_docx(ruta: Path) -> str:
    try:
        import docx  # python-docx
    except ImportError as e:  # noqa: BLE001
        raise RuntimeError(
            "Falta 'python-docx' para leer .docx. Instálalo con: "
            "pip install python-docx"
        ) from e
    doc = docx.Document(str(ruta))
    return "\n".join(p.text for p in doc.paragraphs)


def extraer_texto(ruta: Path) -> str:
    ext = ruta.suffix.lower()
    if ext in (".txt", ".md"):
        return _texto_de_txt(ruta)
    if ext == ".pdf":
        return _texto_de_pdf(ruta)
    if ext == ".docx":
        return _texto_de_docx(ruta)
    return ""


# ─── Troceo de documentos largos ──────────────────────────────────────
def trocear(texto: str, max_chars: int) -> list[str]:
    """Parte `texto` en piezas de hasta `max_chars`, cortando en un salto
    de línea cercano al límite. Un documento corto devuelve una pieza."""
    texto = texto.strip()
    if len(texto) <= max_chars:
        return [texto] if texto else []
    piezas: list[str] = []
    inicio = 0
    while inicio < len(texto):
        fin = min(inicio + max_chars, len(texto))
        if fin < len(texto):
            corte = texto.rfind("\n", inicio, fin)
            if corte > inicio + max_chars // 2:
                fin = corte
        pieza = texto[inicio:fin].strip()
        if pieza:
            piezas.append(pieza)
        inicio = fin
    return piezas


# ─── Cliente del cerebro (stdlib, sin dependencias) ───────────────────
def ingestar_bloque(
    *,
    api_url: str,
    api_key: str,
    skill: str,
    bloque: str,
    fuente: str,
    piezas: list[str],
) -> dict:
    cuerpo = {"skill": skill, "bloque": bloque, "fuente": fuente, "piezas": piezas}
    req = urllib.request.Request(
        api_url.rstrip("/") + "/api/v1/material/ingestar",
        data=json.dumps(cuerpo).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", "X-Matix-Key": api_key},
    )
    # La embebida de varias piezas puede tardar; damos margen.
    with urllib.request.urlopen(req, timeout=120) as resp:
        if resp.status not in (200, 201):
            raise RuntimeError(f"HTTP {resp.status}")
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ingesta documentos de una carpeta a la biblioteca de "
        "material de Matix (un skill = la carpeta; un bloque = cada archivo).",
    )
    parser.add_argument("carpeta", help="Carpeta del skill (ej. .../calistenia).")
    parser.add_argument("--skill", help="Skill/track (default: nombre de la carpeta).")
    # Override del slug de bloque cuando solo se procesa UN archivo. Útil cuando
    # el filename trae sufijos ("bloque_4_placeholder.md") pero queremos taggear
    # con un slug limpio ("bloque_4"). Solo aplica si la carpeta tiene 1 archivo
    # ingestable; con varios, los slugs siguen viniendo del filename de cada uno.
    parser.add_argument("--bloque", help="Override del slug del bloque (solo "
                        "con carpeta de 1 archivo).")
    parser.add_argument("--api-url", default=os.environ.get("MATIX_API_URL"))
    parser.add_argument("--api-key", default=os.environ.get("MATIX_API_KEY"))
    parser.add_argument("--max-chars", type=int, default=18000)
    parser.add_argument(
        "--dry-run", action="store_true", help="No sube nada; solo muestra."
    )
    args = parser.parse_args()

    # Consolas de Windows suelen ser cp1252 y revientan con caracteres
    # fuera de ese set. Forzamos UTF-8 (con reemplazo) para no crashear
    # imprimiendo nombres de archivo con tildes u otros símbolos.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    carpeta = Path(args.carpeta).expanduser()
    if not carpeta.is_dir():
        print(f"  [x] No existe la carpeta: {carpeta}", file=sys.stderr)
        return 2

    if not args.dry_run and (not args.api_url or not args.api_key):
        print(
            "  [x] Falta la URL del cerebro o la API key.\n"
            "      Define MATIX_API_URL y MATIX_API_KEY (o pasa --api-url\n"
            "      y --api-key). Usa --dry-run para probar sin ellas.",
            file=sys.stderr,
        )
        return 2

    skill = slug_bloque(args.skill or carpeta.name)
    archivos = sorted(
        p for p in carpeta.rglob("*")
        if p.is_file() and p.suffix.lower() in EXTENSIONES
    )
    if not archivos:
        print(f"No hay documentos {sorted(EXTENSIONES)} en {carpeta}.")
        return 0

    print(
        f"Carpeta: {carpeta}\nSkill: {skill}\n"
        f"Archivos (bloques): {len(archivos)}"
        + ("  (DRY-RUN: no se sube nada)" if args.dry_run else "")
        + "\n"
    )

    # Si se pasó `--bloque` y hay UN solo archivo, lo usamos como override del
    # slug. Con varios archivos lo ignoramos (sería ambiguo) y avisamos.
    bloque_override: str | None = None
    if args.bloque:
        if len(archivos) == 1:
            bloque_override = slug_bloque(args.bloque)
        else:
            print(
                "  [!] --bloque ignorado: la carpeta tiene varios archivos; "
                "cada uno mantiene su slug por nombre.\n",
                file=sys.stderr,
            )

    ok = fallidos = vacios = piezas_total = 0
    for i, ruta in enumerate(archivos, start=1):
        bloque = bloque_override or slug_bloque(ruta.stem)
        print(f"  [{i}/{len(archivos)}] {ruta.name} -> bloque '{bloque}'", end=" ", flush=True)
        try:
            texto = extraer_texto(ruta).strip()
        except RuntimeError as e:
            print(f"FALLÓ ({e})")
            fallidos += 1
            continue
        if not texto:
            print("- vacío, lo salto")
            vacios += 1
            continue

        piezas = trocear(texto, args.max_chars)
        if args.dry_run:
            print(f"ok ({len(piezas)} pieza(s))")
            piezas_total += len(piezas)
            ok += 1
            continue
        try:
            res = ingestar_bloque(
                api_url=args.api_url,
                api_key=args.api_key,
                skill=skill,
                bloque=bloque,
                fuente=ruta.name,
                piezas=piezas,
            )
            extra = (
                f", reemplazó {res['reemplazados']}" if res.get("reemplazados") else ""
            )
            print(f"ok ({res.get('creados', len(piezas))} pieza(s){extra})")
            piezas_total += res.get("creados", len(piezas))
            ok += 1
        except (urllib.error.URLError, RuntimeError, ValueError) as e:
            print(f"FALLÓ ({e})")
            fallidos += 1

    print(
        f"\nListo. Bloques ok: {ok} · piezas: {piezas_total} · "
        f"vacíos: {vacios} · fallidos: {fallidos}"
    )
    if not args.dry_run and ok:
        print(
            "El material quedó en la biblioteca (store aparte de tus "
            "apuntes). Matix ya puede traerlo por skill/bloque."
        )
    return 1 if fallidos else 0


if __name__ == "__main__":
    raise SystemExit(main())
