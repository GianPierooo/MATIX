import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ocr_service.dart';

/// Fases del flujo de captura + OCR (Capa 7-A).
///
/// `camara`: esperando que el usuario dispare la foto.
/// `procesando`: ML Kit está extrayendo el texto.
/// `listo`: terminó — `texto` trae lo reconocido (puede venir vacío).
/// `error`: ML Kit falló; `error` trae el mensaje para mostrar.
enum FaseCaptura { camara, procesando, listo, error }

@immutable
class EstadoCaptura {
  const EstadoCaptura({
    this.fase = FaseCaptura.camara,
    this.texto = '',
    this.error,
  });

  final FaseCaptura fase;
  final String texto;
  final String? error;

  /// El OCR terminó pero no encontró texto. La UI lo trata igual que un
  /// error blando: avisa y deja escribir a mano.
  bool get vacio => fase == FaseCaptura.listo && texto.trim().isEmpty;
}

/// Orquesta captura → OCR → listo / error. La pantalla de cámara le
/// pasa la ruta de la foto recién tomada; el controller corre el OCR
/// on-device y publica el resultado. La corrección del texto vive en
/// la pantalla de resultado (estado local del `TextField`), no acá:
/// este controller solo entrega lo que ML Kit reconoció.
class CapturaController extends Notifier<EstadoCaptura> {
  @override
  EstadoCaptura build() => const EstadoCaptura();

  Future<void> procesarFoto(String rutaImagen) async {
    state = const EstadoCaptura(fase: FaseCaptura.procesando);
    try {
      final texto = await ref.read(ocrServiceProvider).extraerTexto(rutaImagen);
      state = EstadoCaptura(fase: FaseCaptura.listo, texto: texto);
    } catch (e) {
      state = EstadoCaptura(
        fase: FaseCaptura.error,
        error: 'No pude leer el texto de la foto: $e',
      );
    } finally {
      // La imagen ya cumplió su rol y no sale del teléfono: la
      // borramos del temporal. Si falla el borrado, no es crítico.
      try {
        await File(rutaImagen).delete();
      } catch (_) {}
    }
  }

  /// Vuelve a la cámara para tomar otra foto.
  void reiniciar() => state = const EstadoCaptura();
}

final ocrServiceProvider = Provider<OcrService>((ref) {
  final servicio = OcrService();
  ref.onDispose(servicio.dispose);
  return servicio;
});

final capturaControllerProvider =
    NotifierProvider<CapturaController, EstadoCaptura>(CapturaController.new);
