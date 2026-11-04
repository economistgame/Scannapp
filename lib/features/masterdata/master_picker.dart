import 'package:flutter/material.dart';

/// Selector con búsqueda para elegir un dato maestro (proveedor, producto...).
///
/// Solo se puede elegir lo que hay en la lista. Si lo escrito no existe,
/// aparece "Añadir «texto»": [onCreate] lo da de alta en los datos maestros y
/// devuelve el nombre definitivo (o null si no se pudo crear).
Future<String?> showMasterPicker(
  BuildContext context, {
  required String title,
  required Future<List<String>> Function() loadItems,
  required Future<String?> Function(String name) onCreate,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _MasterPicker(title: title, loadItems: loadItems, onCreate: onCreate),
  );
}

class _MasterPicker extends StatefulWidget {
  const _MasterPicker({
    required this.title,
    required this.loadItems,
    required this.onCreate,
  });

  final String title;
  final Future<List<String>> Function() loadItems;
  final Future<String?> Function(String name) onCreate;

  @override
  State<_MasterPicker> createState() => _MasterPickerState();
}

class _MasterPickerState extends State<_MasterPicker> {
  final _ctrl = TextEditingController();
  List<String>? _items;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.loadItems().then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    final created = await widget.onCreate(name);
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final q = _query.trim();
    final lower = q.toLowerCase();
    final filtered =
        items?.where((e) => e.toLowerCase().contains(lower)).toList() ??
            const <String>[];
    final exists = items?.any((e) => e.toLowerCase() == lower) ?? false;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar o escribir uno nuevo',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (q.isNotEmpty && !exists)
                          ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: Text('Añadir «$q»'),
                            onTap: () => _create(q),
                          ),
                        for (final e in filtered)
                          ListTile(
                            title: Text(e),
                            onTap: () => Navigator.of(context).pop(e),
                          ),
                        if (items.isEmpty && q.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Todavía no hay ninguno. Escribe un nombre arriba '
                              'para crear el primero.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
