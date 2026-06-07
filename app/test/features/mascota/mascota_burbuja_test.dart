import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/mascota/presentation/avatar_matix.dart';
import 'package:matix/features/mascota/presentation/mascota_burbuja.dart';

void main() {
  testWidgets(
      'sin mensaje no pinta robot: un solo robot en la app (el de Inicio)',
      (tester) async {
    // La burbuja GLOBAL ya NO muestra una "bolita" persistente cuando no hay
    // mensaje. Antes eso duplicaba el robot-compañero (PresenciaMatix) en Inicio
    // y su tap navegaba al chat. Ahora, sin mensaje, no dibuja nada.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MascotaBurbuja())),
      ),
    );
    await tester.pump();

    expect(find.byType(AvatarMatix), findsNothing);
  });
}
