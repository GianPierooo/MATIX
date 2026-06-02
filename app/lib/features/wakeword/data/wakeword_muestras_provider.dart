import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wakeword_muestras_repository.dart';

/// Repositorio de subida de muestras de voz del wake word. Provider simple
/// para poder inyectar un fake en tests de la pantalla.
final wakeWordMuestrasRepoProvider =
    Provider<WakeWordMuestrasRepository>((ref) {
  final repo = WakeWordMuestrasRepository();
  ref.onDispose(repo.close);
  return repo;
});
