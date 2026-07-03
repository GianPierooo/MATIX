# Checklist Matix 2.0 — rumbo "determinista primero, IA como escalación"

Hoja de ruta de la etapa de afinamiento de costos de IA. La 1.0 está TERMINADA
(ver `docs/ESTADO.md`); esto NO reescribe nada, AFINA fugas de tokens sin perder
la comprensión natural.

## Filosofía (la escalera)

Para cada cosa, quedarse en el PRIMER escalón que la resuelva:

1. Comando directo tipado (`cerebro/app/comandos/`).
2. Clasificador por keywords (sin LLM).
3. Plantilla determinista.
4. Modelo barato (gpt-4o-mini / Haiku).
5. Modelo fuerte (Sonnet) — solo si de verdad hay que razonar o generar.

La base ya es buena: enrutador y clasificador por keywords sin LLM
(`enrutador.py`, `clasificador_rapido.py`), briefing/cierre por plantilla
(`briefing/armar.py`, `briefing/cierre.py`), dedup de embeddings por hash
(`recuerdos.py:141`), prompt caching en Anthropic (`llm.py`).

## Reglas de verificación

- AMBOS gates verdes antes de CADA commit (`flutter analyze --no-fatal-infos` +
  `flutter test` en `app/`; `uv run pytest -q` en `cerebro/`).
- Separar SIEMPRE lo "probado por unit tests + gates" de lo "pendiente de
  verificación en vivo": mientras el data plane de Supabase siga restringido
  (OTA caído), el cerebro no puede leer prod y NADA se declara "verificado en
  vivo".

## Tareas

### T2 — Telemetría de tokens por operación (fundamento) · DISEÑO
Instrumentación centralizada en `cerebro/app/matix/llm.py` que registre por
llamada: modelo, tokens in, tokens out y la OPERACIÓN (chat/embedding/visión/
extracción/…). Hoy `uso.py` acumula tokens y costo pero mezcla chat+visión y NO
distingue operación. Barato, sin filtrar contenido sensible. El número base real
se captura en vivo; ahora se deja la instrumentación lista.

### T3 — No volcar las 124 tools en mensajes medianos · #3
`seleccion_tools.py:133` `_UMBRAL_LARGO = 240` → subir a ~600. Un mensaje
conversacional de 2-3 frases hoy cruza a "todas las 124 tools" en cada vuelta del
loop (hasta `_MAX_VUELTAS=6`). CORE = 44 tools. Ajustar/añadir tests de selección.

### T4 — Acotar el ruteo al modelo fuerte · #2
Sonnet ~20x el mini en input. Dos fugas:
- `chat.py:403`: `if doc_texto or imgs: modelo = fuerte` — TODO adjunto va a
  Sonnet (un recibo/Yape simple no lo necesita).
- `enrutador.py:120-137` `_PESADO`: verbos "explica/revisa/mejora/corrige"
  capturan el fuerte en casos triviales.
Refinar sin degradar lo que sí necesita razonar. Tests de casos frontera.

### T5 — Parser de fechas-es determinista · #1 (la pieza grande) · DISEÑO
Hoy las fechas las resuelve el LLM a propósito: `clasificador_rapido.py:172`
`_MARCADORES_FECHA` y su uso en `:204`/`:265` VETAN la ruta rápida cuando hay
fecha. Diseñar un parser es-PE en America/Lima ("mañana", "pasado mañana", "el
viernes", "viernes 10am", "en 2 semanas", "el 15", "hoy en la noche", …) para que
esos recordatorios/tareas no gasten un turno de LLM.
REGLA INNEGOCIABLE: si el parser NO está seguro, cae de vuelta al LLM. Nunca
adivina. Set de tests EXHAUSTIVO (casos claros que resuelve + casos ambiguos que
delega).

### T6 — Handlers deterministas (si hay margen)
- G6: crear/marcar/borrar subtarea (hoy inexistente como comando/tool).
- G13: restaurar de papelera (los comandos existen pero no están en `_HANDLERS`
  ni expuestos como tool; "restaurar" en `tools.py` solo es una NOTA que manda a
  la app).
Priorizar el handler tipado en `cerebro/app/comandos/`; la IA solo elige la
intención.

## Estado de arranque (contexto)

- Storage de Supabase RESTRINGIDO por cuota (bucket `apks` acumulaba APKs). El
  prune del CI ya está commiteado (`86cab2f`); el dueño borra los viejos en el
  Dashboard. Mientras siga restringido, el OTA está caído y no hay verificación
  en vivo.
- Migraciones 0038-0048 aplicadas en prod. Backup lógico data-only en
  `C:\Users\gianp\Matix_backups\`.
