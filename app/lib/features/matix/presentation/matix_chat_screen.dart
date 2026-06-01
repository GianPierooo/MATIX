import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../../apuntes/providers/apuntes_providers.dart';
import '../../captura_camara/presentation/captura_camara_screen.dart';
import '../../modelos/providers/modelos_providers.dart';
import '../../modos/providers/modos_providers.dart';
import '../data/contacto_memoria.dart';
import '../data/documento_repository.dart';
import '../data/matix_transcribir_repository.dart';
import '../data/uso_repository.dart';
import '../domain/mensaje.dart';
import '../providers/matix_chat_providers.dart';
import '../providers/uso_providers.dart';
import '../providers/voz_providers.dart';
import 'manos_libres_screen.dart';
import 'widgets/menu_adjuntar.dart';

/// Pantalla principal de Matix (Capa 2 Paso 1): chat solo texto.
///
/// La conversación vive en `chatMatixProvider`. Esta pantalla solo:
/// 1. La pinta como burbujas (usuario a la derecha, Matix a la izquierda),
/// 2. Manda el texto que escribe el usuario al notifier,
/// 3. Muestra "Matix está pensando…" mientras hay un POST en vuelo,
/// 4. Muestra el error inline con un botón "Reintentar" si falla.
///
/// Sin tools / sin voz / sin persistencia. Esos son pasos posteriores.
class MatixChatScreen extends ConsumerStatefulWidget {
  const MatixChatScreen({super.key});

  @override
  ConsumerState<MatixChatScreen> createState() => _MatixChatScreenState();
}

