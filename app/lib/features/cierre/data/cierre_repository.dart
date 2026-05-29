import '../../../api/matix_client.dart';

/// Cierre del día tal como lo devuelve el cerebro
/// (`GET /api/v1/briefing/cierre`). Capa 8 · Paso 2.
class CierreHoy {
  const CierreHoy({
    required this.fecha,
    required this.diaSemana,
    required this.saludo,
    required this.hechas,
    required this.pendientesHoy,
    required this.tareasManana,
    required this.eventosManana,
    required this.cierreFrase,
    required this.resumenCorto,
    required this.textoParaVoz,
  });

  final String fecha;
  final String diaSemana;
  final String saludo;
  final List<TareaHecha> hechas;
  final List<TareaPendiente> pendientesHoy;
  final List<TareaPendiente> tareasManana;
  final List<EventoManana> eventosManana;
  final String cierreFrase;
  final String resumenCorto;
  final String textoParaVoz;

  factory CierreHoy.fromJson(Map<String, dynamic> j) => CierreHoy(
        fecha: j['fecha'] as String,
        diaSemana: j['dia_semana'] as String,
        saludo: j['saludo'] as String,
        hechas: ((j['hechas'] as List?) ?? const [])
            .map((e) => TareaHecha.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        pendientesHoy: ((j['pendientes_hoy'] as List?) ?? const [])
            .map((e) => TareaPendiente.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        tareasManana: ((j['tareas_manana'] as List?) ?? const [])
            .map((e) => TareaPendiente.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        eventosManana: ((j['eventos_manana'] as List?) ?? const [])
            .map((e) => EventoManana.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        cierreFrase: j['cierre_frase'] as String? ?? '',
        resumenCorto: j['resumen_corto'] as String? ?? '',
        textoParaVoz: j['texto_para_voz'] as String? ?? '',
      );
}

class TareaHecha {
  const TareaHecha({required this.titulo, this.contexto});
  final String titulo;
  final String? contexto;

  factory TareaHecha.fromJson(Map<String, dynamic> j) => TareaHecha(
        titulo: j['titulo'] as String,
        contexto: j['contexto'] as String?,
      );
}

class TareaPendiente {
  const TareaPendiente({
    required this.titulo,
    this.prioridad = 'media',
    this.contexto,
  });
  final String titulo;
  final String prioridad;
  final String? contexto;

  factory TareaPendiente.fromJson(Map<String, dynamic> j) => TareaPendiente(
        titulo: j['titulo'] as String,
        prioridad: (j['prioridad'] as String?) ?? 'media',
        contexto: j['contexto'] as String?,
      );
}

class EventoManana {
  const EventoManana({
    required this.hora,
    required this.titulo,
    this.todoElDia = false,
  });
  final String hora;
  final String titulo;
  final bool todoElDia;

  factory EventoManana.fromJson(Map<String, dynamic> j) => EventoManana(
        hora: j['hora'] as String? ?? '',
        titulo: j['titulo'] as String,
        todoElDia: j['todo_el_dia'] as bool? ?? false,
      );
}

class CierreRepository {
  CierreRepository(this._client);
  final MatixClient _client;

  Future<CierreHoy> hoy() async {
    final j = await _client.getOne('/api/v1/briefing/cierre');
    return CierreHoy.fromJson(j);
  }
}
