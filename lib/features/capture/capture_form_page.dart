import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/models.dart';
import '../grai/grai_parser.dart';
import '../scanner/scanner_page.dart';

/// Formulario de captura:
/// (1) Pedido: escaneado o a mano
/// (2) Proveedor: autorrellenado (por pedido o último usado), editable
/// (3) Líneas: modelo de caja + cantidad, manual o a partir del GRAI
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
  bool _supplierEditedByUser = false;

  @override
  void initState() {
    super.initState();
    // Proveedor por defecto: el último utilizado
    widget.db.lastSupplier().then((s) {
      if (s != null && _supplierCtrl.text.isEmpty && mounted) {
        _supplierCtrl.text = s;
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
    if (_supplierEditedByUser && _supplierCtrl.text.isNotEmpty) return;
    final s = await widget.db.supplierForOrder(_orderCtrl.text.trim());
    if (s != null && mounted) setState(() => _supplierCtrl.text = s);
  }

  // ---- (3) Líneas ---------------------------------------------------------

  Future<void> _addManualLine() async {
    final models = await widget.db.modelNames();
    if (!mounted) return;
    final line = await showDialog<CaptureLine>(
      context: context,
      builder: (_) => _LineDialog(
        id: _uuid.v4(),
        knownModels: models,
        source: LineSource.manual,
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
      _snack('El código escaneado no parece un GRAI válido');
      return;
    }

    var modelName = await widget.db.modelNameForCode(code);
    final models = await widget.db.modelNames();
    if (!mounted) return;

    // Si el trozo no está en el catálogo local, el usuario lo asigna una vez
    // y queda guardado para próximas lecturas (también offline).
    final line = await showDialog<CaptureLine>(
      context: context,
      builder: (_) => _LineDialog(
        id: _uuid.v4(),
        knownModels: models,
        source: LineSource.grai,
        initialModel: modelName,
        graiRaw: raw,
        graiCode: code,
        modelIsKnown: modelName != null,
      ),
    );
    if (line == null) return;
    if (modelName == null) await widget.db.saveModel(code, line.boxModel);
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
              decoration: const InputDecoration(
                labelText: 'Proveedor',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _supplierEditedByUser = true,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Introduce el proveedor'
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
    required this.knownModels,
    required this.source,
    this.initialModel,
    this.graiRaw,
    this.graiCode,
    this.modelIsKnown = false,
  });

  final String id;
  final List<String> knownModels;
  final LineSource source;
  final String? initialModel;
  final String? graiRaw;
  final String? graiCode;
  final bool modelIsKnown;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _modelCtrl = TextEditingController(text: widget.initialModel ?? '');
  final _qtyCtrl = TextEditingController(text: '1');
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    _modelCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text(widget.modelIsKnown
                    ? 'Código de modelo detectado: ${widget.graiCode}'
                    : 'Código ${widget.graiCode} sin modelo asignado. '
                        'Indica el modelo; se recordará para futuros escaneos.'),
              ),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _modelCtrl.text),
              optionsBuilder: (v) => widget.knownModels.where(
                  (m) => m.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => _modelCtrl.text = v,
              fieldViewBuilder: (context, ctrl, focus, _) => TextFormField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(labelText: 'Modelo de caja'),
                onChanged: (v) => _modelCtrl.text = v,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
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
            onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            Navigator.pop(
              context,
              CaptureLine(
                id: widget.id,
                boxModel: _modelCtrl.text.trim(),
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
