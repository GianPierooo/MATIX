import 'dart:typed_data';

/// Backend de inferencia de la cadena openWakeWord.
///
/// Se deja detrás de una interfaz para que la lógica de buffering/ventaneo
/// (`WakeWordPipeline`) sea testeable con un fake determinista: los modelos
/// ONNX nativos no corren en `flutter test`, pero la fontanería sí debe estar
/// probada. La implementación real vive en `onnx_backend.dart`.
abstract class WakeWordBackend {
  /// Carga los tres modelos (melspectrograma, embedding, clasificador).
  ///
  /// `migaja` (opcional) se invoca con el nombre del paso ANTES de cada
  /// creación de sesión ONNX, para dejar un rastro en disco que sobreviva a un
  /// crash nativo (ver [WakeWordCrumbs]).
  Future<void> cargar({void Function(String paso)? migaja});

  /// Corre el melspectrograma sobre `muestras` crudas. OJO: openWakeWord
  /// espera los valores int16 representados como float32 SIN normalizar (no se
  /// dividen entre 32768). Devuelve los frames mel resultantes — cada uno de
  /// 32 bins — ya con la transformación `x/10 + 2` aplicada.
  Future<List<Float32List>> melspectrograma(Float32List muestras);

  /// Embedding de una ventana de 76 frames mel (32 bins c/u) → vector de 96.
  Future<Float32List> embedding(List<Float32List> ventana76);

  /// Probabilidad de wake word (0..1) a partir de los últimos 16 embeddings.
  Future<double> clasificar(List<Float32List> ventana16);

  /// Libera los modelos.
  Future<void> liberar();
}

/// Tubería de detección de wake word de openWakeWord, en Dart puro.
///
/// Replica el `AudioFeatures` de openWakeWord (streaming): el audio entra en
/// PCM16 mono 16 kHz; se procesa en bloques de 1280 muestras (80 ms). Por cada
/// bloque se calcula el melspectrograma (≈8 frames de 32 bins), se toma una
/// ventana de 76 frames mel para producir un embedding de 96, y con los
/// últimos 16 embeddings el clasificador da una probabilidad. Si cruza el
/// umbral, se dispara una detección y entra un periodo refractario para no
/// re-disparar con la misma cola de audio.
///
/// Toda la aritmética de buffers vive aquí (testeable); la inferencia ONNX
/// está detrás de `WakeWordBackend`.
class WakeWordPipeline {
  WakeWordPipeline(
    this._backend, {
    this.umbral = kUmbralPorDefecto,
    this.refractarioFrames = kRefractarioPorDefecto,
  });

  /// Umbral por defecto. openWakeWord recomienda 0.5 para sus modelos, pero
  /// "hey jarvis" es un modelo en INGLÉS y el usuario habla español: en device
  /// real los scores al decir "hey jarvis" llegan a ~0.40, así que 0.5 casi
  /// nunca cruza. Bajamos el default a 0.30 (con margen bajo ese 0.40) para que
  /// el placeholder sea usable. El modelo "oye matix" en español subirá los
  /// scores y se podrá volver a subir. Ajustable en vivo desde Ajustes.
  static const double kUmbralPorDefecto = 0.30;

  /// Tras una detección, cuántos bloques (≈80 ms c/u) se ignoran antes de
  /// volver a clasificar. 16 ≈ 1.28 s: evita que el mismo "hey jarvis"
  /// dispare varias veces.
  static const int kRefractarioPorDefecto = 16;

  static const int kMuestrasBloque = 1280; // 80 ms @ 16 kHz
  static const int kBinsMel = 32;
  static const int kVentanaMel = 76; // frames mel que pide el embedding
  static const int kVentanaFeatures = 16; // embeddings que pide el clasificador

  // Contexto que el melspectrograma necesita a los lados (3 hops de 160) para
  // que un bloque de 1280 produzca exactamente sus frames sin perder bordes.
  static const int _contexto = 160 * 3;
  static const int _maxRaw = kMuestrasBloque + _contexto; // 1760
  static const int _maxMel = 10 * 97; // ~10 s de frames mel
  static const int _maxFeatures = 120; // ~10 s de embeddings

