import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../data/google_repository.dart';
import '../providers/google_providers.dart';

/// Card de Ajustes → Conexiones → Google Calendar.
///
/// Estados que pinta:
///   - cargando            → spinner
///   - no conectado        → CTA "Conectar Google"
///   - conectado           → email + último sync + acciones
///                           (Sincronizar / Desconectar)
///   - error               → mensaje + botón reintentar
///
/// El flujo OAuth (cuando el usuario toca "Conectar"):
///   1. Pedimos al cerebro la URL de autorización.
///   2. La abrimos en el navegador del teléfono (externalApplication).
///   3. El usuario autoriza, Google redirige al cerebro
///      `/api/v1/google/oauth/callback` que muestra "Listo".
///   4. Cuando el usuario vuelve a la app, mostramos un botón
///      "Ya autoricé · Verificar" que re-chequea el status.
class ConexionGoogleTile extends ConsumerStatefulWidget {
  const ConexionGoogleTile({super.key});

  @override
  ConsumerState<ConexionGoogleTile> createState() =>
      _ConexionGoogleTileState();
}

class _ConexionGoogleTileState extends ConsumerState<ConexionGoogleTile> {
  bool _abriendoOAuth = false;
  bool _esperandoCallback = false;
  bool _sincronizando = false;
  GoogleSyncResumen? _ultimoResumenSync;
  String? _errorAccion;

