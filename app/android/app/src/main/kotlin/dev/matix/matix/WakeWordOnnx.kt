package dev.matix.matix

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.res.AssetManager
import java.nio.FloatBuffer

/**
 * Cadena de openWakeWord en Kotlin para el foreground service (escucha en
 * segundo plano). Es el espejo de `WakeWordPipeline.dart`:
 *
 *  - audio en bloques de 1280 muestras (80 ms @ 16 kHz),
 *  - melspectrograma -> buffer rodante (init 76 frames de unos),
 *  - ventana de 76 frames mel -> embedding (96),
 *  - clasificador sobre los últimos 16 embeddings -> probabilidad,
 *  - umbral + refractario tras disparo.
 *
 * Usa la API Java de ONNX Runtime (`ai.onnxruntime.*`) directamente, NO
 * flutter_onnxruntime: el service es 100% nativo y no necesita el engine de
 * Flutter vivo. Alimenta los valores int16 como float SIN normalizar (como
 * espera openWakeWord) y aplica x/10+2 al melspectrograma.
 */
class WakeWordOnnx(assets: AssetManager, clasificadorArchivo: String) {
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val melSes: OrtSession
    private val embSes: OrtSession
    private val clfSes: OrtSession

    companion object {
        const val BLOQUE = 1280
        const val BINS = 32
        const val VENTANA_MEL = 76
        const val VENTANA_FEAT = 16
        const val DIM_EMB = 96
        private const val CONTEXTO = 160 * 3
        private const val MAX_RAW = BLOQUE + CONTEXTO // 1760
        private const val MAX_MEL = 970
        private const val MAX_FEAT = 120
        // Los .onnx son assets de Flutter; en el APK viven bajo flutter_assets/.
        private const val DIR = "flutter_assets/assets/models/wakeword"
    }

    init {
        val opts = OrtSession.SessionOptions()
        opts.setIntraOpNumThreads(1)
        melSes = env.createSession(leerAsset(assets, "$DIR/melspectrogram.onnx"), opts)
        embSes = env.createSession(leerAsset(assets, "$DIR/embedding_model.onnx"), opts)
        clfSes = env.createSession(leerAsset(assets, "$DIR/$clasificadorArchivo"), opts)
    }

    private fun leerAsset(assets: AssetManager, ruta: String): ByteArray =
        assets.open(ruta).use { it.readBytes() }

    // ── Estado del pipeline ───────────────────────────────────────────
    private val raw = ArrayList<Float>(MAX_RAW + BLOQUE)
    private val mel = ArrayList<FloatArray>(MAX_MEL + 16)
    private val features = ArrayList<FloatArray>(MAX_FEAT + 2)
    private var refractario = 0
    private var iniciado = false

    @Volatile var umbral: Double = 0.30
    @Volatile var ultimoScore: Double = 0.0
        private set

    private fun asegurarInit() {
        if (iniciado) return
        repeat(VENTANA_MEL) { mel.add(FloatArray(BINS) { 1.0f }) }
        iniciado = true
    }

    fun reiniciar() {
        raw.clear(); mel.clear(); features.clear()
        refractario = 0; ultimoScore = 0.0; iniciado = false
    }

    /** Procesa un bloque de exactamente 1280 muestras int16. true si detectó. */
    fun procesarBloque(bloque: ShortArray): Boolean {
        asegurarInit()
        for (s in bloque) raw.add(s.toFloat())
        if (raw.size > MAX_RAW) raw.subList(0, raw.size - MAX_RAW).clear()

        val frames = melspec(FloatArray(raw.size) { raw[it] })
        mel.addAll(frames)
        if (mel.size > MAX_MEL) mel.subList(0, mel.size - MAX_MEL).clear()

        if (mel.size >= VENTANA_MEL) {
            val ventana = mel.subList(mel.size - VENTANA_MEL, mel.size)
            features.add(embedding(ventana))
            if (features.size > MAX_FEAT) features.subList(0, features.size - MAX_FEAT).clear()
        }

        if (refractario > 0) { refractario--; return false }
        if (features.size >= VENTANA_FEAT) {
            val ventana = features.subList(features.size - VENTANA_FEAT, features.size)
            ultimoScore = clasificar(ventana).toDouble()
            if (ultimoScore >= umbral) {
                refractario = VENTANA_FEAT // ~1.3 s
                features.clear()
                return true
            }
        }
        return false
    }

    private fun melspec(muestras: FloatArray): List<FloatArray> {
        OnnxTensor.createTensor(env, FloatBuffer.wrap(muestras), longArrayOf(1, muestras.size.toLong())).use { t ->
            melSes.run(mapOf(melSes.inputNames.first() to t)).use { res ->
                val plano = aplanar(res[0].value)
                val frames = ArrayList<FloatArray>(plano.size / BINS)
                var i = 0
                while (i + BINS <= plano.size) {
                    val f = FloatArray(BINS) { j -> plano[i + j] / 10.0f + 2.0f }
                    frames.add(f); i += BINS
                }
                return frames
            }
        }
    }

    private fun embedding(ventana: List<FloatArray>): FloatArray {
        val plano = FloatArray(VENTANA_MEL * BINS)
        for (i in 0 until VENTANA_MEL) for (j in 0 until BINS) plano[i * BINS + j] = ventana[i][j]
        OnnxTensor.createTensor(env, FloatBuffer.wrap(plano), longArrayOf(1, VENTANA_MEL.toLong(), BINS.toLong(), 1)).use { t ->
            embSes.run(mapOf(embSes.inputNames.first() to t)).use { res ->
                return aplanar(res[0].value)
            }
        }
    }

    private fun clasificar(ventana: List<FloatArray>): Float {
        val plano = FloatArray(VENTANA_FEAT * DIM_EMB)
        for (i in 0 until VENTANA_FEAT) for (j in 0 until DIM_EMB) plano[i * DIM_EMB + j] = ventana[i][j]
        OnnxTensor.createTensor(env, FloatBuffer.wrap(plano), longArrayOf(1, VENTANA_FEAT.toLong(), DIM_EMB.toLong())).use { t ->
            clfSes.run(mapOf(clfSes.inputNames.first() to t)).use { res ->
                val plano2 = aplanar(res[0].value)
                return if (plano2.isEmpty()) 0f else plano2[0]
            }
        }
    }

    /** Aplana el valor de un OnnxTensor (arrays anidados) a un FloatArray, en
     * orden row-major. */
    private fun aplanar(v: Any?): FloatArray {
        val out = ArrayList<Float>()
        fun rec(o: Any?) {
            when (o) {
                is FloatArray -> for (x in o) out.add(x)
                is Array<*> -> for (e in o) rec(e)
                is Float -> out.add(o)
            }
        }
        rec(v)
        return FloatArray(out.size) { out[it] }
    }

    fun cerrar() {
        try { melSes.close() } catch (_: Exception) {}
        try { embSes.close() } catch (_: Exception) {}
        try { clfSes.close() } catch (_: Exception) {}
    }
}
