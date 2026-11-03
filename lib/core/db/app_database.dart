import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Base de datos local (SQLite). Es la fuente de verdad: la app nunca
/// depende de la red para guardar un escaneo.
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'caja_scanner.db');
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE captures(
            id TEXT PRIMARY KEY,
            order_code TEXT NOT NULL,
            supplier TEXT NOT NULL,
            scanned_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending'
          )''');
        await db.execute('''
          CREATE TABLE capture_lines(
            id TEXT PRIMARY KEY,
            capture_id TEXT NOT NULL REFERENCES captures(id) ON DELETE CASCADE,
            box_model TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            source TEXT NOT NULL,
            grai_raw TEXT
          )''');
        // Catálogo local: código de modelo extraído del GRAI -> nombre de modelo
        await db.execute('''
          CREATE TABLE box_models(
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )''');
        // Catálogo local: pedido -> proveedor (para autorrellenar)
        await db.execute('''
          CREATE TABLE order_suppliers(
            order_code TEXT PRIMARY KEY,
            supplier TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
      },
    );
    return AppDatabase._(db);
  }

  // ---- Capturas -----------------------------------------------------------

  Future<void> saveCapture(Capture c) async {
    await _db.transaction((txn) async {
      await txn.insert('captures', c.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('capture_lines', where: 'capture_id = ?', whereArgs: [c.id]);
      for (final l in c.lines) {
        await txn.insert('capture_lines', l.toMap(c.id));
      }
      // Recordamos pedido -> proveedor para autorrellenar la próxima vez
      await txn.insert(
        'order_suppliers',
        {'order_code': c.order, 'supplier': c.supplier},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('settings', {'key': 'last_supplier', 'value': c.supplier},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Capture>> listCaptures({SyncStatus? status}) async {
    final rows = await _db.query(
      'captures',
      where: status == null ? null : 'sync_status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'scanned_at DESC',
    );
    final result = <Capture>[];
    for (final r in rows) {
      final lines = await _db.query('capture_lines',
          where: 'capture_id = ?', whereArgs: [r['id']]);
      result.add(Capture(
        id: r['id'] as String,
        order: r['order_code'] as String,
        supplier: r['supplier'] as String,
        scannedAt: DateTime.parse(r['scanned_at'] as String).toLocal(),
        status: SyncStatus.values.byName(r['sync_status'] as String),
        lines: lines.map(CaptureLine.fromMap).toList(),
      ));
    }
    return result;
  }

  Future<void> markSynced(String id) => _db.update(
        'captures',
        {'sync_status': SyncStatus.synced.name},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> deleteCapture(String id) =>
      _db.delete('captures', where: 'id = ?', whereArgs: [id]);

  // ---- Catálogos ----------------------------------------------------------

  Future<String?> supplierForOrder(String order) async {
    final r = await _db.query('order_suppliers',
        where: 'order_code = ?', whereArgs: [order], limit: 1);
    return r.isEmpty ? null : r.first['supplier'] as String;
  }

  Future<String?> lastSupplier() async {
    final r = await _db.query('settings',
        where: 'key = ?', whereArgs: ['last_supplier'], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<String?> modelNameForCode(String code) async {
    final r = await _db.query('box_models',
        where: 'code = ?', whereArgs: [code], limit: 1);
    return r.isEmpty ? null : r.first['name'] as String;
  }

  Future<void> saveModel(String code, String name) => _db.insert(
        'box_models',
        {'code': code, 'name': name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<String>> modelNames() async {
    final r = await _db.query('box_models', orderBy: 'name');
    return r.map((e) => e['name'] as String).toList();
  }

  /// Carga/actualiza catálogos descargados del servidor cuando hay conexión.
  Future<void> upsertCatalogs({
    Map<String, String> models = const {},
    Map<String, String> orderSuppliers = const {},
  }) async {
    final batch = _db.batch();
    models.forEach((code, name) => batch.insert(
        'box_models', {'code': code, 'name': name},
        conflictAlgorithm: ConflictAlgorithm.replace));
    orderSuppliers.forEach((o, s) => batch.insert(
        'order_suppliers', {'order_code': o, 'supplier': s},
        conflictAlgorithm: ConflictAlgorithm.replace));
    await batch.commit(noResult: true);
  }

  // ---- Ajustes genéricos (clave/valor) -----------------------------------

  Future<String?> getSetting(String key) async {
    final r = await _db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => _db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---- Catálogo de modelos (para editarlo desde ajustes) -----------------

  Future<List<({String code, String name})>> listModels() async {
    final r = await _db.query('box_models', orderBy: 'code');
    return r
        .map((e) => (code: e['code'] as String, name: e['name'] as String))
        .toList();
  }

  Future<void> deleteModel(String code) =>
      _db.delete('box_models', where: 'code = ?', whereArgs: [code]);

  // ---- Configuración del parser GRAI -------------------------------------

  Future<int> _intSetting(String key, int def) async {
    final v = await getSetting(key);
    return v == null ? def : int.tryParse(v) ?? def;
  }

  /// Trozo del código escaneado que identifica el modelo, en caracteres.
  /// `start` es la posición del primer carácter (1 = el primero).
  Future<({int start, int length})> graiModelSlice() async => (
        start: await _intSetting('grai_model_start', 8),
        length: await _intSetting('grai_model_length', 4),
      );

  Future<void> setGraiModelSlice(int start, int length) async {
    for (final e in {
      'grai_model_start': start,
      'grai_model_length': length
    }.entries) {
      await _db.insert('settings', {'key': e.key, 'value': '${e.value}'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
