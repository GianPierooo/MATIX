import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/google_repository.dart';

final googleRepositoryProvider = Provider<GoogleRepository>((ref) {
  return GoogleRepository(ref.watch(matixClientProvider));
});

/// Estado actual de la conexión Google. La pantalla Ajustes lo
/// `watch`-ea y muestra "Conectar" o "Conectado · email" según.
/// Invalidar este provider tras autorizar refresca el UI.
final googleStatusProvider = FutureProvider<GoogleStatus>((ref) async {
  return ref.watch(googleRepositoryProvider).status();
});
