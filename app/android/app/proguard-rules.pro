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
