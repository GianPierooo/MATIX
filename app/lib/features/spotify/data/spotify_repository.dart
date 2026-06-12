import '../../../api/matix_client.dart';

/// Estado de la conexión Spotify (lo que devuelve
/// `GET /api/v1/spotify/status`).
class SpotifyStatus {
  const SpotifyStatus({
    required this.conectado,
    this.busquedaDisponible = false,
  });

  /// `true` si ya hay refresh token (el usuario autorizó su Premium):
  /// el cerebro puede ORDENAR reproducir en la PC.
  final bool conectado;

  /// `true` si hay client id/secret: la búsqueda por Web API funciona
  /// aunque todavía no se haya autorizado el playback.
  final bool busquedaDisponible;

  factory SpotifyStatus.fromJson(Map<String, dynamic> j) => SpotifyStatus(
        conectado: j['conectado'] as bool? ?? false,
        busquedaDisponible: j['busqueda_disponible'] as bool? ?? false,
      );
}

/// Acceso a los endpoints de Spotify del cerebro.
class SpotifyRepository {
  SpotifyRepository(this._client);
  final MatixClient _client;

  Future<SpotifyStatus> status() async {
    final j = await _client.getOne('/api/v1/spotify/status');
    return SpotifyStatus.fromJson(j);
  }

  /// URL de consentimiento de Spotify que la app abre en el navegador
  /// del teléfono. Tras autorizar, Spotify redirige al callback del
  /// cerebro que guarda el refresh token.
  Future<String> obtenerUrlOAuth() async {
    final j = await _client.getOne('/api/v1/spotify/oauth/url');
    return j['url'] as String;
  }

  Future<void> desconectar() async {
    await _client.delete('/api/v1/spotify/disconnect');
  }
}
