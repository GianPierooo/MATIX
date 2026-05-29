"""OCR de imágenes vía OpenAI vision.

Reusa el cliente AsyncOpenAI de `matix/llm.py` para no duplicar la
custodia de la API key ni el medidor de uso — toda la facturación
con OpenAI pasa por el mismo punto.

Decisión: `gpt-4o-mini` por costo bajo. Multimodal nativo. La
imagen viaja como `image_url` apuntando a la URL pública de
Supabase Storage; OpenAI la descarga del lado servidor. Eso evita
mandar base64 (costo de ancho de banda × 1.33) y tope de tamaño
inline.

Si en el futuro el manuscrito flojea, parametrizamos el `modelo`
para subir a `gpt-4o` solo cuando el usuario lo pida.
"""
from __future__ import annotations

import logging

from ..matix.llm import _get_client
from ..matix.uso import medidor

logger = logging.getLogger("matix.vision.ocr")

# Modelo multimodal por defecto. Soporta image_url, no manda imagen
# base64.
_MODELO_DEFAULT = "gpt-4o-mini"

# Prompt corto y específico — pedimos la transcripción directa sin
# adornos, sin comentar la foto. La idea es que el output sea
# pegado tal cual al apunte.
_SYSTEM = (
    "Sos un OCR. Te paso una imagen y devolvés el texto que aparece "
    "en ella, lo más fielmente posible. Sin comentarios tuyos, sin "
    "describir la imagen, sin envoltorios tipo 'el texto dice'. "
    "Si hay fórmulas, transcribilas como texto plano (no LaTeX). "
    "Si no hay texto visible o no podés extraerlo, respondé "
    "exactamente la cadena <SIN_TEXTO>."
)


# Cuando el modelo decide que no hay texto extraíble, devuelve este
# marcador. El router lo interpreta para no guardar la cadena en el
# apunte y marcar `ocr_ok=False`.
SIN_TEXTO_TOKEN = "<SIN_TEXTO>"


async def extraer_texto(
    *, url_imagen: str, modelo: str = _MODELO_DEFAULT
) -> str:
    """Llama a OpenAI vision sobre `url_imagen` y devuelve el texto
    transcripto. Si el modelo no encuentra texto, devuelve "" (no el
    token interno).

    Lanza la excepción cruda de OpenAI si la API rebota (rate limit,
    timeout, content blocked, etc.) — el caller del router decide
    qué responder al cliente.
    """
    client = _get_client()
    resp = await client.chat.completions.create(
        model=modelo,
        messages=[
            {"role": "system", "content": _SYSTEM},
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": url_imagen},
                    }
                ],
            },
        ],
        temperature=0.0,
    )
    medidor.registrar_chat(resp.usage)
    bruto = (resp.choices[0].message.content or "").strip()
    if bruto == SIN_TEXTO_TOKEN or not bruto:
        return ""
    return bruto
