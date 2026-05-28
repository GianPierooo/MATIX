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

## Paso 2 — Modo tutor (resumir / preguntar / explicar) ✅

Sobre la base del Paso 1, Matix actúa como tutor del material del
usuario. Implementado con UNA tool nueva (`leer_apunte` para
acceder al contenido completo) + system prompt extendido. Las
capacidades no son tools dedicadas — son comportamientos guiados
por el prompt sobre la base de búsqueda + lectura del apunte.

- **Resumir** un apunte o un conjunto, citando título y resumiendo
  con palabras propias.
- **Preguntas de práctica** desde un apunte (5-8, conceptuales y
  de aplicación, sin las respuestas en el primer turno).
- **Explicar** un tema usando el apunte como fuente primaria,
  complementando con conocimiento general cuando hace falta y
  distinguiéndolo claramente.

## Paso 3 — Sesión de estudio en voz ✅ (cierra Capa 3)

Repaso interactivo conducido por Matix en modo manos libres,
turno a turno. NO suma tools nuevas — la pieza central es el
system prompt que codifica el protocolo de la sesión.

- Punto de entrada: botón "Repasar" en el AppBar de Universidad
  → abre manos libres con seed que invita al usuario a elegir
  el apunte.
- El protocolo: una pregunta por turno, evaluación específica
  contra el apunte, feedback con cita, ritmo sin pausas
  "¿seguimos?". Cierra con resumen (qué anduvo bien / qué
  repasar).
- Grounding: si el apunte no alcanza para evaluar lo que dijo
  el usuario, Matix lo dice — no inventa.

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
