package dev.matix.matix

import android.content.Intent
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
 */
class MainActivity : FlutterActivity() {
    private val canal = "dev.matix.matix/share"
    private var channel: MethodChannel? = null
    private var textoInicialCompartido: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Captura el texto del intent que ARRANCÓ la app (compartir con
        // la app cerrada), antes de que Flutter lo pida.
        textoInicialCompartido = extraerTextoCompartido(intent)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedText" -> {
                        result.success(textoInicialCompartido)
                        // Se consume una sola vez: en un hot-restart o
                        // segunda llamada no queremos re-capturarlo.
                        textoInicialCompartido = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Mantener el intent vigente como el actual de la Activity.
        setIntent(intent)
        val texto = extraerTextoCompartido(intent)
        if (texto != null) {
            channel?.invokeMethod("onSharedText", texto)
        }
    }

    /** Devuelve el texto compartido si el intent es un ACTION_SEND de
     * texto; null en cualquier otro caso (ej. el MAIN del launcher). */
    private fun extraerTextoCompartido(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        val tipo = intent.type ?: return null
        if (!tipo.startsWith("text/")) return null
        val texto = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        return if (texto.isNullOrEmpty()) null else texto
    }
}
