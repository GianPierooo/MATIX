import '../../../api/matix_client.dart';

/// Apunte recién capturado por voz desde Inicio (Capa 3 Paso C2).
///
/// Lo devuelve `POST /api/v1/matix/capturar-apunte`: el cerebro ya
/// clasificó la idea contra los proyectos/cursos existentes. Con
/// `destinoLabel` la UI arma el snackbar de una línea, y con `id`
/// abre el apunte para corregirlo.
class ApunteCapturado {
  const ApunteCapturado({
    required this.id,
    required this.titulo,
    required this.etiquetas,
    required this.general,
    this.proyectoNombre,
    this.cursoNombre,
  });

  final String id;
  final String titulo;
  final List<String> etiquetas;
  final bool general;
  final String? proyectoNombre;
  final String? cursoNombre;

  /// Frase de una línea para el snackbar de confirmación, en tú:
  /// "Guardado en proyecto Tesis" / "Guardado en el curso Cálculo" /
  /// "Guardado como apunte general".
  String get destinoLabel {
    if (proyectoNombre != null && proyectoNombre!.isNotEmpty) {
      return 'Guardado en proyecto $proyectoNombre';
    }
    if (cursoNombre != null && cursoNombre!.isNotEmpty) {
      return 'Guardado en el curso $cursoNombre';
    }
    return 'Guardado como apunte general';
  }

  factory ApunteCapturado.fromJson(Map<String, dynamic> j) {
    return ApunteCapturado(
      id: j['id'].toString(),
      titulo: (j['titulo'] as String?) ?? '',
      etiquetas: (j['etiquetas'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      general: (j['general'] as bool?) ?? true,
      proyectoNombre: j['proyecto_nombre'] as String?,
      cursoNombre: j['curso_nombre'] as String?,
    );
  }
}

/// Wrapper sobre `POST /api/v1/matix/capturar-apunte`.
///
/// Recibe un texto ya transcrito (Whisper) y lo guarda como apunte
/// clasificado en una sola pasada, SIN abrir el chat de Matix. La
/// clasificación (a qué proyecto/curso pertenece) la decide el
/// cerebro; este repo solo traduce el JSON.
class CapturaApunteRepository {
  CapturaApunteRepository(this._client);
  final MatixClient _client;

  /// Guarda `texto` como apunte. Lanza `MatixApiException` si el
  /// cerebro falla (503 si falta OPENAI_API_KEY, 502 si el modelo o
  /// la tool fallaron). El caller NO debe crear nada si esto lanza:
  /// así no quedan apuntes huérfanos.
  Future<ApunteCapturado> capturar(String texto) async {
    final j = await _client.post(
      '/api/v1/matix/capturar-apunte',
      {'texto': texto},
    );
    return ApunteCapturado.fromJson(j);
  }
}
