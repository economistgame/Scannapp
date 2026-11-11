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
      version: 3,
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
        await _createMasterTables(db);
        // Catálogo local: pedido -> proveedor (para autorrellenar)
        await db.execute('''
          CREATE TABLE order_suppliers(
            order_code TEXT PRIMARY KEY,
            supplier TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 -> v2: datos maestros propios (proveedores y productos).
          await _createMasterTables(db);
          await db.execute(
              'INSERT INTO products(name) SELECT DISTINCT name FROM box_models');
          await db.execute(
              'INSERT OR IGNORE INTO suppliers(name) SELECT DISTINCT supplier FROM order_suppliers');
          await db.execute(
              'INSERT OR IGNORE INTO suppliers(name) SELECT DISTINCT supplier FROM captures');
          await db.execute('DROP TABLE box_models');
        } else if (oldVersion < 3) {
          // v2 -> v3: el código del producto pasa a ser su EAN. Los códigos
          // antiguos (trozos de GRAI) que no son un EAN válido se descartan.
          await db.execute('''
            CREATE TABLE products_new(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              ean TEXT UNIQUE
            )''');
          await db.execute('''
            INSERT INTO products_new(id, name, ean)
            SELECT id, name,
              CASE WHEN code IS NOT NULL
                    AND length(code) IN (8, 12, 13, 14)
                    AND code NOT GLOB '*[^0-9]*'
                   THEN code ELSE NULL END
            FROM products''');
          await db.execute('DROP TABLE products');
          await db.execute('ALTER TABLE products_new RENAME TO products');
        }
      },
    );
    return AppDatabase._(db);
  }

  /// Datos maestros: lista de proveedores y de productos (modelos de caja).
  static Future<void> _createMasterTables(DatabaseExecutor db) async {
    // Nombre único sin distinguir mayúsculas.
    await db.execute(
        'CREATE TABLE suppliers(name TEXT PRIMARY KEY COLLATE NOCASE)');
    // Un producto puede tener un EAN (único) o ninguno (solo manual).
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        ean TEXT UNIQUE
      )''');
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

  // ---- Autorrelleno de proveedor -----------------------------------------

  /// Proveedor usado antes con ese pedido, si sigue existiendo en datos maestros.
  Future<String?> supplierForOrder(String order) async {
    final r = await _db.rawQuery(
      'SELECT s.name AS name FROM order_suppliers os '
      'JOIN suppliers s ON s.name = os.supplier COLLATE NOCASE '
      'WHERE os.order_code = ? LIMIT 1',
      [order],
    );
    return r.isEmpty ? null : r.first['name'] as String;
  }

  /// Último proveedor usado, si sigue existiendo en datos maestros.
  Future<String?> lastSupplier() async {
    final r = await _db.rawQuery(
      'SELECT s.name AS name FROM settings st '
      'JOIN suppliers s ON s.name = st.value COLLATE NOCASE '
      "WHERE st.key = 'last_supplier' LIMIT 1",
    );
    return r.isEmpty ? null : r.first['name'] as String;
  }

  // ---- Datos maestros: proveedores ---------------------------------------

  Future<List<String>> listSuppliers() async {
    final r = await _db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    return r.map((e) => e['name'] as String).toList();
  }

  /// Añade el proveedor si no existe (sin distinguir mayúsculas).
  Future<void> addSupplier(String name) => _db.insert(
        'suppliers',
        {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  /// Cambia el nombre. Las capturas ya guardadas conservan el nombre anterior.
  Future<void> renameSupplier(String oldName, String newName) => _db.update(
        'suppliers',
        {'name': newName.trim()},
        where: 'name = ?',
        whereArgs: [oldName],
      );

  Future<void> deleteSupplier(String name) =>
      _db.delete('suppliers', where: 'name = ?', whereArgs: [name]);

  // ---- Datos maestros: productos -----------------------------------------

  Future<List<Product>> listProducts() async {
    final r = await _db.query('products', orderBy: 'name COLLATE NOCASE');
    return r
        .map((e) => Product(
            id: e['id'] as int,
            name: e['name'] as String,
            ean: e['ean'] as String?))
        .toList();
  }

  /// Nombres de producto sin repetir (un modelo puede tener varios EAN).
  Future<List<String>> productNames() async {
    final r = await _db.rawQuery(
        'SELECT DISTINCT name FROM products ORDER BY name COLLATE NOCASE');
    return r.map((e) => e['name'] as String).toList();
  }

  Future<String?> productNameForEan(String ean) async {
    final r = await _db.query('products',
        where: 'ean = ?', whereArgs: [ean], limit: 1);
    return r.isEmpty ? null : r.first['name'] as String;
  }

  /// Crea (id == null) o actualiza un producto. Lanza excepción si el EAN
  /// ya pertenece a otro producto.
  Future<void> saveProduct({int? id, required String name, String? ean}) async {
    final values = {
      'name': name.trim(),
      'ean': (ean == null || ean.trim().isEmpty) ? null : ean.trim(),
    };
    if (id == null) {
      await _db.insert('products', values);
    } else {
      await _db.update('products', values, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteProduct(int id) =>
      _db.delete('products', where: 'id = ?', whereArgs: [id]);

  /// Asocia un EAN a un producto existente (por nombre). Si ese producto ya
  /// tiene otro EAN, se añade una entrada nueva con el mismo nombre para no
  /// perder el anterior.
  Future<void> linkEanToProduct(String ean, String name) async {
    await _db.transaction((txn) async {
      final taken = await txn.query('products',
          where: 'ean = ?', whereArgs: [ean], limit: 1);
      if (taken.isNotEmpty) return;
      final free = await txn.query('products',
          where: 'name = ? COLLATE NOCASE AND ean IS NULL',
          whereArgs: [name],
          limit: 1);
      if (free.isNotEmpty) {
        await txn.update('products', {'ean': ean},
            where: 'id = ?', whereArgs: [free.first['id']]);
      } else {
        await txn.insert('products', {'name': name, 'ean': ean});
      }
    });
  }

  /// Carga/actualiza los datos maestros descargados del servidor.
  /// [models] es EAN -> nombre del producto.
  Future<void> upsertCatalogs({
    Map<String, String> models = const {},
    Map<String, String> orderSuppliers = const {},
    List<String> suppliers = const [],
  }) async {
    await _db.transaction((txn) async {
      for (final name in suppliers) {
        await txn.insert('suppliers', {'name': name.trim()},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final e in models.entries) {
        final n = await txn.update('products', {'name': e.value},
            where: 'ean = ?', whereArgs: [e.key]);
        if (n == 0) {
          await txn.insert('products', {'name': e.value, 'ean': e.key});
        }
      }
      for (final e in orderSuppliers.entries) {
        await txn.insert('suppliers', {'name': e.value.trim()},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert(
            'order_suppliers', {'order_code': e.key, 'supplier': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
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
}
