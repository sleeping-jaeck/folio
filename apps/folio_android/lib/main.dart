import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.start();
  runApp(FolioApp(services: services));
}

class FolioApp extends StatelessWidget {
  const FolioApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6B4F2C);
    return Services(
      services: services,
      child: MaterialApp(
        title: 'Folio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: seed,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}
