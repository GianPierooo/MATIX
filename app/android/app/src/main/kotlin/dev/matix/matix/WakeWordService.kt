package dev.matix.matix

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service de micrófono que escucha el wake word con la app en
 * segundo plano / pantalla apagada / bloqueada.
 *
 * - Captura mic con AudioRecord (16 kHz mono PCM16) en un hilo propio.
 * - Corre la cadena ONNX de openWakeWord en Kotlin (WakeWordOnnx), sin engine
 *   de Flutter.
 * - Notificación persistente "Matix está escuchando" (requisito del foreground
 *   service de micrófono).
 * - WakeLock parcial mientras escucha: la CPU no se duerme con la pantalla
 *   apagada (sin esto, en Doze el bucle de inferencia se congela).
 * - Al detectar: lanza la app por un FULL-SCREEN INTENT (patrón de llamada
 *   entrante), que enciende la pantalla y muestra la Activity sobre el lock.
 * - START_STICKY + onTaskRemoved: si el SO mata el service (típico en
 *   MagicOS/Honor) o el usuario barre la app de recientes, intentamos revivir.
 *
 * DIAGNÓSTICO: todo va logueado al TAG [TAG] con marcas de tiempo de vida del
 * service (heartbeat), score por inferencia (throttle), y los puntos de
 * arranque/parada/recreación, para medir por logcat por qué el background
 * falla en este Honor antes de endurecer.
 */
class WakeWordService : Service() {
    companion object {
        const val EXTRA_UMBRAL = "umbral"
        const val EXTRA_CLASIFICADOR = "clasificador"
        const val EXTRA_ABRIR_WAKEWORD = "abrir_wakeword"

        private const val CANAL_ESCUCHA = "wakeword_escucha"
        private const val CANAL_ALERTA = "wakeword_alerta"
        private const val NOTIF_ESCUCHA = 4711
        private const val NOTIF_ALERTA = 4712
        private const val TAG = "WAKEWORD_BG"
        private const val SR = 16000
        // SharedPreferences nativa donde Dart espeja el umbral del slider.
        const val SP = "matix_wakeword"

        // Fuente de audio. VOICE_RECOGNITION aplica algo de limpieza pensada para
        // ASR; si el score en background queda bajo, se mide MIC/UNPROCESSED (más
        // crudo). Centralizado aquí para cambiarlo en un solo lugar.
        private const val AUDIO_SOURCE = MediaRecorder.AudioSource.VOICE_RECOGNITION
    }

    @Volatile private var corriendo = false
    private var hilo: Thread? = null
    private var umbralActual = 0.30
    private var wakeLock: PowerManager.WakeLock? = null
    private var arranqueMs = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Diagnóstico de recreación: intent nulo ⇒ lo recreó el SO (START_STICKY)
        // tras matarlo. Lo logueamos para medir cada cuánto pasa en este Honor.
        val recreado = intent == null
        Log.i(TAG, "onStartCommand recreado=$recreado flags=$flags startId=$startId")
        DiagLog.log(this, "onStartCommand recreado=$recreado flags=$flags")

        // UNA fuente de verdad del umbral: el valor del slider, que Dart espeja a
        // esta SharedPreferences nativa. Si el SO recrea el service con intent
        // nulo, igual leemos el último valor de aquí.
        val sp = getSharedPreferences(SP, Context.MODE_PRIVATE)
        val umbral = if (intent != null && intent.hasExtra(EXTRA_UMBRAL)) {
            intent.getDoubleExtra(EXTRA_UMBRAL, 0.30)
        } else {
            sp.getFloat("umbral", 0.30f).toDouble()
        }
        val clf = intent?.getStringExtra(EXTRA_CLASIFICADOR)
            ?: sp.getString("clasificador", null) ?: "oye_matix.onnx"
        umbralActual = umbral
        crearCanales()

