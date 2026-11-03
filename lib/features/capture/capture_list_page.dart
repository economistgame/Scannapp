import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/db/models.dart';
import '../../core/sync/sync_service.dart';
import '../settings/settings_page.dart';
import 'capture_form_page.dart';

class CaptureListPage extends StatefulWidget {
  const CaptureListPage({super.key, required this.db, required this.sync});
  final AppDatabase db;
  final SyncService sync;

  @override
  State<CaptureListPage> createState() => _CaptureListPageState();
}

class _CaptureListPageState extends State<CaptureListPage> {
  List<Capture> _captures = [];
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _reload();
    widget.sync.onChanged = _reload; // refresca al terminar una sincronización
  }

  @override
  void dispose() {
    widget.sync.onChanged = null;
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await widget.db.listCaptures();
    if (mounted) setState(() => _captures = list);
  }

  Future<void> _new() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CaptureFormPage(db: widget.db)),
    );
    if (saved == true) {
      await _reload();
      widget.sync.syncNow(); // intenta enviar si ya hay conexión
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending =
        _captures.where((c) => c.status == SyncStatus.pending).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturas'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('Pendientes: $pending'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsPage(db: widget.db))),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar ahora',
            onPressed: () async {
              final r = await widget.sync.syncNow();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(r)));
            },
          ),
        ],
      ),
      body: _captures.isEmpty
          ? const Center(child: Text('No hay capturas'))
          : ListView.separated(
              itemCount: _captures.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = _captures[i];
                final total = c.lines.fold<int>(0, (s, l) => s + l.quantity);
                return ListTile(
                  title: Text('Pedido ${c.order} · ${c.supplier}'),
                  subtitle: Text(
                      '${_fmt.format(c.scannedAt)} · ${c.lines.length} líneas · $total uds'),
                  trailing: Icon(
                    c.status == SyncStatus.synced
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    color: c.status == SyncStatus.synced
                        ? Colors.green
                        : Colors.orange,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
    );
  }
}
