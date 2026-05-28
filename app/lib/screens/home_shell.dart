import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/matix_client.dart';
import '../config.dart';
import '../features/autoupdate/data/update_service.dart';
import '../features/autoupdate/presentation/update_dialog.dart';
import '../features/autoupdate/providers/update_providers.dart';
import '../features/matix/presentation/matix_chat_screen.dart';
import '../features/proyectos/presentation/proyectos_list_screen.dart';
import '../features/tareas/presentation/tareas_list_screen.dart';
import '../theme/matix_colors.dart';
import 'inicio_screen.dart';
import 'universidad_screen.dart';

/// Cáscara principal: bottom nav personalizado + IndexedStack que preserva
/// el estado de cada sección al cambiar de pestaña.
///
/// La barra inferior tiene **cinco pestañas** con Matix elevado en el
/// centro (estilo FAB), siguiendo `mockups/matix-nav.jsx`:
///
///   Inicio · Proyectos · Matix(centro) · Tareas · Universidad
///
/// Apuntes y Calendario son secciones del hub pero no viven en la barra:
/// Calendario se accede desde Inicio (header) y desde "Ver agenda";
/// Apuntes se accederán desde Universidad y desde Proyectos cuando se
/// construyan esas pantallas.
///
/// Al arrancar, hace un ping al cerebro vía `/health`. Si falla, muestra
/// un `SnackBar` con el detalle.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.client});

  final MatixClient client;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _dialogoUpdateMostrado = false;

  static const _screens = <Widget>[
    InicioScreen(),
    ProyectosListScreen(),
    MatixChatScreen(),
    TareasListScreen(),
    UniversidadScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pingCerebro());
  }

  Future<void> _pingCerebro() async {
    try {
      final info = await widget.client.health();
      debugPrint('Cerebro OK: $info');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo contactar al cerebro: $e'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Reintentar', onPressed: _pingCerebro),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos el resultado del chequeo de update. La primera vez
    // que llega "hay actualización", mostramos el diálogo. Después
    // queda un banner discreto persistente hasta que la instale o
    // cierre la sesión.
    ref.listen<AsyncValue<UpdateCheckResult>>(updateCheckProvider, (
      prev,
      next,
    ) {
      next.whenData((result) {
        if (result is HayActualizacion && !_dialogoUpdateMostrado) {
          _dialogoUpdateMostrado = true;
          // Microtarea para evitar mostrar el dialog durante el build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            mostrarUpdateDialog(
              context,
              info: result.info,
              buildLocal: result.buildLocal,
            );
          });
        }
      });
    });
    // Forzamos el primer read del provider para que dispare el
    // chequeo. `watch` haría rebuild en cada cambio; con read solo
    // levantamos el FutureProvider la primera vez.
    ref.watch(updateCheckProvider);

    return Scaffold(
      // Permite que el círculo elevado de Matix "sobresalga" sobre el body
      // sin recortarse.
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _MatixBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Banner debug-mode que muestra a qué cerebro apunta la app.
class ConfigBanner extends StatelessWidget {
  const ConfigBanner({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MatixConfig.env != 'dev') return child;
    return Banner(
      message: MatixConfig.env,
      location: BannerLocation.topEnd,
      child: child,
    );
  }
}

// ─── Bottom nav custom ──────────────────────────────────────────────────────

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.isCenter = false,
  });
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isCenter;
}

class _MatixBottomNav extends StatelessWidget {
  const _MatixBottomNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <_NavItem>[
    _NavItem(
      label: 'Inicio',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
    ),
    _NavItem(
      label: 'Proyectos',
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag,
    ),
    _NavItem(
      label: 'Matix',
      icon: Icons.auto_awesome,
      activeIcon: Icons.auto_awesome,
      isCenter: true,
    ),
    _NavItem(
      label: 'Tareas',
      icon: Icons.checklist_outlined,
      activeIcon: Icons.checklist,
    ),
    _NavItem(
      label: 'Universidad',
      icon: Icons.school_outlined,
      activeIcon: Icons.school,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MatixColors.bg,
        border: Border(top: BorderSide(color: MatixColors.hairline, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _items[i].isCenter
                      ? _CenterTab(
                          active: i == currentIndex,
                          onTap: () => onTap(i),
                        )
                      : _SideTab(
                          item: _items[i],
                          active: i == currentIndex,
                          onTap: () => onTap(i),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.item,
    required this.active,
    required this.onTap,
  });
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? MatixColors.accent : MatixColors.muted;
    return InkResponse(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: active
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 4)
                  : const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? MatixColors.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                active ? item.activeIcon : item.icon,
                size: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterTab extends StatelessWidget {
  const _CenterTab({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      // El círculo se eleva ~22 px por encima de la barra (efecto FAB).
      child: Transform.translate(
        offset: const Offset(0, -22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [MatixColors.accent, MatixColors.purple],
                ),
                boxShadow: [
                  BoxShadow(
                    color: MatixColors.accent.withValues(alpha: 0.50),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
                // "Hueco" oscuro alrededor del círculo, como en los mockups.
                border: Border.all(color: MatixColors.bg, width: 5),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Matix',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: active ? MatixColors.accent : MatixColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
