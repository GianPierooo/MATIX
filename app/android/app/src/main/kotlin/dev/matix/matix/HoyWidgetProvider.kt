package dev.matix.matix

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget "Hoy": lista de los ítems del día (actual + próximos), capada a 4 filas
 * con "+X más". Filas FIJAS: la app empuja hasta 4 y ocultamos las que sobran.
 * Solo renderiza lo que empuja Dart; sin lógica de negocio.
 */
class HoyWidgetProvider : HomeWidgetProvider() {

    // Ids de las 4 filas fijas del layout.
    private val filas = listOf(
        Fila(R.id.hoy_row_0, R.id.hoy_bar_0, R.id.hoy_hora_0, R.id.hoy_titulo_0, R.id.hoy_sub_0),
        Fila(R.id.hoy_row_1, R.id.hoy_bar_1, R.id.hoy_hora_1, R.id.hoy_titulo_1, R.id.hoy_sub_1),
        Fila(R.id.hoy_row_2, R.id.hoy_bar_2, R.id.hoy_hora_2, R.id.hoy_titulo_2, R.id.hoy_sub_2),
        Fila(R.id.hoy_row_3, R.id.hoy_bar_3, R.id.hoy_hora_3, R.id.hoy_titulo_3, R.id.hoy_sub_3),
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_hoy)

            val vacio = widgetData.getString("vacio", "1") != "0"
            val count = (widgetData.getString("hoy_count", "0") ?: "0").toIntOrNull() ?: 0

            views.setTextViewText(R.id.hoy_actualizado, widgetData.getString("actualizado", ""))

            if (vacio || count == 0) {
                filas.forEach { views.setViewVisibility(it.row, View.GONE) }
                views.setViewVisibility(R.id.hoy_overflow, View.GONE)
                views.setViewVisibility(R.id.hoy_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.hoy_empty,
                    if (vacio) "Abre Matix para ver tu día" else "Nada más por hoy",
                )
            } else {
                views.setViewVisibility(R.id.hoy_empty, View.GONE)
                filas.forEachIndexed { i, f ->
                    if (i < count) {
                        views.setViewVisibility(f.row, View.VISIBLE)
                        views.setTextViewText(f.hora, widgetData.getString("hoy_${i}_hora", ""))
                        views.setTextViewText(f.titulo, widgetData.getString("hoy_${i}_titulo", ""))
                        views.setTextViewText(f.sub, widgetData.getString("hoy_${i}_sub", ""))
                        views.setInt(
                            f.bar, "setBackgroundColor",
                            parseColor(widgetData.getString("hoy_${i}_color", "#2D7FF9")),
                        )
                        val payload = widgetData.getString("hoy_${i}_payload", "hoy") ?: "hoy"
                        views.setOnClickPendingIntent(f.row, deepLink(context, payload))
                    } else {
                        views.setViewVisibility(f.row, View.GONE)
                    }
                }
                val overflow = widgetData.getString("hoy_overflow", "") ?: ""
                if (overflow.isEmpty()) {
                    views.setViewVisibility(R.id.hoy_overflow, View.GONE)
                } else {
                    views.setViewVisibility(R.id.hoy_overflow, View.VISIBLE)
                    views.setTextViewText(R.id.hoy_overflow, overflow)
                }
            }

            // Tap en el encabezado → abre Inicio (Tu día).
            views.setOnClickPendingIntent(R.id.hoy_header, deepLink(context, "hoy"))

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private data class Fila(
        val row: Int,
        val bar: Int,
        val hora: Int,
        val titulo: Int,
        val sub: Int,
    )
}
