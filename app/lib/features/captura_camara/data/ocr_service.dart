import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR on-device con ML Kit (Capa 7-A).
///
/// Envuelve el `TextRecognizer` de ML Kit para que el resto de la
/// feature no dependa del SDK directamente. El reconocimiento corre
/// **local en el teléfono** con el modelo latino empaquetado: la
/// imagen nunca sale del dispositivo. Es el flujo nuevo y aparte del
/// de foto→apunte, que sí manda la imagen a OpenAI.
///
/// El `TextRecognizer` reserva recursos nativos; hay que cerrarlo con
/// [dispose] cuando ya no se usa (lo hace el provider vía `onDispose`).
class OcrService {
  OcrService({TextRecognizer? recognizer})
      : _recognizer =
            recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  /// Extrae el texto de la imagen en [rutaImagen]. Devuelve la cadena
  /// reconocida ya trimmeada — vacía si ML Kit no encontró texto. No
  /// lanza por "no hay texto": eso es un resultado válido (vacío) que
  /// la UI traduce a "escribe a mano".
  Future<String> extraerTexto(String rutaImagen) async {
    final entrada = InputImage.fromFilePath(rutaImagen);
    final reconocido = await _recognizer.processImage(entrada);
    return reconocido.text.trim();
  }

  Future<void> dispose() => _recognizer.close();
}
