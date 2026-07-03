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

## Estado (al día)

Primera racha (telemetría + determinismo + handlers):
- ✅ T2 telemetría por operación (`e357ae2`).
- ✅ T3 umbral de tools 240→600 (`ea2783b`).
- ✅ T4 acotar ruteo al fuerte (`ff1763e`).
- ✅ T5 parser de fechas-es determinista (`7a55b86`).
- ✅ T6 subtareas (G6) + restaurar papelera (G13) por IA (`29be5f3`).

Segunda racha (determinismo profundo + infra + funcional + design system):
- ✅ B1 consultas de tareas deterministas en la ruta rápida (`53d0149`).
- ✅ B2 resumen de documento PC al barato + cap + MAP en lotes (`62a4117`).
- ✅ B4 desempate de proactividad al barato (`ad13c14`).
- ✅ B3 prefijo de tools CORE-primero + 2º cache breakpoint (`3df83e8`).
- ✅ C1 keep-alive de Supabase (GitHub Action cada ~3 días) (`3930851`).
- ✅ D1 split de recurrencia empuja la fila nueva a Google (`387f609`).
- ⚠️ D2 marcar-hecho desde el widget: base Dart (deep-link `completar:`) hecha y
  testeada (`9642838`); **falta el botón nativo en los RemoteViews** (device-only).
- ✅ E1 CERRADO: `MatixButtonStyles` (primario/Alto/Medio/Compacto/Ancho +
  destructivo/exito) + los 19 primarios canónicos (accent+white) convertidos
  (tandas A-E, `bb22d8c`→`c1729de`). Queda 1 NO-canónico a propósito
  (`entrenar_voz_screen.dart:495`, accent SIN foreground → convertirlo cambiaría
  el color de texto). 0 primarios canónicos sin convertir, 0 imports muertos.
- ⚠️ E2 tokens `MatixSpacing` (18/22/26/28/36/40/42) creados + primeros usos
  (`ff5d7cf`). **~640 números mágicos restantes** = por tandas por-archivo.
- ⚠️ E3 colores de sombra → tokens `MatixColors.shadow*` (`15473a4`). Los ~8
  `BoxShadow` inline DIFERIDOS: no matchean tokens existentes (el glow del FAB es
  "casi" fab, no exacto) → serían tokens single-use sin reuso y con riesgo de look.

Endurecimiento de tests (Fase 2, esta racha): ampliada la red de las 4 fronteras
deterministas, TODAS confirmadas sólidas (sin bugs nuevos): parser de fechas
(disyunciones, cross-type, bordes mes/año, meridiano 1-12, `c03d9b1`); frontera
B1 (consultas puras vs 10 frases trampa, `57fee96`); ruteo al fuerte (sub/sobre-
escalación, `953ea28`); selección de tools (umbral 600, dos grupos, prefijo CORE,
`d04b59f`).

Salud del repo: 🟢 VERDE (verificado 2 veces). `main == origin/main`, nada colgado,
sin stashes, sin secretos trackeados, prune del CI bien formado, gates verdes de
cero (pytest 798 passed/200 skipped; flutter 597 passed; analyze 1 info no-fatal).
Rojos ESPERABLES en Actions: `build-and-publish` en commits que tocan `app/**`
falla en "Subir APK a Storage" por 402 (storage restringido); los gates verdes.

Auditoría adversarial (racha previa):
- 🐞→✅ P0: el parser de fechas ADIVINABA con dos fechas/horas ("el lunes o el
  martes" → lunes) y aceptaba meridiano inválido ("a las 99pm" → 15:00). Arreglado:
  delega ante múltiples/inválidas (`ecfbfaa`).
- 🐞→✅ Sub-escalación: una consulta del hub con razonamiento ("revisa mis tareas y
  dime cuál priorizar y por qué") se degradaba al barato. Umbral 70→40 (`de6110c`).
- ✅ Drift de conteo de tools 124→128 corregido (`4837f57`).
- ✅ Telemetría: resumen-doc y proactividad ahora etiquetan su operación (`499a9a0`).
- Verificado sólido: paridad tool-defs↔handlers (128=128, 0 huérfanos); frontera de
  B1 (intercepta 4, delega 6, sin falsos); T2 cubre CADA call-site de llm.py;
  G6/G13 wired en `_HANDLERS` + TOOL_DEFINITIONS; sin TODO/FIXME.

VERIFICACIÓN EN VIVO PENDIENTE: el data plane de Supabase sigue restringido (OTA
caído). Nada se declara verificado contra prod. Ahorros reales = leer la telemetría
de T2 (`GET /matix/uso` → `por_operacion`) cuando el servicio vuelva. D1 (Google)
se verifica contra Google real; D2 (widget) se valida en device.

Deferidos con criterio (bajo valor / alto churn): LRU de embedding de consulta
(repeticiones idénticas raras, embeddings ~$0.02/1M → ahorro despreciable); rollout
E1/E2 masivo (mecánico, ~650 sitios). Anotados, no bloqueantes.

## Tareas

### T2 — Telemetría de tokens por operación (fundamento) · DISEÑO
Instrumentación centralizada en `cerebro/app/matix/llm.py` que registre por
llamada: modelo, tokens in, tokens out y la OPERACIÓN (chat/embedding/visión/
extracción/…). Hoy `uso.py` acumula tokens y costo pero mezcla chat+visión y NO
distingue operación. Barato, sin filtrar contenido sensible. El número base real
se captura en vivo; ahora se deja la instrumentación lista.

### T3 — No volcar las 128 tools en mensajes medianos · #3
`seleccion_tools.py:133` `_UMBRAL_LARGO = 240` → subir a ~600. Un mensaje
conversacional de 2-3 frases hoy cruza a "todas las 128 tools" en cada vuelta del
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
