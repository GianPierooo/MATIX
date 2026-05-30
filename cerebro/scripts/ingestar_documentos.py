"""Ingesta documentos de una carpeta al RAG de Matix (Capa 3).

Lee los archivos de una carpeta (.txt, .md, .pdf, .docx), extrae el
texto y crea un APUNTE por documento llamando al cerebro
(`POST /api/v1/apuntes`). Crear el apunte dispara el indexador semántico
(embeddings con OpenAI → tabla `apunte_chunks`), así que tras correr esto
Matix ya puede buscar y citar el contenido por significado.

Reusa todo el pipeline que ya existe (apuntes + indexador del Paso 1 de
Capa 3); NO toca la base de datos directamente: solo habla con el cerebro
por su API, igual que la app. Por eso únicamente necesita la URL del
cerebro y la MATIX_API_KEY — ninguna credencial de Supabase.

La imagen/archivo original NO se sube: solo viaja el texto extraído.

────────────────────────────────────────────────────────────────────
USO
────────────────────────────────────────────────────────────────────

1) Instala las librerías para leer PDF y DOCX (los .txt/.md no necesitan
   nada extra):

       pip install pypdf python-docx

2) Dale la URL del cerebro y tu API key. Dos opciones:

   a) Variables de entorno (recomendado):

       # Windows (PowerShell)
       $env:MATIX_API_URL = "https://tu-cerebro.up.railway.app"
       $env:MATIX_API_KEY = "tu-token-secreto"
       python scripts/ingestar_documentos.py "C:/ruta/a/INGLES"

       # Linux / macOS
       export MATIX_API_URL="https://tu-cerebro.up.railway.app"
       export MATIX_API_KEY="tu-token-secreto"
       python scripts/ingestar_documentos.py ~/Documentos/INGLES

   b) Por argumento, sin tocar el entorno:

       python scripts/ingestar_documentos.py "C:/ruta/a/INGLES" \
         --api-url "https://tu-cerebro.up.railway.app" \
         --api-key "tu-token-secreto"

3) La etiqueta del apunte por defecto es el nombre de la carpeta
   (p.ej. "INGLES"), para que puedas filtrarlos después. Cámbiala con
   `--etiqueta`.

Opciones útiles:
   --dry-run         No crea nada; solo muestra qué haría (para probar).
   --etiqueta TXT    Etiqueta a poner en cada apunte (default: carpeta).
   --curso-id UUID   Asocia los apuntes a un curso existente.
   --proyecto-id U   Asocia los apuntes a un proyecto existente.
   --max-chars N     Corta documentos largos en apuntes de ~N caracteres
                     (default 18000) para que TODO quede indexado: el
                     indexador embebe ~1 chunk por apunte.

Es seguro re-correrlo, pero NO es idempotente: vuelve a crear los
apuntes. Si reingestas una carpeta, borra antes los apuntes viejos de esa
etiqueta desde la app (o no la reingestes).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

EXTENSIONES = {".txt", ".md", ".pdf", ".docx"}


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
    return "\n\n".join((pagina.extract_text() or "") for pagina in lector.pages)


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
    """Parte `texto` en piezas de hasta `max_chars`, cortando en un
    salto de línea cercano al límite para no romper a mitad de frase.
    Un documento corto devuelve una sola pieza."""
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
def crear_apunte(
    *,
    api_url: str,
    api_key: str,
    titulo: str,
    contenido: str,
    etiquetas: list[str],
    curso_id: str | None,
    proyecto_id: str | None,
) -> None:
    cuerpo: dict[str, object] = {
        "titulo": titulo,
        "contenido": contenido,
        "etiquetas": etiquetas,
    }
    if curso_id:
        cuerpo["curso_id"] = curso_id
    if proyecto_id:
        cuerpo["proyecto_id"] = proyecto_id

    datos = json.dumps(cuerpo).encode("utf-8")
    req = urllib.request.Request(
        api_url.rstrip("/") + "/api/v1/apuntes",
        data=datos,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Matix-Key": api_key,
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status not in (200, 201):
            raise RuntimeError(f"HTTP {resp.status}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ingesta documentos de una carpeta al RAG de Matix.",
    )
    parser.add_argument("carpeta", help="Carpeta con los documentos.")
    parser.add_argument("--etiqueta", help="Etiqueta (default: nombre de la carpeta).")
    parser.add_argument("--api-url", default=os.environ.get("MATIX_API_URL"))
    parser.add_argument("--api-key", default=os.environ.get("MATIX_API_KEY"))
    parser.add_argument("--curso-id", dest="curso_id")
    parser.add_argument("--proyecto-id", dest="proyecto_id")
    parser.add_argument("--max-chars", type=int, default=18000)
    parser.add_argument(
        "--dry-run", action="store_true", help="No crea nada; solo muestra."
    )
    args = parser.parse_args()

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

    etiqueta = args.etiqueta or carpeta.name
    archivos = sorted(
        p for p in carpeta.rglob("*")
        if p.is_file() and p.suffix.lower() in EXTENSIONES
    )
    if not archivos:
        print(f"No hay documentos {sorted(EXTENSIONES)} en {carpeta}.")
        return 0

    print(
        f"Carpeta: {carpeta}\nEtiqueta: {etiqueta}\n"
        f"Documentos encontrados: {len(archivos)}"
        + ("  (DRY-RUN: no se crea nada)" if args.dry_run else "")
        + "\n"
    )

    fallidos = vacios = apuntes = 0
    for i, ruta in enumerate(archivos, start=1):
        nombre = ruta.relative_to(carpeta)
        print(f"  [{i}/{len(archivos)}] {nombre}", end=" ", flush=True)
        try:
            texto = extraer_texto(ruta).strip()
        except RuntimeError as e:
            print(f"FALLÓ ({e})")
            fallidos += 1
            continue
        if not texto:
            print("— vacío, lo salto")
            vacios += 1
            continue

        piezas = trocear(texto, args.max_chars)
        base = ruta.stem
        for k, pieza in enumerate(piezas, start=1):
            titulo = base if len(piezas) == 1 else f"{base} (parte {k}/{len(piezas)})"
            if args.dry_run:
                apuntes += 1
                continue
            try:
                crear_apunte(
                    api_url=args.api_url,
                    api_key=args.api_key,
                    titulo=titulo,
                    contenido=pieza,
                    etiquetas=[etiqueta],
                    curso_id=args.curso_id,
                    proyecto_id=args.proyecto_id,
                )
                apuntes += 1
            except (urllib.error.URLError, RuntimeError) as e:
                print(f"FALLÓ al crear «{titulo}» ({e})")
                fallidos += 1
                break
        else:
            print(f"ok ({len(piezas)} apunte(s))")

    procesados = len(archivos) - fallidos - vacios
    print(
        f"\nListo. Documentos procesados: {procesados} · apuntes creados: "
        f"{apuntes} · vacíos: {vacios} · fallidos: {fallidos}"
    )
    if not args.dry_run:
        print(
            "Los embeddings se generan en segundo plano en el cerebro; en "
            "unos segundos Matix ya podrá buscar este material."
        )
    return 1 if fallidos else 0


if __name__ == "__main__":
    raise SystemExit(main())
