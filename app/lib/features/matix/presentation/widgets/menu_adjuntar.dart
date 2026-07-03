import 'package:flutter/material.dart';

import '../../../../theme/matix_colors.dart';

/// Las opciones del menú de adjuntar del chat (tipo WhatsApp). El orden es el
/// del mockup (`mockups/menu-adjuntar.jsx`).
enum OpcionAdjuntar { documento, fotoVideo, camara, audio, contacto }

class _OpcionVisual {
  const _OpcionVisual(this.opcion, this.label, this.icono, this.color);
  final OpcionAdjuntar opcion;
  final String label;
  final IconData icono;
  final Color color;
}

const List<_OpcionVisual> _opciones = [
  _OpcionVisual(OpcionAdjuntar.documento, 'Documento',
      Icons.description_outlined, MatixColors.purple),
  _OpcionVisual(OpcionAdjuntar.fotoVideo, 'Foto/Video',
      Icons.photo_library_outlined, MatixColors.accent),
  _OpcionVisual(OpcionAdjuntar.camara, 'Cámara',
      Icons.photo_camera_outlined, MatixColors.red),
  _OpcionVisual(OpcionAdjuntar.audio, 'Audio',
      Icons.graphic_eq, MatixColors.amber),
  _OpcionVisual(OpcionAdjuntar.contacto, 'Contacto',
      Icons.person_outline, MatixColors.green),
];

/// Abre el menú de adjuntar (bottom sheet) y devuelve la opción elegida, o
/// `null` si el usuario lo cierra. La acción concreta de cada opción la
/// resuelve el llamador (la pantalla de chat), reutilizando los flujos que
/// ya existen.
Future<OpcionAdjuntar?> mostrarMenuAdjuntar(BuildContext context) {
  return showModalBottomSheet<OpcionAdjuntar>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _MenuAdjuntarSheet(),
  );
}

class _MenuAdjuntarSheet extends StatelessWidget {
  const _MenuAdjuntarSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: MatixColors.cardHi,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: MatixColors.hairline)),
          boxShadow: [
            BoxShadow(
              color: MatixColors.shadowStrong,
              blurRadius: 50,
              offset: Offset(0, -20),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Asa.
            Container(
              width: 42,
              height: 5,
              margin: const EdgeInsets.only(top: 2, bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            // Header.
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Adjuntar',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Compártelo con Matix',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MatixColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            // Grid 4 columnas (envuelve; deja sitio para opciones futuras).
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 20,
              crossAxisSpacing: 8,
              padding: const EdgeInsets.only(top: 4),
              childAspectRatio: 0.82,
              children: [
                for (final o in _opciones)
                  _OpcionTile(
                    visual: o,
                    onTap: () => Navigator.of(context).pop(o.opcion),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcionTile extends StatelessWidget {
  const _OpcionTile({required this.visual, required this.onTap});
  final _OpcionVisual visual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: visual.color.withValues(alpha: 0.32)),
              boxShadow: [
                BoxShadow(
                  color: visual.color.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(visual.icono, color: visual.color, size: 26),
          ),
          const SizedBox(height: 9),
          Text(
            visual.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MatixColors.text,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
