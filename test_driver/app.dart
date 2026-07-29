// Entrypoint SOLO de desarrollo para el harness del MCP
// (scripts/mcp-driver/). NUNCA se usa en produccion — lib/main.dart es el
// entrypoint real, este archivo vive fuera de lib/ a proposito para que no
// pueda colarse en un build de release por accidente.
//
// Corre la app real (mismo VulpTiketingApp) con dos cosas de mas:
// 1. `enableFlutterDriverExtension` — permite que un proceso externo
//    (test_driver/bridge.dart) controle la app via el protocolo de
//    flutter_driver: tocar botones por texto/tooltip/key, leer texto,
//    esperar a que algo aparezca/desaparezca.
// 2. Un `DataHandler` con comandos "directos" que saltan la UI por
//    completo para lo que un test de UI no puede tocar: selectores de
//    archivo nativos (file_picker) que viven fuera del arbol de widgets de
//    Flutter. Cada comando directo llama al mismo metodo de Notifier/
//    Service que llamaria la UI real — nunca toca SQLite a mano, para no
//    inventar un segundo camino de logica de negocio (decision 0009).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:vulp_tiketing/app.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/import_export/tiketback_service.dart';
import 'package:vulp_tiketing/features/import_export/tiketdata_service.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';

const _uuid = Uuid();

void main() {
  // Container explicito (no el implicito de ProviderScope) para que el
  // DataHandler pueda leer/invalidar providers desde fuera del arbol de
  // widgets — UncontrolledProviderScope lo comparte con la app real sin
  // crear un segundo container.
  final container = ProviderContainer();

  enableFlutterDriverExtension(
    handler: (mensaje) => _manejarComandoDirecto(container, mensaje),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const VulpTiketingApp(),
    ),
  );
}

Future<String> _manejarComandoDirecto(ProviderContainer container, String? mensaje) async {
  try {
    final peticion = jsonDecode(mensaje ?? '{}') as Map<String, dynamic>;
    final cmd = peticion['cmd'] as String? ?? '';
    final args = (peticion['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    final resultado = await _ejecutar(container, cmd, args);
    return jsonEncode({'ok': true, 'resultado': resultado});
  } catch (e) {
    return jsonEncode({'ok': false, 'error': e.toString()});
  }
}

Future<dynamic> _ejecutar(
  ProviderContainer container,
  String cmd,
  Map<String, dynamic> args,
) async {
  switch (cmd) {
    case 'import_tiketdata':
      final db = await container.read(databaseProvider.future);
      final modo = args['modo'] == 'reemplazar'
          ? ModoImportacion.reemplazar
          : ModoImportacion.fusionar;
      await TiketdataService(db).importarCatalogo(
        rutaOrigen: args['path'] as String,
        modo: modo,
      );
      container.invalidate(productoNotifierProvider);
      container.invalidate(categoriaNotifierProvider);
      return null;

    case 'export_tiketdata':
      final db = await container.read(databaseProvider.future);
      await TiketdataService(db).exportarCatalogo(args['path'] as String);
      return null;

    case 'export_tiketback':
      await TiketbackService().exportar(
        contrasenaExportacion: args['password'] as String,
        rutaBaseDeDatos: await AppDatabase.ruta(),
        rutaDestino: args['path'] as String,
      );
      return null;

    case 'restore_tiketback':
      await TiketbackService().restaurar(
        contrasenaExportacion: args['password'] as String,
        rutaBaseDeDatos: await AppDatabase.ruta(),
        rutaOrigen: args['path'] as String,
      );
      container.invalidate(databaseProvider);
      return null;

    case 'seed_categoria':
      final nombre = args['nombre'] as String;
      final id = _uuid.v4();
      await container.read(categoriaNotifierProvider.notifier).crear(
            Categoria(id: id, nombre: nombre, updatedAt: DateTime.now()),
          );
      return {'id': id};

    case 'seed_producto':
      final id = _uuid.v4();
      await container.read(productoNotifierProvider.notifier).crear(
            Producto(
              id: id,
              nombre: args['nombre'] as String,
              precioBase: (args['precio'] as num).toDouble(),
              categoriaId: args['categoriaId'] as String?,
              updatedAt: DateTime.now(),
            ),
          );
      return {'id': id};

    case 'listar_productos':
      final productos = await container.read(productoNotifierProvider.future);
      return productos
          .map((p) => {
                'id': p.id,
                'nombre': p.nombre,
                'precio': p.precioBase,
                'activo': p.activo,
              })
          .toList();

    case 'listar_categorias':
      final categorias = await container.read(categoriaNotifierProvider.future);
      return categorias.map((c) => {'id': c.id, 'nombre': c.nombre}).toList();

    default:
      throw ArgumentError('comando directo desconocido: $cmd');
  }
}
