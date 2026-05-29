import 'package:flutter/foundation.dart';

import '../../../core/notif_id.dart';
import 'recordatorio_evento.dart';

/// Recurrencia de un evento, modelada como una REGLA guardada en la propia
/// fila (no se materializan ocurrencias). Calendario · Paso 3.
///
/// Las ocurrencias se expanden solo dentro del rango visible (mes/día) y los
/// recordatorios se agendan en una ventana móvil de ~30 días. Toda la lógica
/// vive como funciones puras para poder testearla sin UI ni notificaciones.

/// Frecuencia base de la serie. "cada día de semana" no es un valor propio:
/// se modela como [semanal] con `diasSemana = {1,2,3,4,5}`.
enum FrecuenciaRecurrencia { diaria, semanal, mensual }

/// Condición de fin de la serie.
enum FinRecurrencia { nunca, hasta, conteo }

FrecuenciaRecurrencia? _freqDesdeJson(String? v) {
  switch (v) {
    case 'diaria':
      return FrecuenciaRecurrencia.diaria;
    case 'semanal':
      return FrecuenciaRecurrencia.semanal;
    case 'mensual':
      return FrecuenciaRecurrencia.mensual;
    default:
      return null;
  }
}

String _freqAJson(FrecuenciaRecurrencia f) {
  switch (f) {
    case FrecuenciaRecurrencia.diaria:
      return 'diaria';
    case FrecuenciaRecurrencia.semanal:
      return 'semanal';
    case FrecuenciaRecurrencia.mensual:
      return 'mensual';
  }
}

FinRecurrencia _finDesdeJson(String? v) {
  switch (v) {
    case 'hasta':
      return FinRecurrencia.hasta;
    case 'conteo':
      return FinRecurrencia.conteo;
    default:
      return FinRecurrencia.nunca;
  }
}

String _finAJson(FinRecurrencia f) {
  switch (f) {
    case FinRecurrencia.nunca:
      return 'nunca';
    case FinRecurrencia.hasta:
      return 'hasta';
    case FinRecurrencia.conteo:
      return 'conteo';
  }
}

@immutable
class ReglaRecurrencia {
  const ReglaRecurrencia({
    required this.frecuencia,
    this.diasSemana = const <int>{},
    this.fin = FinRecurrencia.nunca,
    this.hasta,
    this.conteo,
  });

  final FrecuenciaRecurrencia frecuencia;

  /// Días ISO (1=lunes … 7=domingo) para [FrecuenciaRecurrencia.semanal].
  /// Vacío = se usa el día de inicio de la serie. Ignorado en otras
  /// frecuencias.
  final Set<int> diasSemana;

  final FinRecurrencia fin;

  /// Fecha límite inclusiva (solo si [fin] == [FinRecurrencia.hasta]).
  final DateTime? hasta;

  /// Nº total de ocurrencias contadas desde el inicio de la serie (solo si
  /// [fin] == [FinRecurrencia.conteo]).
  final int? conteo;

  ReglaRecurrencia copyWith({
    FrecuenciaRecurrencia? frecuencia,
    Set<int>? diasSemana,
    FinRecurrencia? fin,
    DateTime? hasta,
    int? conteo,
  }) =>
      ReglaRecurrencia(
        frecuencia: frecuencia ?? this.frecuencia,
        diasSemana: diasSemana ?? this.diasSemana,
        fin: fin ?? this.fin,
        hasta: hasta ?? this.hasta,
        conteo: conteo ?? this.conteo,
      );