  Future<void> _conectar() async {
    setState(() {
      _abriendoOAuth = true;
      _errorAccion = null;
    });
    try {
      final url = await ref.read(googleRepositoryProvider).obtenerUrlOAuth();
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw Exception('No pude abrir el navegador.');
      }
      // El usuario está ahora en Chrome autorizando. Cuando vuelva
      // a la app, va a tocar "Ya autoricé" para que rechequeemos.
      if (mounted) setState(() => _esperandoCallback = true);
    } on MatixApiException catch (e) {
      setState(() => _errorAccion = _mensajeApi(e));
    } catch (e) {
      setState(() => _errorAccion = 'No pude iniciar OAuth: $e');
    } finally {
      if (mounted) setState(() => _abriendoOAuth = false);
    }
  }

  Future<void> _verificarConexion() async {
    setState(() => _esperandoCallback = false);
    ref.invalidate(googleStatusProvider);
    // Refrescamos también los eventos por si el callback del
    // cerebro hizo el sync inicial al autorizar.
    ref.invalidate(eventosProvider);
  }

  Future<void> _sincronizar() async {
    setState(() {
      _sincronizando = true;
      _errorAccion = null;
      _ultimoResumenSync = null;
    });
    try {
      final r = await ref.read(googleRepositoryProvider).sincronizar();
      if (!mounted) return;
      setState(() => _ultimoResumenSync = r);
      ref.invalidate(googleStatusProvider);
      ref.invalidate(eventosProvider);
    } on MatixApiException catch (e) {
      setState(() => _errorAccion = _mensajeApi(e));
      if (e.statusCode == 401) {
        // Token revocado: forzamos a reconectar.
        ref.invalidate(googleStatusProvider);
      }
    } catch (e) {
      setState(() => _errorAccion = 'Sync falló: $e');
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _desconectar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Desconectar Google'),
        content: const Text(
          'Voy a borrar el acceso del cerebro a tu Google Calendar. '
          'Los eventos ya sincronizados se quedan en el hub.\n\n'
          'Para que Google también olvide el permiso, andá a '
          'myaccount.google.com/permissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MatixColors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(googleRepositoryProvider).desconectar();
      ref.invalidate(googleStatusProvider);
    } catch (e) {
      setState(() => _errorAccion = 'No pude desconectar: $e');
    }
  }

  String _mensajeApi(MatixApiException e) {
    if (e.statusCode == 503) {
      return 'OAuth Google no habilitado en el cerebro (faltan vars).';
    }
    if (e.statusCode == 401) {
      return 'Tu acceso a Google expiró. Reconectá.';
    }
    return 'Error ${e.statusCode}: ${e.message}';
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(googleStatusProvider);
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
          onReintentar: () => ref.invalidate(googleStatusProvider),
        ),
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.event_repeat,
                  color: MatixColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Google Calendar',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (s.conectado && !s.tieneEscritura)
              _BannerReconectarParaEscritura(
                abriendoOAuth: _abriendoOAuth,
                onReconectar: _conectar,
              ),
            if (s.conectado)
              _ConectadoBody(
                status: s,
                sincronizando: _sincronizando,
                resumen: _ultimoResumenSync,
                onSincronizar: _sincronizar,
                onDesconectar: _desconectar,
              )
            else
              _NoConectadoBody(
                abriendoOAuth: _abriendoOAuth,
                esperandoCallback: _esperandoCallback,
                onConectar: _conectar,
                onVerificar: _verificarConexion,
              ),
            if (_errorAccion != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MatixColors.red.withValues(alpha: 0.12),
                  border: Border.all(
                    color: MatixColors.red.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _errorAccion!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MatixColors.text,
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

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MatixColors.accent,
          ),
        ),
        const SizedBox(width: 12),
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
            style: const TextStyle(
              fontSize: 12,
              color: MatixColors.red,
            ),
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
              ? 'Te abrí Chrome para que autorices. Cuando termines, '
                  'volvé acá y tocá "Ya autoricé".'
              : 'Conectá tu cuenta para ver tus eventos del Google '
                  'Calendar en el hub.',
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
                  label: const Text('Volver a abrir Chrome'),
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
                  : const Icon(Icons.account_circle, size: 18),
              label: Text(
                abriendoOAuth ? 'Abriendo navegador…' : 'Conectar Google',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: MatixColors.accent,
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
  const _ConectadoBody({
    required this.status,
    required this.sincronizando,
    required this.resumen,
    required this.onSincronizar,
    required this.onDesconectar,
  });
  final GoogleStatus status;
  final bool sincronizando;
  final GoogleSyncResumen? resumen;
  final VoidCallback onSincronizar;
  final VoidCallback onDesconectar;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM HH:mm', 'es');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: MatixColors.green.withValues(alpha: 0.12),
            border: Border.all(
              color: MatixColors.green.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Conectado · ${status.email ?? ''}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MatixColors.green,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status.ultimoSyncEn == null
              ? 'Sin sincronizar todavía.'
              : 'Último sync: ${fmt.format(status.ultimoSyncEn!.toLocal())}',
          style: const TextStyle(
            fontSize: 11.5,
            color: MatixColors.muted,
          ),
        ),
        if (resumen != null) ...[
          const SizedBox(height: 4),
          Text(
            'Últimas: +${resumen!.creados} nuevos, '
            '${resumen!.actualizados} actualizados, '
            '${resumen!.mandadosAPapelera} a papelera'
            '${resumen!.empujadosAGoogle > 0 ? ", ${resumen!.empujadosAGoogle} subidos a Google" : ""}.',
            style: const TextStyle(
              fontSize: 11.5,
              color: MatixColors.muted,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: sincronizando ? null : onSincronizar,
                icon: sincronizando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync, size: 18),
                label: Text(sincronizando ? 'Sincronizando…' : 'Sincronizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: MatixColors.accent,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onDesconectar,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Desconectar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MatixColors.red,
                side: BorderSide(
                  color: MatixColors.red.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Banner ámbar que aparece cuando el usuario está conectado a Google
/// pero con el scope viejo (Paso 1, solo lectura). El push bidireccional
/// del Paso 2 necesita el scope `calendar` — para concederlo hay que
/// reautorizar una vez. El CTA reusa el mismo flujo OAuth.
class _BannerReconectarParaEscritura extends StatelessWidget {
  const _BannerReconectarParaEscritura({
    required this.abriendoOAuth,
    required this.onReconectar,
  });
  final bool abriendoOAuth;
  final VoidCallback onReconectar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MatixColors.amber.withValues(alpha: 0.12),
        border: Border.all(color: MatixColors.amber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sync_alt,
                color: MatixColors.amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Sincronización bidireccional',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: MatixColors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tu conexión actual solo permite leer Google Calendar. '
            'Para que los eventos que crees en Matix también suban a '
            'Google, reconectá una vez para conceder el permiso de '
            'escritura.',
            style: TextStyle(
              fontSize: 11.5,
              color: MatixColors.muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: abriendoOAuth ? null : onReconectar,
              icon: abriendoOAuth
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: MatixColors.amber,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(
                abriendoOAuth
                    ? 'Abriendo navegador…'
                    : 'Reconectar para bidireccional',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MatixColors.amber,
                side: BorderSide(
                  color: MatixColors.amber.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
