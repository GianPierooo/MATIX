import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../providers/apuntes_providers.dart';

class EditorApunteScreen extends ConsumerStatefulWidget {
  const EditorApunteScreen({super.key, this.apunteId, this.avisoOcr});
  final String? apunteId;

  /// Capa 7 · Paso 1: si la pantalla se abre tras un "apunte desde
  /// foto" y el OCR falló, ese mensaje se pinta como banner ámbar.
  /// Null en cualquier otro caso.
  final String? avisoOcr;

  @override
  ConsumerState<EditorApunteScreen> createState() =>
      _EditorApunteScreenState();
}

class _EditorApunteScreenState extends ConsumerState<EditorApunteScreen> {
  final _titulo = TextEditingController();
  final _contenido = TextEditingController();
  final _etiquetas = TextEditingController();
  bool _cargando = false;
  bool _guardando = false;
  String? _error;
  bool get _esEdicion => widget.apunteId != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) _cargar();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _contenido.dispose();
    _etiquetas.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final a =
          await ref.read(apuntesRepoProvider).obtener(widget.apunteId!);
      setState(() {
        _titulo.text = a.titulo;
        _contenido.text = a.contenido;
        _etiquetas.text = a.etiquetas.join(', ');
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (_titulo.text.trim().isEmpty) {
      setState(() => _error = 'Pon un título');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final tags = _etiquetas.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (_esEdicion) {
        await ref.read(apuntesRepoProvider).actualizar(widget.apunteId!, {
          'titulo': _titulo.text.trim(),
          'contenido': _contenido.text,
          'etiquetas': tags,
        });
      } else {
        await ref.read(apuntesRepoProvider).crear(
              titulo: _titulo.text.trim(),
              contenido: _contenido.text,
              etiquetas: tags,
            );
      }
      ref.invalidate(apuntesListProvider);
      if (mounted) Navigator.of(context).pop();
    } on MatixApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar apunte'),
        content: const Text('No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatixColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apuntesRepoProvider).borrar(widget.apunteId!);
    ref.invalidate(apuntesListProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar apunte' : 'Nuevo apunte'),
        actions: [
          if (_esEdicion)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: MatixColors.red),
              onPressed: _borrar,
            ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: MatixColors.accent),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.avisoOcr != null) ...[
                    _BannerOcrFallo(mensaje: widget.avisoOcr!),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _titulo,
                    decoration: const InputDecoration(labelText: 'Título'),
                    autofocus: !_esEdicion,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contenido,
                    decoration: const InputDecoration(
                      labelText: 'Contenido',
                      alignLabelWithHint: true,
                    ),
                    minLines: 6,
                    maxLines: 20,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _etiquetas,
                    decoration: const InputDecoration(
                      labelText: 'Etiquetas (separadas por coma)',
                      hintText: 'ej. idea, urgente, matix',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: const TextStyle(color: MatixColors.red)),
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
                        : Text(_esEdicion ? 'Guardar' : 'Crear apunte'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BannerOcrFallo extends StatelessWidget {
  const _BannerOcrFallo({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MatixColors.amber.withValues(alpha: 0.12),
        border:
            Border.all(color: MatixColors.amber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.image_search,
              color: MatixColors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                fontSize: 12.5,
                color: MatixColors.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
