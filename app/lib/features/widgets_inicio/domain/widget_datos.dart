import 'package:flutter/painting.dart' show Color;

import '../../horario/domain/plan_dia.dart';
import '../../mascota/domain/presencia.dart' show bloqueActual, bloqueSiguiente;
import '../../../theme/matix_colors.dart';

/// Datos LISTOS para renderizar en el widget nativo. La app los calcula con el
/// plan del día YA determinista (fuente única) y los empuja al almacenamiento
/// del widget; el nativo solo lee y pinta. Sin lógica de negocio en el nativo.

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Color de la barra del ítem según su semántica (igual que la app, pero
/// simplificado para el widget): proyecto/trabajo en AZUL, eventos fijos en
/// VERDE, vencidos/urgentes en ROJO, prácticas tentativas en ÁMBAR. PURO.
String colorWidget(String tipo, bool fijo, {bool vencido = false}) {
  final c = vencido
      ? MatixColors.red
      : fijo
          ? MatixColors.green // clase / evento / ancla (fijo)
          : tipo == 'skill'
              ? MatixColors.amber // práctica tentativa
              : MatixColors.accent; // proyecto / trabajo / tarea (azul)
  return _hex(c);
}

/// Texto relativo del próximo ítem: "Ahora" si ya empezó, si no "en X min" /
/// "en X h Y min". Se calcula al empujar (es aproximado entre refrescos). PURO.
String relativoDe(BloquePlan b, int ahoraMin) {
  if (b.inicioMin <= ahoraMin) return 'Ahora';
  final m = b.inicioMin - ahoraMin;
  if (m >= 60) {
    final h = m ~/ 60;
    final mm = m % 60;
    return mm > 0 ? 'en $h h $mm min' : 'en $h h';
  }
  return 'en $m min';
}

/// Fecha corta en español, sin depender de `initializeDateFormatting` (para que
/// el cálculo sea PURO y testeable sin init de locale). Ej: "lun 8 jun".
String fechaCorta(DateTime d) {
  const dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${dias[d.weekday - 1]} ${d.day} ${meses[d.month - 1]}';
}

/// Deep link de "marcar hecho" desde el widget. Convierte el payload de un ítem
/// (`tarea:<id>`) en el payload de completar (`completar:<id>`) que el botón
/// "hecho" del widget dispara; `null` si el ítem no es una tarea completable
/// (p. ej. un evento fijo o el estado vacío). PURO y testeable. El nativo hace la
/// misma conversión para armar el PendingIntent del botón.
String? payloadCompletar(String itemPayload) {
  const pref = 'tarea:';
  if (!itemPayload.startsWith(pref)) return null;
  final id = itemPayload.substring(pref.length);
  return id.isEmpty ? null : 'completar:$id';
}

/// Extrae el id de tarea de un payload `completar:<id>` (lo que recibe la app al
/// tocar el botón "hecho" del widget); `null` si no es un payload de completar.
String? tareaIdDeCompletar(String payload) {
  const pref = 'completar:';
  if (!payload.startsWith(pref)) return null;
  final id = payload.substring(pref.length);
  return id.isEmpty ? null : id;
}

/// Un ítem del widget (próximo o fila de hoy). Todo precalculado en Dart.
class WidgetItem {
  const WidgetItem({
    required this.hora,
    required this.titulo,
    required this.fijo,
    required this.colorHex,
    required this.sub,
    required this.payload,
  });

  final String hora; // "HH:MM"
  final String titulo;
  final bool fijo; // true = fijo/inmovible; false = tentativo
  final String colorHex; // "#RRGGBB" (ya resuelto)
  final String sub; // contexto corto ("Fijo" / "OneXotic" / "Tentativo")
  final String payload; // deep link: 'tarea:<id>' | 'hoy'
}

/// El paquete completo que se empuja al widget.
class DatosWidget {
  const DatosWidget({
    required this.vacio,
    required this.fecha,
    required this.proximo,
    required this.proximoRel,
    required this.hoy,
    required this.overflow,
    required this.actualizado,
  });

  /// Sin plan / app nunca abierta → el widget muestra "Abre Matix para ver tu
  /// día" (nunca en blanco ni roto).
  final bool vacio;

  /// Fecha legible para el encabezado ("lun 8 jun").
  final String fecha;

  /// Lo que toca AHORA o lo siguiente. `null` si ya no queda nada hoy.
  final WidgetItem? proximo;

  /// Texto relativo del próximo ("Ahora" / "en 25 min"). Vacío si no hay.
  final String proximoRel;

  /// Ítems del día desde ahora (actual + próximos), capados.
  final List<WidgetItem> hoy;

  /// Cuántos quedaron fuera del cap ("+X más"). 0 si no hay overflow.
  final int overflow;

  /// "HH:MM" de cuándo se calculó (diagnóstico).
  final String actualizado;

  const DatosWidget.vacioInicial()
      : vacio = true,
        fecha = '',
        proximo = null,
        proximoRel = '',
        hoy = const [],
        overflow = 0,
        actualizado = '';

  /// `true` cuando hay plan pero no queda nada pendiente hoy (día cerrado) →
  /// estado celebratorio "todo hecho", no un widget vacío triste.
  bool get sinPendientes => !vacio && proximo == null && hoy.isEmpty;
}

WidgetItem _item(BloquePlan b, int ahoraMin) {
  final ctx = b.proyecto ?? b.skill;
  final vencido = b.finMin <= ahoraMin; // (no aparece con selección de upcoming)
  return WidgetItem(
    hora: b.inicio,
    titulo: b.titulo,
    fijo: b.esFijo,
    colorHex: colorWidget(b.tipo, b.esFijo, vencido: vencido),
    sub: b.esFijo ? 'Fijo' : (ctx ?? 'Tentativo'),
    payload: b.tareaId != null ? 'tarea:${b.tareaId}' : 'hoy',
  );
}

/// Calcula los datos del widget desde el plan del día y la hora actual. PURO y
/// testeable. Reusa `bloqueActual`/`bloqueSiguiente` (no duplica la selección).
///
/// - Sin plan o sin bloques → estado vacío ("Abre Matix…").
/// - "Próximo" = el bloque que cubre AHORA, o el siguiente; `null` si ya no
///   queda nada (día cerrado → estado "todo hecho").
/// - "Hoy" = actual + próximos (de ahora en adelante), capado a [maxHoy] con
///   "+X más" para el resto.
DatosWidget construirDatosWidget(
  PlanDia? plan,
  DateTime ahora, {
  int maxHoy = 4,
}) {
  if (plan == null || plan.bloques.isEmpty) {
    return DatosWidget(
      vacio: true,
      fecha: fechaCorta(ahora),
      proximo: null,
      proximoRel: '',
      hoy: const [],
      overflow: 0,
      actualizado: '',
    );
  }
  final ahoraMin = ahora.hour * 60 + ahora.minute;

  // Relevante = lo que aún no terminó (actual + próximos), en orden de hora.
  final relevantes = [
    for (final b in plan.bloques)
      if (b.finMin > ahoraMin) b,
  ]..sort((a, b) => a.inicioMin.compareTo(b.inicioMin));

  final actual = bloqueActual(plan.bloques, ahoraMin);
  final siguiente = bloqueSiguiente(plan.bloques, ahoraMin);
  final prox = actual ?? siguiente;

  final hoy = relevantes.take(maxHoy).map((b) => _item(b, ahoraMin)).toList();
  final overflow = relevantes.length - hoy.length;

  return DatosWidget(
    vacio: false,
    fecha: fechaCorta(ahora),
    proximo: prox == null ? null : _item(prox, ahoraMin),
    proximoRel: prox == null ? '' : relativoDe(prox, ahoraMin),
    hoy: hoy,
    overflow: overflow < 0 ? 0 : overflow,
    actualizado: hhmmDesdeMin(ahoraMin),
  );
}
