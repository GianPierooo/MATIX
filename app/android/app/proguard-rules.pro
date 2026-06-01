# Reglas R8/ProGuard para la build de release.
#
# ML Kit · reconocimiento de texto on-device (Capa 7-A). Solo
# empaquetamos el modelo latino, pero el plugin
# `google_mlkit_text_recognition` referencia también los reconocedores
# de otros scripts (chino, devanagari, japonés, coreano) que NO
# incluimos. Sin estas reglas, R8 (el minify del release, activado por
# defecto por el plugin de Flutter) falla con "Missing class …" y la
# build del CI se cae en `:app:minifyReleaseWithR8`.
#
# Son exactamente las reglas que sugiere el propio R8 en
# build/app/outputs/mapping/release/missing_rules.txt.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# flutter_local_notifications · persiste las notificaciones PROGRAMADAS en
# SharedPreferences con Gson. Lee la caché con
#   new TypeToken<ArrayList<NotificationDetails>>() {}.getType()
# (FlutterLocalNotificationsPlugin.java:508). Si R8 borra la firma
# genérica de ese TypeToken, Gson revienta con
# "java.lang.RuntimeException: Missing type parameter." en TODA llamada
# que lea esa caché (loadScheduledNotifications): cancel / zonedSchedule /
# pendingNotificationRequests, y también el receiver nativo que dispara la
# alarma — por eso además NO llegaba ninguna notificación.
#
# IMPORTANTE: este proyecto compila con R8 en *full mode* (AGP 8, default).
# En full mode un `-keep class ... TypeToken` simple NO basta para
# preservar la firma genérica. Hay que usar EXACTAMENTE las reglas
# oficiales de Gson (con `allowobfuscation,allowshrinking`), que son las
# que mantienen `Signature` sobre los TypeToken anónimos. Este era el bug:
# las reglas anteriores no cubrían full mode.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# Reglas oficiales de Gson (META-INF/proguard/gson.pro) — válidas en R8
# full mode.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# El plugin y su modelo serializado por Gson (NotificationDetails y el
# TypeToken anónimo de la línea 508 viven acá): mantenemos clase y campos.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { <fields>; }

# ONNX Runtime (flutter_onnxruntime · wake word). Su librería nativa
# (libonnxruntime4j_jni.so) busca por NOMBRE, vía JNI (FindClass/GetMethodID),
# las clases y métodos Java de `ai.onnxruntime.*` al construir y convertir los
# tensores. R8 (minify del release, full mode) los renombra/elimina porque solo
# los referencia el código nativo (R8 no lo "ve"); entonces GetMethodID falla y
# ORT revienta con un SIGSEGV DENTRO de OrtSession.run, justo al convertir la
# SALIDA del modelo (convertOrtValueToONNXValue -> convertToTensorInfo).
#
# Síntoma exacto (confirmado en tombstone del Honor, Android 16):
#   signal 11 (SIGSEGV) en __strlen_aarch64 <- art::JavaVMExt::JniAbort
#   <- GetMethodID <- convertToTensorInfo <- Java_ai_onnxruntime_OrtSession_run
# Cargaba bien y corría, pero moría al construir el tensor de salida — y solo en
# release (en debug R8 está apagado). Por eso los tests con backend falso no lo
# detectaban.
#
# Fix: preservar COMPLETO ai.onnxruntime (sin renombrar ni borrar nada).
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
