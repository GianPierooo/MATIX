import 'package:flutter/material.dart';

import '../../../theme/matix_colors.dart';

/// Modelos ligeros para los selectores de "Nueva Tarea" — solo los
/// campos que el dropdown necesita.

@immutable
class CategoriaRef {
  const CategoriaRef({required this.id, required this.nombre, this.color});
  final String id;
  final String nombre;
  final String? color;

  factory CategoriaRef.fromJson(Map<String, dynamic> j) => CategoriaRef(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        color: j['color'] as String?,
      );

  Color get colorOrAccent => _parseHex(color) ?? MatixColors.accent;
}

@immutable
class CursoRef {
  const CursoRef({required this.id, required this.nombre, this.color});
  final String id;
  final String nombre;
  final String? color;

  factory CursoRef.fromJson(Map<String, dynamic> j) => CursoRef(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        color: j['color'] as String?,
      );

  Color get colorOrAccent => _parseHex(color) ?? MatixColors.accent;
}

@immutable
class ProyectoRef {
  const ProyectoRef({
    required this.id,
    required this.nombre,
    required this.estado,
    this.color,
  });
  final String id;
  final String nombre;
  final String estado; // 'activo' | 'aparcado' | 'terminado'
  final String? color;

  bool get esActivo => estado == 'activo';

  factory ProyectoRef.fromJson(Map<String, dynamic> j) => ProyectoRef(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        estado: j['estado'] as String,
        color: j['color'] as String?,
      );

  Color get colorOrAccent => _parseHex(color) ?? MatixColors.accent;
}

Color? _parseHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.replaceFirst('#', '');
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
