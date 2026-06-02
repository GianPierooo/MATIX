# Entrenar "oye matix" (wake word en español)

El wake word usa hoy un **placeholder en inglés** (`hey_jarvis_v0.1.onnx`). Como
el modelo es en inglés y se habla en español, los scores quedan bajos (~0.40) y
cuesta que dispare. El arreglo de fondo es entrenar el modelo real **"oye
matix"** en español con openWakeWord.

## Por qué Colab y no local

Esta máquina: **RTX 3050 Laptop (4 GB VRAM)** y **Python 3.14** (demasiado nuevo:
PyTorch / openWakeWord aún no traen wheels para 3.14). El entrenamiento necesita
además datasets de negativos/aumentación de varios GB. Forzarlo local sería
pelear con el entorno por horas con alto riesgo de fallo. openWakeWord trae un
notebook oficial pensado para la GPU gratis de Colab, así que **se entrena en
Colab**. El clasificador resultante es minúsculo; lo pesado es la data, que
Colab descarga sola.

## Compatibilidad (confirmada)

Un modelo entrenado con openWakeWord usa la **misma cadena compartida**:
`melspectrogram.onnx → embedding_model.onnx → clasificador`, con el clasificador
de entrada `[1,16,96]` float32 y salida `[1,1]` — **idéntico** a
`hey_jarvis_v0.1.onnx`. Por eso el swap NO toca los modelos mel/embedding ni el
código del pipeline: solo se reemplaza el archivo del clasificador. (El nombre
del tensor de entrada que exporta el entrenamiento puede no ser `x.1`, pero
ambos pipelines lo enlazan por `inputNames.first()`, así que da igual.)

## Cómo correr el entrenamiento

1. Sube `docs/oye_matix_colab.ipynb` a https://colab.research.google.com (o
   ábrelo desde GitHub).
2. **Entorno de ejecución → Cambiar tipo de entorno → GPU (T4)**.
3. Corre las celdas en orden (1 → 9). Tarda ~20–60 min (domina la descarga).
   - Celda 3 sintetiza "oye matix" con 8 voces de Piper en español (es_AR,
     es_ES x5, es_MX x2), con variación de tempo/ruido, remuestreado a 16 kHz.
   - Celda 4 baja RIRs + ~2000 h de features negativas precomputadas + features
     de validación de falsos positivos.
   - Celdas 6–7 aumentan, calculan features y entrenan el clasificador.
   - Celda 8 imprime la interfaz ONNX (debe ser entrada `[1,16,96]`, salida
     `[1,1]`); celda 9 descarga `oye_matix.onnx`.

### Métricas
El propio `train.py` reporta accuracy / recall / false-positives-per-hour de
validación al final (objetivos del YAML: accuracy ≥ 0.6, recall ≥ 0.25,
FP/h ≤ 0.2). Anota esos números: son la base para decidir si iterar.

### Si algo se rompe (los típicos)
- `piper-phonemize` no compila → no lo usamos (vamos por el CLI `piper-tts`).
- Flags de `piper` distintos según versión → ajusta la línea del `subprocess` en
  la celda 3 (`--length_scale` / `--noise_scale`).
- `Clip does not have the correct sample rate` → algún WAV no quedó en 16 kHz:
  el `ffmpeg -ar 16000 -ac 1` de la celda 3 lo cubre; re-corre esa celda.
- Pocas voces (8) en español → apóyate en aumentación; si hace falta, agrega
  20–50 grabaciones reales tuyas diciendo "oye matix" en `positive_train`.

## Cómo integrarlo (el swap, ya pre-cableado)

Cuando tengas `oye_matix.onnx`:

1. Cópialo a `app/assets/models/wakeword/`.
2. En `app/lib/features/wakeword/data/wakeword_modelo.dart` cambia las **dos**
   constantes:
   ```dart
   static const String archivo = 'oye_matix.onnx';
   static const String frase   = 'oye matix';
   ```
3. `flutter analyze && flutter test`, build e instala.

Eso reemplaza el modelo en **ambos pipelines** a la vez: el de Dart (app abierta)
lo lee de la constante, y el service nativo (segundo plano) recibe el nombre del
archivo por el MethodChannel. La notificación del service de fondo ya es genérica
("Di la palabra…"), así que no hay que tocar Kotlin. El umbral sigue ajustable
con el slider (probablemente puedas subirlo respecto a 0.30 una vez en español).

## Expectativa realista

El primer modelo es una **base**. Pruébalo en el teléfono mirando el readout de
score (Ajustes / la notificación en segundo plano) y el umbral. Si no rinde,
iteramos: más muestras, más aumentación, o grabaciones reales de tu voz y tu
micro para afinarlo (el camino más efectivo para clavar tu pronunciación).
