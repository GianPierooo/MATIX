import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../widgets/pantalla_scroll.dart';
import '../providers/universidad_providers.dart';

class NuevoCursoScreen extends ConsumerStatefulWidget {
  const NuevoCursoScreen({super.key});
  @override
  ConsumerState<NuevoCursoScreen> createState() =>
      _NuevoCursoScreenState();
}

class _NuevoCursoScreenState extends ConsumerState<NuevoCursoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _profesor = TextEditingController();
  String? _color;
  bool _guardando = false;
  String? _error;

  static const _colores = [
    '#2D7FF9',
    '#21D07A',
    '#FF4D5E',
    '#E0A33A',
    '#9B7BFF',
    '#F06EA9',
    '#3CCFCF',
  ];

  @override
  void dispose() {
    _nombre.dispose();
    _profesor.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(cursosRepoProvider).crear(
            nombre: _nombre.text.trim(),
            profesor: _profesor.text.trim().isEmpty
                ? null
                : _profesor.text.trim(),
            color: _color,
          );
      ref.invalidate(cursosListProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // PantallaScroll garantiza el scroll, el safe area y el colchón inferior
    // (incluido el teclado); solo le pasamos el contenido del formulario.
    return PantallaScroll(
      appBar: AppBar(title: const Text('Nuevo curso')),
      formKey: _formKey,
      padding: const EdgeInsets.all(20),
      children: [
        TextFormField(
          controller: _nombre,
          decoration: const InputDecoration(labelText: 'Nombre del curso'),
          autofocus: true,
          validator: (s) =>
              (s == null || s.trim().isEmpty) ? 'Pon un nombre' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _profesor,
          decoration:
              const InputDecoration(labelText: 'Profesor/a (opcional)'),
        ),
        const SizedBox(height: 20),
        const Text('COLOR',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: MatixColors.muted,
            )),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          children: _colores.map((c) {
            final sel = _color == c;
            final color =
                Color(0xFF000000 | int.parse(c.substring(1), radix: 16));
            return GestureDetector(
              onTap: () => setState(() => _color = sel ? null : c),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border:
                      sel ? Border.all(color: Colors.white, width: 3) : null,
                ),
              ),
            );
          }).toList(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: MatixColors.red)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.2),
                )
              : const Text('Crear curso'),
        ),
      ],
    );
  }
}
