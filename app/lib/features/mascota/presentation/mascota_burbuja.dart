import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/markdown_plano.dart';
import '../../../theme/matix_colors.dart';
import '../domain/personalidad.dart';
import '../providers/mascota_providers.dart';
import 'avatar_matix.dart';

/// Burbuja GLOBAL de la mascota: SOLO la despedida (al salir de la app). Vive en
/// el HomeShell, sobre todas las pestañas.
///
/// El robot-compañero del día (bolita colapsada ⇄ tarjeta expandida) NO vive
/// aquí: es [PresenciaMatix], que solo se monta en Inicio. Antes esta burbuja
/// pintaba ADEMÁS una "bolita" persistente cuando no había mensaje, lo que
/// duplicaba el robot en Inicio (dos avatares) y, peor, su tap navegaba al chat
/// en vez de alternar estados. Por eso, sin mensaje, no dibuja NADA (no ocupa ni
/// intercepta): así hay un solo robot y no tapa el contenido del timeline.
class MascotaBurbuja extends ConsumerWidget {
  const MascotaBurbuja({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msg = ref.watch(mascotaControllerProvider);
    final ctrl = ref.read(mascotaControllerProvider.notifier);

    // Anclada a la IZQUIERDA. Sin mensaje (caso normal): nada en pantalla — el
    // compañero es PresenciaMatix en Inicio. Con mensaje: la burbuja de despedida.
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
            ? const SizedBox.shrink(key: ValueKey('vacio'))
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
