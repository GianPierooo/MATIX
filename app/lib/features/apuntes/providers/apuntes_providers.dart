import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/apuntes_repository.dart';
import '../domain/apunte.dart';

final apuntesRepoProvider = Provider<ApuntesRepository>(
  (ref) => ApuntesRepository(ref.watch(matixClientProvider)),
);

final apuntesListProvider = FutureProvider<List<Apunte>>(
  (ref) => ref.watch(apuntesRepoProvider).listar(),
);
