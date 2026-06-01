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
 * - Al detectar: lanza la app por un FULL-SCREEN INTENT (patrón de llamada
 *   entrante), que enciende la pantalla y muestra la Activity sobre el lock —
 *   la vía soportada para lanzar UI desde background en Android 10+.
 * - START_STICKY: si el SO mata el service (típico en MagicOS/Honor), Android
 *   intenta recrearlo.
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
    }

    @Volatile private var corriendo = false
    private var hilo: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val umbral = intent?.getDoubleExtra(EXTRA_UMBRAL, 0.30) ?: 0.30
        val clf = intent?.getStringExtra(EXTRA_CLASIFICADOR) ?: "hey_jarvis_v0.1.onnx"
        crearCanales()
        // startForeground con el type de micrófono (obligatorio en Android 10+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ESCUCHA, notifEscucha(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIF_ESCUCHA, notifEscucha())
        }
        if (!corriendo) {
            corriendo = true
            hilo = Thread { bucle(umbral, clf) }.apply { start() }
            Log.i(TAG, "service arrancado (umbral=$umbral)")
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "service onDestroy")
        corriendo = false
        try { hilo?.join(800) } catch (_: InterruptedException) {}
        hilo = null
        super.onDestroy()
    }

    private fun bucle(umbral: Double, clf: String) {
        var rec: AudioRecord? = null
        var onnx: WakeWordOnnx? = null
        try {
            onnx = WakeWordOnnx(assets, clf).also { it.umbral = umbral }
            Log.i(TAG, "modelos ONNX cargados")
            val minBuf = AudioRecord.getMinBufferSize(
                SR, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            )
            val bufSize = maxOf(minBuf, WakeWordOnnx.BLOQUE * 2 * 4)
            rec = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, SR,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize,
            )
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord no se inicializó (¿permiso de micro?)")
                return
            }
            rec.startRecording()
            Log.i(TAG, "AudioRecord grabando")

            val pend = ArrayList<Short>(WakeWordOnnx.BLOQUE * 2)
            val buf = ShortArray(WakeWordOnnx.BLOQUE)
            var primero = true
            while (corriendo) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                if (primero) { primero = false; Log.i(TAG, "primer audio ($n muestras)") }
                for (i in 0 until n) pend.add(buf[i])
                while (pend.size >= WakeWordOnnx.BLOQUE) {
                    val bloque = ShortArray(WakeWordOnnx.BLOQUE) { pend[it] }
                    pend.subList(0, WakeWordOnnx.BLOQUE).clear()
                    if (onnx.procesarBloque(bloque)) {
                        Log.i(TAG, "DETECTADO en background (score=${onnx.ultimoScore})")
                        dispararAlerta()
                        // Refractario del pipeline ya evita re-disparo inmediato;
                        // además limpiamos el pendiente para no encolar audio.
                        pend.clear()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "bucle error: $e")
        } finally {
            try { rec?.stop() } catch (_: Exception) {}
            try { rec?.release() } catch (_: Exception) {}
            onnx?.cerrar()
            Log.i(TAG, "bucle terminado")
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
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ALERTA, notif)
        // Algunos OEM permiten el lanzamiento directo desde el foreground
        // service; lo intentamos como complemento (si falla, queda el FSI).
        try { startActivity(intent) } catch (e: Exception) { Log.w(TAG, "startActivity directo falló: $e") }
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

    private fun notifEscucha(): Notification {
        val abrir = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(
            this, 1, abrir, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CANAL_ESCUCHA)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Matix está escuchando")
            .setContentText("Di \"hey jarvis\" para abrir el modo de voz")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }
}
