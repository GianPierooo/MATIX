import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resuelve un contacto (por nombre) a un número para abrir su chat de WhatsApp
/// (Tier C.1). Si el nombre es ambiguo o no existe, lo reporta para que Matix
/// pregunte; nunca adivina un número.
class ResultadoContacto {
  const ResultadoContacto({
    required this.estado,
    this.numero,
    this.nombre,
    this.ambiguos = const [],
  });

  /// 'ok' | 'ninguno' | 'varios' | 'sin_permiso'
  final String estado;
  final String? numero;
  final String? nombre;
  final List<String> ambiguos;
}

class ContactosResolver {
  ContactosResolver();

  Future<ResultadoContacto> resolver(String consulta) async {
    final q = consulta.trim();
    if (q.isEmpty) return const ResultadoContacto(estado: 'ninguno');

    // Si ya es un número, úsalo directo (sin tocar la agenda).
    if (_pareceNumero(q)) {
      return ResultadoContacto(estado: 'ok', numero: q, nombre: q);
    }

    final permiso = await Permission.contacts.request();
    if (!permiso.isGranted) return const ResultadoContacto(estado: 'sin_permiso');
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      return const ResultadoContacto(estado: 'sin_permiso');
    }

    final contactos = await FlutterContacts.getContacts(withProperties: true);
    final objetivo = _norm(q);
    final matches = contactos
        .where((c) => c.phones.isNotEmpty && _norm(c.displayName).contains(objetivo))
        .toList();

    if (matches.isEmpty) return const ResultadoContacto(estado: 'ninguno');

    final nombresDistintos = matches.map((c) => c.displayName).toSet().toList();
    if (nombresDistintos.length > 1) {
      return ResultadoContacto(estado: 'varios', ambiguos: nombresDistintos);
    }

    final c = matches.first;
    return ResultadoContacto(
      estado: 'ok',
      numero: c.phones.first.number,
      nombre: c.displayName,
    );
  }

  bool _pareceNumero(String s) {
    final d = s.replaceAll(RegExp(r'[\s+()-]'), '');
    return d.length >= 7 && RegExp(r'^\d+$').hasMatch(d);
  }

  String _norm(String s) {
    var r = s.toLowerCase().trim();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      r = r.replaceAll(con[i], sin[i]);
    }
    return r;
  }
}
