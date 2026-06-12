import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../providers/spotify_providers.dart';

/// Card de Ajustes → Conexiones → Spotify.
///
/// Conectar tu Premium para que Matix REPRODUZCA en la PC. El flujo OAuth:
///   1. La app pide al cerebro la URL de consentimiento.
///   2. La abre en el navegador del teléfono (externalApplication).
///   3. Inicias sesión en Spotify y autorizas; Spotify redirige al
///      callback PÚBLICO del cerebro, que guarda el refresh token.
///   4. Al volver, tocas "Ya autoricé" y se re-chequea el estado.
class ConexionSpotifyTile extends ConsumerStatefulWidget {
  const ConexionSpotifyTile({super.key});

  @override
  ConsumerState<ConexionSpotifyTile> createState() =>
      _ConexionSpotifyTileState();
}

class _ConexionSpotifyTileState extends ConsumerState<ConexionSpotifyTile> {
  bool _abriendoOAuth = false;
  bool _esperandoCallback = false;
  String? _errorAccion;

  Future<void> _conectar() async {
    setState(() {
      _abriendoOAuth = true;
      _errorAccion = null;
    });
    try {
      final url = await ref.read(spotifyRepositoryProvider).obtenerUrlOAuth();
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('No pude abrir el navegador.');
      if (mounted) setState(() => _esperandoCallback = true);
    } on MatixApiException catch (e) {
      setState(() => _errorAccion = _mensajeApi(e));
    } catch (e) {
      setState(() => _errorAccion = 'No pude iniciar la conexión: $e');
    } finally {
      if (mounted) setState(() => _abriendoOAuth = false);
    }
  }

  Future<void> _verificar() async {
    setState(() => _esperandoCallback = false);
    ref.invalidate(spotifyStatusProvider);
  }

  Future<void> _desconectar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Desconectar Spotify'),
        content: const Text(
          'Voy a borrar el acceso del cerebro para reproducir en tu Spotify. '
          'La búsqueda de canciones sigue funcionando.\n\n'
          'Para que Spotify también olvide el permiso, ve a tu cuenta en '
          'spotify.com → Aplicaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatixColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(spotifyRepositoryProvider).desconectar();
      ref.invalidate(spotifyStatusProvider);
    } catch (e) {
      setState(() => _errorAccion = 'No pude desconectar: $e');
    }
  }

  String _mensajeApi(MatixApiException e) {
    if (e.statusCode == 503) {
      return 'Falta configurar Spotify en el cerebro (client id/secret).';
    }
    return 'Error ${e.statusCode}: ${e.message}';
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(spotifyStatusProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MatixColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: estado.when(
        loading: () => const _Loading(),
        error: (e, _) => _Error(
          mensaje: e.toString(),
          onReintentar: () => ref.invalidate(spotifyStatusProvider),
        ),
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.music_note, color: MatixColors.green, size: 20),
                SizedBox(width: 10),
                Text(
                  'Spotify',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (s.conectado)
              _ConectadoBody(onDesconectar: _desconectar)
            else
              _NoConectadoBody(
                abriendoOAuth: _abriendoOAuth,
                esperandoCallback: _esperandoCallback,
                onConectar: _conectar,
                onVerificar: _verificar,
              ),
            if (_errorAccion != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: MatixColors.red.withValues(alpha: 0.12),
                  border: Border.all(
                    color: MatixColors.red.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _errorAccion!,
                  style: const TextStyle(fontSize: 12, color: MatixColors.text),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MatixColors.green,
          ),
        ),
        SizedBox(width: 12),
        Text(
          'Consultando estado…',
          style: TextStyle(fontSize: 13, color: MatixColors.muted),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            mensaje,
            style: const TextStyle(fontSize: 12, color: MatixColors.red),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: onReintentar,
        ),
      ],
    );
  }
}

class _NoConectadoBody extends StatelessWidget {
  const _NoConectadoBody({
    required this.abriendoOAuth,
    required this.esperandoCallback,
    required this.onConectar,
    required this.onVerificar,
  });
  final bool abriendoOAuth;
  final bool esperandoCallback;
  final VoidCallback onConectar;
  final VoidCallback onVerificar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          esperandoCallback
              ? 'Te abrí el navegador para que inicies sesión en Spotify y '
                  'autorices. Cuando termines, vuelve aquí y toca "Ya autoricé".'
              : 'Conecta tu Premium para que ponga música en tu compu cuando '
                  'se lo pidas.',
          style: const TextStyle(
            fontSize: 12.5,
            color: MatixColors.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        if (esperandoCallback)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onConectar,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir de nuevo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MatixColors.muted,
                    side: const BorderSide(color: MatixColors.hairline),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onVerificar,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Ya autoricé'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MatixColors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: abriendoOAuth ? null : onConectar,
              icon: abriendoOAuth
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.link, size: 18),
              label: Text(
                abriendoOAuth ? 'Abriendo navegador…' : 'Conectar Spotify',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConectadoBody extends StatelessWidget {
  const _ConectadoBody({required this.onDesconectar});
  final VoidCallback onDesconectar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: MatixColors.green.withValues(alpha: 0.12),
            border: Border.all(color: MatixColors.green.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Conectado · puedo reproducir en tu PC',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MatixColors.green,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onDesconectar,
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Desconectar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MatixColors.red,
              side: BorderSide(color: MatixColors.red.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }
}
