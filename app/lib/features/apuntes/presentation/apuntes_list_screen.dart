import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/matix_colors.dart';
import '../domain/apunte.dart';
import '../providers/apuntes_providers.dart';
import 'apunte_desde_foto_flow.dart';
import 'editor_apunte_screen.dart';

class ApuntesListScreen extends ConsumerWidget {
  const ApuntesListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apuntes = ref.watch(apuntesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apuntes'),
        actions: [
          IconButton(
            tooltip: 'Apunte desde foto',
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => iniciarFlujoApunteDesdeFoto(context, ref),
          ),
          IconButton(
            tooltip: 'Nuevo apunte',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const EditorApunteScreen()),
            ),
          ),
        ],
      ),
      body: apuntes.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (lista) => lista.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Tu primer apunte arranca aquí.\nUsa el + para crear uno.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MatixColors.muted),
                  ),
                ),
              )
            : RefreshIndicator(
                color: MatixColors.accent,
                onRefresh: () async => ref.invalidate(apuntesListProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _Card(apunte: lista[i]),
                ),
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.apunte});
  final Apunte apunte;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  EditorApunteScreen(apunteId: apunte.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  apunte.titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.text,
                  ),
                ),
                if (apunte.contenido.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    apunte.contenido,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MatixColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      DateFormat("d MMM yyyy", 'es')
                          .format(apunte.actualizadoEn.toLocal()),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: MatixColors.muted,
                      ),
                    ),
                    const Spacer(),
                    ...apunte.etiquetas.take(3).map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: MatixColors.accent
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#$t',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: MatixColors.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
