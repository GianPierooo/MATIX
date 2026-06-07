package dev.matix.matix

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget "Próximo": compacto, una sola cosa (lo que toca ahora o lo siguiente).
 *
 * El nativo SOLO renderiza las claves que la app empuja vía `home_widget`
 * (`construirDatosWidget` en Dart hace toda la selección, reusando el plan
 * determinista). Aquí no hay lógica de negocio ni llamadas al cerebro.
 */
class ProximoWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_proximo)

            val vacio = widgetData.getString("vacio", "1") != "0"
            val hay = widgetData.getString("prox_hay", "0") == "1"

            if (vacio || !hay) {
                views.setViewVisibility(R.id.prox_content, View.GONE)
                views.setViewVisibility(R.id.prox_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.prox_empty,
                    if (vacio) "Abre Matix para ver tu día" else "Nada más por hoy",
                )
            } else {
                views.setViewVisibility(R.id.prox_content, View.VISIBLE)
                views.setViewVisibility(R.id.prox_empty, View.GONE)
                views.setTextViewText(R.id.prox_hora, widgetData.getString("prox_hora", ""))
                views.setTextViewText(R.id.prox_titulo, widgetData.getString("prox_titulo", ""))
                views.setTextViewText(R.id.prox_sub, widgetData.getString("prox_sub", ""))
                views.setInt(
                    R.id.prox_bar, "setBackgroundColor",
                    parseColor(widgetData.getString("prox_color", "#2D7FF9")),
                )
            }

            // Tap en el widget → deep link (abre Matix en la pantalla/ítem).
            val payload = widgetData.getString("prox_payload", "hoy") ?: "hoy"
            views.setOnClickPendingIntent(R.id.prox_root, deepLink(context, payload))

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** Color hex "#RRGGBB" → int ARGB; cae al acento si no parsea. */
internal fun parseColor(hex: String?): Int = try {
    Color.parseColor(hex ?: "#2D7FF9")
} catch (_: Exception) {
    Color.parseColor("#2D7FF9")
}

/** PendingIntent que lanza Matix con el payload del ítem (deep link). El lado
 *  Flutter lo recibe vía `HomeWidget.widgetClicked` / `initiallyLaunched`. */
internal fun deepLink(context: Context, payload: String): PendingIntent {
    val uri = Uri.parse("matixwidget://abrir")
        .buildUpon()
        .appendQueryParameter("payload", payload)
        .build()
    return HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        uri,
    )
}