        // startForeground con el type de micrófono (obligatorio en Android 10+).
        // En Android 14+ esto puede lanzar ForegroundServiceStartNotAllowed o
        // SecurityException si el arranque vino de background sin exención: lo
        // atrapamos y logueamos para diagnosticar el punto (a).
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ESCUCHA, notifEscucha(0.0, 0.0, umbral),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIF_ESCUCHA, notifEscucha(0.0, 0.0, umbral))
            }
            Log.i(TAG, "startForeground OK (umbral=$umbral, clf=$clf)")
            DiagLog.log(this, "startForeground OK (clf=$clf)")
        } catch (e: Exception) {
            // No pudimos volvernos foreground: típico de bg-start restringido en
            // Android 14+. Logueamos y abortamos limpio (no dejamos hilo huérfano).
            Log.e(TAG, "startForeground FALLÓ: $e")
            DiagLog.log(this, "startForeground FALLÓ: $e")
            stopSelf()
            return START_NOT_STICKY
        }

        adquirirWakeLock()

        if (!corriendo) {
            corriendo = true
            arranqueMs = SystemClock.elapsedRealtime()
            hilo = Thread { bucle(umbral, clf) }.apply { start() }
            Log.i(TAG, "service arrancado (umbral=$umbral)")
        } else {
            Log.i(TAG, "onStartCommand: ya estaba corriendo, no relanzo hilo")
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // El usuario barrió la app de recientes. En muchos OEM esto MATA los
        // services del proceso. Pedimos al SO que nos reprograme con el mismo
        // intent (algunos lo respetan; en otros START_STICKY ya lo cubre).
        Log.w(TAG, "onTaskRemoved (app barrida de recientes)")
        DiagLog.log(this, "onTaskRemoved (app barrida)")
        try {
            val reinicio = Intent(applicationContext, WakeWordService::class.java).apply {
                putExtra(EXTRA_UMBRAL, umbralActual)
            }
            val pi = PendingIntent.getService(
                this, 1, reinicio,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
            )
            val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            am.set(
                android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 1000,
                pi,
            )
            Log.i(TAG, "onTaskRemoved: reinicio programado en 1s")
        } catch (e: Exception) {
            Log.e(TAG, "onTaskRemoved: no pude programar reinicio: $e")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val vividoS = if (arranqueMs > 0) (SystemClock.elapsedRealtime() - arranqueMs) / 1000 else 0
        Log.w(TAG, "onDestroy (el service vivió ${vividoS}s)")
        DiagLog.log(this, "onDestroy (vivió ${vividoS}s)")
        corriendo = false
        try { hilo?.join(800) } catch (_: InterruptedException) {}
        hilo = null
        liberarWakeLock()
        super.onDestroy()
    }

    private fun adquirirWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "matix:wakeword").apply {
                setReferenceCounted(false)
                acquire(60 * 60 * 1000L) // tope de seguridad: 1 h, se renueva al re-arrancar
            }
            Log.i(TAG, "WakeLock adquirido")
        } catch (e: Exception) {
            Log.e(TAG, "no pude adquirir WakeLock: $e")
        }
    }

    private fun liberarWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.i(TAG, "WakeLock liberado")
            }
        } catch (e: Exception) {
            Log.e(TAG, "error liberando WakeLock: $e")
        }
        wakeLock = null
    }

    private fun bucle(umbral: Double, clf: String) {
        var rec: AudioRecord? = null
        var onnx: WakeWordOnnx? = null
        try {
            onnx = WakeWordOnnx(assets, clf).also { it.umbral = umbral }
            Log.i(TAG, "modelos ONNX cargados (clf=$clf)")
            val minBuf = AudioRecord.getMinBufferSize(
                SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufSize = maxOf(minBuf, WakeWordOnnx.BLOQUE * 2 * 4)
            Log.i(TAG, "AudioRecord src=$AUDIO_SOURCE minBuf=$minBuf bufSize=$bufSize")
            rec = AudioRecord(
                AUDIO_SOURCE, SR,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize,
            )
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord NO se inicializó (state=${rec.state}; ¿permiso de micro?)")
                DiagLog.log(this, "AudioRecord NO init (state=${rec.state})")
                return
            }
            rec.startRecording()
            Log.i(TAG, "AudioRecord grabando (recordingState=${rec.recordingState})")
            DiagLog.log(this, "AudioRecord grabando (recState=${rec.recordingState}, src=$AUDIO_SOURCE)")

            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val pend = ArrayList<Short>(WakeWordOnnx.BLOQUE * 2)
            val buf = ShortArray(WakeWordOnnx.BLOQUE)
            var primero = true
            var maxScore = 0.0
            var ultimoScore = 0.0
            var ultimaNotif = 0L
            var ultimoHeartbeat = 0L
            var ultimoHeartbeatArchivo = 0L
            var lotes = 0L
            var framesLeidos = 0L
            while (corriendo) {
                val n = rec.read(buf, 0, buf.size)
                if (n < 0) {
                    // Error de lectura (mic robado por otra app, o SO restringió).
                    Log.e(TAG, "AudioRecord.read devolvió $n (mic perdido) — corto bucle")
                    DiagLog.log(this, "AudioRecord.read=$n (mic perdido) — corto")
                    break
                }
                if (n == 0) continue
                framesLeidos += n
                if (primero) {
                    primero = false
                    Log.i(TAG, "primer audio ($n muestras)")
                    DiagLog.log(this, "primer audio ($n muestras)")
                }
                for (i in 0 until n) pend.add(buf[i])
                while (pend.size >= WakeWordOnnx.BLOQUE) {
                    val bloque = ShortArray(WakeWordOnnx.BLOQUE) { pend[it] }
                    pend.subList(0, WakeWordOnnx.BLOQUE).clear()
                    val det = onnx.procesarBloque(bloque)
                    lotes++
                    ultimoScore = onnx.ultimoScore
                    if (ultimoScore > maxScore) maxScore = ultimoScore
                    if (det) {
                        Log.i(TAG, "DETECTADO en background (score=${"%.3f".format(ultimoScore)})")
                        DiagLog.log(this, "DETECTADO (score=${"%.3f".format(ultimoScore)})")
                        dispararAlerta()
                        pend.clear()
                        maxScore = 0.0
                    }
                }
                val ahora = System.currentTimeMillis()
                // Heartbeat de diagnóstico cada ~3 s: confirma que el bucle sigue
                // vivo con la pantalla apagada, y muestra el score que se ve en bg.
                if (ahora - ultimoHeartbeat > 3000) {
                    ultimoHeartbeat = ahora
                    val vividoS = (SystemClock.elapsedRealtime() - arranqueMs) / 1000
                    val hb = "vivo ${vividoS}s lotes=$lotes score=${"%.3f".format(ultimoScore)} " +
                        "max=${"%.3f".format(maxScore)} umbral=${"%.2f".format(umbralActual)} " +
                        "wl=${wakeLock?.isHeld}"
                    Log.i(TAG, "❤ $hb")
                    // Al archivo solo cada ~30 s (evita I/O constante en producción;
                    // basta para ver supervivencia a los minutos 1, 5, 30…).
                    if (ahora - ultimoHeartbeatArchivo > 30000) {
                        ultimoHeartbeatArchivo = ahora
                        DiagLog.log(this, "❤ $hb")
                    }
                }
                // Readout en la notificación ~cada 1.2 s.
                if (ahora - ultimaNotif > 1200) {
                    ultimaNotif = ahora
                    nm.notify(NOTIF_ESCUCHA, notifEscucha(maxScore, ultimoScore, umbral))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "bucle error: $e")
        } finally {
            try { rec?.stop() } catch (_: Exception) {}
            try { rec?.release() } catch (_: Exception) {}
            onnx?.cerrar()
            Log.i(TAG, "bucle terminado (corriendo=$corriendo)")
        }
    }

    /** Lanza el modo de voz por full-screen intent (enciende pantalla + sobre
     * el lock) y, best-effort, también intenta abrir la Activity directo. */
    private fun dispararAlerta() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_ABRIR_WAKEWORD, true)
        }
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notif = NotificationCompat.Builder(this, CANAL_ALERTA)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Matix")
            .setContentText("Te escucho — abriendo el modo de voz…")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(pi, true)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setTimeoutAfter(8000)
            .build()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ALERTA, notif)
        // Diagnóstico del LANZAMIENTO desde background (lo que falla en Honor):
        // ¿está concedido el full-screen intent (Android 14+)? ¿overlay?
        val fsi = if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else true
        val overlay = android.provider.Settings.canDrawOverlays(this)
        DiagLog.log(this, "dispararAlerta · canUseFSI=$fsi · overlay=$overlay")
        // Lanzamiento directo: restringido desde background en Android 10+, salvo
        // exenciones (overlay concedido). Con overlay suele funcionar; sin él
        // queda el full-screen intent (que requiere su permiso). Logueamos el
        // resultado para saber qué vía abrió.
        try {
            startActivity(intent)
            DiagLog.log(this, "startActivity OK")
        } catch (e: Exception) {
            Log.w(TAG, "startActivity directo falló: $e")
            DiagLog.log(this, "startActivity FALLÓ: ${e.javaClass.simpleName}")
        }
    }

    private fun crearCanales() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CANAL_ESCUCHA, "Escucha en segundo plano",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Matix escuchando la palabra de activación" },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CANAL_ALERTA, "Activación por voz",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Abre el modo de voz al oír la palabra"
                setBypassDnd(true)
            },
        )
    }

    private fun notifEscucha(maxScore: Double, ahora: Double, umbral: Double): Notification {
        val abrir = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(
            this, 1, abrir, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val texto = "score máx ${fmt(maxScore)} (ahora ${fmt(ahora)}) · umbral ${fmt(umbral)}"
        return NotificationCompat.Builder(this, CANAL_ESCUCHA)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Matix está escuchando")
            .setContentText(texto)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$texto\nDi la palabra para abrir el modo de voz."))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pi)
            .build()
    }

    private fun fmt(x: Double): String = String.format(java.util.Locale.US, "%.2f", x)
}
