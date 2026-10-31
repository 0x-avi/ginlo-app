import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../ml/matcher.dart';
import 'sales.dart';

/// A product in the shop's catalog.
class Product {
  final int? id;
  final String name;
  final double price;
  final int stock;

  /// Pack sizes of one design share a family (e.g. "Lays Classic" for the Rs.10/20/50 packs).
  final String? family;

  const Product({this.id, required this.name, required this.price, this.stock = 0, this.family});

  factory Product.fromRow(Map<String, Object?> r) => Product(
    id: r['id'] as int,
    name: r['name'] as String,
    price: (r['price'] as num).toDouble(),
    stock: r['stock'] as int,
    family: r['family'] as String?,
  );
}

/// The on-phone database. One file (ginlo.db) in the app's private storage.
///
/// Tables (same as the Python prototype):
///   products   - what the shop sells
///   embeddings - one fingerprint (+ its crop image) per taught angle of a product
///   sales      - every paid bill
///   settings   - UPI ID, shop name, ...
class AppDb {
  AppDb._(this.db);
  final Database db;

  static AppDb? _instance;

  /// Bumped after every write, so screens showing catalog data know to reload.
  static final changes = ValueNotifier<int>(0);
  void _changed() => changes.value++;

  /// Opens the database once and reuses it (creating the tables on first launch).
  static Future<AppDb> open() async {
    if (_instance != null) return _instance!;
    final path = p.join(await getDatabasesPath(), 'ginlo.db');
    final db = await openDatabase(
      path,
      version: 3, // 2: sales.payment  3: embeddings.capture + variant
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, price REAL NOT NULL,
            stock INTEGER NOT NULL DEFAULT 0, family TEXT)''');
        await db.execute('''
          CREATE TABLE embeddings(
            id INTEGER PRIMARY KEY,
            product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            model TEXT NOT NULL, vector BLOB NOT NULL, crop BLOB,
            capture TEXT, variant TEXT)''');
        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY, ts TEXT NOT NULL, total REAL NOT NULL, items_json TEXT NOT NULL,
            payment TEXT NOT NULL DEFAULT 'UPI')''');
        await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
      // Databases made by an older version of the app get the new columns added in place.
      onUpgrade: (db, from, to) async {
        if (from < 2) await db.execute("ALTER TABLE sales ADD COLUMN payment TEXT NOT NULL DEFAULT 'UPI'");
        if (from < 3) {
          // Group old rows into captures by their shared crop picture; mark them 'legacy' (their
          // fingerprints may come from the small stored picture, so re-teaching is better).
          await db.execute('ALTER TABLE embeddings ADD COLUMN capture TEXT');
          await db.execute('ALTER TABLE embeddings ADD COLUMN variant TEXT');
          await db.execute('''
            UPDATE embeddings SET variant = 'legacy', capture = 'old-' || (
              SELECT MIN(e2.id) FROM embeddings e2
              WHERE e2.product_id = embeddings.product_id AND e2.crop IS embeddings.crop)''');
        }
      },
    );
    return _instance = AppDb._(db);
  }

  // ------------------------------------------------------------ products

  Future<List<Product>> products() async => (await db.query('products', orderBy: 'name')).map(Product.fromRow).toList();

  /// Adds a product, or updates its price (and stock, if given) when the name exists.
  Future<int> upsertProduct(String name, double price, {int? stock}) async {
    name = name.trim();
    await db.rawInsert(
      'INSERT INTO products(name, price, stock) VALUES (?, ?, ?) '
      'ON CONFLICT(name) DO UPDATE SET price = excluded.price',
      [name, price, stock ?? 0],
    );
    if (stock != null) await db.update('products', {'stock': stock}, where: 'name = ?', whereArgs: [name]);
    final row = await db.query('products', columns: ['id'], where: 'name = ?', whereArgs: [name]);
    _changed();
    return row.first['id'] as int;
  }

  /// Changes one product's price, stock and/or name (Modify tab).
  Future<void> updateProduct(int id, {double? price, int? stock, String? name}) async {
    await db.update(
      'products',
      {'price': ?price, if (stock != null) 'stock': stock < 0 ? 0 : stock, if (name != null) 'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<void> deleteProduct(int id) async {
    await db.delete('products', where: 'id = ?', whereArgs: [id]); // its angles go too (ON DELETE CASCADE)
    _changed();
  }

  /// Number of taught angles (captures) per product id, for one embedder.
  Future<Map<int, int>> angleCounts(String model) async => {
    for (final r in await db.rawQuery(
      'SELECT product_id, COUNT(DISTINCT capture) AS n FROM embeddings WHERE model = ? GROUP BY product_id',
      [model],
    ))
      r['product_id'] as int: r['n'] as int,
  };

  /// Products whose angles are all 'legacy' (taught before captures kept their full-quality
  /// fingerprint): re-teaching them gives better recognition.
  Future<Set<int>> productsNeedingReteach(String model) async => {
    for (final r in await db.rawQuery(
      "SELECT product_id FROM embeddings WHERE model = ? GROUP BY product_id "
      "HAVING SUM(CASE WHEN variant IS NULL OR variant != 'legacy' THEN 1 ELSE 0 END) = 0",
      [model],
    ))
      r['product_id'] as int,
  };

  // ------------------------------------------------------------ embeddings (taught angles)
  //
  // One Capture tap in Learn = one "capture": its fingerprints in every teach variant (one row each,
  // sharing a `capture` id) and its crop picture, stored once on the first row.

  /// Saves one capture: [vectors][i] is the fingerprint for teach variant [variants][i].
  Future<void> addCapture(
    int productId,
    String model,
    List<Float32List> vectors,
    List<String> variants,
    Uint8List crop,
  ) async {
    final capture = '${DateTime.now().microsecondsSinceEpoch}-$productId';
    await db.transaction((tx) async {
      for (var i = 0; i < vectors.length; i++) {
        await tx.insert('embeddings', {
          'product_id': productId,
          'model': model,
          'vector': vectors[i].buffer.asUint8List(vectors[i].offsetInBytes, vectors[i].lengthInBytes),
          'crop': i == 0 ? crop : null,
          'capture': capture,
          'variant': variants[i],
        });
      }
    });
    _changed();
  }

  /// Every taught fingerprint for one embedder, with its product (what the Matcher searches).
  Future<List<Angle>> angles(String model) async {
    final rows = await db.rawQuery(
      'SELECT e.id, e.product_id, e.vector, p.name, p.price FROM embeddings e '
      'JOIN products p ON p.id = e.product_id WHERE e.model = ?',
      [model],
    );
    return [
      for (final r in rows)
        Angle(
          r['id'] as int,
          r['product_id'] as int,
          r['name'] as String,
          (r['price'] as num).toDouble(),
          // copy into a fresh buffer: a Float32List view needs 4-byte alignment
          Uint8List.fromList(r['vector'] as Uint8List).buffer.asFloat32List(),
        ),
    ];
  }

  /// One row per capture (id + crop picture) for the gallery where you remove bad ones.
  Future<List<({int id, Uint8List? crop})>> productAngles(int productId, String model) async => [
    for (final r in await db.rawQuery(
      'SELECT MIN(id) AS id, MAX(crop) AS crop FROM embeddings WHERE product_id = ? AND model = ? '
      'GROUP BY capture ORDER BY id',
      [productId, model],
    ))
      (id: r['id'] as int, crop: r['crop'] as Uint8List?),
  ];

  /// The first taught picture of a product (by name), to show as its photo. Null if none.
  Future<Uint8List?> productPhoto(String name, String model) async {
    final r = await db.rawQuery(
      'SELECT e.crop FROM embeddings e JOIN products p ON p.id = e.product_id '
      'WHERE p.name = ? AND e.model = ? AND e.crop IS NOT NULL ORDER BY e.id LIMIT 1',
      [name, model],
    );
    return r.isEmpty ? null : r.first['crop'] as Uint8List;
  }

  /// Removes a taught angle: every fingerprint of the capture that row belongs to.
  Future<void> deleteAngle(int id) async {
    await db.rawDelete('DELETE FROM embeddings WHERE capture = (SELECT capture FROM embeddings WHERE id = ?)', [id]);
    _changed();
  }

  /// Captures with fewer than [variants] fingerprints for this embedder (taught before every
  /// capture got all teach variants), with their crop picture.
  Future<List<({int productId, String capture, Uint8List crop})>> anglesNeedingVariants(
    String model,
    int variants,
  ) async => [
    for (final r in await db.rawQuery(
      'SELECT product_id, capture, MAX(crop) AS crop FROM embeddings WHERE model = ? '
      'GROUP BY capture HAVING COUNT(*) < ? AND MAX(crop) IS NOT NULL',
      [model, variants],
    ))
      (productId: r['product_id'] as int, capture: r['capture'] as String, crop: r['crop'] as Uint8List),
  ];

  /// Adds fingerprints to an existing capture. Never deletes: the capture's original fingerprint
  /// (made from the full-quality camera frame) is better than any re-made from its stored picture.
  Future<void> addVariants(
    int productId,
    String model,
    String capture,
    List<Float32List> vectors,
    String variant,
  ) async {
    await db.transaction((tx) async {
      for (final v in vectors) {
        await tx.insert('embeddings', {
          'product_id': productId,
          'model': model,
          'vector': v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes),
          'capture': capture,
          'variant': variant,
        });
      }
    });
    _changed();
  }

  // ------------------------------------------------------------ sales

  /// Saves a paid bill and lowers each product's stock by what was sold.
  Future<int> recordSale(List<BillLine> lines, double total, String payment) async {
    final id = await db.transaction((tx) async {
      final id = await tx.insert('sales', {
        'ts': DateTime.now().toIso8601String(),
        'total': total,
        'items_json': Sale.linesToJson(lines),
        'payment': payment,
      });
      for (final l in lines.where((l) => l.productId != null)) {
        await tx.rawUpdate('UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?', [l.qty, l.productId]);
      }
      return id;
    });
    _changed();
    return id;
  }

  /// Paid bills with from <= time < to.
  Future<List<Sale>> sales(DateTime from, DateTime to) async => [
    for (final r in await db.query(
      'sales',
      where: 'ts >= ? AND ts < ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'ts',
    ))
      Sale(
        r['id'] as int,
        DateTime.parse(r['ts'] as String),
        (r['total'] as num).toDouble(),
        r['payment'] as String,
        Sale.linesFromJson(r['items_json'] as String),
      ),
  ];

  /// Saves bills with their own timestamps, without touching stock (used for demo data).
  Future<void> insertSales(List<Sale> sales) async {
    await db.transaction((tx) async {
      for (final x in sales) {
        await tx.insert('sales', {
          'ts': x.time.toIso8601String(),
          'total': x.total,
          'items_json': Sale.linesToJson(x.lines),
          'payment': x.payment,
        });
      }
    });
    _changed();
  }

  // ------------------------------------------------------------ catalog export / import
  //
  // The dev and prod apps are separate installs with separate databases. Export writes the
  // catalog (products + taught fingerprints) to a file; import merges such a file into this app.

  /// Folder both apps can be given files in (`Android/data/<app>/files` on the phone storage).
  static Future<String> exchangeDir() async =>
      (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory()).path;

  static const exchangeFile = 'ginlo_catalog.db';

  /// Writes a copy of the whole database (VACUUM INTO = SQLite's "save a compact copy").
  Future<String> exportCatalog() async {
    final path = p.join(await exchangeDir(), exchangeFile);
    final f = File(path);
    if (await f.exists()) await f.delete();
    await db.execute('VACUUM INTO ?', [path]);
    return path;
  }

  /// Merges products + fingerprints from an exported file. Products already here (same name) keep
  /// their price/stock; captures already imported are skipped, so importing twice is harmless.
  Future<({int products, int captures})> importCatalog() async {
    final path = p.join(await exchangeDir(), exchangeFile);
    if (!await File(path).exists()) throw StateError('No $exchangeFile in ${await exchangeDir()}');
    final before = await _counts();
    await db.execute('ATTACH DATABASE ? AS src', [path]);
    try {
      await db.execute(
        'INSERT OR IGNORE INTO products(name, price, stock, family) SELECT name, price, stock, family FROM src.products',
      );
      await db.execute('''
        INSERT INTO embeddings(product_id, model, vector, crop, capture, variant)
        SELECT p.id, e.model, e.vector, e.crop, e.capture, e.variant
        FROM src.embeddings e
        JOIN src.products sp ON sp.id = e.product_id
        JOIN products p ON p.name = sp.name
        WHERE e.capture IS NULL OR e.capture NOT IN (SELECT capture FROM embeddings WHERE capture IS NOT NULL)''');
    } finally {
      await db.execute('DETACH DATABASE src');
    }
    final after = await _counts();
    _changed();
    return (products: after.products - before.products, captures: after.captures - before.captures);
  }

  Future<({int products, int captures})> _counts() async {
    final r = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM products) AS p, (SELECT COUNT(DISTINCT capture) FROM embeddings) AS c',
    );
    return (products: r.first['p'] as int, captures: r.first['c'] as int);
  }

  // ------------------------------------------------------------ shop (name + UPI ID for the QR)

  Future<({String name, String upiId})> shop() async =>
      (name: await setting('shop_name') ?? 'My Store', upiId: await setting('upi_id') ?? '');

  Future<void> setShop(String name, String upiId) async {
    await setSetting('shop_name', name.trim());
    await setSetting('upi_id', upiId.trim());
    _changed();
  }

  // ------------------------------------------------------------ settings

  Future<String?> setting(String key) async {
    final row = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return row.isEmpty ? null : row.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) =>
      db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}
