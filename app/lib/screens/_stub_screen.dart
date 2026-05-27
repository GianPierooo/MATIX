import 'package:flutter/material.dart';

import '../theme/matix_colors.dart';
import '../theme/matix_spacing.dart';
import '../theme/matix_typography.dart';
import 'ajustes_screen.dart';

/// Layout reutilizable para las pantallas "próximamente" de Capa 1
/// Paso 3. Cada sección se reemplaza por su pantalla real en los
/// Pasos 4-8.
///
/// Mientras los stubs estén vivos, el icono de Ajustes del AppBar
/// es el único acceso a esa pantalla. Cuando una sección real (p.ej.
/// Inicio en el Paso 8) la reemplace, ese acceso se mueve al header
/// definitivo (avatar GP en los mockups).
class StubScreen extends StatelessWidget {
  const StubScreen({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AjustesScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(MatixSpacing.xl3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: MatixText.title),
              const SizedBox(height: MatixSpacing.m),
              Text(
                subtitle,
                style: MatixText.small,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: MatixSpacing.xl3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MatixSpacing.l,
                  vertical: MatixSpacing.m,
                ),
                decoration: const BoxDecoration(
                  color: MatixColors.cardHi,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: Text('Próximamente', style: MatixText.small),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
