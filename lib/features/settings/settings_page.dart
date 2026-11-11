import 'package:flutter/material.dart';

import '../../core/db/app_database.dart';
import '../grai/grai_parser.dart';
import '../masterdata/master_data_page.dart';

/// Ajustes:
///  - Lectura del GRAI (prueba) y acceso a los datos maestros.
///  - Envío de datos: ninguno / API / email.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.db});
  final AppDatabase db;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiUrlCtrl = TextEditingController();
  final _apiTokenCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _sampleCtrl = TextEditingController();
  String _mode = 'none';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.db;
    _apiUrlCtrl.text = await db.getSetting('api_base_url') ?? '';
    _apiTokenCtrl.text = await db.getSetting('api_token') ?? '';
    _emailCtrl.text = await db.getSetting('email_to') ?? '';
    _mode = await db.getSetting('sync_mode') ?? 'none';
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [
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
    if (_mode == 'api' && _apiUrlCtrl.text.trim().isEmpty) {
      _snack('Indica la URL de la API');
      return;
    }
    if (_mode == 'email' && !_emailCtrl.text.contains('@')) {
      _snack('Indica un email de destino válido');
      return;
    }
    final db = widget.db;
    await db.setSetting('sync_mode', _mode);
    await db.setSetting('api_base_url', _apiUrlCtrl.text.trim());
    await db.setSetting('api_token', _apiTokenCtrl.text.trim());
    await db.setSetting('email_to', _emailCtrl.text.trim());
    _snack('Ajustes guardados');
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _preview = '';

  /// Lee el GRAI de prueba y muestra el EAN, la serie y el modelo que sale.
  Future<void> _updatePreview() async {
    final raw = _sampleCtrl.text;
    if (raw.trim().isEmpty) {
      setState(() => _preview = '');
      return;
    }
    final g = const GraiParser().parse(raw);
    if (g == null) {
      setState(() => _preview = 'No parece un GRAI: 14 dígitos que empiecen '
          'por 0, con o sin 8003 delante');
      return;
    }
    final name = await widget.db.productNameForEan(g.ean);
    if (!mounted || raw != _sampleCtrl.text) return;
    final serial = g.serial.isEmpty ? '—' : g.serial;
    final model = name == null
        ? 'Este EAN no está en los datos maestros'
        : 'Modelo: $name';
    setState(() => _preview = 'EAN ${g.ean} · serie $serial\n$model');
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
                Text('Lectura del GRAI', style: t),
                const SizedBox(height: 8),
                const Text(
                    'El modelo se identifica por su EAN, que va dentro del GRAI: '
                    '8003 + 0 + EAN (13 dígitos) + nº de serie. Define cada EAN y '
                    'su nombre en Datos maestros.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _sampleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Prueba: pega un GRAI de ejemplo',
                    helperText: _preview.isEmpty ? null : _preview,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _updatePreview(),
                ),
                const Divider(height: 32),
                Text('Datos maestros', style: t),
                const SizedBox(height: 8),
                const Text(
                    'Listas de proveedores y de productos (con su EAN). '
                    'Al capturar solo se puede elegir lo que haya aquí.'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Proveedores y productos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MasterDataPage(db: widget.db))),
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
