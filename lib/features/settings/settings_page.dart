import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db/app_database.dart';
import '../grai/grai_parser.dart';

/// Ajustes:
///  - Identificación de producto: qué trozo del GRAI identifica el modelo y
///    catálogo código -> modelo.
///  - Envío de datos: ninguno / API / email.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.db});
  final AppDatabase db;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _startCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _apiUrlCtrl = TextEditingController();
  final _apiTokenCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _sampleCtrl = TextEditingController();
  String _mode = 'none';
  List<({String code, String name})> _models = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.db;
    final slice = await db.graiModelSlice();
    _startCtrl.text = '${slice.start}';
    _lengthCtrl.text = '${slice.length}';
    _apiUrlCtrl.text = await db.getSetting('api_base_url') ?? '';
    _apiTokenCtrl.text = await db.getSetting('api_token') ?? '';
    _emailCtrl.text = await db.getSetting('email_to') ?? '';
    _mode = await db.getSetting('sync_mode') ?? 'none';
    _models = await db.listModels();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [
      _startCtrl,
      _lengthCtrl,
      _apiUrlCtrl,
      _apiTokenCtrl,
      _emailCtrl,
      _sampleCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final start = int.tryParse(_startCtrl.text);
    final length = int.tryParse(_lengthCtrl.text);
    if (start == null || length == null || start < 1 || length < 1 || start - 1 + length > 60) {
      _snack('Indica un carácter inicial (≥ 1) y un nº de caracteres (≥ 1)');
      return;
    }
    if (_mode == 'api' && _apiUrlCtrl.text.trim().isEmpty) {
      _snack('Indica la URL de la API');
      return;
    }
    if (_mode == 'email' && !_emailCtrl.text.contains('@')) {
      _snack('Indica un email de destino válido');
      return;
    }
    final db = widget.db;
    await db.setGraiModelSlice(start, length);
    await db.setSetting('sync_mode', _mode);
    await db.setSetting('api_base_url', _apiUrlCtrl.text.trim());
    await db.setSetting('api_token', _apiTokenCtrl.text.trim());
    await db.setSetting('email_to', _emailCtrl.text.trim());
    _snack('Ajustes guardados');
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Previsualiza qué código de modelo saldría con los valores actuales.
  String get _preview {
    final start = int.tryParse(_startCtrl.text);
    final length = int.tryParse(_lengthCtrl.text);
    if (start == null || length == null || _sampleCtrl.text.trim().isEmpty) {
      return '—';
    }
    final parser = GraiParser(start: start, length: length);
    final code = parser.extractModelCode(_sampleCtrl.text);
    if (code != null) return code;
    return 'el código es demasiado corto (mín. ${parser.minChars} caracteres)';
  }

  Future<void> _editModel([({String code, String name})? m]) async {
    final codeCtrl = TextEditingController(text: m?.code ?? '');
    final nameCtrl = TextEditingController(text: m?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(m == null ? 'Nuevo modelo' : 'Editar modelo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: codeCtrl,
            enabled: m == null,
            decoration: const InputDecoration(labelText: 'Código (trozo del GRAI)'),
          ),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre del modelo'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    codeCtrl.dispose();
    nameCtrl.dispose();
    if (ok != true || code.isEmpty || name.isEmpty) return;
    await widget.db.saveModel(code, name);
    _models = await widget.db.listModels();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes'), actions: [
        IconButton(icon: const Icon(Icons.save), onPressed: _save),
      ]),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Identificación de producto (GRAI)', style: t),
                const SizedBox(height: 8),
                const Text(
                    'Trozo del código escaneado (en caracteres) que identifica el modelo de caja. '
                    'Cuenta desde el primer carácter del GRAI; si el código lleva delante el '
                    'identificador 8003, se ignora.'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _startCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Desde el carácter nº',
                          helperText: '1 = el primero',
                          border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lengthCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Nº de caracteres',
                          border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _sampleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Prueba: pega un GRAI de ejemplo',
                    helperText: 'Código de modelo resultante: $_preview',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text('Catálogo de modelos', style: t)),
                  IconButton(
                      icon: const Icon(Icons.add), onPressed: () => _editModel()),
                ]),
                if (_models.isEmpty) const Text('Sin modelos todavía'),
                for (final m in _models)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.name),
                    subtitle: Text('Código: ${m.code}'),
                    onTap: () => _editModel(m),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await widget.db.deleteModel(m.code);
                        _models = await widget.db.listModels();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                const Divider(height: 32),
                Text('Envío de datos', style: t),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'none', label: Text('Ninguno')),
                    ButtonSegment(value: 'api', label: Text('API')),
                    ButtonSegment(value: 'email', label: Text('Email')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 12),
                if (_mode == 'api') ...[
                  TextField(
                    controller: _apiUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'URL base de la API',
                        hintText: 'https://api.ejemplo.com',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiTokenCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Token (opcional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Se envía automáticamente al recuperar la conexión.'),
                ],
                if (_mode == 'email') ...[
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email de destino',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Se prepara un correo con un CSV adjunto al pulsar el botón de sincronizar.'),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar ajustes')),
              ],
            ),
    );
  }
}
