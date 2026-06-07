import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/theme/matix_spacing.dart';

void main() {
  testWidgets(
      'scrollBottom = inset del sistema + alto de la barra + holgura (+ robot)',
      (tester) async {
    late double sinRobot;
    late double conRobot;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: 24), // gesto/barra del sistema
        ),
        child: Builder(
          builder: (ctx) {
            sinRobot = MatixLayout.scrollBottom(ctx);
            conRobot = MatixLayout.scrollBottom(ctx, conRobot: true);
            return const SizedBox();
          },
        ),
      ),
    );

    // La convención SÍ suma el alto de la barra (antes el bug lo olvidaba).
    expect(sinRobot, 24 + MatixLayout.alturaBarraNav + MatixLayout.holgura);
    // El robot añade su holgura encima.
    expect(conRobot, sinRobot + MatixLayout.holguraRobot);
    // Regresión: debe reservar MÁS que el viejo guard (inset + 32), que cortaba.
    expect(sinRobot, greaterThan(24 + 32));
    // `bottomNavGuard` es el alias sin robot.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 24)),
        child: Builder(
          builder: (ctx) {
            expect(MatixLayout.bottomNavGuard(ctx), sinRobot);
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
