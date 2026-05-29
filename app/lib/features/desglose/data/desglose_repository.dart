import '../../../api/matix_client.dart';
import '../domain/paso_propuesto.dart';

/// Resultado del desglose: si la tarea ya era atómica, `esAtomica` es
/// true y `pasos` viene vacía.
class ResultadoDesglose {
  const ResultadoDesglose({required this.esAtomica, required this.pasos});
  final bool esAtomica;
  final List<PasoPropuesto> pasos;
}

/// Llama al cerebro para partir una tarea en pasos accionables
/// (Capa 7 · Desglose). El cerebro NO crea nada — devuelve candidatos
/// que el usuario revisa y confirma.
class DesgloseRepository {
  DesgloseRepository(this._client);
  final MatixClient _client;

  Future<ResultadoDesglose> desglosar({
    required String titulo,
    String? nota,
  }) async {
    final j = await _client.post('/api/v1/matix/desglosar-tarea', {
      'titulo': titulo,
      if (nota != null && nota.trim().isNotEmpty) 'nota': nota,
    });
    final crudas = (j['pasos'] as List?) ?? const [];
    final pasos = crudas
        .cast<Map<String, dynamic>>()
        .map(PasoPropuesto.fromCerebro)
        .where((p) => p.titulo.isNotEmpty)
        .toList();
    return ResultadoDesglose(
      esAtomica: (j['es_atomica'] as bool?) ?? pasos.isEmpty,
      pasos: pasos,
    );
  }
}
