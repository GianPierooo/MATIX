import '../../horario/domain/plan_dia.dart';
import '../../mascota/domain/presencia.dart' show bloqueActual, bloqueSiguiente;
import '../../../theme/matix_colors.dart';

/// Datos LISTOS para renderizar en el widget nativo. La app los calcula con el
/// plan del día YA determinista (fuente única) y los empuja al almacenamiento
/// del widget; el nativo solo lee y pinta. Sin lógica de negocio en el nativo.

/// `#RRGGBB` del color de Matix para un `tipo` de bloque. Espeja el `_colorTipo`
/// de `plan_dia_section.dart` (misma fuente de tokens), pero como hex para el
/// nativo. PURO.
String colorHexTipo(String tipo) {
  final c = switch (tipo) {
    'clase' => MatixColors.teal,
    'evento' => MatixColors.purple,
    'ancla' => MatixColors.muted,
    'transicion' => MatixColors.muted,
    'skill' => MatixColors.pink,
    'tarea' => MatixColors.amber,
    _ => MatixColors.accent, // trabajo y default
  };
  return '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
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
    required this.proximo,
    required this.hoy,
    required this.overflow,
    required this.actualizado,
  });

  /// Sin plan / app nunca abierta → el widget muestra "Abre Matix para ver tu
  /// día" (nunca en blanco ni roto).
  final bool vacio;

  /// Lo que toca AHORA o lo siguiente. `null` si ya no queda nada hoy.
  final WidgetItem? proximo;

  /// Ítems del día desde ahora (actual + próximos), capados.
  final List<WidgetItem> hoy;

  /// Cuántos quedaron fuera del cap ("+X más"). 0 si no hay overflow.
  final int overflow;

  /// "HH:MM" de cuándo se calculó (diagnóstico).
  final String actualizado;

  const DatosWidget.vacioInicial()
      : vacio = true,
        proximo = null,
        hoy = const [],
        overflow = 0,
        actualizado = '';

  /// `true` cuando hay plan pero no queda nada pendiente hoy (día cerrado).
  bool get sinPendientes => !vacio && proximo == null && hoy.isEmpty;
}

WidgetItem _item(BloquePlan b) {
  final ctx = b.proyecto ?? b.skill;
  return WidgetItem(
    hora: b.inicio,
    titulo: b.titulo,
    fijo: b.esFijo,
    colorHex: colorHexTipo(b.tipo),
    sub: b.esFijo ? 'Fijo' : (ctx ?? 'Tentativo'),
    payload: b.tareaId != null ? 'tarea:${b.tareaId}' : 'hoy',
  );
}

/// Calcula los datos del widget desde el plan del día y la hora actual. PURO y
/// testeable. Reusa `bloqueActual`/`bloqueSiguiente` (no duplica la selección).
///
/// - Sin plan o sin bloques → estado vacío ("Abre Matix…").
/// - "Próximo" = el bloque que cubre AHORA, o el siguiente; `null` si ya no
///   queda nada (día cerrado).
/// - "Hoy" = actual + próximos (de ahora en adelante), capado a [maxHoy] con
///   "+X más" para el resto.
DatosWidget construirDatosWidget(
  PlanDia? plan,
  DateTime ahora, {
  int maxHoy = 4,
}) {
  if (plan == null || plan.bloques.isEmpty) {
    return const DatosWidget.vacioInicial();
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

  final hoy = relevantes.take(maxHoy).map(_item).toList();
  final overflow = relevantes.length - hoy.length;

  return DatosWidget(
    vacio: false,
    proximo: prox == null ? null : _item(prox),
    hoy: hoy,
    overflow: overflow < 0 ? 0 : overflow,
    actualizado: hhmmDesdeMin(ahoraMin),
  );
}
