import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../domain/personalidad.dart';
import '../providers/mascota_providers.dart';
import 'avatar_matix.dart';

/// Tarjeta de saludo en Inicio: el robot Matix te recibe, cálido y con un toque
/// de contexto (franja del día + un dato rápido). Rápida y barata (template, sin
/// llamar al modelo). Tocarla abre el chat. Si la mascota está apagada, no se
/// muestra.
class SaludoMascotaCard extends ConsumerWidget {
  const SaludoMascotaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(mascotaConfigProvider);
    if (!cfg.habilitada) return const SizedBox.shrink();

    final ctx = ref.watch(contextoMascotaProvider);
    final ahora = DateTime.now();
    final msg = saludo(franjaDe(ahora.hour), ctx, semilla: ahora.day + ahora.hour);

    void abrirChat() =>
        ref.read(mascotaControllerProvider.notifier).responder('Hablemos');
    void verDia() =>
        ref.read(mascotaControllerProvider.notifier).responder('Ver mi día');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: abrirChat,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MatixColors.accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AvatarMatix(size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.texto,
                        style: const TextStyle(
                          fontSize: 14,
                          color: MatixColors.text,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _MiniChip(texto: 'Hablemos', primario: true, onTap: abrirChat),
                          const SizedBox(width: 8),
                          _MiniChip(texto: 'Ver mi día', primario: false, onTap: verDia),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.texto,
    required this.primario,
    required this.onTap,
  });
  final String texto;
  final bool primario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primario
          ? MatixColors.accent
          : MatixColors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: primario ? Colors.white : MatixColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
