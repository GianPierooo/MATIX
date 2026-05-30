# Ingestar documentos a la biblioteca de material (Fase 1)

`scripts/ingestar_documentos.py` sube los documentos de una carpeta a la
**biblioteca de material de aprendizaje** de Matix — un store **separado**
de tus apuntes (tu inbox de ideas). El material es lo que consumen los
*tracks*.

Cada pieza queda etiquetada por:

- **skill** = la **carpeta** (ej. `calistenia`) → un track.
- **bloque** = cada **archivo** (ej. `Bloque 3.pdf` → `bloque_3`) → una etapa.

Así Matix puede traer *"el bloque 3 de calistenia"* sin mezclarlo con la
búsqueda de apuntes. El cerebro trocea, embebe y guarda en
`material_chunks`; el archivo original se queda en tu PC (solo viaja el
texto).

> **No va a los apuntes.** Los apuntes son tu inbox de ideas; esto es
> material de estudio, y vive aparte.

- Formatos: `.txt`, `.md`, `.pdf`, `.docx` (recorre subcarpetas).
- Habla con el cerebro por su API → solo necesita la URL del cerebro y tu
  `MATIX_API_KEY`. **No** toca Supabase ni necesita sus credenciales.
- **Idempotente por skill+bloque:** re-ingestar el mismo archivo
  **reemplaza** su material (no duplica).

---

## 1. Qué instalar

Los `.txt` y `.md` no necesitan nada. Para PDF y Word:

```bash
pip install pypdf python-docx
```

## 2. Dónde poner la URL del cerebro y la API key

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

**B) Por argumento:** `--api-url` y `--api-key` en el comando.

> No pegues la key en archivos que se suban al repo.

## 3. Cómo organizar la carpeta

Una carpeta por **skill**, y dentro un archivo por **bloque**:

```
calistenia/
  Bloque 1.pdf
  Bloque 2.pdf
  Bloque 3.md
```

Apuntas el script a la carpeta del skill (`calistenia`). Cada archivo se
ingesta como su bloque.

## 4. Comando final para ingestar

Desde `cerebro/`:

```powershell
# Windows, con MATIX_API_URL y MATIX_API_KEY ya definidas (paso 2A)
python scripts/ingestar_documentos.py "C:/Users/gianp/Documentos/calistenia"
```

```bash
# Linux/macOS
python scripts/ingestar_documentos.py ~/Documentos/calistenia
```

El **skill** por defecto es el nombre de la carpeta (`calistenia`);
cámbialo con `--skill`. El **bloque** sale del nombre de cada archivo.

### Probar sin subir nada

```bash
python scripts/ingestar_documentos.py "C:/ruta/a/calistenia" --dry-run
```

## Opciones

| Opción | Para qué |
|---|---|
| `--dry-run` | No sube nada; solo muestra qué haría. |
| `--skill TEXTO` | Skill/track (default: nombre de la carpeta). |
| `--api-url URL` | URL del cerebro (si no usas `MATIX_API_URL`). |
| `--api-key KEY` | API key (si no usas `MATIX_API_KEY`). |
| `--max-chars N` | Corta archivos largos en piezas de ~N caracteres (default 18000). |

**Documentos largos:** se parten en varias piezas (todas con el mismo
skill+bloque) para que **todo** quede indexado y buscable.

## Cómo lo usa Matix

Matix consulta este store con la tool `buscar_material(consulta, skill?,
bloque?)` — filtrando por skill y/o bloque. Es independiente de
`buscar_apuntes` (tus ideas): los dos mundos no se mezclan.

## Notas

- **Re-ingestar es seguro:** reemplaza el material de ese skill+bloque.
  Si renombras un archivo, su bloque cambia (queda el viejo y el nuevo);
  borra el viejo desde la biblioteca si hace falta.
- Para apuntes que ya están en el hub (no archivos), el backfill de
  embeddings es `scripts/embed_apuntes.py` — eso es otra cosa (apuntes,
  no material).
- Requiere la **migración 0015** aplicada en Supabase (crea
  `material_chunks`).
```
