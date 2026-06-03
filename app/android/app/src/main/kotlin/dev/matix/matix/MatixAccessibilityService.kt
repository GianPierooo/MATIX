package dev.matix.matix

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

/**
 * Tier C.0 — PERCEPCIÓN (solo lectura). Lee el árbol de la ventana activa
 * BAJO DEMANDA y lo entrega aplanado a un JSON compacto para que Matix lo use
 * como DATO. Nada de streaming continuo: solo captura cuando la app lo pide.
 *
 * READ-ONLY POR DISEÑO: este servicio NO tiene ninguna ruta de código que
 * ejecute acciones. No llama performAction, performGlobalAction ni
 * dispatchGesture. Solo lee.
 *
 * Gotcha del foreground (resuelto): cuando el usuario le pide a Matix «léeme la
 * pantalla», la ventana activa suele ser la PROPIA UI de Matix (la trajo el
 * wake word / abrió el chat), no la app que quería leer. Por eso rastreamos el
 * ÚLTIMO paquete en primer plano que NO es Matix (vía TYPE_WINDOW_STATE_CHANGED)
 * y, al capturar, buscamos la ventana de ESE paquete entre las ventanas
 * interactivas; solo si no la encontramos caemos a la ventana activa.
 */
class MatixAccessibilityService : AccessibilityService() {

    companion object {
        /** Instancia viva del servicio (null si está apagado). La consulta el
         *  MethodChannel de MainActivity para capturar bajo demanda. */
        @Volatile
        var instancia: MatixAccessibilityService? = null
            private set

        const val MI_PAQUETE = "dev.matix.matix"
        // UI del sistema (barra, sombra de notificaciones, launcher gestos): no
        // es «la app que el usuario estaba viendo».
        private val PAQUETES_SISTEMA = setOf(
            "com.android.systemui",
        )
        // ALLOWLIST DE ACCIÓN (Tier C.1) — ENFORZADA: el servicio SOLO ejecuta
        // taps/setText si la ventana activa pertenece a uno de estos paquetes.
        // En C.1 únicamente WhatsApp. Fuera de aquí, toda acción se bloquea.
        // (La LECTURA sigue siendo bajo demanda y permisiva, como en C.0.)
        private val PAQUETES_ACCIONABLES = setOf(
            "com.whatsapp",
        )
        private const val MAX_NODOS = 600
        private const val MAX_PROFUNDIDAD = 30

        // Kill switch por notificación.
        private const val CANAL_ACCION = "matix_accion"
        private const val NOTIF_ACCION_ID = 7711
        const val ACTION_DETENER = "dev.matix.matix.DETENER_ACCION"
    }

    /** Último paquete de una app real en primer plano (no Matix, no systemui). */
    @Volatile
    private var ultimoPaqueteForeground: String? = null

