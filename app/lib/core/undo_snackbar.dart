import 'package:flutter/material.dart';

import '../theme/matix_colors.dart';

/// Muestra un snackbar con la acción "Deshacer" durante unos
/// segundos (Capa 2 Paso 5: el hub indulgente).
///
/// `mensaje` describe lo que acaba de pasar ("Tarea completada",
/// "Tarea borrada"). `onUndo` es lo que se ejecuta si el usuario
/// pulsa "Deshacer". Si no pulsa, el snackbar desaparece solo.
///
/// Usar con un `BuildContext` que tenga `ScaffoldMessenger` arriba —
/// es decir, casi cualquiera (incluye los Scaffolds del HomeShell y
/// las pantallas push-eadas).
void mostrarSnackbarDeshacer(
  BuildContext context, {
  required String mensaje,
  required Future<void> Function() onUndo,
  Duration duracion = const Duration(seconds: 5),
}) {
  final messenger = ScaffoldMessenger.of(context);
  // Limpio los snackbars previos para que la fila no se acumule
  // (p. ej. si completás 3 tareas seguidas, queremos solo la última).
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(mensaje),
      duration: duracion,
      backgroundColor: MatixColors.cardHi,
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Deshacer',
        textColor: MatixColors.accent,
        onPressed: () async {
          // El cliente espera que onUndo haga el trabajo. Si falla,
          // mostramos otro snackbar con el error en vez de tragarlo
          // en silencio.
          try {
            await onUndo();
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('No se pudo deshacer: $e'),
                backgroundColor: MatixColors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    ),
  );
}
