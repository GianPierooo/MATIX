import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/spotify_repository.dart';

final spotifyRepositoryProvider = Provider<SpotifyRepository>((ref) {
  return SpotifyRepository(ref.watch(matixClientProvider));
});

/// Estado de la conexión Spotify. Ajustes lo `watch`-ea para mostrar
/// "Conectar Spotify" o "Conectado". Invalidarlo tras autorizar refresca.
final spotifyStatusProvider = FutureProvider<SpotifyStatus>((ref) async {
  return ref.watch(spotifyRepositoryProvider).status();
});
