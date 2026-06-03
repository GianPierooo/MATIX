package dev.matix.matix

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Kill switch del botón «Detener» de la notificación (Tier C.1). Al tocarlo,
 * aborta el bucle de acción al instante, en cualquier punto.
 */
class DetenerAccionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == MatixAccessibilityService.ACTION_DETENER) {
            MatixAccessibilityService.instancia?.abortar()
        }
    }
}
