/// Configuración inyectada en tiempo de compilación vía `--dart-define`.
///
/// Hay dos perfiles típicos:
///
/// **Debug local** — el cerebro corre en la PC, la app se conecta vía
/// `adb reverse` o `10.0.2.2` (emulador):
/// ```powershell
/// flutter run `
///   --dart-define MATIX_API_URL=http://localhost:8000 `
///   --dart-define MATIX_API_KEY=<el de cerebro/.env> `
///   --dart-define MATIX_ENV=dev
/// ```
///
/// **Release prod (post-despliegue Capa 2)** — el cerebro corre en
/// Railway con HTTPS:
/// ```powershell
/// flutter build apk --release `
///   --dart-define MATIX_API_URL=https://<tu-proyecto>.up.railway.app `
///   --dart-define MATIX_API_KEY=<la nueva MATIX_API_KEY> `
///   --dart-define MATIX_ENV=prod
/// ```
///
/// El valor por defecto apunta a la PC desde un emulador Android
/// (`10.0.2.2`) — útil cuando alguien tira `flutter run` sin args.
/// Para producción SIEMPRE hay que pasar `--dart-define MATIX_API_URL`.
class MatixConfig {
  const MatixConfig._();

  static const String apiUrl = String.fromEnvironment(
    'MATIX_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String apiKey = String.fromEnvironment('MATIX_API_KEY');

  static const String env = String.fromEnvironment(
    'MATIX_ENV',
    defaultValue: 'dev',
  );

  /// Build number inyectado en compile-time por el workflow CI
  /// (= `GITHUB_RUN_NUMBER`). Monótono creciente.
  ///
  /// NO se usa el `versionCode` del AndroidManifest porque
  /// `flutter build --split-per-abi` lo multiplica por una constante
  /// (versionCode = base * 1000 + abi_offset) para diferenciar
  /// APKs por ABI. Eso hace que `package_info_plus.buildNumber` no
  /// se corresponda con el build "lógico" que conoce el cerebro,
  /// y rompe la comparación al chequear updates.
  ///
  /// Default 0 cuando se buildea sin pasar el define (dev local),
  /// lo que hace que cualquier versión publicada del servidor se
  /// detecte como "nueva" en builds locales — comportamiento OK
  /// para desarrollo.
  static const int buildNumber = int.fromEnvironment(
    'MATIX_BUILD_NUMBER',
    defaultValue: 0,
  );

  static bool get hasApiKey => apiKey.isNotEmpty;

  /// `true` si la URL configurada es HTTPS (i.e. estamos hablando con
  /// el cerebro en la nube). Útil para decidir si mostrar el banner
  /// "dev" / "prod" en la UI, o para no aplicar tweaks de cleartext.
  static bool get esProd => apiUrl.startsWith('https://');
}
