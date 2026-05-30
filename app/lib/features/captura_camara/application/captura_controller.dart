import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/clasificacion_repository.dart';
import '../data/ocr_service.dart';
import '../domain/destino_ocr.dart';

/// Fases del flujo de la cámara inteligente (Capa 7-A · unificado).
///
/// `camara`: esperando que el usuario dispare la foto.
/// `procesando`: ML Kit está extrayendo el texto (on-device).
/// `clasificando`: el texto va al cerebro, que decide a qué flujo
///   pertenece (tareas / eventos / apunte). SOLO viaja el texto.
/// `listo`: terminó — `texto` trae lo reconocido (puede venir vacío) y
///   `destino` el flujo sugerido (corregible por el usuario).
/// `error`: ML Kit falló; `error` trae el mensaje para mostrar.
enum FaseCaptura { camara, procesando, clasificando, listo, error }

@immutable
class EstadoCaptura {
  const EstadoCaptura({
    this.fase = FaseCaptura.camara,
    this.texto = '',
    this.error,
    this.destino = DestinoOcr.apunte,
  });

  final FaseCaptura fase;
  final String texto;
  final String? error;

  /// Flujo sugerido por la clasificación. Solo es significativo en
  /// [FaseCaptura.listo]; antes vale el catch-all [DestinoOcr.apunte].
  final DestinoOcr destino;

  /// El OCR terminó pero no encontró texto. La UI lo trata igual que un
  /// error blando: avisa y deja escribir a mano.
  bool get vacio => fase == FaseCaptura.listo && texto.trim().isEmpty;
}

/// Orquesta captura → OCR → clasificación → listo / error. La pantalla
/// de cámara le pasa la ruta de la foto recién tomada (o elegida de la
/// galería); el controller corre el OCR on-device y, si hay texto, le
/// pregunta al cerebro a qué flujo pertenece. La corrección del texto y
/// del tipo viven en la pantalla de resultado, no acá: este controller
/// solo entrega lo que ML Kit reconoció y el destino sugerido.
class CapturaController extends Notifier<EstadoCaptura> {
  @override
  EstadoCaptura build() => const EstadoCaptura();

  Future<void> procesarFoto(String rutaImagen) async {
    state = const EstadoCaptura(fase: FaseCaptura.procesando);
    try {
      final texto = await ref.read(ocrServiceProvider).extraerTexto(rutaImagen);
      if (texto.trim().isEmpty) {
        // Sin texto no hay nada que clasificar: catch-all apunte y a
        // editar/escribir a mano.
        state = const EstadoCaptura(
          fase: FaseCaptura.listo,
          destino: DestinoOcr.apunte,
        );
        return;
      }
      // El texto ya está; Matix decide a qué flujo va. Es best-effort:
      // si la clasificación falla (sin red, sin API key), seguimos con
      // apunte — la captura nunca se queda atascada y el usuario puede
      // corregir el tipo en la pantalla siguiente.
      state = EstadoCaptura(fase: FaseCaptura.clasificando, texto: texto);
      var destino = DestinoOcr.apunte;
      try {
        destino =
            await ref.read(clasificacionRepositoryProvider).clasificar(texto);
      } catch (_) {}
      state = EstadoCaptura(
        fase: FaseCaptura.listo,
        texto: texto,
        destino: destino,
      );
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

/// Repo de clasificación de capturas (cámara inteligente). Lo
/// sobreescriben los tests con un fake para no pegar al cerebro.
final clasificacionRepositoryProvider = Provider<ClasificacionRepository>(
  (ref) => ClasificacionRepository(ref.watch(matixClientProvider)),
);

final capturaControllerProvider =
    NotifierProvider<CapturaController, EstadoCaptura>(CapturaController.new);
