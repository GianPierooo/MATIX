import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dispositivo_providers.dart';

/// Tier C.0 · activación de la PERCEPCIÓN de pantalla.
///
/// Explica por qué Matix pide accesibilidad (solo lectura, bajo demanda),
/// advierte sobre el Modo de Protección Avanzada (APM), deep-linkea a Ajustes,
/// y muestra si el servicio está activado (se re-chequea al volver a la app).
class AccesibilidadScreen extends ConsumerStatefulWidget {
  const AccesibilidadScreen({super.key});

  @override
  ConsumerState<AccesibilidadScreen> createState() => _AccesibilidadScreenState();
}

class _AccesibilidadScreenState extends ConsumerState<AccesibilidadScreen>
    with WidgetsBindingObserver {
  bool? _activo; // null = aún chequeando

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chequear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de Ajustes, re-chequeamos el estado del servicio.
    if (state == AppLifecycleState.resumed) _chequear();
  }

  Future<void> _chequear() async {
    final activo = await ref.read(accesibilidadServiceProvider).activa();
    if (mounted) setState(() => _activo = activo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activo = _activo;

    return Scaffold(
      appBar: AppBar(title: const Text('Leer la pantalla')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Estado(activo: activo),
          const SizedBox(height: 20),
          Text('Qué hace', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Con este permiso, Matix puede leer el texto de la app que tienes '
            'abierta cuando se lo pides (por ejemplo, «léeme el último '
            'mensaje» o «¿qué dice acá?»).',
          ),
          const SizedBox(height: 16),
          Text('Lo que NO hace', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Es solo lectura y bajo demanda. Matix no toca, no escribe ni '
            'desliza nada, y no lee tu pantalla en segundo plano ni en '
            'silencio: cada vez que lee algo, te lo avisa. Lo que lee se usa '
            'para responderte y se descarta; no se guarda.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Importante: si tienes activado el Modo de Protección '
                    'Avanzada (APM), Android bloquea los servicios de '
                    'accesibilidad y esto no va a funcionar. Tienes que '
                    'apagar el APM para poder activar el permiso.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await ref.read(accesibilidadServiceProvider).abrirAjustes();
            },
            icon: const Icon(Icons.settings_accessibility),
            label: Text(
              activo == true
                  ? 'Abrir Ajustes de accesibilidad'
                  : 'Activar en Ajustes de accesibilidad',
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _chequear,
            child: const Text('Ya lo activé, volver a verificar'),
          ),
        ],
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({required this.activo});
  final bool? activo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icono, color, texto) = switch (activo) {
      true => (Icons.check_circle, Colors.green, 'Activado: Matix ya puede leer la pantalla cuando se lo pidas.'),
      false => (Icons.cancel, theme.colorScheme.error, 'Desactivado: actívalo abajo para que Matix pueda leer la pantalla.'),
      null => (Icons.hourglass_empty, theme.colorScheme.outline, 'Verificando…'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
