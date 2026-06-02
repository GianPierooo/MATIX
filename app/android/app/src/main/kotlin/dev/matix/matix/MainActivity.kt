package dev.matix.matix

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Compartir-a-Matix (Capa 7): MainActivity recibe el intent ACTION_SEND
 * de texto/URL (declarado en el manifest) y se lo pasa a Flutter por un
 * MethodChannel. Dos casos:
 *
 *  - App CERRADA al compartir: el intent llega en `configureFlutterEngine`.
 *    Lo guardamos y Flutter lo pide con `getInitialSharedText` (se consume
 *    una sola vez).
 *  - App ABIERTA (singleTop): el intent llega en `onNewIntent`; lo
 *    empujamos a Flutter invocando `onSharedText`.
 *
 * Solo `text/plain`. Las URLs vienen como texto en EXTRA_TEXT.
 *
 * Wake word en segundo plano (Capa 2): un segundo MethodChannel
 * (`wakeword_bg`) controla el foreground service [WakeWordService]
 * (iniciar/detener), pide la excepción de batería, y entrega a Flutter la
 * señal de "abrir modo de voz" cuando el service lanzó la app al detectar la
 * palabra (full-screen intent).
 */
class MainActivity : FlutterActivity() {
    private val canalShare = "dev.matix.matix/share"
    private val canalWake = "dev.matix.matix/wakeword_bg"
    private var channelShare: MethodChannel? = null
    private var channelWake: MethodChannel? = null
    private var textoInicialCompartido: String? = null
    private var aperturaWakePendiente = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Texto compartido que ARRANCÓ la app (compartir con la app cerrada).
        textoInicialCompartido = extraerTextoCompartido(intent)
        if (textoInicialCompartido != null) consumirIntent()
        // ¿La app la lanzó el service del wake word (detección en background)?
        if (intent?.getBooleanExtra(WakeWordService.EXTRA_ABRIR_WAKEWORD, false) == true) {
            aperturaWakePendiente = true
            consumirIntent()
        }

        channelShare = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalShare).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedText" -> {
                        result.success(textoInicialCompartido)
                        textoInicialCompartido = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        channelWake = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalWake).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "iniciar" -> {
                        val umbral = call.argument<Double>("umbral") ?: 0.30
                        val clf = call.argument<String>("clasificador") ?: "oye_matix.onnx"
                        iniciarService(umbral, clf)
                        result.success(true)
                    }
                    "detener" -> {
                        detenerService()
                        result.success(true)
                    }
                    "pedirIgnorarBateria" -> result.success(pedirIgnorarBateria())
                    "estaIgnorandoBateria" -> result.success(estaIgnorandoBateria())
                    // Flutter lo llama al arrancar para saber si debe abrir el
                    // modo de voz (la app la lanzó el wake word). Una sola vez.
                    "consumirAperturaWakeWord" -> {
                        result.success(aperturaWakePendiente)
                        aperturaWakePendiente = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val texto = extraerTextoCompartido(intent)
        if (texto != null) {
            channelShare?.invokeMethod("onSharedText", texto)
            consumirIntent()
            return
        }
        // App ya abierta y el service la trajo al frente por detección.
        if (intent.getBooleanExtra(WakeWordService.EXTRA_ABRIR_WAKEWORD, false)) {
            channelWake?.invokeMethod("onWakeWordBackground", null)
            consumirIntent()
        }
    }

    private fun iniciarService(umbral: Double, clf: String) {
        // Espejamos el umbral del slider a la SharedPreferences nativa que lee
        // el service: así, aunque el SO recree el service (START_STICKY) con
        // intent nulo, usa el MISMO umbral que el pipeline Dart. Fuente única.
        getSharedPreferences(WakeWordService.SP, Context.MODE_PRIVATE).edit()
            .putFloat("umbral", umbral.toFloat())
            .putString("clasificador", clf)
            .apply()
        val intent = Intent(this, WakeWordService::class.java).apply {
            putExtra(WakeWordService.EXTRA_UMBRAL, umbral)
            putExtra(WakeWordService.EXTRA_CLASIFICADOR, clf)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun detenerService() {
        stopService(Intent(this, WakeWordService::class.java))
    }

    private fun estaIgnorandoBateria(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun pedirIgnorarBateria(): Boolean {
        if (estaIgnorandoBateria()) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            // Si el OEM no expone el diálogo directo, abrimos los ajustes.
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun consumirIntent() {
        val limpio = Intent(Intent.ACTION_MAIN)
        limpio.setPackage(packageName)
        setIntent(limpio)
    }

    private fun extraerTextoCompartido(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        val tipo = intent.type ?: return null
        if (!tipo.startsWith("text/")) return null
        val texto = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        return if (texto.isNullOrEmpty()) null else texto
    }
}
