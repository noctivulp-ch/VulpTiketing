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
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:vulp_tiketing/app.dart';
import 'package:vulp_tiketing/core/crypto/cifrado_nativo.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/import_export/tiketback_service.dart';
import 'package:vulp_tiketing/features/import_export/tiketdata_service.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';
import 'package:vulp_tiketing/features/venta/venta_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';

import 'diagnostico.dart';

const _uuid = Uuid();

void main() {
  // Container explicito (no el implicito de ProviderScope) para que el
  // DataHandler pueda leer/invalidar providers desde fuera del arbol de
  // widgets — UncontrolledProviderScope lo comparte con la app real sin
  // crear un segundo container.
  final container = ProviderContainer();

  // `enableTextEntryEmulation: false` NO es un detalle: por defecto
  // `enableFlutterDriverExtension` llama a `TestTextInput.register()`, que
  // REEMPLAZA la entrada de texto del sistema por un mock. Con el default,
  // el teclado fisico deja de escribir en la app por completo — los eventos
  // de tecla siguen llegando (Tab mueve el foco, el cursor parpadea) pero los
  // caracteres se van al canal mockeado y se descartan. Es decir: la app
  // instrumentada quedaba imposible de usar a mano, que es justo lo contrario
  // del requisito ("el MCP debe permitir el uso completo de la app").
  //
  // Con esto el teclado humano manda siempre. El bridge enciende la emulacion
  // solo durante el instante en que necesita escribir y la vuelve a apagar
  // (ver `POST /enter_text` en bridge.dart).
  enableFlutterDriverExtension(
    handler: (mensaje) => _manejarComandoDirecto(container, mensaje),
    enableTextEntryEmulation: false,
  );

  // El diagnostico va DESPUES de `enableFlutterDriverExtension` y antes de
  // `runApp`.
  //
  // No puede ir antes: `enableFlutterDriverExtension` instala su PROPIO binding
  // (`_DriverBinding`), y un binding solo puede crearse una vez. Cualquier cosa
  // que toque `SchedulerBinding.instance` o llame a `ensureInitialized()` antes
  // se lo impide, y entonces la extension no se registra: el harness conecta al
  // VM service y espera para siempre una extension que nunca aparece. Se
  // reconoce por "Flutter Driver extension is taking a long time to become
  // available" — que dice, con razon, que debe ser la PRIMERA llamada de main().
  //
  // Vive en test_driver/, asi que no existe en produccion.
  DiagnosticoDev.instalar();

  runApp(UncontrolledProviderScope(container: container, child: const VulpTiketingApp()));
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
      await TiketdataService(db).importarCatalogo(rutaOrigen: args['path'] as String, modo: modo);
      container.invalidate(productoNotifierProvider);
      container.invalidate(categoriaNotifierProvider);
      return null;

    case 'export_tiketdata':
      final db = await container.read(databaseProvider.future);
      await TiketdataService(db).exportarCatalogo(args['path'] as String);
      return null;

    case 'export_tiketback':
      final db = await container.read(databaseProvider.future);
      final libros = await container.read(libroVentasServiceProvider.future);
      await TiketbackService().exportar(
        contrasenaExportacion: args['password'] as String,
        directorioDatos: p.dirname(await AppDatabase.ruta()),
        nombreBasePrincipal: p.basename(await AppDatabase.ruta()),
        archivosDeLibro: (await libros.todos(db)).map((l) => l.archivo).toList(),
        rutaDestino: args['path'] as String,
      );
      return null;

    case 'restore_tiketback':
      await TiketbackService().restaurar(
        contrasenaExportacion: args['password'] as String,
        directorioDatos: p.dirname(await AppDatabase.ruta()),
        nombreBasePrincipal: p.basename(await AppDatabase.ruta()),
        rutaOrigen: args['path'] as String,
        alcance: AlcanceRestauracion.values.byName((args['alcance'] as String?) ?? 'todo'),
      );
      container.invalidate(databaseProvider);
      return null;

    case 'seed_categoria':
      final nombre = args['nombre'] as String;
      final id = _uuid.v4();
      await container
          .read(categoriaNotifierProvider.notifier)
          .crear(Categoria(id: id, nombre: nombre, updatedAt: DateTime.now()));
      return {'id': id};

    case 'seed_producto':
      final id = _uuid.v4();
      await container
          .read(productoNotifierProvider.notifier)
          .crear(
            Producto(
              id: id,
              nombre: args['nombre'] as String,
              precioBase: (args['precio'] as num).toDouble(),
              categoriaId: args['categoriaId'] as String?,
              updatedAt: DateTime.now(),
            ),
          );
      return {'id': id};

    case 'cargar_base_pruebas':
      // La base de pruebas ÚNICA: el menú real más 500 ventas repartidas por
      // semanas, días y turnos (`seed/base-de-pruebas.json`, generado por
      // `scripts/generar_datos_prueba.dart`). La manda
      // `scripts/cargar-datos-prueba.sh`.
      //
      // El CONTENIDO viaja en el comando, no una ruta: desde Android 10 la app
      // no puede leer `/sdcard`, así que un `adb push` no le sirve de nada. Acá
      // se escribe en el directorio propio de la app, que es el único al que sí
      // llega.
      //
      // Las ventas se insertan por SQL y no por `VentaEnCursoNotifier` como
      // `seed_venta`: ese camino fecha todo AHORA, y lo que importa acá es
      // justamente que estén repartidas en el tiempo. El catálogo sí entra por
      // el servicio de importación real.
      final db = await container.read(databaseProvider.future);
      final crudo = args['json'] as String;
      final datos = jsonDecode(crudo) as Map<String, dynamic>;

      final temporal = File(p.join(p.dirname(await AppDatabase.ruta()), 'base-de-pruebas.json'));
      await temporal.writeAsString(crudo);
      await TiketdataService(
        db,
      ).importarCatalogo(rutaOrigen: temporal.path, modo: ModoImportacion.reemplazar);
      await temporal.delete();

      final ventas = (datos['ventas'] as List).cast<Map<String, dynamic>>();
      await db.transaction((txn) async {
        await txn.delete('linea_venta');
        await txn.delete('venta');
        for (final venta in ventas) {
          await txn.insert('venta', {
            'id': venta['id'],
            'fecha_hora': venta['fecha_hora'],
            'estado': venta['estado'],
            'updated_at': venta['updated_at'],
          });
          for (final linea in (venta['lineas'] as List).cast<Map<String, dynamic>>()) {
            await txn.insert('linea_venta', linea);
          }
        }
      });

      container.invalidate(productoNotifierProvider);
      container.invalidate(categoriaNotifierProvider);
      container.invalidate(ventaNotifierProvider);
      return {'productos': (datos['productos'] as List).length, 'ventas': ventas.length};

    case 'seed_venta':
      // Siembra una venta real pasando por VentaEnCursoNotifier, el mismo
      // camino que la UI — nunca por SQLite a mano, para no inventar un
      // segundo camino de logica de negocio (decision 0009).
      //
      // Existe porque juzgar la COMPOSICION de las pantallas con la base vacia
      // lleva a rediseñar zonas que en uso real se llenan: el carrito, los
      // rankings de Reportes, el panel de Configuracion. Sin ventas, Reportes
      // se evalua siempre en su estado vacio.
      final carrito = container.read(ventaEnCursoNotifierProvider.notifier);
      final lineas = (args['lineas'] as List).cast<Map>();
      for (final linea in lineas) {
        carrito.agregarLineaDeCatalogo(
          productoId: linea['productoId'] as String,
          precioAplicado: (linea['precio'] as num).toDouble(),
          cantidad: (linea['cantidad'] as num?)?.toInt() ?? 1,
        );
      }
      await carrito.guardar();
      container.invalidate(ventaNotifierProvider);
      return {'lineas': lineas.length};

    case 'listar_productos':
      final productos = await container.read(productoNotifierProvider.future);
      return productos
          .map((p) => {'id': p.id, 'nombre': p.nombre, 'precio': p.precioBase, 'activo': p.activo})
          .toList();

    case 'listar_categorias':
      final categorias = await container.read(categoriaNotifierProvider.future);
      return categorias.map((c) => {'id': c.id, 'nombre': c.nombre}).toList();

    case 'orientacion':
      // Rotar la app desde adentro, sin depender de la rotacion del sistema.
      //
      // `adb shell settings put system user_rotation` no sirve: en EMUI el
      // ajuste no pega, y ademas con la rotacion automatica apagada el aparato
      // se queda en vertical pase lo que pase. Asi la orientacion es
      // DETERMINISTA, que es lo que hace falta para revisar un layout.
      final modo = args['modo'] as String? ?? 'libre';
      await SystemChrome.setPreferredOrientations(switch (modo) {
        'vertical' => [DeviceOrientation.portraitUp],
        'horizontal' => [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        _ => DeviceOrientation.values,
      });
      return {'modo': modo};

    case 'diagnostico':
      // Errores acumulados y frames fuera de presupuesto desde el arranque o
      // desde el ultimo `diagnostico_limpiar`.
      return DiagnosticoDev.resumen(maximo: (args['maximo'] as num?)?.toInt() ?? 10);

    case 'diagnostico_limpiar':
      // Se limpia ANTES de una interaccion para que lo que aparezca despues sea
      // atribuible a ella y no al arranque.
      DiagnosticoDev.limpiar();
      return null;

    case 'diagnostico_cifrado':
      // Mide AES-GCM EN EL DISPOSITIVO. Es la unica forma de saber si
      // `cryptography_flutter` esta usando el cifrado del sistema: en Linux no
      // hay implementacion nativa y cae a Dart puro, asi que el numero de la
      // laptop no dice nada sobre la tablet del negocio.
      //
      // Referencia medida en Dart puro (laptop): 10,7 MB/s.
      final mb = (args['mb'] as num?)?.toInt() ?? 32;
      final datos = Uint8List(mb * 1024 * 1024);
      final nonce = List<int>.generate(12, (i) => i);

      // Se miden LAS DOS implementaciones en el MISMO aparato. Comparar contra
      // el numero de la laptop no dice nada: son maquinas distintas.
      Future<int> medir(Cipher cifrador) async {
        final clave = await cifrador.newSecretKey();
        // Calentamiento: la primera llamada paga el arranque del canal a la
        // plataforma, y mediria eso en vez del cifrado.
        await cifrador.encrypt(Uint8List(1024 * 1024), secretKey: clave, nonce: nonce);
        final reloj = Stopwatch()..start();
        await cifrador.encrypt(datos, secretKey: clave, nonce: nonce);
        return (reloj..stop()).elapsedMilliseconds;
      }

      String velocidad(int ms) => (mb / (ms / 1000)).toStringAsFixed(1);

      final msActual = await medir(AesGcm.with256bits());
      final msDart = await medir(DartAesGcm.with256bits());

      return {
        'nativo': cifradoNativoDisponible,
        'implementacion': Cryptography.instance.runtimeType.toString(),
        'mb': mb,
        'actual_ms': msActual,
        'actual_mbps': velocidad(msActual),
        'dartPuro_ms': msDart,
        'dartPuro_mbps': velocidad(msDart),
      };

    default:
      throw ArgumentError('comando directo desconocido: $cmd');
  }
}
