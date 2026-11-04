import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/models.dart';
import '../grai/grai_parser.dart';
import '../masterdata/master_picker.dart';
import '../scanner/scanner_page.dart';

/// Formulario de captura:
/// (1) Pedido: escaneado o a mano
/// (2) Proveedor: se elige de los datos maestros; se autorrellena (por pedido
///     o último usado) y el usuario puede cambiarlo
/// (3) Líneas: producto de los datos maestros + cantidad, manual o a partir
///     del GRAI
class CaptureFormPage extends StatefulWidget {
  const CaptureFormPage({super.key, required this.db});
  final AppDatabase db;

  @override
  State<CaptureFormPage> createState() => _CaptureFormPageState();
}

class _CaptureFormPageState extends State<CaptureFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _orderCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _lines = <CaptureLine>[];
  final _uuid = const Uuid();
  bool _supplierChosenByUser = false;

  @override
  void initState() {
    super.initState();
    // Proveedor por defecto: el último utilizado (si sigue en datos maestros)
    widget.db.lastSupplier().then((s) {
      if (s != null && _supplierCtrl.text.isEmpty && mounted) {
        setState(() => _supplierCtrl.text = s);
      }
    });
  }

  @override
  void dispose() {
    _orderCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  // ---- (1) Pedido ---------------------------------------------------------

  Future<void> _scanOrder() async {
    final code = await ScannerPage.scan(context, title: 'Escanear pedido');
    if (code == null) return;
    _orderCtrl.text = code.trim();
    await _autofillSupplier();
  }

  // ---- (2) Proveedor ------------------------------------------------------

  Future<void> _autofillSupplier() async {
    if (_supplierChosenByUser) return;
    final s = await widget.db.supplierForOrder(_orderCtrl.text.trim());
    if (s != null && mounted) setState(() => _supplierCtrl.text = s);
  }

  Future<void> _pickSupplier() async {
    final s = await showMasterPicker(
      context,
      title: 'Proveedor',
      loadItems: widget.db.listSuppliers,
      onCreate: (name) async {
        await widget.db.addSupplier(name);
        return name;
      },
    );
    if (s != null && mounted) {
      setState(() {
        _supplierCtrl.text = s;
        _supplierChosenByUser = true;
      });
    }
  }

  // ---- (3) Líneas ---------------------------------------------------------

  /// Selector de producto. Si [graiCode] viene informado, un producto creado
  /// desde aquí queda asociado a ese código de GRAI.
  Future<String?> _pickProduct({String? graiCode}) {
    return showMasterPicker(
      context,
      title: 'Producto',
      loadItems: widget.db.productNames,
      onCreate: (name) async {
        try {
          await widget.db.saveProduct(name: name, code: graiCode);
          return name;
        } catch (_) {
          _snack('No se pudo crear el producto');
          return null;
        }
      },
    );
  }

  Future<void> _addManualLine() async {
    final line = await showDialog<CaptureLine>(
      context: context,
      builder: (_) => _LineDialog(
        id: _uuid.v4(),
        source: LineSource.manual,
        pickProduct: () => _pickProduct(),
      ),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _addLineFromGrai() async {
    final raw = await ScannerPage.scan(context, title: 'Escanear GRAI');
    if (raw == null || !mounted) return;

    final slice = await widget.db.graiModelSlice();
    final parser = GraiParser(start: slice.start, length: slice.length);
    final code = parser.extractModelCode(raw);

    if (code == null) {
      _snack('El código escaneado es demasiado corto: hacen falta al menos '
          '${parser.minChars} caracteres (revisa el trozo en Ajustes)');
      return;
    }

    final productName = await widget.db.productNameForCode(code);
    if (!mounted) return;

    // Si el código no está en los datos maestros, el usuario elige (o crea) el
    // producto al que corresponde y queda guardado para próximas lecturas.
    final line = await showDialog<CaptureLine>(
      context: context,
      builder: (_) => _LineDialog(
        id: _uuid.v4(),
        source: LineSource.grai,
        pickProduct: () =>
            _pickProduct(graiCode: productName == null ? code : null),
        initialProduct: productName,
        graiRaw: raw,
        graiCode: code,
      ),
    );
    if (line == null) return;
    if (productName == null) {
      await widget.db.linkCodeToProduct(code, line.boxModel);
    }
    setState(() => _lines.add(line));
  }

  // ---- Guardar ------------------------------------------------------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      _snack('Añade al menos una línea');
      return;
    }
    final capture = Capture(
      id: _uuid.v4(),
      order: _orderCtrl.text.trim(),
      supplier: _supplierCtrl.text.trim(),
      scannedAt: DateTime.now(),
      lines: List.of(_lines),
    );
    await widget.db.saveCapture(capture);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva captura')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _orderCtrl,
              decoration: InputDecoration(
                labelText: 'Pedido',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanOrder,
                ),
              ),
              onChanged: (_) => _autofillSupplier(),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Introduce el pedido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _supplierCtrl,
              readOnly: true,
              onTap: _pickSupplier,
              decoration: const InputDecoration(
                labelText: 'Proveedor',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Elige el proveedor'
                  : null,
            ),
            const SizedBox(height: 24),
            Text('Líneas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Sin líneas todavía'),
              ),
            for (final l in _lines)
              Card(
                child: ListTile(
                  leading: Icon(l.source == LineSource.grai
                      ? Icons.qr_code
                      : Icons.edit),
                  title: Text(l.boxModel),
                  subtitle: Text('Cantidad: ${l.quantity}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _lines.remove(l)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addManualLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Manual'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _addLineFromGrai,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear GRAI'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({
    required this.id,
    required this.source,
    required this.pickProduct,
    this.initialProduct,
    this.graiRaw,
    this.graiCode,
  });

  final String id;
  final LineSource source;
  final Future<String?> Function() pickProduct;
  final String? initialProduct;
  final String? graiRaw;
  final String? graiCode;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _productCtrl =
      TextEditingController(text: widget.initialProduct ?? '');
  final _qtyCtrl = TextEditingController(text: '1');
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _productCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final p = await widget.pickProduct();
    if (p != null && mounted) setState(() => _productCtrl.text = p);
  }

  @override
  Widget build(BuildContext context) {
    final known = widget.initialProduct != null;
    return AlertDialog(
      title: Text(widget.source == LineSource.grai
          ? 'Línea desde GRAI'
          : 'Línea manual'),
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.graiCode != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(known
                    ? 'Código ${widget.graiCode} reconocido.'
                    : 'El código ${widget.graiCode} no está en los datos '
                        'maestros. Elige el producto al que corresponde '
                        '(se recordará) o crea uno nuevo.'),
              ),
            TextFormField(
              controller: _productCtrl,
              readOnly: true,
              onTap: _pick,
              decoration: const InputDecoration(
                labelText: 'Producto',
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Elige un producto' : null,
            ),
            TextFormField(
              controller: _qtyCtrl,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return (n == null || n <= 0) ? 'Cantidad > 0' : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            Navigator.pop(
              context,
              CaptureLine(
                id: widget.id,
                boxModel: _productCtrl.text.trim(),
                quantity: int.parse(_qtyCtrl.text),
                source: widget.source,
                graiRaw: widget.graiRaw,
              ),
            );
          },
          child: const Text('Añadir'),
        ),
      ],
    );
  }
}
