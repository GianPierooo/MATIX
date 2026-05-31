// Construcción de payload con `if (x != null)`, igual que el resto de repos.
// ignore_for_file: use_null_aware_elements

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Un hecho duradero que Matix sabe del usuario (memoria personal).
class Recuerdo {
  const Recuerdo({
    required this.id,
    required this.contenido,
    this.categoria,
    this.esencial = true,
  });

  final String id;
  final String contenido;

  /// Para agrupar en la pantalla (quien_soy, metas, personas…). Puede ser null.
  final String? categoria;

  /// Si va SIEMPRE en el contexto de Matix (esencial) o solo se recupera por
  /// relevancia (RAG).
  final bool esencial;

  factory Recuerdo.fromJson(Map<String, dynamic> j) => Recuerdo(
        id: j['id'] as String,
        contenido: j['contenido'] as String,
        categoria: j['categoria'] as String?,
        esencial: j['esencial'] as bool? ?? true,
      );
}

/// Wrapper sobre `/api/v1/memoria`. La memoria vive en el cerebro (la inyecta
/// en su contexto); acá el usuario la ve y la controla del todo.
class MemoriaRepository {
  MemoriaRepository(this._client);
  final MatixClient _client;

  Future<List<Recuerdo>> listar() async {
    final raw = await _client.getList('/api/v1/memoria');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Recuerdo.fromJson)
        .toList(growable: false);
  }

  Future<Recuerdo> crear({
    required String contenido,
    String? categoria,
    bool esencial = true,
  }) async {
    final j = await _client.post('/api/v1/memoria', {
      'contenido': contenido,
      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      'esencial': esencial,
    });
    return Recuerdo.fromJson(j);
  }

  Future<Recuerdo> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/memoria/$id', cambios);
    return Recuerdo.fromJson(j);
  }

  Future<void> borrar(String id) async {
    await _client.delete('/api/v1/memoria/$id');
  }
}

final memoriaRepositoryProvider = Provider<MemoriaRepository>(
  (ref) => MemoriaRepository(ref.watch(matixClientProvider)),
);

/// Lista de recuerdos. Se refresca con `ref.invalidate` (la usa el chat
/// cuando Matix toca la memoria, y la propia pantalla tras editar/borrar).
final memoriaListProvider = FutureProvider<List<Recuerdo>>(
  (ref) => ref.watch(memoriaRepositoryProvider).listar(),
);