  /// Claves de columna para enviar al guardar. Solo manda lo que aplica a la
  /// frecuencia/fin elegidos; el resto va `null` para limpiar restos previos.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'recurrencia_freq': _freqAJson(frecuencia),
        'recurrencia_dias_semana':
            frecuencia == FrecuenciaRecurrencia.semanal && diasSemana.isNotEmpty
                ? (diasSemana.toList()..sort())
                : null,
        'recurrencia_fin_tipo': _finAJson(fin),
        'recurrencia_hasta': fin == FinRecurrencia.hasta && hasta != null
            ? _soloFecha(hasta!)
            : null,
        'recurrencia_conteo':
            fin == FinRecurrencia.conteo ? conteo : null,
      };

  /// Las 5 columnas en `null`: vuelve el evento a único. Se usa al guardar un
  /// evento sin recurrencia para limpiar cualquier regla anterior.
  static Map<String, dynamic> jsonNulo() => const <String, dynamic>{
        'recurrencia_freq': null,
        'recurrencia_dias_semana': null,
        'recurrencia_fin_tipo': null,
        'recurrencia_hasta': null,
        'recurrencia_conteo': null,
      };

  /// Reconstruye la regla desde el JSON de un evento, o `null` si no hay
  /// recurrencia (`recurrencia_freq` ausente o desconocida).
  static ReglaRecurrencia? maybeFromEventoJson(Map<String, dynamic> json) {
    final freq = _freqDesdeJson(json['recurrencia_freq'] as String?);
    if (freq == null) return null;
    final diasRaw = json['recurrencia_dias_semana'] as List<dynamic>?;
    final dias = <int>{
      for (final d in diasRaw ?? const <dynamic>[])
        if (d is num) d.toInt(),
    };
    final hastaRaw = json['recurrencia_hasta'] as String?;
    return ReglaRecurrencia(
      frecuencia: freq,
      diasSemana: dias,
      fin: _finDesdeJson(json['recurrencia_fin_tipo'] as String?),
      hasta: hastaRaw == null ? null : DateTime.parse(hastaRaw),
      conteo: (json['recurrencia_conteo'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReglaRecurrencia &&
      other.frecuencia == frecuencia &&
      setEquals(other.diasSemana, diasSemana) &&
      other.fin == fin &&
      other.hasta == hasta &&
      other.conteo == conteo;

  @override
  int get hashCode =>
      Object.hash(frecuencia, fin, hasta, conteo, Object.hashAllUnordered(diasSemana));
}

String _soloFecha(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _fechaDe(DateTime d) => DateTime(d.year, d.month, d.day);

/// Suma `meses` a una fecha conservando hora/min, devolviendo `null` si el
/// día no existe en el mes destino (p. ej. el 31 en febrero) — esa ocurrencia
/// se salta, no se desborda al mes siguiente.
DateTime? _sumaMesesEstricto(DateTime base, int meses) {
  final total = base.month - 1 + meses;
  final anio = base.year + total ~/ 12;
  final mes = total % 12 + 1;
  final ultimoDia = DateTime(anio, mes + 1, 0).day;
  if (base.day > ultimoDia) return null;
  return DateTime(anio, mes, base.day, base.hour, base.minute, base.second);
}

/// Expande las ocurrencias de la serie cuyo INICIO cae en `[desde, hasta]`
/// (ambos inclusive, comparando por instante local). `inicioSerie` es el
/// ancla (primera ocurrencia, hora incluida).
///
/// El conteo de [FinRecurrencia.conteo] se cuenta desde el ancla, aunque las
/// primeras ocurrencias queden antes de `desde`. Devuelve las ocurrencias
/// ordenadas. Tiene un tope de iteraciones por seguridad.
List<DateTime> ocurrenciasEntre({
  required ReglaRecurrencia regla,
  required DateTime inicioSerie,
  required DateTime desde,
  required DateTime hasta,
}) {
  const tope = 5000;
  final fuera = <DateTime>[];
  final limiteFecha = regla.fin == FinRecurrencia.hasta ? regla.hasta : null;
  final maxConteo = regla.fin == FinRecurrencia.conteo ? regla.conteo : null;
  if (maxConteo != null && maxConteo <= 0) return fuera;

  var emitidas = 0;

  bool dentroDeFin(DateTime occ) {
    if (limiteFecha != null && _fechaDe(occ).isAfter(_fechaDe(limiteFecha))) {
      return false;
    }
    return true;
  }

  /// Acepta una ocurrencia ya validada contra el fin. Devuelve `false` cuando
  /// se alcanzó el conteo (señal para cortar el bucle).
  bool registrar(DateTime occ) {
    if (!occ.isBefore(desde) && !occ.isAfter(hasta)) {
      fuera.add(occ);
    }
    emitidas++;
    return maxConteo == null || emitidas < maxConteo;
  }

  switch (regla.frecuencia) {
    case FrecuenciaRecurrencia.diaria:
      for (var i = 0; i < tope; i++) {
        final occ = inicioSerie.add(Duration(days: i));
        if (!dentroDeFin(occ)) break;
        if (occ.isAfter(hasta)) break;
        if (!registrar(occ)) break;
      }
      break;

    case FrecuenciaRecurrencia.semanal:
      // Días ISO objetivo; si no hay, el día de inicio de la serie.
      final dias = regla.diasSemana.isNotEmpty
          ? (regla.diasSemana.toList()..sort())
          : <int>[inicioSerie.weekday];
      // Arranca en el lunes de la semana del ancla, para recorrer en orden.
      final ancla = _fechaDe(inicioSerie);
      var lunes = ancla.subtract(Duration(days: ancla.weekday - 1));
      var corta = false;
      for (var semana = 0; semana < tope && !corta; semana++) {
        for (final iso in dias) {
          final dia = lunes.add(Duration(days: semana * 7 + (iso - 1)));
          final occ = DateTime(dia.year, dia.month, dia.day,
              inicioSerie.hour, inicioSerie.minute, inicioSerie.second);
          if (occ.isBefore(inicioSerie)) continue; // antes del ancla
          if (!dentroDeFin(occ)) {
            corta = true;
            break;
          }
          if (occ.isAfter(hasta)) {
            corta = true;
            break;
          }
          if (!registrar(occ)) {
            corta = true;
            break;
          }
        }
      }
      break;

    case FrecuenciaRecurrencia.mensual:
      for (var i = 0; i < tope; i++) {
        final occ = _sumaMesesEstricto(inicioSerie, i);
        if (occ == null) continue; // el día no existe ese mes → se salta
        if (!dentroDeFin(occ)) break;
        if (occ.isAfter(hasta)) break;
        if (!registrar(occ)) break;
      }
      break;
  }

  fuera.sort();
  return fuera;
}

/// Ocurrencias cuyo inicio cae en el día local `dia` (00:00–23:59:59).
List<DateTime> ocurrenciasEnDia({
  required ReglaRecurrencia regla,
  required DateTime inicioSerie,
  required DateTime dia,
}) {
  final desde = _fechaDe(dia);
  final hasta = DateTime(dia.year, dia.month, dia.day, 23, 59, 59, 999);
  return ocurrenciasEntre(
    regla: regla,
    inicioSerie: inicioSerie,
    desde: desde,
    hasta: hasta,
  );
}

/// `true` si la serie tiene al menos una ocurrencia en el día local `dia`.
bool eventoOcurreEnDia({
  required ReglaRecurrencia regla,
  required DateTime inicioSerie,
  required DateTime dia,
}) =>
    ocurrenciasEnDia(regla: regla, inicioSerie: inicioSerie, dia: dia)
        .isNotEmpty;

/// Un recordatorio concreto a agendar: instante de disparo + id estable.
@immutable
class RecordatorioOcurrencia {
  const RecordatorioOcurrencia(this.cuando, this.notifId);
  final DateTime cuando;
  final int notifId;

  @override
  bool operator ==(Object other) =>
      other is RecordatorioOcurrencia &&
      other.cuando == cuando &&
      other.notifId == notifId;

  @override
  int get hashCode => Object.hash(cuando, notifId);
}

/// Recordatorios a agendar para un evento dentro de una ventana móvil.
///
/// - Sin recurrencia (`regla == null`): un único recordatorio con el id base
///   del evento ([notifIdDe]), si su instante es futuro.
/// - Recurrente: para cada ocurrencia en `[ahora, ahora + ventanaDias]`,
///   `cuando = ocurrencia − offset`; se incluye solo si `cuando` es futuro,
///   con id derivado de la fecha de la ocurrencia ([notifIdDeOcurrencia]).
///
/// Como los ids dependen solo de `(eventoId, fecha de ocurrencia)`, recomputar
/// la misma ventana permite cancelar exactamente lo agendado sin guardar
/// estado. Una serie cuyas ocurrencias ya pasaron devuelve lista vacía.
List<RecordatorioOcurrencia> recordatoriosVentana({
  required String eventoId,
  required ReglaRecurrencia? regla,
  required DateTime inicioSerie,
  required int? offsetMin,
  required DateTime ahora,
  int ventanaDias = 30,
}) {
  if (offsetMin == null || offsetMin < 0) {
    return const <RecordatorioOcurrencia>[];
  }

  if (regla == null) {
    final cuando = momentoRecordatorio(inicioSerie, offsetMin);
    if (cuando == null || !cuando.isAfter(ahora)) {
      return const <RecordatorioOcurrencia>[];
    }
    return <RecordatorioOcurrencia>[
      RecordatorioOcurrencia(cuando, notifIdDe(eventoId)),
    ];
  }

  final finVentana = ahora.add(Duration(days: ventanaDias));
  final ocurrencias = ocurrenciasEntre(
    regla: regla,
    inicioSerie: inicioSerie,
    desde: ahora,
    hasta: finVentana,
  );
  final fuera = <RecordatorioOcurrencia>[];
  for (final occ in ocurrencias) {
    final cuando = occ.subtract(Duration(minutes: offsetMin));
    if (!cuando.isAfter(ahora)) continue;
    fuera.add(RecordatorioOcurrencia(cuando, notifIdDeOcurrencia(eventoId, occ)));
  }
  return fuera;
}

/// Todos los ids de notificación que una serie pudo agendar en la ventana
/// `[ahora, ahora + ventanaDias]`, sin importar la regla actual: el id base
/// del evento ([notifIdDe]) más el id por-día ([notifIdDeOcurrencia]) de cada
/// día del rango.
///
/// Cualquier ocurrencia (diaria, semanal o mensual) cae en algún día del
/// rango, así que cancelar este conjunto limpia recordatorios de una regla
/// previa aunque haya cambiado (p. ej. de "lunes y miércoles" a solo
/// "lunes"). Determinista: no depende de la regla, solo de `(eventoId, día)`.
Set<int> idsCancelacionVentana({
  required String eventoId,
  required DateTime ahora,
  int ventanaDias = 30,
}) {
  final ids = <int>{notifIdDe(eventoId)};
  final hoy = _fechaDe(ahora);
  for (var i = 0; i <= ventanaDias; i++) {
    ids.add(notifIdDeOcurrencia(eventoId, hoy.add(Duration(days: i))));
  }
  return ids;
}
