"""Extrae texto de un documento adjunto al chat (PDF, DOCX, TXT, MD).

Misma lógica que `scripts/ingestar_documentos.py` (la ingestión de material),
pero trabajando sobre BYTES en memoria — la app sube el archivo por multipart;
acá no tocamos disco. El texto extraído viaja como contexto del turno del chat
para que Matix lo lea/analice/resuma; lo capeamos para no inflar tokens.

pypdf y python-docx son dependencias del cerebro (ver pyproject). Si por lo que
sea no están, devolvemos un error claro en vez de crashear.
"""
from __future__ import annotations

import io

# Extensiones soportadas (en minúscula, con punto).
EXTENSIONES = {".pdf", ".docx", ".txt", ".md"}

# Tope del texto que mandamos como contexto al modelo. Un documento más largo
# se corta acá (con aviso `truncado=True`): suficiente para resumir/analizar
# sin disparar el costo de tokens. ~16k chars ≈ 4-5k tokens.
MAX_CHARS = 16_000


class DocumentoNoSoportado(ValueError):
    """Extensión fuera de EXTENSIONES."""


def _ext(nombre: str) -> str:
    n = (nombre or "").lower()
    punto = n.rfind(".")
    return n[punto:] if punto != -1 else ""


def _texto_de_txt(datos: bytes) -> str:
    # utf-8-sig se traga el BOM que ponen Notepad y otros editores de Windows
    # (si no, el contenido arrancaría con un carácter invisible).
    return datos.decode("utf-8-sig", errors="ignore")


def _texto_de_pdf(datos: bytes) -> str:
    try:
        from pypdf import PdfReader
    except ImportError as e:  # noqa: BLE001
        raise RuntimeError(
            "Falta 'pypdf' en el cerebro para leer PDFs."
        ) from e
    lector = PdfReader(io.BytesIO(datos))
    return "\n\n".join((p.extract_text() or "") for p in lector.pages)


def _texto_de_docx(datos: bytes) -> str:
    try:
        import docx  # python-docx
    except ImportError as e:  # noqa: BLE001
        raise RuntimeError(
            "Falta 'python-docx' en el cerebro para leer .docx."
        ) from e
    doc = docx.Document(io.BytesIO(datos))
    return "\n".join(p.text for p in doc.paragraphs)


def extraer(nombre: str, datos: bytes) -> tuple[str, bool]:
    """Devuelve `(texto, truncado)` del documento `nombre` con bytes `datos`.

    Lanza `DocumentoNoSoportado` si la extensión no se reconoce, o
    `RuntimeError` si falta la librería del formato. El texto se normaliza
    (strip) y se capea a `MAX_CHARS`."""
    ext = _ext(nombre)
    if ext not in EXTENSIONES:
        raise DocumentoNoSoportado(
            f"No puedo leer «{nombre}». Formatos: PDF, DOCX, TXT, MD."
        )
    if ext in (".txt", ".md"):
        texto = _texto_de_txt(datos)
    elif ext == ".pdf":
        texto = _texto_de_pdf(datos)
    else:  # .docx
        texto = _texto_de_docx(datos)

    texto = (texto or "").strip()
    if len(texto) > MAX_CHARS:
        # Cortamos en un salto de línea cercano al límite para no partir
        # una palabra/frase a la mitad.
        corte = texto.rfind("\n", MAX_CHARS // 2, MAX_CHARS)
        fin = corte if corte > 0 else MAX_CHARS
        return texto[:fin].strip(), True
    return texto, False
