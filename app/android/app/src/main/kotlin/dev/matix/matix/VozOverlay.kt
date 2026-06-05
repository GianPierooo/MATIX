package dev.matix.matix

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Overlay flotante del WAKE WORD: cuando "Oye Matix" se dispara y hay OTRA app
 * en primer plano (un juego), Matix NO toma la pantalla completa — muestra esta
 * burbuja ENCIMA, sin matar la app de atrás. La burbuja:
 *   - Muestra el estado del turno de voz (escuchando / pensando / hablando).
 *   - Tiene dos toques: "Abrir" (expandir a Matix completo) y "Cerrar" (terminar).
 *   - NO es modal: el juego sigue recibiendo el touch fuera de la burbuja
 *     (FLAG_NOT_TOUCH_MODAL) y conserva el foco de teclado (FLAG_NOT_FOCUSABLE).
 *   - No es persistente: sube al wake (`mostrar`) y baja al cerrar (`ocultar`).
 *
 * Espeja el patrón probado de OverlayConfirmacion (mismo TYPE_APPLICATION_OVERLAY
 * y WindowManager). La INTELIGENCIA (STT/chat/TTS) NO vive acá: este overlay solo
 * pinta el estado y rebota los toques a Dart por callbacks.
 */
object VozOverlay {

    private var vista: View? = null
    private var lblEstado: TextView? = null

    /** ¿Hay permiso "mostrar sobre otras apps"? Si no, el caller degrada. */
    fun puede(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** Muestra la burbuja. `onAbrir` = expandir a Matix completo; `onCerrar` =
     *  terminar la sesión. Devuelve true si se mostró (false = sin permiso). */
    fun mostrar(
        context: Context,
        estadoInicial: String,
        onAbrir: () -> Unit,
        onCerrar: () -> Unit,
    ): Boolean {
        if (!puede(context)) return false
        ocultar(context) // por si quedó una colgada

        val app = context.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = app.resources.displayMetrics.density

        val tarjeta = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (10 * dp).toInt(), (10 * dp).toInt())
            background = GradientDrawable().apply {
                cornerRadius = 22 * dp
                setColor(Color.parseColor("#1B2138")) // MatixColors.cardHi
                setStroke((1 * dp).toInt(), Color.parseColor("#662D7FF9"))
            }
        }

        // Puntito "Matix" (avatar minimal) — accent.
        tarjeta.addView(View(app).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2D7FF9"))
            }
            layoutParams = LinearLayout.LayoutParams((14 * dp).toInt(), (14 * dp).toInt()).apply {
                rightMargin = (10 * dp).toInt()
            }
        })

        lblEstado = TextView(app).apply {
            text = etiqueta(estadoInicial)
            setTextColor(Color.parseColor("#E8ECF4")) // MatixColors.text
            textSize = 13.5f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        tarjeta.addView(lblEstado)

        tarjeta.addView(boton(app, dp, "Abrir") {
            ocultar(app)
            onAbrir()
        })
        tarjeta.addView(boton(app, dp, "Cerrar") {
            ocultar(app)
            onCerrar()
        })

        val tipo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            tipo,
            // NO modal: el juego de atrás conserva foco de teclado y los toques
            // FUERA de la burbuja le llegan. Los botones SÍ reciben sus taps.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = (90 * dp).toInt()
        }

        return try {
            wm.addView(tarjeta, params)
            vista = tarjeta
            true
        } catch (_: Exception) {
            vista = null
            false
        }
    }

    /** Cambia el texto de estado (escuchando / pensando / hablando). */
    fun actualizar(estado: String) {
        lblEstado?.post { lblEstado?.text = etiqueta(estado) }
    }

    fun ocultar(context: Context) {
        val v = vista ?: return
        try {
            val wm = context.applicationContext
                .getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(v)
        } catch (_: Exception) {
            // ya removido
        }
        vista = null
        lblEstado = null
    }

    private fun etiqueta(estado: String): String = when (estado) {
        "escuchando" -> "Te escucho…"
        "pensando" -> "Pensando…"
        "hablando" -> "Matix"
        else -> "Hola, dime"
    }

    private fun boton(
        context: Context,
        dp: Float,
        texto: String,
        onTap: () -> Unit,
    ): TextView = TextView(context).apply {
        text = texto
        setTextColor(Color.parseColor("#2D7FF9"))
        textSize = 12.5f
        setPadding((12 * dp).toInt(), (8 * dp).toInt(), (12 * dp).toInt(), (8 * dp).toInt())
        setOnClickListener { onTap() }
    }
}
