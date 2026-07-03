import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../data/memoria_repository.dart';

/// "Sobre mí" — la memoria personal de Matix. El usuario ve, edita y borra
/// todo lo que Matix sabe de él: control total. Matix también la llena por
/// el chat ("recuerda que…"), pero acá manda el usuario.
class SobreMiScreen extends ConsumerWidget {
  const SobreMiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memoriaListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre mí'),
        actions: [
          IconButton(
            tooltip: 'Añadir',
            icon: const Icon(Icons.add),
            onPressed: () => _abrirEditor(context, ref, null),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MatixColors.accent),
        ),
        error: (e, _) => _Error(
          mensaje: e is MatixApiException ? e.message : e.toString(),
          onRetry: () => ref.invalidate(memoriaListProvider),
        ),
        data: (lista) =>
            lista.isEmpty ? const _Vacio() : _Lista(recuerdos: lista),
      ),
    );
  }
}

/// Agrupa por categoría y pinta cada recuerdo como una tarjeta tocable.
class _Lista extends ConsumerWidget {
  const _Lista({required this.recuerdos});
  final List<Recuerdo> recuerdos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupos = <String, List<Recuerdo>>{};
    for (final r in recuerdos) {
      final cat = (r.categoria == null || r.categoria!.trim().isEmpty)
          ? 'General'
          : r.categoria!.trim();
      grupos.putIfAbsent(cat, () => []).add(r);
    }
    final cats = grupos.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            'Esto es lo que Matix sabe de ti para darte tips aterrizados. '
            'Edita o borra lo que quieras — acá mandas tú.',
            style: TextStyle(fontSize: 12.5, color: MatixColors.muted, height: 1.4),
          ),
        ),
        for (final cat in cats) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              cat.toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: MatixColors.muted,
              ),
            ),
          ),
          for (final r in grupos[cat]!) _RecuerdoTile(recuerdo: r),
        ],
      ],
    );
  }
}

class _RecuerdoTile extends ConsumerWidget {
  const _RecuerdoTile({required this.recuerdo});
  final Recuerdo recuerdo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
      child: Material(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirEditor(context, ref, recuerdo),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    recuerdo.contenido,
                    style: const TextStyle(fontSize: 14, color: MatixColors.text),
                  ),
                ),
                if (!recuerdo.esencial) ...[
                  const SizedBox(width: 8),
                  const Tooltip(
                    message: 'Solo se usa cuando viene al caso',
                    child: Icon(Icons.search, size: 15, color: MatixColors.muted),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 18, color: MatixColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology_outlined,
                size: 56, color: MatixColors.muted),
            const SizedBox(height: 16),
            const Text(
              'Matix todavía no sabe nada de ti.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: MatixColors.muted,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            const Text(
              'Dile "recuerda que…" en el chat, o añade algo aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: MatixColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onRetry});
  final String mensaje;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: MatixColors.red, size: 40),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: MatixColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Abre el editor (alta si `recuerdo` es null, edición si no).
void _abrirEditor(BuildContext context, WidgetRef ref, Recuerdo? recuerdo) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MatixColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EditorRecuerdo(recuerdo: recuerdo),
  );
}

class _EditorRecuerdo extends ConsumerStatefulWidget {
  const _EditorRecuerdo({this.recuerdo});
  final Recuerdo? recuerdo;
  @override
  ConsumerState<_EditorRecuerdo> createState() => _EditorRecuerdoState();
}

class _EditorRecuerdoState extends ConsumerState<_EditorRecuerdo> {
  late final TextEditingController _contenido;
  late final TextEditingController _categoria;
  late bool _esencial;
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.recuerdo != null;

  @override
  void initState() {
    super.initState();
    _contenido = TextEditingController(text: widget.recuerdo?.contenido ?? '');
    _categoria = TextEditingController(text: widget.recuerdo?.categoria ?? '');
    _esencial = widget.recuerdo?.esencial ?? true;
  }

  @override
  void dispose() {
    _contenido.dispose();
    _categoria.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final texto = _contenido.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = 'Escribe qué quieres que Matix recuerde.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final repo = ref.read(memoriaRepositoryProvider);
    final cat = _categoria.text.trim();
    try {
      if (_esEdicion) {
        await repo.actualizar(widget.recuerdo!.id, {
          'contenido': texto,
          'categoria': cat.isEmpty ? null : cat,
          'esencial': _esencial,
        });
      } else {
        await repo.crear(
          contenido: texto,
          categoria: cat.isEmpty ? null : cat,
          esencial: _esencial,
        );
      }
      ref.invalidate(memoriaListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e is MatixApiException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Olvidar esto'),
        content: const Text('Matix dejará de saber esto sobre ti. No se '
            'puede recuperar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: MatixColors.red),
            child: const Text('Olvidar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await ref.read(memoriaRepositoryProvider).borrar(widget.recuerdo!.id);
      ref.invalidate(memoriaListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e is MatixApiException ? e.message : e.toString();
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _esEdicion ? 'Editar recuerdo' : 'Nuevo recuerdo',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: MatixColors.text,
                  ),
                ),
              ),
              if (_esEdicion)
                IconButton(
                  tooltip: 'Olvidar',
                  onPressed: _guardando ? null : _borrar,
                  icon: const Icon(Icons.delete_outline, color: MatixColors.red),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contenido,
            autofocus: !_esEdicion,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Qué recordar',
              hintText: 'Ej.: mi meta del semestre es aprobar Cálculo III',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoria,
            decoration: const InputDecoration(
              labelText: 'Categoría (opcional)',
              hintText: 'metas, personas, preferencias…',
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _esencial,
            onChanged: (v) => setState(() => _esencial = v),
            title: const Text('Tenerlo siempre presente',
                style: TextStyle(fontSize: 14, color: MatixColors.text)),
            subtitle: Text(
              _esencial
                  ? 'Matix lo usa en cada conversación.'
                  : 'Matix lo recupera solo cuando viene al caso.',
              style: const TextStyle(fontSize: 12, color: MatixColors.muted),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: MatixColors.red, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            style: MatixButtonStyles.primarioMedio,
            child: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.2),
                  )
                : Text(_esEdicion ? 'Guardar' : 'Recordar'),
          ),
        ],
      ),
    );
  }
}
