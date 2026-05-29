import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/captura_apunte_repository.dart';

/// Repo de la captura rápida por voz de Inicio. Usa el `MatixClient`
/// compartido (mismo timeout largo de `/matix/...`).
final capturaApunteRepoProvider = Provider<CapturaApunteRepository>(
  (ref) => CapturaApunteRepository(ref.watch(matixClientProvider)),
);
