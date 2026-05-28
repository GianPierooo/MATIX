import '../../../api/matix_client.dart';

/// Estado de la conexión Google del usuario (lo que devuelve
/// `GET /api/v1/google/status`).
class GoogleStatus {
  const GoogleStatus({
    required this.conectado,
    this.email,
    this.scopes = const [],
    this.conectadoEn,
    this.ultimoSyncEn,
  });

  final bool conectado;
  final String? email;
  final List<String> scopes;
  final DateTime? conectadoEn;
  final DateTime? ultimoSyncEn;

  factory GoogleStatus.fromJson(Map<String, dynamic> j) => GoogleStatus(
        conectado: j['conectado'] as bool? ?? false,
        email: j['email'] as String?,
        scopes: ((j['scopes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        conectadoEn: _parseTs(j['conectado_en']),
        ultimoSyncEn: _parseTs(j['ultimo_sync_en']),
      );
}

class GoogleSyncResumen {
  const GoogleSyncResumen({
    required this.email,
    required this.creados,
    required this.actualizados,
    required this.mandadosAPapelera,
    required this.totalRemoto,
  });

  final String email;
  final int creados;
  final int actualizados;
  final int mandadosAPapelera;
  final int totalRemoto;

  factory GoogleSyncResumen.fromJson(Map<String, dynamic> j) =>
      GoogleSyncResumen(
        email: j['email'] as String,
        creados: (j['creados'] as num).toInt(),
        actualizados: (j['actualizados'] as num).toInt(),
        mandadosAPapelera: (j['mandados_a_papelera'] as num).toInt(),
        totalRemoto: (j['total_remoto'] as num).toInt(),
      );
}

DateTime? _parseTs(dynamic v) =>
    v == null ? null : DateTime.parse(v as String);

/// Wrapper sobre `/api/v1/google/*` del cerebro.
class GoogleRepository {
  GoogleRepository(this._client);
  final MatixClient _client;

  Future<GoogleStatus> status() async {
    final j = await _client.getOne('/api/v1/google/status');
    return GoogleStatus.fromJson(j);
  }

  /// Devuelve la URL OAuth a la que mandar al usuario.
  Future<String> obtenerUrlOAuth() async {
    final j = await _client.getOne('/api/v1/google/oauth/url');
    return j['url'] as String;
  }

  /// Trigger del sync. El cerebro hace todo: lee Google, upsert a
  /// Supabase, marca papelera lo que ya no está.
  Future<GoogleSyncResumen> sincronizar() async {
    // POST con body vacío.
    final j = await _client.post('/api/v1/google/sync', const {});
    return GoogleSyncResumen.fromJson(j);
  }

  Future<void> desconectar() async {
    await _client.delete('/api/v1/google/disconnect');
  }
}
