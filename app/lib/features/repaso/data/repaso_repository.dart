import '../../../api/matix_client.dart';

/// Una tarea que se pasó de fecha (parte del repaso semanal). Lleva
/// `id` para poder reprogramarla desde el repaso.
class TareaVencidaRepaso {
  const TareaVencidaRepaso({
    required this.id,
    required this.titulo,
    this.contexto,
    this.venceEn,
  });

  final String id;
  final String titulo;
  final String? contexto;
  final String? venceEn;

  factory TareaVencidaRepaso.fromJson(Map<String, dynamic> j) =>
      TareaVencidaRepaso(
        id: j['id'].toString(),
        titulo: (j['titulo'] as String?) ?? '',
        contexto: j['contexto'] as String?,
        venceEn: j['vence_en'] as String?,
      );
}

/// Repaso semanal sintetizado por Matix (`GET /briefing/repaso-semanal`).
/// `resumen` y `focos` los redacta el LLM; el resto son datos del hub.
class RepasoSemanal {
  const RepasoSemanal({
    required this.semanaDesde,
    required this.semanaHasta,
    required this.resumen,
    required this.focos,
    required this.completadas,
    required this.vencidas,
    required this.eventos,
    required this.apuntesNuevos,
  });

  final String semanaDesde;
  final String semanaHasta;
  final String resumen;
  final List<String> focos;
  final int completadas;
  final List<TareaVencidaRepaso> vencidas;
  final int eventos;
  final int apuntesNuevos;

  factory RepasoSemanal.fromJson(Map<String, dynamic> j) => RepasoSemanal(
        semanaDesde: (j['semana_desde'] as String?) ?? '',
        semanaHasta: (j['semana_hasta'] as String?) ?? '',
        resumen: (j['resumen'] as String?) ?? '',
        focos: ((j['focos'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        completadas: (j['completadas'] as num?)?.toInt() ?? 0,
        vencidas: ((j['vencidas'] as List?) ?? const [])
            .map((e) =>
                TareaVencidaRepaso.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        eventos: (j['eventos'] as num?)?.toInt() ?? 0,
        apuntesNuevos: (j['apuntes_nuevos'] as num?)?.toInt() ?? 0,
      );
}

class RepasoRepository {
  RepasoRepository(this._client);
  final MatixClient _client;

  Future<RepasoSemanal> obtener() async {
    final j = await _client.getOne('/api/v1/briefing/repaso-semanal');
    return RepasoSemanal.fromJson(j);
  }
}
