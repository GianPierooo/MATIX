import '../../../api/matix_client.dart';
import '../../../config.dart';

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

/// Razón por la que falló el chequeo. Categorías diagnósticas para
/// que el UI muestre algo útil en lugar de "Sin conexión" siempre.
enum RazonFallo {
  /// No se pudo contactar al cerebro (sin red, DNS, timeout).
  sinRed,
  /// El cerebro devolvió 401 — la API key embebida no sirve.
  authInvalida,
  /// El cerebro devolvió un código no-200 distinto a 401.
  errorServidor,
  /// La respuesta llegó pero no se pudo parsear (campos faltantes,
  /// tipos inesperados).
  parseo,
  /// Build local no inyectado (typically dev local sin --dart-define).
  /// NO es un fallo real, pero queremos verlo en la UI.
  buildLocalAusente,
  /// Cualquier otra cosa.
  otro,
}

/// Resultado del chequeo de actualización.
sealed class UpdateCheckResult {
  const UpdateCheckResult({required this.buildLocal});

  /// Build local SIEMPRE disponible — incluso cuando el chequeo
  /// remoto falló. La UI lo muestra para que el usuario sepa qué
  /// versión está corriendo.
  final int buildLocal;
}

class Actualizado extends UpdateCheckResult {
  const Actualizado({required super.buildLocal, this.buildRemoto});

  /// Si pudimos leer el build remoto, lo guardamos para mostrar
  /// "estás al día (instalado X / disponible X)". `null` si la
  /// tabla `app_versions` está vacía.
  final int? buildRemoto;
}

class HayActualizacion extends UpdateCheckResult {
  const HayActualizacion({
    required super.buildLocal,
    required this.info,
  });
  final UpdateDisponible info;
}

class ChequeoFallido extends UpdateCheckResult {
  const ChequeoFallido({
    required super.buildLocal,
    required this.razon,
    required this.detalle,
  });
  final RazonFallo razon;
  /// String legible para mostrar al usuario (status code, mensaje
  /// del error, etc.). No se muestra solo — la UI lo combina con
  /// la `razon` que sabe interpretar.
  final String detalle;
}

/// Servicio de auto-actualización.
///
/// Decisión: el build local NO se lee desde `package_info_plus` /
/// el manifest del APK. Se lee desde `MatixConfig.buildNumber` que
/// el workflow CI inyecta vía `--dart-define MATIX_BUILD_NUMBER=$GITHUB_RUN_NUMBER`.
///
/// Por qué: `flutter build --split-per-abi` muta el versionCode del
/// manifest (lo multiplica por 1000 + abi_offset). Eso desincroniza
/// el "build number lógico" (lo que el cerebro conoce) del valor
/// que package_info reportaría. Inyectar el número via dart-define
/// evita ese acoplamiento por completo.
class UpdateService {
  UpdateService(this._client);
  final MatixClient _client;

  Future<UpdateCheckResult> chequear() async {
    final buildLocal = MatixConfig.buildNumber;

    // Si nadie le pasó --dart-define MATIX_BUILD_NUMBER (típico en
    // dev local con `flutter run`), buildLocal queda en 0. No es un
    // bug, pero queremos avisarlo en el UI para evitar confusión.
    // Igual seguimos con el chequeo: el servidor tendrá build > 0
    // y vamos a detectar "update disponible", lo cual también es
    // útil en dev (probás el flujo del diálogo).

    final Map<String, dynamic> j;
    try {
      j = await _client.getOne('/api/v1/version');
    } on MatixApiException catch (e) {
      return ChequeoFallido(
        buildLocal: buildLocal,
        razon: _razonDeStatus(e.statusCode),
        detalle: 'HTTP ${e.statusCode}: ${e.message}',
      );
    } catch (e) {
      return ChequeoFallido(
        buildLocal: buildLocal,
        razon: RazonFallo.sinRed,
        detalle: e.toString(),
      );
    }

    // El cerebro responde {disponible: false} cuando la tabla
    // `app_versions` está vacía. La app lo lee como "no hay update".
    if (j['disponible'] == false) {
      return Actualizado(buildLocal: buildLocal);
    }

    final UpdateDisponible remote;
    try {
      remote = UpdateDisponible(
        version: j['version'] as String,
        buildNumber: (j['build_number'] as num).toInt(),
        apkUrl: j['apk_url'] as String,
        notas: (j['notas'] as String?) ?? '',
        sha: j['sha'] as String?,
      );
    } catch (e) {
      return ChequeoFallido(
        buildLocal: buildLocal,
        razon: RazonFallo.parseo,
        detalle: 'Campos inesperados en /version: $e',
      );
    }

    // Comparación: int > int. El servidor manda `build_number` como
    // num en JSON (Pydantic lo serializa como int), parseamos a int
    // aceptando double por seguridad. No hay caso de string.
    if (remote.buildNumber > buildLocal) {
      return HayActualizacion(buildLocal: buildLocal, info: remote);
    }
    return Actualizado(buildLocal: buildLocal, buildRemoto: remote.buildNumber);
  }

  RazonFallo _razonDeStatus(int code) {
    if (code == 0) return RazonFallo.sinRed;
    if (code == 401 || code == 403) return RazonFallo.authInvalida;
    return RazonFallo.errorServidor;
  }
}
