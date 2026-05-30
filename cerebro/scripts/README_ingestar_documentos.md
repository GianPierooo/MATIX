# Ingestar documentos al RAG de Matix

`scripts/ingestar_documentos.py` sube los documentos de una carpeta a la
memoria de Matix (RAG, Capa 3). Lee cada archivo, extrae el texto y crea
**un apunte por documento** llamando al cerebro. Crear el apunte dispara
el indexador (embeddings con OpenAI), así que después Matix puede buscar
y citar ese material por significado.

- Formatos: `.txt`, `.md`, `.pdf`, `.docx` (recorre subcarpetas).
- Solo viaja el **texto** extraído: el archivo original no se sube.
- Habla con el cerebro por su API (igual que la app). **No** necesita
  credenciales de Supabase — solo la URL del cerebro y tu `MATIX_API_KEY`.

---

## 1. Qué instalar

Los `.txt` y `.md` no necesitan nada. Para PDF y Word:

```bash
pip install pypdf python-docx
```

(Si solo vas a subir `.txt`/`.md`, puedes saltarte este paso.)

## 2. Dónde poner la URL del cerebro y la API key

Dos formas — elige una:

**A) Variables de entorno (recomendado).** La URL es la del cerebro en
Railway; la key es el mismo `MATIX_API_KEY` que usa la app.

```powershell
# Windows (PowerShell)
$env:MATIX_API_URL = "https://tu-cerebro.up.railway.app"
$env:MATIX_API_KEY = "tu-token-secreto"
```

```bash
# Linux / macOS
export MATIX_API_URL="https://tu-cerebro.up.railway.app"
export MATIX_API_KEY="tu-token-secreto"
```

**B) Por argumento** (sin tocar el entorno): `--api-url` y `--api-key`
en el comando (ver abajo).

> No pegues la key en ningún archivo que se suba al repo.

## 3. Correrlo sobre tu carpeta INGLES

Desde la carpeta `cerebro/`:

```powershell
# Windows, con las variables ya definidas (paso 2A)
python scripts/ingestar_documentos.py "C:/Users/gianp/Documentos/INGLES"
```

```bash
# Linux/macOS
python scripts/ingestar_documentos.py ~/Documentos/INGLES
```

O pasando la URL/key por argumento (paso 2B):

```bash
python scripts/ingestar_documentos.py "C:/ruta/a/INGLES" \
  --api-url "https://tu-cerebro.up.railway.app" \
  --api-key "tu-token-secreto"
```

La **etiqueta** de los apuntes es, por defecto, el nombre de la carpeta
(`INGLES`), para poder filtrarlos luego. Cámbiala con `--etiqueta`.

### Probar sin crear nada

```bash
python scripts/ingestar_documentos.py "C:/ruta/a/INGLES" --dry-run
```

Lista qué documentos encontró y cuántos apuntes crearía, sin tocar nada.

---

## Opciones

| Opción | Para qué |
|---|---|
| `--dry-run` | No crea nada; solo muestra qué haría. |
| `--etiqueta TEXTO` | Etiqueta de los apuntes (default: nombre de la carpeta). |
| `--api-url URL` | URL del cerebro (si no usas `MATIX_API_URL`). |
| `--api-key KEY` | API key (si no usas `MATIX_API_KEY`). |
| `--curso-id UUID` | Asocia los apuntes a un curso existente. |
| `--proyecto-id UUID` | Asocia los apuntes a un proyecto existente. |
| `--max-chars N` | Corta documentos largos en apuntes de ~N caracteres (default 18000). |

**Documentos largos:** el indexador embebe ~1 chunk por apunte, así que
un PDF muy largo se parte en varios apuntes (`Documento (parte 1/3)`, …)
para que **todo** el contenido quede buscable. Ajusta el tamaño con
`--max-chars`.

## Notas

- **No es idempotente.** Cada corrida crea apuntes nuevos. Si reingestas
  una carpeta, borra antes desde la app los apuntes viejos de esa
  etiqueta (si no, quedan duplicados).
- Los embeddings se generan en segundo plano en el cerebro; tras correr
  el script, en unos segundos Matix ya puede usar el material.
- Para apuntes que ya están en el hub (no archivos), el backfill de
  embeddings es `scripts/embed_apuntes.py`.
