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
