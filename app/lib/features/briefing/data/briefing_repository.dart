import '../../../api/matix_client.dart';

/// Estructura del briefing del día tal como lo devuelve el cerebro
/// (`GET /api/v1/briefing/hoy`). Capa 8 reducida · Paso 1.
class BriefingHoy {
  const BriefingHoy({
    required this.fecha,
    required this.diaSemana,
    required this.saludo,
    required this.eventos,
    required this.tareasHoy,
    required this.tareasVencidasTotal,
    required this.tareasVencidasMasAntiguaDias,
    required this.alertas,
    required this.resumenCorto,
    required this.textoParaVoz,
  });

  final String fecha;
  final String diaSemana;
  final String saludo;
  final List<EventoBriefing> eventos;
  final List<TareaBriefing> tareasHoy;
  final int tareasVencidasTotal;
  final int tareasVencidasMasAntiguaDias;
  final List<AlertaBriefing> alertas;
  final String resumenCorto;
  final String textoParaVoz;

  factory BriefingHoy.fromJson(Map<String, dynamic> j) {
    final venc = (j['tareas_vencidas'] as Map?) ?? const {};
    return BriefingHoy(
      fecha: j['fecha'] as String,
      diaSemana: j['dia_semana'] as String,
      saludo: j['saludo'] as String,
      eventos: ((j['eventos'] as List?) ?? const [])
          .map((e) => EventoBriefing.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      tareasHoy: ((j['tareas_hoy'] as List?) ?? const [])
          .map((e) => TareaBriefing.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      tareasVencidasTotal: (venc['total'] as num?)?.toInt() ?? 0,
      tareasVencidasMasAntiguaDias:
          (venc['mas_antigua_dias'] as num?)?.toInt() ?? 0,
      alertas: ((j['alertas'] as List?) ?? const [])
          .map((e) => AlertaBriefing.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      resumenCorto: j['resumen_corto'] as String,
      textoParaVoz: j['texto_para_voz'] as String,
    );
  }
}

class EventoBriefing {
  const EventoBriefing({
    required this.hora,
    required this.horaFin,
    required this.titulo,
    this.ubicacion,
    this.todoElDia = false,
    this.esDeGoogle = false,
  });

  final String hora;
  final String horaFin;
  final String titulo;
  final String? ubicacion;
  final bool todoElDia;
  final bool esDeGoogle;

  factory EventoBriefing.fromJson(Map<String, dynamic> j) => EventoBriefing(
        hora: j['hora'] as String? ?? '',
        horaFin: j['hora_fin'] as String? ?? '',
        titulo: j['titulo'] as String,
        ubicacion: j['ubicacion'] as String?,
        todoElDia: j['todo_el_dia'] as bool? ?? false,
        esDeGoogle: j['es_de_google'] as bool? ?? false,
      );
}

class TareaBriefing {
  const TareaBriefing({
    required this.titulo,
    required this.prioridad,
    this.contexto,
    required this.venceEn,
  });

  final String titulo;
  final String prioridad;
  final String? contexto;
  final String venceEn;

  factory TareaBriefing.fromJson(Map<String, dynamic> j) => TareaBriefing(
        titulo: j['titulo'] as String,
        prioridad: (j['prioridad'] as String?) ?? 'media',
        contexto: j['contexto'] as String?,
        venceEn: j['vence_en'] as String,
      );
}

class AlertaBriefing {
  const AlertaBriefing({required this.tipo, required this.mensaje});

  final String tipo;
  final String mensaje;

  factory AlertaBriefing.fromJson(Map<String, dynamic> j) => AlertaBriefing(
        tipo: j['tipo'] as String,
        mensaje: j['mensaje'] as String,
      );
}

class BriefingRepository {
  BriefingRepository(this._client);
  final MatixClient _client;

  Future<BriefingHoy> hoy() async {
    final j = await _client.getOne('/api/v1/briefing/hoy');
    return BriefingHoy.fromJson(j);
  }
}
