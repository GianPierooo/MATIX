import 'dart:convert';

import 'package:flutter/services.dart';

import 'pantalla_aplanado.dart';

/// Resultado de leer la pantalla (Tier C.0). Procesa y descarta: el texto vive
/// solo el tiempo de mandarlo al modelo; no se persiste.
class LecturaPantalla {
  const LecturaPantalla({
    required this.activo,
    required this.ok,
    this.app = '',
    this.texto = '',
    this.motivo,
  });

  /// `true` si el servicio de accesibilidad está activado.
  final bool activo;

  /// `true` si se obtuvo contenido legible de la app del usuario.
  final bool ok;

  /// Paquete de la app leída (p. ej. com.whatsapp).
  final String app;

  /// Texto aplanado de la pantalla (DATO para el modelo).
  final String texto;

  /// Por qué no se pudo leer ('sin_ventana' = solo se veía Matix).
  final String? motivo;
}

/// Lee la pantalla activa del teléfono vía el servicio nativo de accesibilidad
/// (`dev.matix.matix/accesibilidad`). SOLO LECTURA: no hay métodos que toquen,
/// escriban ni deslicen — el canal nativo tampoco los expone.
class AccesibilidadService {
  AccesibilidadService({MethodChannel? canal})
      : _canal = canal ?? const MethodChannel('dev.matix.matix/accesibilidad');

  final MethodChannel _canal;

  /// ¿El usuario activó el servicio en Ajustes > Accesibilidad?
  Future<bool> activa() async {
    try {
      return await _canal.invokeMethod<bool>('estaActivo') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre Ajustes > Accesibilidad para que el usuario lo active.
  Future<void> abrirAjustes() async {
    try {
      await _canal.invokeMethod('abrirAjustes');
    } on PlatformException {
      // sin-op: la pantalla de activación ya explica el camino manual
    }
  }

  /// Captura la pantalla bajo demanda y la aplana a texto. Si el servicio está
  /// apagado o no hay ventana legible, lo refleja en el resultado (degradación
  /// limpia: la UI guía al usuario, nunca crashea).
  Future<LecturaPantalla> leer() async {
    if (!await activa()) {
      return const LecturaPantalla(activo: false, ok: false, motivo: 'inactivo');
    }
    final String? crudo;
    try {
      crudo = await _canal.invokeMethod<String>('leerPantalla');
    } on PlatformException {
      return const LecturaPantalla(activo: true, ok: false, motivo: 'error');
    }
    if (crudo == null || crudo.isEmpty) {
      // Servicio activado pero sin instancia viva todavía.
      return const LecturaPantalla(activo: false, ok: false, motivo: 'sin_instancia');
    }
    final mapa = jsonDecode(crudo) as Map<String, dynamic>;
    if (mapa['ok'] != true) {
      return LecturaPantalla(
        activo: true,
        ok: false,
        motivo: (mapa['motivo'] as String?) ?? 'sin_ventana',
      );
    }
    return LecturaPantalla(
      activo: true,
      ok: true,
      app: appDeCaptura(mapa),
      texto: aplanarPantalla(mapa),
    );
  }

  // ── Tier C.1 · ACCIÓN (tap / setText), blindada ────────────────────

  /// Lee el texto del primer nodo con ese viewId (verificar encabezado, caja).
  Future<String?> leerTextoPorId(String viewId) async {
    try {
      return await _canal.invokeMethod<String>('leerTextoPorId', {'viewId': viewId});
    } on PlatformException {
      return null;
    }
  }

  /// Ejecuta una acción estructurada. Devuelve true si el servicio nativo la
  /// realizó (allowlist OK, nodo encontrado, sin kill switch).
  Future<bool> ejecutarAccion(Map<String, dynamic> accion) async {
    try {
      final crudo = await _canal.invokeMethod<String>('ejecutarAccion', {
        'accion': jsonEncode(accion),
      });
      if (crudo == null) return false;
      return (jsonDecode(crudo) as Map<String, dynamic>)['ok'] == true;
    } on PlatformException {
      return false;
    }
  }

  /// Arranca un flujo de acción: limpia el kill switch y muestra la
  /// notificación con el botón «Detener».
  Future<void> iniciarFlujo() async {
    try {
      await _canal.invokeMethod('iniciarFlujo');
    } on PlatformException {
      // sin-op
    }
  }

  /// Log VISIBLE de cada paso (se ve en la notificación, aunque WhatsApp esté
  /// en primer plano): «Escribiendo…», «Enviando…».
  Future<void> actualizarFlujo(String texto) async {
    try {
      await _canal.invokeMethod('actualizarFlujo', {'texto': texto});
    } on PlatformException {
      // sin-op
    }
  }

  /// Cierra el flujo dejando un aviso final con el resultado (o lo quita si
  /// `texto` está vacío).
  Future<void> terminarFlujo([String texto = '']) async {
    try {
      await _canal.invokeMethod('terminarFlujo', {'texto': texto});
    } on PlatformException {
      // sin-op
    }
  }

  /// Kill switch desde la app (voz «para»/«detente», botón Cancelar).
  Future<void> abortar() async {
    try {
      await _canal.invokeMethod('abortar');
    } on PlatformException {
      // sin-op
    }
  }

  /// ¿El bucle fue abortado (kill switch)?
  Future<bool> estaAbortado() async {
    try {
      return await _canal.invokeMethod<bool>('estaAbortado') ?? true;
    } on PlatformException {
      return true; // ante la duda, abortar
    }
  }

  /// Muestra el gate de confirmación como overlay sobre WhatsApp. Devuelve
  /// 'enviar' | 'cancelar' | 'sin_overlay'.
  Future<String> confirmarEnvio(String resumen) async {
    try {
      return await _canal.invokeMethod<String>('confirmarEnvio', {'resumen': resumen}) ??
          'cancelar';
    } on PlatformException {
      return 'cancelar';
    }
  }
}
