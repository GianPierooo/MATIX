"""Capa 7 · Visión por cámara.

Paso 1: foto → apunte. Sube la imagen a Supabase Storage, llama a
OpenAI vision para extraer el texto, y deja el resultado listo para
que el router de apuntes lo persista con su pipeline normal (incluye
auto-embed en background).

Documentación: `docs/Plan_Capa7.md`.
"""
