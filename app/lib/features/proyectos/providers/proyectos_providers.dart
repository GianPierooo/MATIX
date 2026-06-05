import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/proyectos_repository.dart';
import '../domain/proyecto.dart';

final proyectosRepositoryProvider = Provider<ProyectosRepository>((ref) {
  return ProyectosRepository(ref.watch(matixClientProvider));
});

final proyectosListProvider = FutureProvider<List<Proyecto>>((ref) async {
  return ref.watch(proyectosRepositoryProvider).listar();
});

/// Proyecto por id — se invalida al editar.
final proyectoProvider =
    FutureProvider.family<Proyecto, String>((ref, id) async {
  return ref.watch(proyectosRepositoryProvider).obtener(id);
});

/// Descomposición (árbol) del proyecto, para mostrarla en el detalle.
final arbolProyectoProvider =
    FutureProvider.family<List<NodoArbol>, String>((ref, id) async {
  return ref.watch(proyectosRepositoryProvider).arbol(id);
});
