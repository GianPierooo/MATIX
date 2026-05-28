import 'package:package_info_plus/package_info_plus.dart';

import '../../../api/matix_client.dart';

/// Info de una versión disponible en el servidor.
class UpdateDisponible {
  const UpdateDisponible({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.notas,
    this.sha,
  });

  final String version;
  final int buildNumber;
  final String apkUrl;
  final String notas;
  final String? sha;
}

/// Resultado del chequeo de actualización.
///
/// Tres casos:
/// - `actualizado` → la app local está al día (o por encima).
/// - `disponible` → hay una versión nueva. La payload trae los datos
///   para mostrar el diálogo y disparar el download.
/// - `fallido` → no se pudo consultar (sin internet, cerebro caído,
///   parseo). NO rompe nada: lo tratamos como "no chequees, ya
///   reintentaremos la próxima".
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class Actualizado extends UpdateCheckResult {
  const Actualizado(this.buildLocal);
  final int buildLocal;
}

class HayActualizacion extends UpdateCheckResult {
  const HayActualizacion(this.info, {required this.buildLocal});
  final UpdateDisponible info;
  final int buildLocal;
}

class ChequeoFallido extends UpdateCheckResult {
  const ChequeoFallido(this.razon);
  final String razon;
}

/// Servicio de auto-actualización (Capa Infra · post-Firebase).
///
/// Decisión: la comparación es por `buildNumber` (int monótono,
/// = `GITHUB_RUN_NUMBER` del workflow que generó el APK). El string
/// `version` es solo para mostrar al usuario en el diálogo.
///
/// Tolerante a fallo: cualquier error en la consulta o el parseo
/// se traduce a `ChequeoFallido`. El caller (UI) lo trata como "no
/// hay update visible ahora" y la app sigue normal.
class UpdateService {
  UpdateService(this._client);
  final MatixClient _client;

  /// Único punto de entrada: lee versión local, consulta al cerebro,
  /// devuelve un `UpdateCheckResult`. Idempotente y barato — se puede
  /// llamar en cada arranque.
  Future<UpdateCheckResult> chequear() async {
    final int buildLocal;
    try {
      final info = await PackageInfo.fromPlatform();
      buildLocal = int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      return ChequeoFallido('No pude leer versión local: $e');
    }

    final Map<String, dynamic> j;
    try {
      j = await _client.getOne('/api/v1/version');
    } catch (e) {
      // Incluye MatixApiException (sin red, sin auth, etc.).
      return ChequeoFallido('No pude consultar al cerebro: $e');
    }

    // Caso "no hay versión publicada todavía".
    if (j['disponible'] == false) {
      return Actualizado(buildLocal);
    }

    try {
      final remote = UpdateDisponible(
        version: j['version'] as String,
        buildNumber: (j['build_number'] as num).toInt(),
        apkUrl: j['apk_url'] as String,
        notas: (j['notas'] as String?) ?? '',
        sha: j['sha'] as String?,
      );
      if (remote.buildNumber > buildLocal) {
        return HayActualizacion(remote, buildLocal: buildLocal);
      }
      return Actualizado(buildLocal);
    } catch (e) {
      return ChequeoFallido('Respuesta inesperada del cerebro: $e');
    }
  }
}
