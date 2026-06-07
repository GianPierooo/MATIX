import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/markdown_plano.dart';
import '../../../theme/matix_colors.dart';
import '../../matix/providers/navegacion_matix_provider.dart';
import '../domain/personalidad.dart';
import '../providers/mascota_providers.dart';
import 'avatar_matix.dart';

/// Burbuja flotante de la mascota: el robot surge con un mensaje y opciones
/// tocables. Vive sobre el contenido del HomeShell, encima de la barra inferior.
///
/// SIEMPRE visible y anclada ABAJO A LA IZQUIERDA: si no hay mensaje, queda la
/// "bolita" del robot (tocarla abre el chat de Matix); cuando hay mensaje, la
/// bolita se expande a la burbuja con opciones. Persistente entre pestañas
/// (vive en el HomeShell).
class MascotaBurbuja extends ConsumerWidget {
  const MascotaBurbuja({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msg = ref.watch(mascotaControllerProvider);
    final ctrl = ref.read(mascotaControllerProvider.notifier);

    // Todo anclado a la IZQUIERDA (no full-width): bolita o burbuja chica.
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.18), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: msg == null
            // Persistente: la bolita del robot, abajo a la izquierda. Tocar =
            // abrir el chat de Matix.
            ? _Bolita(
                key: const ValueKey('bolita'),
                onTap: () => ref
                    .read(objetivoNavegacionProvider.notifier)
                    .state = SeccionMatix.matix,
              )
            : ConstrainedBox(
                key: ValueKey(msg.texto),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.86,
                ),
                child: _Burbuja(
                  msg: msg,
                  onOpcion: ctrl.responder,
                  onCerrar: ctrl.descartar,
                ),
              ),
      ),
    );
  }
}

/// Bolita persistente del robot (estado colapsado): solo el avatar, tocable.
class _Bolita extends StatelessWidget {
  const _Bolita({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MatixColors.cardHi,
            border: Border.all(color: MatixColors.accent.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: const AvatarMatix(size: 44),
        ),
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.msg,
    required this.onOpcion,
    required this.onCerrar,
  });

  final MensajeMascota msg;
  final void Function(String) onOpcion;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            color: MatixColors.cardHi,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MatixColors.accent.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AvatarMatix(size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        limpiarMarkdown(msg.texto),
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: MatixColors.text,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onCerrar,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: MatixColors.muted),
                    ),
                  ),
                ],
              ),
              if (msg.opciones.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 50),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < msg.opciones.length; i++)
                        _ChipMascota(
                          texto: msg.opciones[i],
                          primario: i == 0,
                          onTap: () => onOpcion(msg.opciones[i]),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip tocable de la burbuja (mismo lenguaje visual que las opciones de Matix).
class _ChipMascota extends StatelessWidget {
  const _ChipMascota({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