    /** Kill switch: cuando es true, ninguna acción se ejecuta y el bucle aborta. */
    @Volatile
    var abortado: Boolean = false
        private set

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Flags aplicados en código (ver nota en accessibility_service_config.xml):
        //  - RETRIEVE_INTERACTIVE_WINDOWS: poder elegir la ventana de la app que
        //    el usuario veía (no la de Matix) — clave para el gotcha del foreground.
        //  - REPORT_VIEW_IDS: incluir los ids de los nodos en la lectura.
        serviceInfo = (serviceInfo ?: AccessibilityServiceInfo()).apply {
            flags = flags or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
        instancia = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // SOLO rastreamos qué app está en primer plano. No reaccionamos a nada
        // más: la lectura es bajo demanda, no por evento.
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == MI_PAQUETE || pkg in PAQUETES_SISTEMA) return
        ultimoPaqueteForeground = pkg
    }

    override fun onInterrupt() {
        // No-op: no hay nada que interrumpir (solo lectura bajo demanda).
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instancia = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instancia = null
        super.onDestroy()
    }

    /**
     * Captura la pantalla del usuario y la devuelve como JSON:
     *   {"ok":true,"app":"<pkg>","arbol":{...}}
     *   {"ok":false,"motivo":"sin_ventana"}
     * Procesa y descarta: no persiste nada.
     */
    fun capturarJson(): String {
        val raiz = resolverVentanaObjetivo()
            ?: return JSONObject().put("ok", false).put("motivo", "sin_ventana").toString()
        val app = raiz.packageName?.toString() ?: ""
        val contador = intArrayOf(0)
        val arbol = nodoAJson(raiz, 0, contador)
        return JSONObject()
            .put("ok", true)
            .put("app", app)
            .put("arbol", arbol ?: JSONObject())
            .toString()
    }

    /** Elige la ventana de la app que el usuario estaba viendo (el gotcha). */
    private fun resolverVentanaObjetivo(): AccessibilityNodeInfo? {
        val objetivo = ultimoPaqueteForeground
        // 1) Entre las ventanas interactivas, la del último paquete no-Matix.
        if (objetivo != null) {
            try {
                for (ventana in windows) {
                    val root = ventana.root ?: continue
                    if (root.packageName?.toString() == objetivo) return root
                }
            } catch (_: Exception) {
                // algunos OEM restringen getWindows(): caemos al activo
            }
        }
        // 2) Ventana activa, solo si NO es la propia UI de Matix.
        val activa = rootInActiveWindow ?: return null
        return if (activa.packageName?.toString() == MI_PAQUETE) null else activa
    }

    /**
     * Convierte un nodo (y sus hijos) a JSON compacto. Solo incluye claves con
     * contenido. Acotado por número de nodos y profundidad para no inflar el
     * payload. Claves: t=texto, d=descripción, id=viewId corto, c=clase corta,
     * h=hijos.
     */
    private fun nodoAJson(
        nodo: AccessibilityNodeInfo?,
        profundidad: Int,
        contador: IntArray,
    ): JSONObject? {
        if (nodo == null || profundidad > MAX_PROFUNDIDAD || contador[0] >= MAX_NODOS) return null
        contador[0]++

        val obj = JSONObject()
        val texto = nodo.text?.toString()?.trim()
        if (!texto.isNullOrEmpty()) obj.put("t", texto)
        val desc = nodo.contentDescription?.toString()?.trim()
        if (!desc.isNullOrEmpty()) obj.put("d", desc)
        val viewId = nodo.viewIdResourceName
        if (!viewId.isNullOrEmpty()) obj.put("id", viewId.substringAfterLast("/"))
        val clase = nodo.className?.toString()
        if (!clase.isNullOrEmpty()) obj.put("c", clase.substringAfterLast("."))

        val hijos = JSONArray()
        for (i in 0 until nodo.childCount) {
            if (contador[0] >= MAX_NODOS) break
            val hijoJson = nodoAJson(nodo.getChild(i), profundidad + 1, contador)
            if (hijoJson != null) hijos.put(hijoJson)
        }
        if (hijos.length() > 0) obj.put("h", hijos)

        // Si el nodo no aporta texto/desc/id ni hijos, no vale la pena.
        return if (obj.length() == 0) null else obj
    }

    // ════════════════════════════════════════════════════════════════════
    // Tier C.1 — ACCIÓN (tap / setText), BLINDADA
    // ════════════════════════════════════════════════════════════════════

    /** Lee el texto (o descripción) del primer nodo con ese viewId en la
     *  ventana objetivo. Para verificar el encabezado del chat, la caja de
     *  texto, etc. Devuelve null si no existe. */
    fun leerTextoPorId(viewId: String): String? {
        val raiz = resolverVentanaObjetivo() ?: return null
        val nodo = raiz.findAccessibilityNodeInfosByViewId(viewId)?.firstOrNull() ?: return null
        return nodo.text?.toString() ?: nodo.contentDescription?.toString()
    }

    /**
     * Ejecuta UNA acción estructurada sobre la ventana activa. JSON de entrada:
     *   {"tipo":"set_text"|"tap","target":{"por":"id"|"texto"|"desc","valor":"…"},"texto":"…"}
     * Devuelve JSON: {"ok":bool,"motivo":"…","app":"…"}.
     *
     * BLINDAJE:
     *  - Si el kill switch está activo → no ejecuta nada.
     *  - ENFORCED allowlist: solo actúa si la app activa está en
     *    PAQUETES_ACCIONABLES (C.1 = solo WhatsApp). Si no, bloquea.
     */
    fun ejecutarAccion(accionJson: String): String {
        if (abortado) return resultadoAccion(false, "abortado")
        val accion = try {
            JSONObject(accionJson)
        } catch (_: Exception) {
            return resultadoAccion(false, "json_invalido")
        }
        val raiz = resolverVentanaObjetivo() ?: return resultadoAccion(false, "sin_ventana")
        val app = raiz.packageName?.toString() ?: ""
        if (app !in PAQUETES_ACCIONABLES) return resultadoAccion(false, "no_permitido", app)

        val target = accion.optJSONObject("target")
            ?: return resultadoAccion(false, "sin_target", app)
        val nodo = buscarNodo(raiz, target.optString("por"), target.optString("valor"))
            ?: return resultadoAccion(false, "sin_nodo", app)

        val ok = when (accion.optString("tipo")) {
            "set_text" -> {
                val args = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        accion.optString("texto"),
                    )
                }
                nodo.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            }
            "tap" -> taparNodo(nodo)
            else -> false
        }
        return resultadoAccion(ok, if (ok) "ok" else "accion_fallo", app)
    }

    /** Tap: si el nodo no es clickable, sube al ancestro clickable más cercano. */
    private fun taparNodo(nodo: AccessibilityNodeInfo): Boolean {
        var n: AccessibilityNodeInfo? = nodo
        while (n != null) {
            if (n.isClickable) return n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            n = n.parent
        }
        return nodo.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    private fun buscarNodo(
        raiz: AccessibilityNodeInfo,
        por: String,
        valor: String,
    ): AccessibilityNodeInfo? {
        if (valor.isEmpty()) return null
        return when (por) {
            "id" -> raiz.findAccessibilityNodeInfosByViewId(valor)?.firstOrNull()
            "texto" -> raiz.findAccessibilityNodeInfosByText(valor)?.firstOrNull()
            "desc" -> buscarPorDescripcion(raiz, valor)
            else -> null
        }
    }

    private fun buscarPorDescripcion(
        raiz: AccessibilityNodeInfo,
        valor: String,
    ): AccessibilityNodeInfo? {
        if (raiz.contentDescription?.toString()?.contains(valor, true) == true) return raiz
        for (i in 0 until raiz.childCount) {
            val hijo = raiz.getChild(i) ?: continue
            val encontrado = buscarPorDescripcion(hijo, valor)
            if (encontrado != null) return encontrado
        }
        return null
    }

    private fun resultadoAccion(ok: Boolean, motivo: String, app: String = ""): String =
        JSONObject().put("ok", ok).put("motivo", motivo).put("app", app).toString()

    // ── Kill switch + notificación («Detener» + log visible) ────────────

    /** Arranca un flujo de acción: limpia el abort y muestra la notificación
     *  con el botón «Detener» (kill switch disponible en todo momento). */
    fun iniciarFlujoAccion() {
        abortado = false
        notificarEstado("Preparando la acción…", enCurso = true, conDetener = true)
    }

    /** Log VISIBLE de cada paso: actualiza la notificación con lo que hace
     *  («Escribiendo…», «Enviando…»). Se ve aunque WhatsApp esté delante. */
    fun actualizarFlujoAccion(texto: String) {
        notificarEstado(texto, enCurso = true, conDetener = true)
    }

    /** Cierra el flujo: deja un aviso final (no persistente) con el resultado,
     *  o quita la notificación si no hay texto. */
    fun terminarFlujoAccion(textoFinal: String) {
        abortado = false
        if (textoFinal.isEmpty()) {
            notificador().cancel(NOTIF_ACCION_ID)
        } else {
            notificarEstado(textoFinal, enCurso = false, conDetener = false)
        }
    }

    /** Kill switch: aborta el bucle al instante. Lo llaman el botón de la
     *  notificación y la app (voz «para»/«detente», botón Cancelar). */
    fun abortar() {
        abortado = true
        notificarEstado("Detenido.", enCurso = false, conDetener = false)
    }

    private fun notificador(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun notificarEstado(texto: String, enCurso: Boolean, conDetener: Boolean) {
        val nm = notificador()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CANAL_ACCION,
                    "Matix en acción",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = "Aviso mientras Matix actúa en una app, con botón para detener." },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CANAL_ACCION)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        builder
            .setContentTitle("Matix está actuando")
            .setContentText(texto)
            .setSmallIcon(android.R.drawable.ic_media_pause)
            .setOngoing(enCurso)
            .setAutoCancel(!enCurso)
        if (conDetener) {
            val detener = PendingIntent.getBroadcast(
                this,
                0,
                Intent(ACTION_DETENER).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(Notification.Action.Builder(null, "Detener", detener).build())
        }
        nm.notify(NOTIF_ACCION_ID, builder.build())
    }
}
