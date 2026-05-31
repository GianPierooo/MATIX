// El indicador de hora actual y el reloj del calendario usan hora de
// Lima (UTC-5 todo el año). Verificamos que `horaLima()` está 5 horas
// detrás del UTC actual, independientemente de la zona del dispositivo.

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/presentation/calendario_screen.dart';

void main() {
  test('horaLima() está 5 horas detrás del UTC actual', () {
    final lima = horaLima();
    final utc = DateTime.now().toUtc();
    final diff = utc.difference(lima);
    // ~5 horas (con margen por el tiempo entre ambas lecturas).
    expect(diff.inMinutes, closeTo(300, 2));
  });
}