class _MatixChatScreenState extends ConsumerState<MatixChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focusInput = FocusNode();
  final _picker = ImagePicker();

  /// Imagen adjunta lista para mandar con el próximo mensaje (Capa 2 ·
  /// chat multimodal). Null = ninguna.
  XFile? _imagenAdjunta;

  /// Documento adjunto (texto ya extraído por el cerebro) listo para mandar
  /// con el próximo mensaje. Null = ninguno.
  ({String nombre, String texto, bool truncado})? _documentoAdjunto;

  /// `true` mientras subimos/extraemos un documento o transcribimos un audio
  /// elegido (para mostrar un indicador y no dejar mandar a medias).
  bool _procesandoAdjunto = false;

  /// Tope: imágenes más pesadas se rechazan con mensaje claro.
  static const int _maxImagenBytes = 4 * 1024 * 1024;

  /// Reloj que actualiza la duración mostrada mientras se graba.
  /// Vive en la UI para no obligar al notifier a tener un Timer
  /// propio.
  Timer? _tickGrabacion;
  DateTime? _inicioGrabacion;

  @override
  void dispose() {
    _tickGrabacion?.cancel();
    _controller.dispose();
    _scroll.dispose();
    _focusInput.dispose();
    super.dispose();
  }

  void _scrollAlFinal() {
    // Microtarea para correr DESPUÉS de que el ListView haya layouted
    // el nuevo mensaje. Si no, jumpTo se queda corto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    final img = _imagenAdjunta;
    final doc = _documentoAdjunto;
    if (texto.isEmpty && img == null && doc == null) return;

    String? dataUrl;
    String? imagenPath;
    if (img != null) {
      final bytes = await File(img.path).readAsBytes();
      if (bytes.length > _maxImagenBytes) {
        if (mounted) {
          _mostrarAviso('La imagen es muy pesada (máx 4 MB). Prueba otra.');
        }
        return;
      }
      // image_picker, al comprimir con imageQuality, entrega JPEG.
      dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      imagenPath = img.path;
    }

    _controller.clear();
    setState(() {
      _imagenAdjunta = null;
      _documentoAdjunto = null;
    });
    await ref.read(chatMatixProvider.notifier).enviar(
          texto,
          imagenDataUrl: dataUrl,
          imagenPath: imagenPath,
          documentoNombre: doc?.nombre,
          documentoTexto: doc?.texto,
        );
    _scrollAlFinal();
    if (mounted) _focusInput.requestFocus();
  }

  void _mostrarAviso(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Menú de adjuntar (tipo WhatsApp) ───────────────────────────────

  /// Abre el menú "+" y rutea a la acción de la opción elegida. Cada opción
  /// reutiliza un flujo que ya existe (visión, OCR, voz/Whisper, memoria).
  Future<void> _abrirMenuAdjuntar() async {
    final op = await mostrarMenuAdjuntar(context);
    if (op == null || !mounted) return;
    switch (op) {
      case OpcionAdjuntar.documento:
        await _adjuntarDocumento();
      case OpcionAdjuntar.fotoVideo:
        await _adjuntarFoto();
      case OpcionAdjuntar.camara:
        await _abrirCamara();
      case OpcionAdjuntar.audio:
        await _menuAudio();
      case OpcionAdjuntar.contacto:
        await _adjuntarContacto();
    }
  }

  /// Foto desde la galería → se adjunta para el flujo de VISIÓN (Matix la ve).
  /// Video: por ahora no (se avisa). La comprime para no mandar 8 MP.
  Future<void> _adjuntarFoto() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (x != null && mounted) setState(() => _imagenAdjunta = x);
    } catch (e) {
      if (mounted) _mostrarAviso('No pude abrir la galería: $e');
    }
  }

  /// Cámara → la pantalla de captura con OCR on-device (flujo existente):
  /// rutea solo a tareas, eventos o apunte. La imagen no sale del teléfono.
  Future<void> _abrirCamara() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CapturaCamaraScreen()),
    );
  }

  /// Documento (PDF/DOCX/TXT/MD): el selector del sistema (SAF) → lo subimos
  /// al cerebro, que extrae el texto, y lo dejamos adjunto para el próximo
  /// mensaje (Matix lo lee/analiza/resume).
  Future<void> _adjuntarDocumento() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'txt', 'md'],
      );
    } catch (e) {
      if (mounted) _mostrarAviso('No pude abrir el selector de archivos: $e');
      return;
    }
    final ruta = res?.files.single.path;
    final nombre = res?.files.single.name ?? 'documento';
    if (ruta == null) return; // cancelado
    setState(() => _procesandoAdjunto = true);
    final repo = DocumentoRepository();
    try {
      final doc = await repo.extraer(File(ruta), nombre: nombre);
      if (!mounted) return;
      setState(() {
        _documentoAdjunto =
            (nombre: doc.nombre, texto: doc.texto, truncado: doc.truncado);
        _procesandoAdjunto = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _procesandoAdjunto = false);
        _mostrarAviso(_mensajeError(e));
      }
    } finally {
      repo.close();
    }
  }

  /// Audio: grabar (flujo de voz existente) o elegir un archivo del sistema
  /// para transcribir con Whisper.
  Future<void> _menuAudio() async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MatixColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.mic_none, color: MatixColors.accent),
              title: const Text('Grabar audio'),
              onTap: () => Navigator.pop(ctx, 'grabar'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.audio_file_outlined, color: MatixColors.accent),
              title: const Text('Elegir un audio'),
              onTap: () => Navigator.pop(ctx, 'elegir'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (accion == 'grabar') {
      await _empezarAGrabar();
    } else if (accion == 'elegir') {
      await _elegirAudio();
    }
  }

  /// Elige un archivo de audio (SAF) → lo transcribe con Whisper (mismo
  /// endpoint que el mic) → deja el texto en el composer para revisar y enviar.
  Future<void> _elegirAudio() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(type: FileType.audio);
    } catch (e) {
      if (mounted) _mostrarAviso('No pude abrir el selector de audio: $e');
      return;
    }
    final ruta = res?.files.single.path;
    if (ruta == null) return; // cancelado
    setState(() => _procesandoAdjunto = true);
    final repo = MatixTranscribirRepository();
    try {
      final texto = await repo.transcribir(File(ruta));
      if (!mounted) return;
      setState(() => _procesandoAdjunto = false);
      if (texto.trim().isNotEmpty) _insertarEnComposer(texto.trim());
    } catch (e) {
      if (mounted) {
        setState(() => _procesandoAdjunto = false);
        _mostrarAviso(_mensajeError(e));
      }
    } finally {
      repo.close();
    }
  }

  /// Contacto: abre el selector NATIVO de contactos (sin leer la agenda
  /// entera ni pedir READ_CONTACTS). Con lo elegido arma un mensaje y se lo
  /// manda a Matix, que lo guarda en su memoria (categoría personas) con la
  /// tool `recordar` y confirma en su voz.
  Future<void> _adjuntarContacto() async {
    Contact? c;
    try {
      c = await FlutterContacts.openExternalPick();
    } catch (e) {
      if (mounted) _mostrarAviso('No pude abrir tus contactos: $e');
      return;
    }
    if (c == null || !mounted) return;

    final mensaje = mensajeGuardarContacto(
      nombre: c.displayName,
      telefonos: c.phones.map((p) => p.number).toList(),
      correos: c.emails.map((e) => e.address).toList(),
    );
    if (mensaje == null) {
      _mostrarAviso('Ese contacto no tiene datos que guardar.');
      return;
    }
    await ref.read(chatMatixProvider.notifier).enviar(mensaje);
    _scrollAlFinal();
  }

  /// Inserta texto en la posición del cursor (o al final), sin mandar.
  void _insertarEnComposer(String texto) {
    final actual = _controller.text;
    final sel = _controller.selection;
    final ins = actual.isEmpty || actual.endsWith(' ') ? texto : ' $texto';
    final nuevo = sel.isValid
        ? actual.replaceRange(sel.start, sel.end, ins)
        : '$actual$ins';
    _controller.value = TextEditingValue(
      text: nuevo,
      selection: TextSelection.collapsed(
        offset: sel.isValid ? sel.start + ins.length : nuevo.length,
      ),
    );
    _focusInput.requestFocus();
  }

  /// Guarda el documento adjunto como un apunte (reusa el CRUD de apuntes).
  Future<void> _guardarDocEnApuntes() async {
    final doc = _documentoAdjunto;
    if (doc == null) return;
    try {
      await ref
          .read(apuntesRepoProvider)
          .crear(titulo: doc.nombre, contenido: doc.texto);
      ref.invalidate(apuntesListProvider);
      if (mounted) _mostrarAviso('Guardado en apuntes: ${doc.nombre}');
    } catch (e) {
      if (mounted) _mostrarAviso('No pude guardar el apunte: $e');
    }
  }

  String _mensajeError(Object e) {
    if (e is MatixApiException) return e.message;
    return '$e';
  }

  Future<void> _reintentar() async {
    await ref.read(chatMatixProvider.notifier).reintentar();
    _scrollAlFinal();
  }

  // ─── Voz ────────────────────────────────────────────────────────

  Future<void> _empezarAGrabar() async {
    final notifier = ref.read(vozNotifierProvider.notifier);
    await notifier.iniciar();
    if (!mounted) return;
    final est = ref.read(vozNotifierProvider);
    if (est.fase != FaseVoz.grabando) return;
    _inicioGrabacion = DateTime.now();
    _tickGrabacion?.cancel();
    _tickGrabacion = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (_inicioGrabacion == null) return;
        ref.read(vozNotifierProvider.notifier).actualizarDuracion(
              DateTime.now().difference(_inicioGrabacion!),
            );
      },
    );
  }

  Future<void> _detenerYTranscribir() async {
    _tickGrabacion?.cancel();
    _inicioGrabacion = null;
    final notifier = ref.read(vozNotifierProvider.notifier);
    final texto = await notifier.detenerYTranscribir();
    if (!mounted || texto == null) return;
    // Insertamos en la posición del cursor (o al final). Importante:
    // NO mandamos solo. El usuario revisa y aprieta enviar.
    _insertarEnComposer(texto);
  }

  Future<void> _cancelarGrabacion() async {
    _tickGrabacion?.cancel();
    _inicioGrabacion = null;
    await ref.read(vozNotifierProvider.notifier).cancelar();
  }

  void _mostrarErrorVoz(String msg, {bool permisoPermanente = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        action: permisoPermanente
            ? SnackBarAction(
                label: 'Ajustes',
                onPressed: () => openAppSettings(),
              )
            : null,
      ),
    );
    ref.read(vozNotifierProvider.notifier).limpiarError();
  }

  void _confirmarLimpiar() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MatixColors.card,
        title: const Text('Limpiar conversación'),
        content: const Text(
          'Vas a borrar este hilo con Matix. No se puede recuperar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              ref.read(chatMatixProvider.notifier).limpiar();
              Navigator.of(ctx).pop();
            },
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
  }

  /// Hoja para elegir/cambiar/salir del modo de Matix. La fuente de verdad
  /// es el cerebro; al elegir, persistimos ahí y el indicador se actualiza.
  void _mostrarModos(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MatixColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref2, _) {
          final modos = ref2.watch(modosProvider);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Modo de Matix',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MatixColors.text,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ajusta el tono y el enfoque. Matix también puede '
                      'cambiarlo solo, siempre avisándote.',
                      style: TextStyle(fontSize: 12, color: MatixColors.muted),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline,
                      color: MatixColors.muted),
                  title: const Text('Modo normal'),
                  subtitle: const Text('Matix general, sin enfoque especial'),
                  trailing: modos.activo == null
                      ? const Icon(Icons.check, color: MatixColors.accent)
                      : null,
                  onTap: () {
                    ref2.read(modosProvider.notifier).desactivar();
                    Navigator.of(ctx).pop();
                  },
                ),
                for (final m in modos.disponibles)
                  ListTile(
                    leading: Icon(
                      Icons.auto_awesome,
                      color: modos.activo == m.nombre
                          ? MatixColors.accent
                          : MatixColors.muted,
                    ),
                    title: Text(m.etiqueta),
                    subtitle: m.descripcion.isEmpty ? null : Text(m.descripcion),
                    trailing: modos.activo == m.nombre
                        ? const Icon(Icons.check, color: MatixColors.accent)
                        : null,
                    onTap: () {
                      ref2.read(modosProvider.notifier).activar(m.nombre);
                      Navigator.of(ctx).pop();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(chatMatixProvider);
    final voz = ref.watch(vozNotifierProvider);

    // Scroll al final cuando llega una respuesta nueva o aparece el
    // indicador "pensando".
    ref.listen<EstadoChatMatix>(chatMatixProvider, (prev, next) {
      if (prev?.mensajes.length != next.mensajes.length || next.enviando) {
        _scrollAlFinal();
      }
    });

    // Errores de voz: mostramos snackbar y limpiamos el flag.
    ref.listen<EstadoVoz>(vozNotifierProvider, (prev, next) {
      if (next.fase == FaseVoz.error && next.error != null) {
        final permanente = next.error!.contains('ajustes del sistema');
        _mostrarErrorVoz(next.error!, permisoPermanente: permanente);
      }
    });

    final vacio = estado.mensajes.isEmpty && !estado.enviando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matix'),
        actions: [
          IconButton(
            tooltip: 'Modo de Matix',
            icon: const Icon(Icons.tune),
            onPressed: () => _mostrarModos(context),
          ),
          IconButton(
            tooltip: 'Modo manos libres',
            icon: const Icon(Icons.headphones),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManosLibresScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Limpiar conversación',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: estado.mensajes.isEmpty ? null : _confirmarLimpiar,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const _MedidorBanner(),
            _ModoIndicador(onTocar: () => _mostrarModos(context)),
            Expanded(
              child: vacio
                  ? const _EstadoInicial()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                        MatixSpacing.xl,
                        MatixSpacing.xl,
                        MatixSpacing.xl,
                        MatixSpacing.m,
                      ),
                      itemCount: estado.mensajes.length +
                          (estado.enviando ? 1 : 0) +
                          (estado.errorUltimoEnvio != null ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i < estado.mensajes.length) {
                          final m = estado.mensajes[i];
                          // Mostramos el chip de acciones SOLO bajo el
                          // último mensaje del asistente, y solo si
                          // hubo tool calls en ese turno.
                          final esUltimoAsistente = m.rol ==
                                  RolMensaje.matix &&
                              i == estado.mensajes.length - 1;
                          final mostrarChip = esUltimoAsistente &&
                              estado.accionesUltimoTurno.isNotEmpty;
                          // Transparencia: bajo el último turno del
                          // asistente mostramos qué modelo respondió cuando
                          // lo eligió el modo Automático.
                          final mostrarModelo = esUltimoAsistente &&
                              estado.autoUltimoTurno &&
                              estado.modeloUltimoTurno != null;
                          return Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              _Burbuja(mensaje: m),
                              if (mostrarChip)
                                _ChipAcciones(
                                  acciones: estado.accionesUltimoTurno,
                                ),
                              if (mostrarModelo)
                                _ModeloUsadoEtiqueta(
                                  modeloId: estado.modeloUltimoTurno!,
                                ),
                            ],
                          );
                        }
                        final iExtra = i - estado.mensajes.length;
                        if (estado.enviando && iExtra == 0) {
                          return const _PensandoBurbuja();
                        }
                        return _ErrorInline(
                          mensaje: estado.errorUltimoEnvio!,
                          onReintentar: _reintentar,
                        );
                      },
                    ),
            ),
            if (_imagenAdjunta != null)
              _PreviewAdjunto(
                path: _imagenAdjunta!.path,
                onQuitar: () => setState(() => _imagenAdjunta = null),
              ),
            if (_procesandoAdjunto)
              const _PreviewProcesando()
            else if (_documentoAdjunto != null)
              _PreviewDocumento(
                nombre: _documentoAdjunto!.nombre,
                truncado: _documentoAdjunto!.truncado,
                onGuardar: _guardarDocEnApuntes,
                onQuitar: () => setState(() => _documentoAdjunto = null),
              ),
            _Composer(
              controller: _controller,
              focusNode: _focusInput,
              enabled: !estado.enviando,
              onEnviar: _enviar,
              onAdjuntar: estado.enviando ? null : _abrirMenuAdjuntar,
              voz: voz,
              onEmpezarVoz: _empezarAGrabar,
              onDetenerVoz: _detenerYTranscribir,
              onCancelarVoz: _cancelarGrabacion,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Estado inicial (sin mensajes) ───────────────────────────────────────

class _EstadoInicial extends StatelessWidget {
  const _EstadoInicial();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [MatixColors.accent, MatixColors.purple],
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: MatixSpacing.xl),
            Text('Hablemos.', style: MatixText.title),
            const SizedBox(height: MatixSpacing.m),
            Text(
              'Matix conoce tu hub: proyectos activos, tareas de hoy, '
              'eventos y evaluaciones cercanas. Por ahora solo conversa '
              '— pronto también podrá crear y editar.',
              style: MatixText.small,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Burbujas ────────────────────────────────────────────────────────────

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje});
  final Mensaje mensaje;

  @override
  Widget build(BuildContext context) {
    final esUsuario = mensaje.rol == RolMensaje.usuario;
    final align = esUsuario ? Alignment.centerRight : Alignment.centerLeft;
    final radius = esUsuario
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          );

    final color = esUsuario ? MatixColors.accent : MatixColors.card;
    final colorTexto = esUsuario ? Colors.white : MatixColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MatixSpacing.s),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: mensaje.contenido));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Mensaje copiado'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MatixSpacing.xl,
                vertical: MatixSpacing.l,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: radius,
                border: esUsuario
                    ? null
                    : Border.all(color: MatixColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mensaje.imagenPath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(mensaje.imagenPath!),
                        width: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                    if (mensaje.contenido.isNotEmpty)
                      const SizedBox(height: MatixSpacing.s),
                  ],
                  if (mensaje.contenido.isNotEmpty)
                    SelectableText(
                      mensaje.contenido,
                      style: MatixText.body.copyWith(color: colorTexto),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PensandoBurbuja extends StatefulWidget {
  const _PensandoBurbuja();
  @override
  State<_PensandoBurbuja> createState() => _PensandoBurbujaState();
}

class _PensandoBurbujaState extends State<_PensandoBurbuja>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MatixSpacing.s),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MatixSpacing.xl,
            vertical: MatixSpacing.l,
          ),
          decoration: BoxDecoration(
            color: MatixColors.card,
            border: Border.all(color: MatixColors.hairline),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (ctx, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _puntito(0),
                  const SizedBox(width: 4),
                  _puntito(1),
                  const SizedBox(width: 4),
                  _puntito(2),
                  const SizedBox(width: MatixSpacing.m),
                  Text('Matix está pensando…', style: MatixText.small),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _puntito(int i) {
    // Desfasa cada punto 1/3 del ciclo. Opacidad oscila 0.25..1.0.
    final t = (_c.value + i / 3) % 1.0;
    final wave = 0.5 - 0.5 * (1 - 2 * (t - 0.5).abs()); // 0..0.5..0
    final opacidad = 0.25 + (1.0 - 0.25) * (wave * 2); // 0.25..1.0
    return Opacity(
      opacity: opacidad,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: MatixColors.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Error inline ────────────────────────────────────────────────────────

class _ErrorInline extends StatelessWidget {
  const _ErrorInline({required this.mensaje, required this.onReintentar});
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MatixSpacing.m),
      child: Container(
        padding: const EdgeInsets.all(MatixSpacing.l),
        decoration: BoxDecoration(
          color: MatixColors.red.withValues(alpha: 0.10),
          border: Border.all(color: MatixColors.red.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              color: MatixColors.red,
              size: 20,
            ),
            const SizedBox(width: MatixSpacing.l),
            Expanded(
              child: Text(
                mensaje,
                style: MatixText.small.copyWith(color: MatixColors.text),
              ),
            ),
            const SizedBox(width: MatixSpacing.m),
            TextButton(
              onPressed: onReintentar,
              style: TextButton.styleFrom(
                foregroundColor: MatixColors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: MatixSpacing.l,
                  vertical: MatixSpacing.s,
                ),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Transparencia del modelo (modo Automático) ──────────────────────────

/// Etiqueta pequeña bajo el último turno cuando el modo Automático eligió el
/// modelo: "Automático · GPT-4o mini". Deja ver qué se usó para que el
/// usuario pueda ajustar el par desde Ajustes › Modelo.
class _ModeloUsadoEtiqueta extends ConsumerWidget {
  const _ModeloUsadoEtiqueta({required this.modeloId});
  final String modeloId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etiqueta = ref.watch(modelosProvider).etiquetaDe(modeloId);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 12, color: MatixColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Automático · $etiqueta',
              style: MatixText.caption.copyWith(
                color: MatixColors.muted,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chip de acciones realizadas ─────────────────────────────────────────

/// Pequeña fila bajo la burbuja del asistente que confirma
/// visualmente lo que hizo. Útil para que el usuario verifique de
/// un vistazo "ah, sí creó la tarea" sin tener que ir a la otra
/// pestaña. Solo se muestra en el último turno (los anteriores
/// quedan limpios).
class _ChipAcciones extends StatelessWidget {
  const _ChipAcciones({required this.acciones});
  final List<String> acciones;

  static const _etiquetas = <String, ({String texto, IconData icono})>{
    // Crear
    'crear_tarea': (texto: 'Tarea creada', icono: Icons.checklist),
    'crear_evento': (texto: 'Evento agendado', icono: Icons.event),
    'crear_apunte': (texto: 'Apunte guardado', icono: Icons.sticky_note_2),
    'crear_proyecto':
        (texto: 'Proyecto creado', icono: Icons.flag_outlined),
    // Editar
    'editar_tarea': (texto: 'Tarea editada', icono: Icons.edit),
    'editar_evento': (texto: 'Evento editado', icono: Icons.edit_calendar),
    'editar_apunte': (texto: 'Apunte editado', icono: Icons.edit_note),
    'editar_proyecto':
        (texto: 'Proyecto editado', icono: Icons.edit),
    // Completar / reabrir
    'completar_tarea':
        (texto: 'Tarea completada', icono: Icons.check_circle),
    'reabrir_tarea':
        (texto: 'Tarea reabierta', icono: Icons.refresh),
    // Eliminar (papelera)
    'eliminar_tarea': (texto: 'Tarea a la papelera', icono: Icons.delete_outline),
    'eliminar_evento':
        (texto: 'Evento a la papelera', icono: Icons.delete_outline),
    'eliminar_apunte':
        (texto: 'Apunte a la papelera', icono: Icons.delete_outline),
    // Proyectos
    'aparcar_proyecto':
        (texto: 'Proyecto aparcado', icono: Icons.pause_circle_outline),
    'terminar_proyecto':
        (texto: 'Proyecto terminado', icono: Icons.task_alt),
    'reactivar_proyecto':
        (texto: 'Proyecto reactivado', icono: Icons.play_circle_outline),
    // Acción siguiente + cierre
    'marcar_accion_siguiente_hecha':
        (texto: 'Acción siguiente hecha', icono: Icons.flag),
    'registrar_cierre':
        (texto: 'Cierre del día registrado', icono: Icons.nightlight_round),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: MatixSpacing.s,
        top: MatixSpacing.s,
        right: MatixSpacing.s,
      ),
      child: Wrap(
        spacing: MatixSpacing.s,
        runSpacing: MatixSpacing.s,
        children: [
          for (final a in acciones)
            _ChipPill(
              texto: _etiquetas[a]?.texto ?? a,
              icono: _etiquetas[a]?.icono ?? Icons.bolt,
            ),
        ],
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({required this.texto, required this.icono});
  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MatixSpacing.l,
        vertical: MatixSpacing.s,
      ),
      decoration: BoxDecoration(
        color: MatixColors.green.withValues(alpha: 0.12),
        border: Border.all(color: MatixColors.green.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: MatixColors.green),
          const SizedBox(width: MatixSpacing.s),
          Text(
            texto,
            style: MatixText.caption.copyWith(
              color: MatixColors.green,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Composer (input + mic + botón enviar) ───────────────────────────────

/// Tira de previsualización de la imagen adjunta, encima del composer.
class _PreviewAdjunto extends StatelessWidget {
  const _PreviewAdjunto({required this.path, required this.onQuitar});
  final String path;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MatixColors.bg,
      padding: const EdgeInsets.fromLTRB(
          MatixSpacing.xl, MatixSpacing.s, MatixSpacing.xl, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined, color: MatixColors.muted),
            ),
          ),
          const SizedBox(width: MatixSpacing.m),
          Expanded(
            child: Text('Imagen adjunta', style: MatixText.small),
          ),
          IconButton(
            tooltip: 'Quitar imagen',
            onPressed: onQuitar,
            icon: const Icon(Icons.close, size: 18, color: MatixColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Preview del documento adjunto: nombre + acción "guardar en apuntes" +
/// quitar. Si el cerebro lo recortó por largo, lo avisa.
class _PreviewDocumento extends StatelessWidget {
  const _PreviewDocumento({
    required this.nombre,
    required this.truncado,
    required this.onGuardar,
    required this.onQuitar,
  });
  final String nombre;
  final bool truncado;
  final VoidCallback onGuardar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MatixColors.bg,
      padding: const EdgeInsets.fromLTRB(
          MatixSpacing.xl, MatixSpacing.s, MatixSpacing.xl, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MatixColors.purple.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description_outlined,
                color: MatixColors.purple, size: 20),
          ),
          const SizedBox(width: MatixSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MatixText.small.copyWith(color: MatixColors.text),
                ),
                Text(
                  truncado
                      ? 'Listo para Matix · recortado por largo'
                      : 'Listo para que Matix lo lea',
                  style: MatixText.caption.copyWith(
                    color: MatixColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onGuardar,
            child: const Text('Guardar en apuntes',
                style: TextStyle(fontSize: 11.5, color: MatixColors.accent)),
          ),
          IconButton(
            tooltip: 'Quitar documento',
            onPressed: onQuitar,
            icon: const Icon(Icons.close, size: 18, color: MatixColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Mientras subimos/extraemos un documento o transcribimos un audio elegido.
class _PreviewProcesando extends StatelessWidget {
  const _PreviewProcesando();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MatixColors.bg,
      padding: const EdgeInsets.fromLTRB(
          MatixSpacing.xl, MatixSpacing.m, MatixSpacing.xl, MatixSpacing.s),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: MatixColors.accent),
          ),
          const SizedBox(width: MatixSpacing.m),
          Text('Procesando el adjunto…', style: MatixText.small),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onEnviar,
    required this.onAdjuntar,
    required this.voz,
    required this.onEmpezarVoz,
    required this.onDetenerVoz,
    required this.onCancelarVoz,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onEnviar;
  final VoidCallback? onAdjuntar;
  final EstadoVoz voz;
  final VoidCallback onEmpezarVoz;
  final VoidCallback onDetenerVoz;
  final VoidCallback onCancelarVoz;

  bool get _grabando => voz.fase == FaseVoz.grabando;
  bool get _transcribiendo => voz.fase == FaseVoz.transcribiendo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MatixColors.bg,
        border: Border(top: BorderSide(color: MatixColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        MatixSpacing.xl,
        MatixSpacing.l,
        MatixSpacing.xl,
        MatixSpacing.l,
      ),
      child: _grabando || _transcribiendo
          ? _composerVoz()
          : _composerNormal(),
    );
  }

  /// Composer estándar con mic + input + enviar.
  Widget _composerNormal() {
    final puedeEscribir = enabled;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MicButton(onTap: enabled ? onEmpezarVoz : null),
        const SizedBox(width: MatixSpacing.s),
        IconButton(
          tooltip: 'Adjuntar',
          onPressed: onAdjuntar,
          icon: const Icon(Icons.add, color: MatixColors.muted),
        ),
        const SizedBox(width: MatixSpacing.s),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: MatixColors.card,
              border: Border.all(color: MatixColors.hairline),
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: puedeEscribir,
              style: MatixText.body,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: puedeEscribir
                    ? 'Escribe a Matix o toca el mic'
                    : 'Matix está respondiendo…',
                hintStyle: MatixText.small,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: MatixSpacing.xl,
                  vertical: MatixSpacing.l,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: MatixSpacing.m),
        _BotonRedondo(
          icon: Icons.send_rounded,
          activo: puedeEscribir,
          onTap: puedeEscribir ? onEnviar : null,
        ),
      ],
    );
  }

  /// Composer mientras estamos grabando o transcribiendo. Reemplaza
  /// completamente el input por una "píldora" roja con el contador,
  /// para que sea inequívoco que el mic está abierto.
  Widget _composerVoz() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // X para cancelar (deshabilitado durante transcribir, que ya
        // está en vuelo y cancelar no haría nada).
        _BotonRedondo(
          icon: Icons.close,
          activo: _grabando,
          onTap: _grabando ? onCancelarVoz : null,
          color: MatixColors.cardHi,
          iconColor: _grabando ? MatixColors.text : MatixColors.muted,
        ),
        const SizedBox(width: MatixSpacing.m),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MatixSpacing.xl,
              vertical: MatixSpacing.l,
            ),
            decoration: BoxDecoration(
              color: _grabando
                  ? MatixColors.red.withValues(alpha: 0.12)
                  : MatixColors.card,
              border: Border.all(
                color: _grabando
                    ? MatixColors.red.withValues(alpha: 0.5)
                    : MatixColors.hairline,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: _grabando
                ? Row(
                    children: [
                      const _PuntoRojoPalpitante(),
                      const SizedBox(width: MatixSpacing.l),
                      Text(
                        'Grabando · ${_formatoDuracion(voz.duracion)}',
                        style: MatixText.body.copyWith(
                          color: MatixColors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MatixColors.accent,
                        ),
                      ),
                      const SizedBox(width: MatixSpacing.l),
                      Text(
                        'Transcribiendo…',
                        style: MatixText.body.copyWith(
                          color: MatixColors.muted,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: MatixSpacing.m),
        // Stop & subir. Durante transcribiendo lo dejamos vivo pero
        // sin acción para que no se mueva el layout.
        _BotonRedondo(
          icon: Icons.check_rounded,
          activo: _grabando,
          onTap: _grabando ? onDetenerVoz : null,
        ),
      ],
    );
  }
}

String _formatoDuracion(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Botón circular reutilizable con el gradiente de Matix (cuando
/// activo) o color sólido (cuando inactivo o de cancelar).
class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.icon,
    required this.activo,
    required this.onTap,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final bool activo;
  final VoidCallback? onTap;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final usaGradiente = activo && color == null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: usaGradiente
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MatixColors.accent, MatixColors.purple],
              )
            : null,
        color: usaGradiente ? null : (color ?? MatixColors.cardHi),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          color: iconColor ??
              (usaGradiente ? Colors.white : MatixColors.muted),
          size: 20,
        ),
      ),
    );
  }
}

/// Botón micrófono. Visualmente distinto del send: lleva el gradiente
/// pero con un ligero offset visual para que se note como "secundario"
/// al lado del input.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _BotonRedondo(
      icon: Icons.mic_rounded,
      activo: onTap != null,
      onTap: onTap,
    );
  }
}

/// Pequeño punto rojo que late mientras se graba — refuerzo visual.
class _PuntoRojoPalpitante extends StatefulWidget {
  const _PuntoRojoPalpitante();
  @override
  State<_PuntoRojoPalpitante> createState() => _PuntoRojoPalpitanteState();
}

class _PuntoRojoPalpitanteState extends State<_PuntoRojoPalpitante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: MatixColors.red
              .withValues(alpha: 0.5 + 0.5 * _c.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Medidor de uso (Capa 2 Paso 5) ──────────────────────────────────────

/// Franja discreta arriba del chat con el consumo acumulado de OpenAI:
/// tokens y costo estimado en USD. Es consumo desde que arrancó el
/// cerebro, no saldo restante. Se invalida tras cada turno del chat.
///
/// **Decisión de Capa 2 Paso 5.1**: el banner se muestra SIEMPRE,
/// incluso en cero. Antes lo escondíamos cuando `vacio` para no
/// "ensuciar" la UI, pero el efecto colateral fue que si el medidor
/// fallaba (timeout, error de parseo, lo que sea), el silencio era
/// imposible de distinguir del estado "sin datos todavía". Mejor
/// hacer la franja visible siempre: estado de cero, de cargando y
/// de error tienen cada uno su renderizado y son verificables a
/// simple vista.
/// Indicador del modo activo, justo bajo el medidor. Solo se muestra cuando
/// hay un modo activo: una píldora "Modo X" con una ✕ para salir y tap para
/// cambiarlo. Cuando es modo normal, no ocupa espacio.
class _ModoIndicador extends ConsumerWidget {
  const _ModoIndicador({required this.onTocar});
  final VoidCallback onTocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modo = ref.watch(modosProvider).modoActivo;
    if (modo == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: MatixColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: MatixColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Modo ${modo.etiqueta}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MatixColors.accent,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () =>
                      ref.read(modosProvider.notifier).desactivar(),
                  borderRadius: BorderRadius.circular(99),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 16, color: MatixColors.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedidorBanner extends ConsumerWidget {
  const _MedidorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uso = ref.watch(usoSnapshotProvider);
    return _MedidorMarco(
      child: uso.when(
        loading: () => Text(
          'Uso: cargando…',
          style: MatixText.micro.copyWith(color: MatixColors.muted),
        ),
        error: (e, _) => Text(
          'Uso: no disponible',
          style: MatixText.micro.copyWith(color: MatixColors.red),
        ),
        data: (s) => _MedidorContenido(uso: s),
      ),
    );
  }
}

/// Contenedor visual común — el marco es estable aunque el contenido
/// esté en distintos estados (loading, error, data).
class _MedidorMarco extends StatelessWidget {
  const _MedidorMarco({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MatixSpacing.xl,
        vertical: MatixSpacing.s,
      ),
      decoration: const BoxDecoration(
        color: MatixColors.card,
        border: Border(bottom: BorderSide(color: MatixColors.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 13, color: MatixColors.muted),
          const SizedBox(width: MatixSpacing.s),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MedidorContenido extends StatelessWidget {
  const _MedidorContenido({required this.uso});
  final UsoSnapshot uso;

  @override
  Widget build(BuildContext context) {
    final costo = '\$${uso.costoUsd.toStringAsFixed(4)}';
    final tokens = _formatoTokens(uso.totalTokens);
    return Row(
      children: [
        Text(
          'Uso: $tokens · $costo',
          style: MatixText.micro.copyWith(color: MatixColors.muted),
        ),
        const Spacer(),
        if (uso.cachedPromptTokens > 0)
          Text(
            '${_formatoTokens(uso.cachedPromptTokens)} cacheados',
            style: MatixText.caption.copyWith(
              color: MatixColors.green,
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

String _formatoTokens(int n) {
  if (n < 1000) return '$n tk';
  if (n < 1_000_000) return '${(n / 1000).toStringAsFixed(1)}k tk';
  return '${(n / 1_000_000).toStringAsFixed(2)}M tk';
}
