import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Secciones a las que Matix puede llevar al usuario desde el chat
/// («llévame a Universidad», «abre Finanzas»). El cerebro las emite en
/// `ChatResponse.navegacion`; el `HomeShell` las escucha y abre la
/// pantalla (cambia de pestaña o empuja la ruta).
///
/// Los nombres deben coincidir EXACTO con el enum del cerebro
/// (`_SECCIONES_NAVEGABLES` en `tools.py`).
enum SeccionMatix {
  inicio,
  tareas,
  calendario,
  proyectos,
  universidad,
  finanzas,
  apuntes,
  ajustes,
}

/// Traduce el string del cerebro a la sección, o `null` si no la
/// reconocemos (defensa: una sección nueva en el cerebro no debe
/// romper la app vieja).
SeccionMatix? seccionMatixDeString(String? raw) => switch (raw) {
      'inicio' => SeccionMatix.inicio,
      'tareas' => SeccionMatix.tareas,
      'calendario' => SeccionMatix.calendario,
      'proyectos' => SeccionMatix.proyectos,
      'universidad' => SeccionMatix.universidad,
      'finanzas' => SeccionMatix.finanzas,
      'apuntes' => SeccionMatix.apuntes,
      'ajustes' => SeccionMatix.ajustes,
      _ => null,
    };

/// Objetivo de navegación pendiente. La capa de chat lo SETEA cuando un
/// turno trae `navegacion`; el `HomeShell` lo OBSERVA, navega, y lo
/// vuelve a `null`. Es one-shot: un valor → una navegación.
final objetivoNavegacionProvider = StateProvider<SeccionMatix?>((_) => null);