  final WakeWordBackend _backend;

  /// Umbral de detección (0..1). Mutable para poder afinarlo en vivo desde el
  /// slider de Ajustes sin re-armar la escucha.
  double umbral;
  final int refractarioFrames;

  final List<int> _pendiente = []; // muestras int16 aún sin completar bloque
  final List<double> _raw = []; // últimas muestras crudas (int16 como double)
  final List<Float32List> _mel = []; // frames mel acumulados
  final List<Float32List> _features = []; // embeddings acumulados
  int _refractario = 0;
  double _ultimoScore = 0;
  bool _iniciado = false;

  /// Última probabilidad calculada (para depurar/visualizar).
  double get ultimoScore => _ultimoScore;

  void _asegurarInit() {
    if (_iniciado) return;
    // El mel buffer arranca con 76 frames de unos (igual que openWakeWord),
    // así el primer embedding ya sale desde el primer bloque.
    for (var i = 0; i < kVentanaMel; i++) {
      final f = Float32List(kBinsMel);
      for (var j = 0; j < kBinsMel; j++) {
        f[j] = 1.0;
      }
      _mel.add(f);
    }
    _iniciado = true;
  }

  /// Limpia todo el estado (al soltar/retomar el micro o tras disparar).
  void reiniciar() {
    _pendiente.clear();
    _raw.clear();
    _mel.clear();
    _features.clear();
    _refractario = 0;
    _ultimoScore = 0;
    _iniciado = false;
  }

  /// Alimenta un lote de PCM16 mono 16 kHz little-endian. Devuelve `true` si
  /// se detectó la palabra dentro de este lote.
  Future<bool> alimentarPcm(Uint8List bytes) async {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    for (var i = 0; i < n; i++) {
      _pendiente.add(bd.getInt16(i * 2, Endian.little));
    }
    return _drenar();
  }

  Future<bool> _drenar() async {
    _asegurarInit();
    var detecto = false;
    while (_pendiente.length >= kMuestrasBloque) {
      final bloque = _pendiente.sublist(0, kMuestrasBloque);
      _pendiente.removeRange(0, kMuestrasBloque);
      if (await _procesarBloque(bloque)) detecto = true;
    }
    return detecto;
  }

  Future<bool> _procesarBloque(List<int> bloque) async {
    // 1) Acumula crudo y recorta a la ventana que necesita el melspectrograma
    //    (último bloque + contexto). Así cada cálculo ve el bloque nuevo más
    //    480 muestras de cola del anterior.
    for (final m in bloque) {
      _raw.add(m.toDouble());
    }
    if (_raw.length > _maxRaw) {
      _raw.removeRange(0, _raw.length - _maxRaw);
    }

    // 2) Melspectrograma → frames de 32 bins.
    final frames = await _backend.melspectrograma(Float32List.fromList(_raw));
    _mel.addAll(frames);
    if (_mel.length > _maxMel) {
      _mel.removeRange(0, _mel.length - _maxMel);
    }

    // 3) Embedding de la última ventana de 76 frames mel.
    if (_mel.length >= kVentanaMel) {
      final ventana = _mel.sublist(_mel.length - kVentanaMel);
      final emb = await _backend.embedding(ventana);
      _features.add(emb);
      if (_features.length > _maxFeatures) {
        _features.removeRange(0, _features.length - _maxFeatures);
      }
    }

    // En refractario no clasificamos (pero seguimos alimentando buffers).
    if (_refractario > 0) {
      _refractario--;
      return false;
    }

    // 4) Clasificador sobre los últimos 16 embeddings.
    if (_features.length >= kVentanaFeatures) {
      final ventana = _features.sublist(_features.length - kVentanaFeatures);
      _ultimoScore = await _backend.clasificar(ventana);
      if (_ultimoScore >= umbral) {
        _refractario = refractarioFrames;
        // Vaciamos los embeddings para no re-disparar con la misma cola.
        _features.clear();
        return true;
      }
    }
    return false;
  }
}
