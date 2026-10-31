import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../ml/matcher.dart';

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
      version: 1,
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
            model TEXT NOT NULL, vector BLOB NOT NULL, crop BLOB)''');
        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY, ts TEXT NOT NULL, total REAL NOT NULL, items_json TEXT NOT NULL)''');
        await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
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

  Future<void> deleteProduct(int id) async {
    await db.delete('products', where: 'id = ?', whereArgs: [id]); // its angles go too (ON DELETE CASCADE)
    _changed();
  }

  /// Number of taught angles per product id, for one embedder.
  Future<Map<int, int>> angleCounts(String model) async => {
    for (final r in await db.rawQuery(
      'SELECT product_id, COUNT(*) AS n FROM embeddings WHERE model = ? GROUP BY product_id',
      [model],
    ))
      r['product_id'] as int: r['n'] as int,
  };

  // ------------------------------------------------------------ embeddings (taught angles)

  /// Saves one taught angle: its fingerprint and the crop it came from.
  Future<void> addAngle(int productId, String model, Float32List vector, Uint8List? crop) async {
    await db.insert('embeddings', {
      'product_id': productId,
      'model': model,
      'vector': vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes),
      'crop': crop,
    });
    _changed();
  }

  /// Every taught angle for one embedder, with its product (what the Matcher searches).
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

  /// One product's taught angles (id + crop image) for the gallery where you remove bad ones.
  Future<List<({int id, Uint8List? crop})>> productAngles(int productId, String model) async => [
    for (final r in await db.query(
      'embeddings',
      columns: ['id', 'crop'],
      where: 'product_id = ? AND model = ?',
      whereArgs: [productId, model],
    ))
      (id: r['id'] as int, crop: r['crop'] as Uint8List?),
  ];

  /// Removes a taught angle (and the same crop's fingerprints for the other embedder).
  Future<void> deleteAngle(int id) async {
    await db.rawDelete(
      'DELETE FROM embeddings WHERE id = ? OR (crop IS NOT NULL AND crop = (SELECT crop FROM embeddings WHERE id = ?))',
      [id, id],
    );
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
