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
    private val canalDispositivo = "dev.matix.matix/dispositivo"
    private val canalAccesibilidad = "dev.matix.matix/accesibilidad"
    private var channelShare: MethodChannel? = null
    private var channelWake: MethodChannel? = null
    private var channelDispositivo: MethodChannel? = null
    private var channelAccesibilidad: MethodChannel? = null
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
                        DiagLog.log(this, "channel 'iniciar' recibido (umbral=$umbral)")
                        iniciarService(umbral, clf)
                        result.success(true)
                    }
                    "detener" -> {
                        DiagLog.log(this, "channel 'detener' recibido")
                        detenerService()
                        result.success(true)
                    }
                    "pedirIgnorarBateria" -> result.success(pedirIgnorarBateria())
                    "estaIgnorandoBateria" -> result.success(estaIgnorandoBateria())
                    // Full-screen intent: en Android 14+ hace falta el permiso
                    // CONCEDIDO para que el service pueda LANZAR la UI desde
                    // background al detectar (si no, la notificación no auto-abre).
                    "puedeFullScreenIntent" -> result.success(puedeFullScreenIntent())
                    "pedirFullScreenIntent" -> result.success(pedirFullScreenIntent())
                    // Overlay ("mostrar sobre otras apps"): exime del bloqueo de
                    // lanzamiento desde background y, en Honor, habilita las
                    // ventanas emergentes en segundo plano.
                    "puedeOverlay" -> result.success(puedeOverlay())
                    "pedirOverlay" -> result.success(pedirOverlay())
                    // Flutter lo llama al arrancar para saber si debe abrir el
                    // modo de voz (la app la lanzó el wake word). Una sola vez.
                    "consumirAperturaWakeWord" -> {
                        result.success(aperturaWakePendiente)
                        aperturaWakePendiente = false
                    }
                    // OVERLAY del wake word: burbuja flotante encima de otra app
                    // (no la mata). La inteligencia (STT/chat/TTS) la corre Dart;
                    // acá solo pintamos el estado y rebotamos los toques.
                    "overlayMostrar" -> {
                        val ok = VozOverlay.mostrar(
                            this,
                            call.argument<String>("estado") ?: "",
                            onAbrir = {
                                runOnUiThread { channelWake?.invokeMethod("onOverlayAbrir", null) }
                            },
                            onCerrar = {
                                runOnUiThread { channelWake?.invokeMethod("onOverlayCerrar", null) }
                            },
                        )
                        result.success(ok)
                    }
                    "overlayActualizar" -> {
                        VozOverlay.actualizar(call.argument<String>("estado") ?: "")
                        result.success(true)
                    }
                    "overlayOcultar" -> {
                        VozOverlay.ocultar(this)
                        result.success(true)
                    }
                    // Manda Matix al fondo (el juego vuelve al frente con la
                    // burbuja encima). Lo usa el overlay tras tomar el turno por
                    // wake: el FGS trajo la app al frente, la devolvemos atrás.
                    "enviarAlFondo" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    // Trae Matix al frente (el overlay tocó "Abrir" → pantalla
                    // completa). singleTop reusa la instancia viva.
                    "traerAlFrente" -> {
                        val i = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        }
                        startActivity(i)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Acciones de teléfono (Capa 6 · Fase 1): la app EJECUTA el Intent que
        // el cerebro propuso, tras la confirmación del usuario. El cerebro
        // nunca actúa solo. Cada método devuelve true/false (false = ninguna
        // app resolvió el intent → Dart degrada con un aviso).
        channelDispositivo = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalDispositivo).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "redactarMensaje" -> result.success(
                        DispositivoIntents.redactarMensaje(
                            this,
                            call.argument<String>("canal") ?: "",
                            call.argument<String>("destinatario"),
                            call.argument<String>("texto") ?: "",
                            call.argument<String>("asunto"),
                        ),
                    )
                    "iniciarLlamada" -> result.success(
                        DispositivoIntents.iniciarLlamada(
                            this,
                            call.argument<String>("numero") ?: "",
                        ),
                    )
                    "crearEvento" -> result.success(
                        DispositivoIntents.crearEvento(
                            this,
                            call.argument<String>("titulo") ?: "",
                            call.argument<Number>("iniciaEnMillis")?.toLong() ?: 0L,
                            call.argument<Number>("terminaEnMillis")?.toLong(),
                            call.argument<String>("ubicacion"),
                            call.argument<String>("descripcion"),
                        ),
                    )
                    "abrir" -> result.success(
                        DispositivoIntents.abrir(
                            this,
                            call.argument<String>("objetivo") ?: "",
                            call.argument<String>("valor") ?: "",
                        ),
                    )
                    "leerUltimaFoto" -> result.success(
                        DispositivoIntents.leerUltimaFoto(this),
                    )
                    else -> result.notImplemented()
                }
            }
        }

        // Tier C.0 · PERCEPCIÓN (solo lectura): estado del servicio de
        // accesibilidad, deep-link a Ajustes, y captura bajo demanda de la
        // pantalla activa. La captura la hace el servicio (instancia viva); si
        // está apagado, devolvemos null y la app guía al usuario.
        channelAccesibilidad = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalAccesibilidad).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "estaActivo" -> result.success(accesibilidadActiva())
                    "abrirAjustes" -> result.success(abrirAjustesAccesibilidad())
                    "leerPantalla" -> result.success(
                        MatixAccessibilityService.instancia?.capturarJson(),
                    )
                    // Tier C.1 · acción blindada
                    "leerTextoPorId" -> result.success(
                        MatixAccessibilityService.instancia?.leerTextoPorId(
                            call.argument<String>("viewId") ?: "",
                        ),
                    )
                    "ejecutarAccion" -> result.success(
                        MatixAccessibilityService.instancia?.ejecutarAccion(
                            call.argument<String>("accion") ?: "{}",
                        ),
                    )
                    "iniciarFlujo" -> {
                        MatixAccessibilityService.instancia?.iniciarFlujoAccion()
                        result.success(true)
                    }
                    "actualizarFlujo" -> {
                        MatixAccessibilityService.instancia?.actualizarFlujoAccion(
                            call.argument<String>("texto") ?: "",
                        )
                        result.success(true)
                    }
                    "terminarFlujo" -> {
                        MatixAccessibilityService.instancia?.terminarFlujoAccion(
                            call.argument<String>("texto") ?: "",
                        )
                        result.success(true)
                    }
                    "abortar" -> {
                        MatixAccessibilityService.instancia?.abortar()
                        result.success(true)
                    }
                    "estaAbortado" -> result.success(
                        MatixAccessibilityService.instancia?.abortado ?: true,
                    )
                    // Gate de confirmación como overlay sobre WhatsApp. Completa
                    // el result cuando el usuario toca Enviar/Cancelar.
                    "confirmarEnvio" -> OverlayConfirmacion.mostrar(
                        this,
                        call.argument<String>("resumen") ?: "¿Enviar?",
                    ) { decision -> result.success(decision) }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** ¿Está nuestro servicio de accesibilidad habilitado por el usuario? Lo
     *  lee del registro canónico del sistema (no depende de la instancia). */
    private fun accesibilidadActiva(): Boolean {
        val activos = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val componente = "$packageName/$packageName.MatixAccessibilityService"
        val componenteCorto = "$packageName/.MatixAccessibilityService"
        return activos.split(':').any { it.equals(componente, true) || it.equals(componenteCorto, true) }
    }

    /** Abre Ajustes > Accesibilidad para que el usuario active el servicio. */
    private fun abrirAjustesAccesibilidad(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            true
        } catch (_: Exception) {
            false
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
        // En Android 14+ arrancar un FGS de micrófono desde background puede
        // lanzar ForegroundServiceStartNotAllowedException. Lo atrapamos y
        // logueamos para diagnosticar (punto a): si la app ya está exenta de
        // batería suele permitirlo, si no, falla aquí.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            android.util.Log.i("WAKEWORD_BG", "iniciarService OK (umbral=$umbral)")
            DiagLog.log(this, "startForegroundService OK")
        } catch (e: Exception) {
            android.util.Log.e("WAKEWORD_BG", "iniciarService FALLÓ (bg-start restringido?): $e")
            DiagLog.log(this, "startForegroundService FALLÓ: $e")
        }
    }

    private fun detenerService() {
        stopService(Intent(this, WakeWordService::class.java))
    }

    private fun estaIgnorandoBateria(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /** ¿La app puede usar full-screen intents para auto-lanzar UI? Antes de
     * Android 14 (SDK 34) siempre sí; desde 14 requiere permiso especial. */
    private fun puedeFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
            as android.app.NotificationManager
        return nm.canUseFullScreenIntent()
    }

    /** Abre los Ajustes del sistema para que el usuario conceda el full-screen
     * intent (Android 14+). Devuelve true si ya estaba concedido. */
    private fun pedirFullScreenIntent(): Boolean {
        if (puedeFullScreenIntent()) return true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun puedeOverlay(): Boolean = Settings.canDrawOverlays(this)

    /** Abre los Ajustes para conceder "mostrar sobre otras apps". Devuelve true
     * si ya estaba concedido. */
    private fun pedirOverlay(): Boolean {
        if (puedeOverlay()) return true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (_: Exception) {
            false
        }
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
