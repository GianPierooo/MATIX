package dev.matix.matix

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
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
        private const val MAX_NODOS = 600
        private const val MAX_PROFUNDIDAD = 30
    }

    /** Último paquete de una app real en primer plano (no Matix, no systemui). */
    @Volatile
    private var ultimoPaqueteForeground: String? = null

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
}
