package dev.matix.matix

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Log de diagnóstico a ARCHIVO para el wake word en segundo plano.
 *
 * Este Honor (MagicOS) CIFRA/filtra logcat para apps de terceros, así que los
 * `Log.i` no se ven por `adb logcat`. Escribimos en
 * `filesDir/wakeword_native.log`, legible por `adb run-as` en builds debug, para
 * poder medir arranque/parada/recreación/score del FGS sin depender de logcat.
 *
 * NUNCA escribir datos personales: solo pasos, tiempos, scores y errores.
 */
object DiagLog {
    private const val ARCHIVO = "wakeword_native.log"
    private const val MAX_BYTES = 64 * 1024
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    @Synchronized
    fun log(ctx: Context, msg: String) {
        try {
            val f = File(ctx.filesDir, ARCHIVO)
            if (f.length() > MAX_BYTES) f.writeText("")
            f.appendText("${fmt.format(Date())}  $msg\n")
        } catch (_: Exception) {
            // El log de diagnóstico nunca debe romper el flujo.
        }
    }
}
