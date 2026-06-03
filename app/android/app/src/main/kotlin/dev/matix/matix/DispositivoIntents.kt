package dev.matix.matix

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CalendarContract
import android.provider.MediaStore
import java.io.File

/**
 * Acciones de teléfono (Capa 6 · Fase 1 — Tier A intents + Tier B galería).
 *
 * El cerebro NO ejecuta nada: sus tools PROPONEN una `accion_dispositivo` y la
 * app, tras la confirmación del usuario, llama aquí para LANZAR el Intent del
 * sistema. Todos los intents son "prellenados": abren la app destino (WhatsApp,
 * teléfono, calendario…) con los datos cargados, y es el usuario quien da el
 * último toque (Enviar / Llamar / Guardar). Por eso no hace falta el permiso
 * CALL_PHONE ni SEND_SMS: usamos ACTION_DIAL / ACTION_SENDTO / ACTION_INSERT.
 *
 * Cada función devuelve `true` si encontró una app que resuelva el intent y lo
 * lanzó; `false` si no hay app capaz (degradación limpia: la capa Dart avisa al
 * usuario en vez de crashear).
 */
object DispositivoIntents {

    /** Redacta un mensaje prellenado por WhatsApp, SMS o correo. */
    fun redactarMensaje(
        activity: Activity,
        canal: String,
        destinatario: String?,
        texto: String,
        asunto: String?,
    ): Boolean {
        return when (canal) {
            "whatsapp" -> lanzarWhatsApp(activity, destinatario, texto)
            "sms" -> lanzar(
                activity,
                Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${destinatario ?: ""}")).apply {
                    putExtra("sms_body", texto)
                },
            )
            "correo" -> lanzar(
                activity,
                Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).apply {
                    if (!destinatario.isNullOrBlank()) {
                        putExtra(Intent.EXTRA_EMAIL, arrayOf(destinatario))
                    }
                    if (!asunto.isNullOrBlank()) putExtra(Intent.EXTRA_SUBJECT, asunto)
                    putExtra(Intent.EXTRA_TEXT, texto)
                },
            )
            else -> false
        }
    }

    /** Marca un número en el teléfono (ACTION_DIAL: no llama solo, el usuario
     *  pulsa el botón verde). Sin permiso CALL_PHONE. */
    fun iniciarLlamada(activity: Activity, numero: String): Boolean {
        if (numero.isBlank()) return false
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(numero)}"))
        return lanzar(activity, intent)
    }

    /** Abre el calendario del teléfono con un evento nuevo prellenado. Las
     *  fechas llegan en epoch-millis (la capa Dart parsea el ISO). */
    fun crearEvento(
        activity: Activity,
        titulo: String,
        iniciaEnMillis: Long,
        terminaEnMillis: Long?,
        ubicacion: String?,
        descripcion: String?,
    ): Boolean {
        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, titulo)
            if (iniciaEnMillis > 0) {
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, iniciaEnMillis)
            }
            if (terminaEnMillis != null && terminaEnMillis > 0) {
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, terminaEnMillis)
            }
            if (!ubicacion.isNullOrBlank()) {
                putExtra(CalendarContract.Events.EVENT_LOCATION, ubicacion)
            }
            if (!descripcion.isNullOrBlank()) {
                putExtra(CalendarContract.Events.DESCRIPTION, descripcion)
            }
        }
        return lanzar(activity, intent)
    }

    /** Abre una URL, un mapa o una app. `objetivo` ∈ {url, mapa, app}. */
    fun abrir(activity: Activity, objetivo: String, valor: String): Boolean {
        if (valor.isBlank()) return false
        return when (objetivo) {
            "url" -> {
                val uri = if (valor.startsWith("http")) valor else "https://$valor"
                lanzar(activity, Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
            }
            "mapa" -> {
                // geo:0,0?q=consulta — lo resuelve cualquier app de mapas.
                val geo = Uri.parse("geo:0,0?q=${Uri.encode(valor)}")
                lanzar(activity, Intent(Intent.ACTION_VIEW, geo)) ||
                    // Sin app de mapas geo: degradamos a Google Maps web.
                    lanzar(
                        activity,
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encode(valor)}"),
                        ),
                    )
            }
            "app" -> abrirApp(activity, valor)
            else -> false
        }
    }

    /**
     * Copia la foto MÁS RECIENTE de la galería a un archivo de caché y devuelve
     * su ruta (para reusar el flujo de OCR/finanzas, que trabaja con paths).
     * Requiere que el permiso de lectura ya esté concedido (lo gestiona Dart);
     * devuelve `null` si no hay fotos o no se pudo leer.
     */
    fun leerUltimaFoto(context: Context): String? {
        val coleccion = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val proyeccion = arrayOf(MediaStore.Images.Media._ID)
        val orden = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        context.contentResolver.query(coleccion, proyeccion, null, null, orden)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
            val uri = ContentUris.withAppendedId(coleccion, id)
            return copiarACache(context, uri)
        }
        return null
    }

    // ── helpers ────────────────────────────────────────────────────────────

    private fun lanzarWhatsApp(activity: Activity, destinatario: String?, texto: String): Boolean {
        // SEGURIDAD: SOLO abrimos el chat directo de un NÚMERO concreto (wa.me).
        // NUNCA caemos al intent de compartir / selector "Enviar a..." de
        // WhatsApp: ese selector es multi-destinatario y deja mandar a cualquiera
        // (causó el bug de enviar al contacto equivocado / a varios). Un envío a
        // un contacto por NOMBRE va por el flujo de accesibilidad (Tier C.1), no
        // por acá. Sin número válido → false (no abrimos nada).
        val soloDigitos = destinatario?.filter { it.isDigit() } ?: ""
        if (soloDigitos.length < 7) return false
        val porNumero = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://wa.me/$soloDigitos?text=${Uri.encode(texto)}"),
        )
        return lanzar(activity, porNumero)
    }

    private fun abrirApp(activity: Activity, valor: String): Boolean {
        // `valor` puede ser un nombre de paquete (com.spotify.music) o el nombre
        // visible de la app. Probamos como paquete; si no, buscamos en la tienda.
        val launch = activity.packageManager.getLaunchIntentForPackage(valor)
        if (launch != null) return lanzar(activity, launch)
        // Degradación: abrir la ficha de la tienda buscando el término.
        return lanzar(
            activity,
            Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=${Uri.encode(valor)}")),
        ) || lanzar(
            activity,
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/search?q=${Uri.encode(valor)}"),
            ),
        )
    }

    private fun copiarACache(context: Context, uri: Uri): String? {
        return try {
            val destino = File(context.cacheDir, "galeria_${System.currentTimeMillis()}.jpg")
            context.contentResolver.openInputStream(uri)?.use { entrada ->
                destino.outputStream().use { salida -> entrada.copyTo(salida) }
            } ?: return null
            destino.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    /** Lanza el intent; `false` si ninguna app lo resuelve (no crashea). */
    private fun lanzar(activity: Activity, intent: Intent): Boolean {
        return try {
            if (intent.resolveActivity(activity.packageManager) == null) return false
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
    }
}
