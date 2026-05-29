import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/tracks_repository.dart';
import '../domain/track.dart';

final tracksRepoProvider = Provider<TracksRepository>(
  (ref) => TracksRepository(ref.watch(matixClientProvider)),
);

final tracksListProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(tracksRepoProvider).listar(),
);
