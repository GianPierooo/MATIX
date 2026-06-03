import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resultado de ejecutar una acción de teléfono.
class ResultadoDispositivo {
  const ResultadoDispositivo.ok([this.mensaje]) : exito = true;
  const ResultadoDispositivo.fallo(this.mensaje) : exito = false;

  final bool exito;

  /// Texto para avisar al usuario cuando la acción no se pudo lanzar
  /// (degradación limpia: nunca crashea, siempre dice algo útil).
  final String? mensaje;
}

/// Ejecuta las acciones de teléfono propuestas por el cerebro (Capa 6 · Fase 1)
/// vía el canal nativo `dev.matix.matix/dispositivo`. El cerebro NUNCA actúa:
/// solo PROPONE; la app confirma (cuando aplica) y lanza el Intent aquí.
///
/// Todos los intents son "prellenados": abren la app destino con los datos
/// cargados y el usuario da el último toque (Enviar / Llamar / Guardar).
class DispositivoService {
  DispositivoService({MethodChannel? canal, ImagePicker? picker})
      : _canal = canal ?? const MethodChannel('dev.matix.matix/dispositivo'),
        _picker = picker ?? ImagePicker();

  final MethodChannel _canal;
  final ImagePicker _picker;

  /// Lanza la acción. Para `galeria` NO ejecuta un Intent: devuelve la ruta de
  /// la foto en `mensaje`-libre (la capa de UI la manda al chat). Por eso la
  /// galería se atiende aparte con [obtenerFoto].
  Future<ResultadoDispositivo> ejecutar(String tipo, Map<String, dynamic> datos) async {
    try {
      switch (tipo) {
        case 'mensaje':
          return _resultado(
            await _canal.invokeMethod<bool>('redactarMensaje', {
              'canal': datos['canal'],
              'destinatario': datos['destinatario'],
              'texto': datos['texto'],
              'asunto': datos['asunto'],
            }),
            siFalla: 'No encontré una app para enviar ese mensaje.',
          );
        case 'llamada':
          return _resultado(
            await _canal.invokeMethod<bool>('iniciarLlamada', {
              'numero': datos['numero'],
            }),
            siFalla: 'No pude abrir el marcador del teléfono.',
          );
        case 'evento':
          return _resultado(
            await _canal.invokeMethod<bool>('crearEvento', {
              'titulo': datos['titulo'],
              'iniciaEnMillis': _aMillis(datos['inicia_en']),
              'terminaEnMillis': _aMillis(datos['termina_en']),
              'ubicacion': datos['ubicacion'],
              'descripcion': datos['descripcion'],
            }),
            siFalla: 'No encontré una app de calendario.',
          );
        case 'abrir':
          return _resultado(
            await _canal.invokeMethod<bool>('abrir', {
              'objetivo': datos['objetivo'],
              'valor': datos['valor'],
            }),
            siFalla: 'No pude abrir eso en el teléfono.',
          );
        default:
          return ResultadoDispositivo.fallo('Acción no reconocida: $tipo');
      }
    } on PlatformException catch (e) {
      return ResultadoDispositivo.fallo('No pude completar la acción: ${e.message}');
    }
  }

  /// Obtiene una foto de la galería para el flujo de OCR/finanzas. `modo`:
  ///  - `ultima`: la más reciente vía MediaStore (pide permiso de lectura; si
  ///    se niega, degrada al selector).
  ///  - `elegir`: el usuario la escoge con el Photo Picker (sin permisos).
  /// Devuelve la ruta del archivo, o `null` si no se obtuvo ninguna.
  Future<String?> obtenerFoto(String modo) async {
    if (modo == 'ultima') {
      final permiso = await Permission.photos.request();
      if (permiso.isGranted || permiso.isLimited) {
        try {
          final ruta = await _canal.invokeMethod<String>('leerUltimaFoto');
          if (ruta != null && ruta.isNotEmpty) return ruta;
        } on PlatformException {
          // cae al selector
        }
      }
      // Permiso negado o sin foto reciente: degradación limpia al selector.
    }
    final foto = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    return foto?.path;
  }

  ResultadoDispositivo _resultado(bool? ok, {required String siFalla}) =>
      (ok ?? false) ? const ResultadoDispositivo.ok() : ResultadoDispositivo.fallo(siFalla);

  /// Convierte un ISO-8601 del cerebro a epoch-millis (UTC), o `null`. Parsear
  /// en Dart evita lidiar con `java.time` y el desugaring en Kotlin.
  int? _aMillis(Object? iso) {
    if (iso is! String || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    return dt?.millisecondsSinceEpoch;
  }
}
