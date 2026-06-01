import 'package:flutter/material.dart';

import '../theme/matix_colors.dart';
import '../theme/matix_spacing.dart';

/// Wrappers de scroll seguros para que NINGÚN apartado corte contenido.
///
/// El problema que resuelven:
/// - El `HomeShell` usa `Scaffold(extendBody: true)`, así que las pestañas se
///   dibujan BAJO la barra inferior: sin padding extra, el fondo queda tapado.
/// - Los formularios deben dejar que el teclado no tape el input.
/// - Los bottom sheets con contenido alto (o con teclado) cortan si no
///   scrollean.
///
/// Usa estos wrappers en pantallas y hojas nuevas y heredas el comportamiento
/// correcto sin tener que acordarte:
/// - [PantallaScroll] para una pantalla completa (Scaffold + scroll + safe
///   area + colchón bajo la barra + teclado).
/// - [HojaScroll] para el contenido de un `showModalBottomSheet`
///   (scroll + colchón del teclado + safe area + asa).

/// Pantalla con scroll garantizado.
///
/// - El body siempre scrollea (un `ListView`), así nada queda cortado.
/// - Reserva colchón inferior: con [bajoNav] true (pestañas del HomeShell)
///   usa [MatixLayout.bottomNavGuard]; si no, el safe area del sistema + algo.
/// - `resizeToAvoidBottomInset` (default de Scaffold) sube el campo enfocado
///   cuando aparece el teclado.
class PantallaScroll extends StatelessWidget {
  const PantallaScroll({
    super.key,
    required this.children,
    this.appBar,
    this.floatingActionButton,
    this.bajoNav = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: MatixSpacing.xl,
      vertical: MatixSpacing.l,
    ),
    this.controller,
    this.onRefresh,
    this.formKey,
  });

  /// Hijos del scroll (en orden vertical).
  final List<Widget> children;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  /// Si se pasa, envuelve el scroll en un `Form` (para pantallas de
  /// formulario, así el teclado y la validación funcionan sin boilerplate).
  final GlobalKey<FormState>? formKey;

  /// `true` si la pantalla vive en una pestaña del HomeShell (Inicio, Tareas,
  /// Calendario, Proyectos, chat): reserva el alto de la barra inferior.
  final bool bajoNav;

  /// Padding base del contenido. El colchón inferior se SUMA a este.
  final EdgeInsets padding;
  final ScrollController? controller;

  /// Si se pasa, envuelve en `RefreshIndicator` (tirar para refrescar).
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final extra = bajoNav
        ? MatixLayout.bottomNavGuard(context)
        : MediaQuery.viewPaddingOf(context).bottom + MatixSpacing.xl3;
    final pad = padding.copyWith(bottom: padding.bottom + extra);

    Widget contenido = ListView(
      controller: controller,
      padding: pad,
      children: children,
    );
    if (formKey != null) {
      contenido = Form(key: formKey, child: contenido);
    }
    if (onRefresh != null) {
      contenido = RefreshIndicator(
        color: MatixColors.accent,
        onRefresh: onRefresh!,
        child: contenido,
      );
    }

    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      // El bottom lo maneja el padding (incluye safe area / barra). El top lo
      // cubre el AppBar si existe; si no, SafeArea protege la barra de estado.
      body: SafeArea(
        top: appBar == null,
        bottom: false,
        child: contenido,
      ),
    );
  }
}

/// Contenido de un bottom sheet con scroll y teclado seguros.
///
/// Úsalo como `builder` de `showModalBottomSheet` (idealmente con
/// `isScrollControlled: true` cuando el contenido sea alto o tenga inputs):
/// el contenido scrollea si no entra, sube por encima del teclado
/// (`viewInsets`) y respeta el safe area inferior.
class HojaScroll extends StatelessWidget {
  const HojaScroll({
    super.key,
    required this.children,
    this.conAsa = true,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
  });

  final List<Widget> children;

  /// El "asa" gris superior del sheet.
  final bool conAsa;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: padding.copyWith(bottom: padding.bottom + teclado),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (conAsa) ...[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
