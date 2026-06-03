package dev.matix.matix

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Gate de confirmación de Tier C.1 como OVERLAY del sistema. Se muestra ENCIMA
 * de WhatsApp (que queda en primer plano), así el tap de enviar actúa sobre la
 * ventana activa. Devuelve la decisión por callback:
 *   "enviar"     → el usuario confirmó (tap explícito en Enviar)
 *   "cancelar"   → el usuario canceló (deja el mensaje escrito, no envía)
 *   "sin_overlay"→ no hay permiso de overlay (la app degrada)
 *
 * No ejecuta ninguna acción de accesibilidad: solo pregunta. El envío real lo
 * hace el bucle tras recibir "enviar".
 */
object OverlayConfirmacion {

    private var vista: View? = null

    fun mostrar(context: Context, resumen: String, onResultado: (String) -> Unit) {
        if (!Settings.canDrawOverlays(context)) {
            onResultado("sin_overlay")
            return
        }
        ocultar(context) // por si quedó una colgada

        val app = context.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = app.resources.displayMetrics.density

        val tarjeta = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt(), (16 * dp).toInt())
            background = GradientDrawable().apply {
                cornerRadius = 18 * dp
                setColor(Color.parseColor("#1E1E1E"))
            }
        }

        tarjeta.addView(TextView(app).apply {
            text = "Confirmar envío"
            setTextColor(Color.WHITE)
            textSize = 18f
            setPadding(0, 0, 0, (10 * dp).toInt())
        })
        tarjeta.addView(TextView(app).apply {
            text = resumen
            setTextColor(Color.parseColor("#DDDDDD"))
            textSize = 15f
            setPadding(0, 0, 0, (18 * dp).toInt())
        })

        val fila = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        fila.addView(Button(app).apply {
            text = "Cancelar"
            setOnClickListener {
                ocultar(app)
                onResultado("cancelar")
            }
        })
        fila.addView(Button(app).apply {
            text = "Enviar"
            setOnClickListener {
                ocultar(app)
                onResultado("enviar")
            }
        })
        tarjeta.addView(fila)

        val contenedor = LinearLayout(app).apply {
            gravity = Gravity.CENTER
            setPadding((24 * dp).toInt(), 0, (24 * dp).toInt(), 0)
            setBackgroundColor(Color.parseColor("#99000000")) // atenúa el fondo
            addView(tarjeta)
        }

        val tipo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            tipo,
            // Focusable (modal) para recibir los taps de los botones; bloquea el
            // fondo a propósito: el usuario debe decidir Enviar o Cancelar.
            0,
            android.graphics.PixelFormat.TRANSLUCENT,
        )

        try {
            wm.addView(contenedor, params)
            vista = contenedor
        } catch (_: Exception) {
            vista = null
            onResultado("sin_overlay")
        }
    }

    fun ocultar(context: Context) {
        val v = vista ?: return
        try {
            val wm = context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(v)
        } catch (_: Exception) {
            // ya removido
        }
        vista = null
    }
}
