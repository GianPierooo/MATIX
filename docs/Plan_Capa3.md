# Plan — Capa 3: Memoria (RAG sobre apuntes)

Matix conoce los apuntes del usuario por **significado**, no por
texto literal. Cuando Gian Piero pregunta "¿qué dije sobre la
demostración del límite?", Matix encuentra el apunte aunque ese
fragmento exacto no aparezca en él.

Llega después de la Capa 2 (chat + tools + voz + despliegue) y
antes de la Capa 4 (sync Google). Reusa todo lo que ya hay: chat
en cerebro, tool calling, modelo único OpenAI, papelera (los
apuntes en papelera **no** se indexan ni aparecen en búsqueda),
medidor de uso.

---

## Paso 1 — Indexar y buscar

Objetivo: Matix puede encontrar apuntes por significado y los cita
al responder.

- **Migración 0005**: extensión `pgvector`, tabla `apunte_chunks`
  (un apunte → 1+ chunks, cada chunk con su `embedding vector(1536)`),
  índice HNSW con `vector_cosine_ops`.
- **Embeddings al escribir**: hook en POST/PATCH de `/apuntes` que,
  tras crear/actualizar, regenera el embedding del apunte. Llama a
  OpenAI `text-embedding-3-small` a través de `cerebro/app/matix/llm.py`
  (sigue siendo el único módulo que importa `openai`). El medidor
  suma el costo.
- **Backfill**: `cerebro/scripts/embed_apuntes.py` que recorre los
  apuntes no eliminados sin chunks y los indexa.
- **Tool `buscar_apuntes(consulta, top_k?)`**: embebe la consulta,
  hace similarity search (coseno, top-K=5 default), devuelve título
  + fragmento + id por cada match. Respeta la papelera —
  `apuntes.eliminado_en IS NULL`.
- **System prompt** actualizado: cuándo usar `buscar_apuntes`, cómo
  citar la fuente, qué hacer si no encuentra nada (decir la
  verdad, no inventar).

Resultado: Matix responde "Hablaste de eso en tu apunte «Cálculo
III · Continuidad». Decías que…", o "No tengo nada anotado sobre
eso".

## Paso 2 — Modo tutor

Sobre la base del Paso 1, Matix puede actuar como tutor del
material del usuario.

- **Resumir un apunte** o un conjunto: tool `resumir_apuntes(filtro)`
  o conversacional sobre el resultado de `buscar_apuntes`.
- **Generar preguntas de práctica** desde un apunte (tipo examen):
  tool `generar_preguntas(apunte_id, n)`.
- **Explicar un tema** con tus propios apuntes como base, no con
  conocimiento genérico del modelo. Matix razona sobre lo que el
  usuario ya escribió.
- **Sesión de estudio**: voz manos libres + tutor → Matix pregunta,
  el usuario responde, Matix corrige. Reusa la pantalla manos
  libres y el TTS de Capa 2.

---

## Lo que NO entra en Capa 3

- **Indexar tareas, proyectos, eventos**. RAG es solo sobre
  **apuntes** — el contenido textual largo que vale la pena buscar
  por significado. Las tareas se buscan por filtros estructurados
  (curso, fecha, prioridad), no por embeddings.
- **Re-ranking** con cross-encoder. Para la escala del usuario
  (decenas a unos cientos de apuntes), similarity coseno directa
  basta. Si en el futuro el ruido aumenta, agregamos un re-ranker.
- **Sync de fuentes externas** (Google Drive, Notion, PDF). Eso
  es Capa 4. Acá solo apuntes que ya están en el hub.
