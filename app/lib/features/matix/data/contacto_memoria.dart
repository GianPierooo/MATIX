/// Arma el mensaje que se le manda a Matix para que guarde un contacto del
/// teléfono en su memoria (categoría personas). Función PURA para poder
/// testearla sin tocar el plugin de contactos.
///
/// Devuelve `null` si no hay ningún dato que valga la pena guardar.
String? mensajeGuardarContacto({
  required String nombre,
  List<String> telefonos = const [],
  List<String> correos = const [],
}) {
  final partes = <String>[];
  final n = nombre.trim();
  if (n.isNotEmpty) partes.add('Nombre: $n');

  final tels = telefonos.map((t) => t.trim()).where((t) => t.isNotEmpty).join(', ');
  if (tels.isNotEmpty) partes.add('Teléfono: $tels');

  final mails = correos.map((c) => c.trim()).where((c) => c.isNotEmpty).join(', ');
  if (mails.isNotEmpty) partes.add('Correo: $mails');

  if (partes.isEmpty) return null;
  return 'Guarda en tu memoria a esta persona de mis contactos '
      '(categoría personas). ${partes.join('. ')}.';
}
