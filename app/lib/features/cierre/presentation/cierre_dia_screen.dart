import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_button_styles.dart';
import '../../push/presentation/confirmar_pendientes_card.dart';
import '../domain/cierre_dia.dart';
import '../providers/cierres_providers.dart';

/// Ritual nocturno: las cosas que SÍ hice hoy. Documento Maestro
/// sección 7. Si ya hay un cierre del día, lo edita; si no, lo crea.
class CierreDiaScreen extends ConsumerStatefulWidget {
  const CierreDiaScreen({super.key});
  @override
  ConsumerState<CierreDiaScreen> createState() => _CierreDiaScreenState();
}

class _CierreDiaScreenState extends ConsumerState<CierreDiaScreen> {
  final _items = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final _nota = TextEditingController();
  bool _cargandoInicial = false;
  bool _guardando = false;
  String? _error;
  String? _ok;
  DateTime get _hoy {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _cargarSiExiste();
  }

  @override
  void dispose() {
    for (final c in _items) {
      c.dispose();
    }
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargarSiExiste() async {
    setState(() => _cargandoInicial = true);
    try {
      final c = await ref.read(cierresRepoProvider).obtenerDe(_hoy);
      if (c != null) {
        // Llenar campos con lo ya guardado
        for (var i = 0; i < _items.length; i++) {
          _items[i].text = i < c.items.length ? c.items[i] : '';
        }
        // Si hay más de 3 items, los añadimos como campos extra
        while (_items.length < c.items.length) {
          _items.add(TextEditingController(text: c.items[_items.length]));
        }
        _nota.text = c.notaExtra ?? '';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  void _agregarItem() {
    setState(() => _items.add(TextEditingController()));
  }

  void _quitarItem(int i) {
    if (_items.length <= 1) return;
    setState(() {
      _items[i].dispose();
      _items.removeAt(i);
    });
  }

  Future<void> _guardar() async {
    final items = _items
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (items.isEmpty) {
      setState(() => _error =
          'Pon al menos una cosa que sí hiciste hoy. No es trampa: cuenta cualquier paso real.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
      _ok = null;
    });
    try {
      await ref.read(cierresRepoProvider).guardar(
            fecha: _hoy,
            items: items,
            notaExtra: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
          );
      ref.invalidate(cierresListProvider);
      ref.invalidate(cierreDeFechaProvider(_hoy));
      setState(() => _ok = 'Guardado. Buen cierre.');
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
    final fecha =
        DateFormat("EEEE d 'de' MMMM", 'es').format(_hoy);
    return Scaffold(
      appBar: AppBar(title: const Text('Cierre del día')),
      body: _cargandoInicial
          ? const Center(
              child: CircularProgressIndicator(color: MatixColors.accent),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    fecha,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MatixColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '3 cosas que sí hice hoy',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: MatixColors.text,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No tiene que ser épico. Cualquier paso real cuenta. '
                    'Lo importante es no irse a dormir creyendo que no '
                    'hiciste nada.',
                    style: TextStyle(
                      fontSize: 13,
                      color: MatixColors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Cierra lo que pasó hoy: tareas/eventos sin confirmar. Vive
                  // ANTES de las "3 cosas que sí hice" para que el repaso del día
                  // tenga datos reales (no depende solo de las notis, que en
                  // Honor/MagicOS pueden no entregar).
                  const ConfirmarPendientesCard(),
                  const SizedBox(height: 16),
                  for (var i = 0; i < _items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  MatixColors.accent.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MatixColors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _items[i],
                              decoration: InputDecoration(
                                hintText: 'Cosa #${i + 1}…',
                                isDense: true,
                              ),
                              maxLines: null,
                            ),
                          ),
                          if (_items.length > 1)
                            IconButton(
                              tooltip: 'Quitar',
                              onPressed: () => _quitarItem(i),
                              icon: const Icon(
                                Icons.close,
                                color: MatixColors.muted,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _agregarItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Añadir otra'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nota,
                    decoration: const InputDecoration(
                      labelText: 'Algo que te haya rondado (opcional)',
                      alignLabelWithHint: true,
                      hintText:
                          'Espacio para descargar lo que da vueltas antes '
                          'de dormir.',
                    ),
                    minLines: 3,
                    maxLines: 8,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MatixColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: MatixColors.red,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  if (_ok != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MatixColors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _ok!,
                        style: const TextStyle(
                          color: MatixColors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: MatixButtonStyles.primarioAlto,
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : const Text('Guardar cierre'),
                  ),
                  const SizedBox(height: 24),
                  const _CierresAnteriores(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}

/// Sección colapsable con cierres anteriores. Permite mirar atrás
/// sin abrumar al usuario que abrió la pantalla solo para cerrar hoy.
class _CierresAnteriores extends ConsumerStatefulWidget {
  const _CierresAnteriores();
  @override
  ConsumerState<_CierresAnteriores> createState() =>
      _CierresAnterioresState();
}

class _CierresAnterioresState
    extends ConsumerState<_CierresAnteriores> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(cierresListProvider);
    return lista.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (todos) {
        final hoy = DateTime.now();
        final anteriores = todos.where((c) {
          final f = c.fecha;
          return !(f.year == hoy.year &&
              f.month == hoy.month &&
              f.day == hoy.day);
        }).toList()
          ..sort((a, b) => b.fecha.compareTo(a.fecha));
        if (anteriores.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expandido = !_expandido),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _expandido
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: MatixColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cierres anteriores · ${anteriores.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: MatixColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expandido)
              for (final c in anteriores.take(30)) _CierrePasadoCard(c: c),
          ],
        );
      },
    );
  }
}

class _CierrePasadoCard extends StatelessWidget {
  const _CierrePasadoCard({required this.c});
  final CierreDia c;

  @override
  Widget build(BuildContext context) {
    final fecha = DateFormat("EEEE d 'de' MMMM", 'es').format(c.fecha);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MatixColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fecha,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: MatixColors.muted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in c.items)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: MatixColors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MatixColors.text,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (c.notaExtra != null && c.notaExtra!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c.notaExtra!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: MatixColors.muted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
