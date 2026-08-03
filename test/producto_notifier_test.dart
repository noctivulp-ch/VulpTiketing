import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'invalidar productoNotifierProvider varias veces no revienta con LateInitializationError',
    () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('''
      CREATE TABLE producto (
        id TEXT PRIMARY KEY, nombre TEXT NOT NULL, imagen TEXT, categoria_id TEXT,
        precio_base REAL NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
      );
    ''');

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);

      await container.read(productoNotifierProvider.future);
      container.invalidate(productoNotifierProvider);
      await container.read(productoNotifierProvider.future);
      container.invalidate(productoNotifierProvider);
      await expectLater(container.read(productoNotifierProvider.future), completes);
    },
  );
}
