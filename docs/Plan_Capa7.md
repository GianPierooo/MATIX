# Plan — Capa 7: Visión por cámara

La capa entera = la cámara como tercera vía de captura, paralela a
texto y voz. Subsistemas posibles: foto → apunte (OCR), foto →
tarea inferida ("encargué insumos"), reconocimiento de espacios
para automatizar, visión en vivo para tutor mode ("explicame esta
ecuación que tengo enfrente").

**Este paso construye solo el primer caso de uso**: tomás una foto
de algo escrito (libro, pizarra, anotación a mano), Matix extrae
el texto y crea un apunte con esa transcripción y la foto adjunta.
El resto de visión queda para iteraciones siguientes.

---

## Alcance del Paso 1

**Sí entra**:

- Botón "Agregar apunte desde foto" en la lista de Apuntes y en
  detalle de un curso de Universidad (donde es típico capturar la
  pizarra o un par de páginas).
- Selección entre **cámara** o **galería** con un sheet simple.
- Envío al cerebro de la imagen + metadatos opcionales (curso,
  proyecto, cuaderno, etiquetas, título sugerido).
- OCR vía **OpenAI vision (`gpt-4o-mini`)** — el cliente OpenAI ya
  está montado en el cerebro (`matix/llm.py`), reusamos.
- Almacenamiento de la imagen en **Supabase Storage** (bucket nuevo
  `apuntes-img`, público con nombre `<uuid>.<ext>`).
- Creación de un apunte normal con `contenido = texto extraído` y
  `adjuntos = [{url, tipo, nombre}]`. Reusa todo el resto del
  pipeline existente (auto-embed para RAG en background, soft-delete,
  edición desde el editor).
- Estado de carga claro en la app: "Subiendo… → Extrayendo texto…".
- Manejo de fallos: si OCR rebota, el apunte **igual se crea** con
  contenido vacío + flag de aviso. Nunca perdés la imagen.

**NO entra en este paso**:

- Múltiples páginas en una sola sesión (un PDF de varias hojas →
  un solo apunte concatenado).
- Pre-procesamiento de la imagen del lado app (rotar, recortar,
  enderezar pizarra). El usuario toma una foto razonable y listo.
- Detección de tipo de contenido (manuscrito vs. impreso vs.
  pizarra) — el prompt es genérico.
- Visión en vivo / video / streaming.
- Foto → tarea / evento / proyecto. Solo apunte por ahora.

---

## Decisiones clave

### 1. Modelo de visión: `gpt-4o-mini`

`gpt-4o-mini` es multimodal y soporta `image_url` como cualquier
otro mensaje. El precio por token de input visual es ~10× menor que
`gpt-4o`, con calidad muy aceptable para texto impreso y pizarra.
Para manuscrito complicado puede flojear — eso lo manejamos en
pasos siguientes.

Si en algún momento el manuscrito sale muy mal, se sube a `gpt-4o`
con un flag — el módulo se diseña con el modelo como parámetro.

### 2. Storage de la imagen: Supabase Storage, bucket público

Bucket nuevo `apuntes-img`. Configuración:

- **Público** (cualquiera con la URL puede leer), pero con nombres
  generados con `uuid4` — la URL es imposible de adivinar.
- Esto es coherente con cómo ya funciona el bucket `apks`. Single
  user app + datos no críticos (notas universitarias) → no
  justifica signed URLs todavía.
- Si en el futuro vamos multi-user o las imágenes pueden contener
  algo sensible (pasaportes, documentos médicos), se cambia a
  privado + signed URL temporal por request.

Path: `apuntes-img/<uuid4>.<jpg|png|webp>`.

### 3. Cómo viaja la imagen del teléfono al cerebro

`multipart/form-data` con el campo `file`, mismo patrón que el
endpoint Whisper (`/api/v1/matix/transcribir`). El cerebro:

1. Recibe los bytes.
2. Sube a Supabase Storage con un nombre `<uuid4>.<ext>`.
3. Llama a OpenAI vision con `image_url` apuntando a la URL pública
   del paso 2. Alternativa: data URL base64 inline — más caro en
   ancho de banda y limita tamaño. Usar URL pública sirve además
   para tener la foto disponible como adjunto del apunte sin
   doble upload.
4. Construye el `ApunteCreate` con `contenido = texto extraído` y
   `adjuntos = [{url, tipo: 'image/jpeg', nombre}]`.
5. Inserta vía el flow existente para que el `BackgroundTasks` del
   router de apuntes dispare el auto-embed sin lógica extra.

### 4. Manejo de fallos

El apunte se crea **siempre** que la imagen se haya subido. Si OCR
falla (Timeout, error de OpenAI, contenido bloqueado por policy):

- `contenido` queda `""` (vacío).
- Se devuelve el apunte normal **más** dos campos extra en el body:
  - `ocr_ok: bool` — false si falló.
  - `mensaje_ocr: string?` — descripción corta del problema, ej.
    "OpenAI rate-limit, intentá de nuevo en un momento".
- La app abre el editor del apunte con la foto adjunta y muestra un
  banner ámbar "No pude extraer el texto. Editalo a mano o tocá
  reintentar OCR" (botón reintentar = endpoint dedicado).

No mostramos error rojo bloqueante. La idea es que **siempre te
quedás con la foto**, y la transcripción es valor agregado.

### 5. Endpoint del cerebro

`POST /api/v1/apuntes/desde-foto` (multipart):

Campos del form:
- `file` (binary) — la imagen. Tipos aceptados: jpg, png, webp.
  Tope 10 MB (más de eso baja la calidad sin valor).
- `titulo` (opt) — si la app pasa uno, se usa; sino, generamos
  `Apunte del DD/MM HH:MM`.
- `curso_id` / `proyecto_id` / `cuaderno_id` (opt) — para asociar.
- `etiquetas` (opt) — CSV.

Respuesta: `ApunteRead` (mismo schema actual) + `ocr_ok` +
`mensaje_ocr`.

### 6. UI en la app

- Botón flotante **secundario** en `apuntes_list_screen` con
  ícono cámara: "📷 Desde foto". Lo ponemos junto al FAB primario
  de "Nuevo apunte".
- En el detalle de un curso de Universidad, sumamos una acción
  rápida "Capturar pizarra" que invoca el mismo flujo pero con
  `curso_id` pre-cargado. (Si la pantalla de curso no expone
  acciones aún, esto entra en una iteración futura — primero el
  botón en Apuntes que ya tiene contexto suficiente.)
- Al tocar el botón, sheet con dos opciones: **Cámara** o
  **Galería**.
- Una vez elegida la foto, pantalla intermedia con stepper:
  - `Subiendo foto…` (mientras viaja multipart al cerebro).
  - `Extrayendo texto…` (mientras OpenAI procesa).
  - Al terminar: navegamos al editor del apunte con todo cargado.
- Si `ocr_ok == false`, el editor se abre con un banner ámbar
  ("No pude extraer el texto, editalo a mano") y la foto adjunta
  ya cargada. El reintento de OCR sin re-subir queda para el
  Paso 2 (más fácil cuando ya tenemos multi-página).

---

## Pasos posibles después

- **Paso 2 — Multi-página**: una sesión = varias fotos → un
  apunte con el texto concatenado y todas las imágenes adjuntas.
  Útil para fotografiar 3 hojas de un cuaderno.
- **Paso 3 — Detector de tipo de contenido**: prompt distinto si
  detecta pizarra (fondo oscuro, tiza), manuscrito (renglones,
  lápiz/tinta), página impresa. Mejora la calidad del OCR.
- **Paso 4 — Editor de la foto**: rotar, recortar, enderezar antes
  de subir. Si el OCR sale flojo, esto suele rescatar.
- **Paso 5 — Foto → tarea/evento**: "encargué insumos" sale una
  factura → tarea de pagar; pizarra con horario → evento.
- **Paso 6 — Visión para tutor mode (Capa 3)**: foto de un ejercicio
  + "explicame esto" → Matix responde con el contexto visual + RAG.
- **Paso 7 — Visión en vivo**: stream de cámara para captura de
  varias páginas pasando rápido.

Cada uno se decide después de vivir con el anterior.
