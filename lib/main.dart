import 'package:flutter/material.dart';

import 'core/db/app_database.dart';
import 'core/sync/sync_service.dart';
import 'features/capture/capture_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final sync = SyncService(db);
  sync.start(); // escucha cambios de conectividad y sincroniza pendientes
  runApp(CajaScannerApp(db: db, sync: sync));
}

class CajaScannerApp extends StatelessWidget {
  const CajaScannerApp({super.key, required this.db, required this.sync});

  final AppDatabase db;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caja Scanner',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: CaptureListPage(db: db, sync: sync),
    );
  }
}
