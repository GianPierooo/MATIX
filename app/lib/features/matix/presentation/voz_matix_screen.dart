import 'package:flutter/material.dart';

import '../data/tts_service.dart';
import '../data/voz_config.dart';

/// Ajuste "Voz de Matix": elige la voz del dispositivo, ajusta tono y
/// velocidad, prueba la voz, y ve la ayuda para instalar voces mejoradas.
///
/// Es UNA sola voz para toda la app: lo que se elige aquí se guarda en
/// `VozPrefs` y lo aplican TODOS los puntos de voz (chat, manos libres,
/// cámara, briefing, cierre) al preparar su motor.
class VozMatixScreen extends StatefulWidget {
  const VozMatixScreen({super.key});

  @override
  State<VozMatixScreen> createState() => _VozMatixScreenState();
}

class _VozMatixScreenState extends State<VozMatixScreen> {
  final VozPrefs _prefs = VozPrefs();
  final VozDispositivoFlutterTts _voz = VozDispositivoFlutterTts();

  VozConfig _cfg = const VozConfig();
  List<VozDisponible> _voces = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _voz.detener();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final cfg = await _prefs.cargar();
      await _voz.preparar();
      final voces = await _voz.voces();
      // Si el usuario no eligió voz, mostramos la "mejor" como sugerida por
      // defecto (sin guardarla aún): el motor ya la usa por idioma.
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _voces = voces;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pude leer las voces del dispositivo.';
        _cargando = false;
      });
    }
  }

  Future<void> _guardarYAplicar(VozConfig nueva) async {
    setState(() => _cfg = nueva);
    await _prefs.guardar(nueva);
    await _voz.aplicar(nueva);
  }

  Future<void> _probar() async {
    await _voz.aplicar(_cfg); // asegura que suena con lo elegido ahora
    await _voz.hablarYEsperar(
      'Hola, soy Matix. Así suena mi voz con este tono y velocidad.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Voz de Matix')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                Text('Voz', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'La voz del dispositivo que usa Matix en todos lados: chat, '
                  'manos libres, cámara, briefing y cierre.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _selectorVoz(theme),
                const SizedBox(height: 24),

                Text('Tono', style: theme.textTheme.titleMedium),
                Slider(
                  value: _cfg.pitch,
                  min: VozConfig.pitchMin,
                  max: VozConfig.pitchMax,
                  divisions: 15,
                  label: _cfg.pitch.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _cfg = _cfg.copyWith(pitch: v)),
                  onChangeEnd: (v) => _guardarYAplicar(_cfg.copyWith(pitch: v)),
                ),
                const SizedBox(height: 8),

                Text('Velocidad', style: theme.textTheme.titleMedium),
                Slider(
                  value: _cfg.rate,
                  min: VozConfig.rateMin,
                  max: VozConfig.rateMax,
                  divisions: 14,
                  label: _cfg.rate.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _cfg = _cfg.copyWith(rate: v)),
                  onChangeEnd: (v) => _guardarYAplicar(_cfg.copyWith(rate: v)),
                ),
                const SizedBox(height: 16),

                FilledButton.icon(
                  onPressed: _probar,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('Probar voz'),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '¿La voz suena robótica? Las voces mejoradas de Google '
                          'en español suenan mucho mejor y son gratis. Instálalas '
                          'desde: Ajustes del teléfono → Idiomas y entrada → Salida '
                          'de texto a voz → motor de Google → ajustes → Instalar '
                          'datos de voz → Español. Luego vuelve aquí y elígela.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _selectorVoz(ThemeData theme) {
    if (_voces.isEmpty) {
      return Text(
        'El dispositivo no expuso voces en español; Matix usará la voz por '
        'defecto del motor. Revisa la ayuda de abajo para instalar una.',
        style: theme.textTheme.bodySmall,
      );
    }
    final mejor = mejorVozEspanol(_voces);
    // Valor seleccionado: la elegida, o "(automática)" si no eligió.
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(
          mejor == null ? 'Automática' : 'Automática (${mejor.name})',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final v in _voces)
        DropdownMenuItem<String?>(
          value: v.name,
          child: Text(
            '${v.name}  ·  ${v.locale}${v.pareceMejorada ? '  ✦' : ''}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    return DropdownButton<String?>(
      value: _cfg.tieneVozElegida ? _cfg.voiceName : null,
      isExpanded: true,
      items: items,
      onChanged: (name) {
        if (name == null) {
          _guardarYAplicar(_cfg.copyWith(limpiarVoz: true));
        } else {
          final v = _voces.firstWhere((x) => x.name == name);
          _guardarYAplicar(_cfg.copyWith(voiceName: v.name, locale: v.locale));
        }
      },
    );
  }
}
