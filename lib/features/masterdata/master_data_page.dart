import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db/app_database.dart';
import '../../core/db/models.dart';
import '../grai/grai_parser.dart';

/// Datos maestros: la lista de proveedores y la de productos (modelos de caja
/// con su código de GRAI). En la captura solo se puede elegir de aquí.
class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key, required this.db});
  final AppDatabase db;

  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  List<String> _suppliers = [];
  List<Product> _products = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await widget.db.listSuppliers();
    final p = await widget.db.listProducts();
    if (!mounted) return;
    setState(() {
      _suppliers = s;
      _products = p;
      _loaded = true;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<bool> _confirmDelete(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar'),
        content: Text('¿Eliminar $what de los datos maestros?\n'
            'Las capturas ya guardadas no cambian.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    return ok == true;
  }

  // ---- Proveedores --------------------------------------------------------

  Future<void> _editSupplier([String? current]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SupplierDialog(initial: current),
    );
    if (name == null || name.isEmpty) return;
    final dup = _suppliers
        .any((s) => s.toLowerCase() == name.toLowerCase() && s != current);
    if (dup) {
      _snack('Ese proveedor ya existe');
      return;
    }
    try {
      if (current == null) {
        await widget.db.addSupplier(name);
      } else {
        await widget.db.renameSupplier(current, name);
      }
    } catch (_) {
      _snack('No se pudo guardar el proveedor');
    }
    await _reload();
  }

  // ---- Productos ----------------------------------------------------------

  Future<void> _editProduct([Product? product]) async {
    final r = await showDialog<({String name, String ean})>(
      context: context,
      builder: (_) => _ProductDialog(initial: product),
    );
    if (r == null || r.name.isEmpty) return;
    try {
      await widget.db
          .saveProduct(id: product?.id, name: r.name, ean: r.ean);
    } catch (_) {
      _snack('Ese EAN ya está asignado a otro producto');
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final onSuppliers = _tabs.index == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos maestros'),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: 'Proveedores (${_suppliers.length})'),
          Tab(text: 'Productos (${_products.length})'),
        ]),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [
              _suppliersTab(),
              _productsTab(),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => onSuppliers ? _editSupplier() : _editProduct(),
        icon: const Icon(Icons.add),
        label: Text(onSuppliers ? 'Proveedor' : 'Producto'),
      ),
    );
  }

  Widget _suppliersTab() {
    if (_suppliers.isEmpty) {
      return const _Empty('Todavía no hay proveedores.\nPulsa «Proveedor» para añadir el primero.');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _suppliers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = _suppliers[i];
        return ListTile(
          title: Text(s),
          onTap: () => _editSupplier(s),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await _confirmDelete('«$s»')) {
                await widget.db.deleteSupplier(s);
                await _reload();
              }
            },
          ),
        );
      },
    );
  }

  Widget _productsTab() {
    if (_products.isEmpty) {
      return const _Empty('Todavía no hay productos.\nPulsa «Producto» para añadir el primero.');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _products.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _products[i];
        return ListTile(
          title: Text(p.name),
          subtitle: Text(
              p.ean == null ? 'Sin EAN (solo manual)' : 'EAN: ${p.ean}'),
          onTap: () => _editProduct(p),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await _confirmDelete('«${p.name}»')) {
                await widget.db.deleteProduct(p.id);
                await _reload();
              }
            },
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({this.initial});
  final String? initial;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  late final _ctrl = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo proveedor' : 'Editar proveedor'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('Guardar')),
      ],
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({this.initial});
  final Product? initial;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
  late final _eanCtrl = TextEditingController(text: widget.initial?.ean ?? '');
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _eanCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final ean = _eanCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre del producto');
      return;
    }
    if (ean.isNotEmpty && !isValidEan(ean)) {
      setState(() => _error = 'El EAN no es válido: revisa los dígitos '
          '(13 dígitos, con el dígito de control correcto)');
      return;
    }
    Navigator.pop(context, (name: name, ean: ean));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo producto' : 'Editar producto'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Nombre del producto (modelo)'),
        ),
        TextField(
          controller: _eanCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'EAN',
            helperText: 'Los 13 dígitos del EAN. Vacío = solo manual.',
            helperMaxLines: 2,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
