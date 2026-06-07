package dev.matix.matix

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget "Hoy": encabezado (HOY + fecha + distintivo), el PRÓXIMO ítem destacado
 * y el resto más sobrio. Capado a 4 con "+X más". Solo renderiza lo que empuja
 * Dart; sin lógica de negocio.
 *
 * Responsive de verdad: según el tamaño del widget muestra más o menos filas —
 * chico = solo el próximo destacado; grande = la lista completa. No se corta feo.
 */
class HoyWidgetProvider : HomeWidgetProvider() {

    // Filas sobrias (1..3); la 0 es el destacado y se renderiza aparte.
    private val filasSobrias = listOf(
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
            render(context, appWidgetManager, id, widgetData,
                appWidgetManager.getAppWidgetOptions(id))
        }
    }

    /** Re-renderiza al cambiar el tamaño del widget (responsive). */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId,
            HomeWidgetPlugin.getData(context), newOptions)
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        id: Int,
        widgetData: SharedPreferences,
        options: Bundle?,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_hoy)

        views.setTextViewText(R.id.hoy_fecha, widgetData.getString("fecha", "") ?: "")
        views.setTextViewText(R.id.hoy_actualizado, widgetData.getString("actualizado", "") ?: "")

        val vacio = widgetData.getString("vacio", "1") != "0"
        val sinPend = widgetData.getString("sin_pendientes", "0") == "1"
        val count = (widgetData.getString("hoy_count", "0") ?: "0").toIntOrNull() ?: 0

        // Cuántas filas caben según la ALTURA del widget (responsive). Chico → 1
        // (solo el destacado); grande → hasta 4.
        val minH = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
        val maxFilas = when {
            minH in 1..119 -> 1
            minH in 120..179 -> 2
            minH in 180..239 -> 3
            else -> 4
        }

        if (vacio || (count == 0 && !sinPend)) {
            ocultarTodo(views)
            views.setViewVisibility(R.id.hoy_empty, View.VISIBLE)
        } else if (sinPend || count == 0) {
            ocultarTodo(views)
            views.setViewVisibility(R.id.hoy_hecho, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.hoy_empty, View.GONE)
            views.setViewVisibility(R.id.hoy_hecho, View.GONE)

            val mostrar = minOf(count, maxFilas)

            // Fila 0: destacado (siempre visible si hay algo).
            views.setViewVisibility(R.id.hoy_row_0, View.VISIBLE)
            views.setTextViewText(R.id.hoy_hora_0, widgetData.getString("hoy_0_hora", ""))
            views.setTextViewText(R.id.hoy_titulo_0, widgetData.getString("hoy_0_titulo", ""))
            views.setTextViewText(R.id.hoy_sub_0, widgetData.getString("hoy_0_sub", ""))
            views.setTextViewText(R.id.hoy_rel_0, widgetData.getString("hoy_0_rel", ""))
            views.setInt(R.id.hoy_bar_0, "setBackgroundColor",
                parseColor(widgetData.getString("hoy_0_color", "#2D7FF9")))
            views.setOnClickPendingIntent(
                R.id.hoy_row_0,
                deepLink(context, widgetData.getString("hoy_0_payload", "hoy") ?: "hoy", id * 16),
            )

            // Filas 1..3: sobrias, según tamaño.
            filasSobrias.forEachIndexed { idx, f ->
                val i = idx + 1
                if (i < mostrar) {
                    views.setViewVisibility(f.row, View.VISIBLE)
                    views.setTextViewText(f.hora, widgetData.getString("hoy_${i}_hora", ""))
                    views.setTextViewText(f.titulo, widgetData.getString("hoy_${i}_titulo", ""))
                    views.setTextViewText(f.sub, widgetData.getString("hoy_${i}_sub", ""))
                    views.setInt(f.bar, "setBackgroundColor",
                        parseColor(widgetData.getString("hoy_${i}_color", "#2D7FF9")))
                    views.setOnClickPendingIntent(
                        f.row,
                        deepLink(context, widgetData.getString("hoy_${i}_payload", "hoy") ?: "hoy",
                            id * 16 + i),
                    )
                } else {
                    views.setViewVisibility(f.row, View.GONE)
                }
            }

            // "+X más": lo oculto por tamaño + lo que ya venía capado desde Dart.
            val overflowDart = (widgetData.getString("hoy_overflow_n", "0") ?: "0").toIntOrNull() ?: 0
            val restantes = (count - mostrar) + overflowDart
            if (restantes > 0) {
                views.setViewVisibility(R.id.hoy_overflow, View.VISIBLE)
                views.setTextViewText(R.id.hoy_overflow, "+$restantes más")
            } else {
                views.setViewVisibility(R.id.hoy_overflow, View.GONE)
            }
        }

        // Tap en el encabezado → abre Inicio (Tu día).
        views.setOnClickPendingIntent(R.id.hoy_header, deepLink(context, "hoy", id * 16 + 15))

        appWidgetManager.updateAppWidget(id, views)
    }

    private fun ocultarTodo(views: RemoteViews) {
        views.setViewVisibility(R.id.hoy_row_0, View.GONE)
        filasSobrias.forEach { views.setViewVisibility(it.row, View.GONE) }
        views.setViewVisibility(R.id.hoy_overflow, View.GONE)
        views.setViewVisibility(R.id.hoy_empty, View.GONE)
        views.setViewVisibility(R.id.hoy_hecho, View.GONE)
    }

    private data class Fila(
        val row: Int,
        val bar: Int,
        val hora: Int,
        val titulo: Int,
        val sub: Int,
    )
}
