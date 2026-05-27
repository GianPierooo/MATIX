import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/matix_client.dart';
import 'core/providers.dart';
import 'screens/home_shell.dart';
import 'theme/matix_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sin esto, `DateFormat('...', 'es')` lanza LocaleDataException en
  // dispositivos que no traen pre-cargado el locale español.
  await initializeDateFormatting('es', null);
  runApp(const ProviderScope(child: MatixApp()));
}

class MatixApp extends ConsumerStatefulWidget {
  const MatixApp({super.key});
  @override
  ConsumerState<MatixApp> createState() => _MatixAppState();
}

class _MatixAppState extends ConsumerState<MatixApp> {
  late final MatixClient _client = ref.read(matixClientProvider);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matix',
      debugShowCheckedModeBanner: false,
      theme: buildMatixTheme(),
      home: ConfigBanner(child: HomeShell(client: _client)),
    );
  }
}
