// Recorre la app con un catálogo de demostración y guarda las capturas del
// README en docs/capturas/. Se lanza con tools/capturas/capturas.sh, que la
// corre aislada (HOME temporal, Xvfb): nunca toca la base de quien la ejecuta.
//
// El catálogo es inventado a propósito: ningún repo público lleva el menú ni
// las ventas de un negocio real.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';

const _token = 'vulp-dev-no-usar-en-produccion';

late FlutterDriver _driver;
late String _salida;

Future<Map<String, dynamic>> _cmd(String cmd, [Map<String, dynamic> args = const {}]) async {
  final r = await _driver.requestData(jsonEncode({'cmd': cmd, 'args': args, 'token': _token}));
  return jsonDecode(r) as Map<String, dynamic>;
}

Future<void> _tocar(String etiqueta) async {
  final r = await _cmd('ui_tocar', {'etiqueta': etiqueta});
  if (r['ok'] != true) {
    final hay = [for (final i in (r['interactuables'] as List? ?? const [])) i['etiqueta']];
    throw StateError('No se pudo tocar "$etiqueta": ${r['error']}. En pantalla: $hay');
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
}

Future<void> _capturar(String nombre) async {
  await Future<void>.delayed(const Duration(milliseconds: 700));
  File('$_salida/$nombre.png').writeAsBytesSync(await _driver.screenshot());
  stdout.writeln('captura: $nombre.png');
}

Future<void> _tema(String modo, String acento) async {
  await _tocar('Configuración');
  await _tocar('Tema');
  await _segmento(modo);
  await _tocar('Configuración');
  await _tocar('Acento');
  await _segmento(acento);
}

/// Cada segmento sale dos veces en la semántica (el botón y su rótulo), y no
/// siempre el primero es el que responde: se tocan los dos.
Future<void> _segmento(String etiqueta) async {
  for (final indice in [0, 1]) {
    await _cmd('ui_tocar', {'etiqueta': etiqueta, 'indice': indice});
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}

Map<String, dynamic> _demo() {
  final ahora = DateTime.now();
  final marca = ahora.toIso8601String();
  const categorias = {
    'cat-bebidas': 'Bebidas',
    'cat-desayunos': 'Desayunos',
    'cat-almuerzos': 'Almuerzos',
    'cat-reposteria': 'Repostería',
  };
  const productos = [
    ('Café negro', 'cat-bebidas', 800),
    ('Café con leche', 'cat-bebidas', 1100),
    ('Batido de fresa', 'cat-bebidas', 1600),
    ('Jugo de naranja', 'cat-bebidas', 1400),
    ('Té frío', 'cat-bebidas', 1000),
    ('Desayuno completo', 'cat-desayunos', 3200),
    ('Tostadas con huevo', 'cat-desayunos', 2400),
    ('Pinto con natilla', 'cat-desayunos', 2800),
    ('Casado de pollo', 'cat-almuerzos', 4200),
    ('Casado de res', 'cat-almuerzos', 4600),
    ('Arroz con pollo', 'cat-almuerzos', 3800),
    ('Sopa del día', 'cat-almuerzos', 3000),
    ('Empanada de queso', 'cat-reposteria', 900),
    ('Queque de vainilla', 'cat-reposteria', 1200),
    ('Galleta de avena', 'cat-reposteria', 600),
  ];
  final rng = Random(2026);
  final ventas = <Map<String, dynamic>>[];
  for (var i = 0; i < 260; i++) {
    final dia = ahora.subtract(Duration(days: rng.nextInt(28)));
    final momento = DateTime(dia.year, dia.month, dia.day, 7 + rng.nextInt(12), rng.nextInt(60));
    final lineas = [
      for (var l = 0; l < 1 + rng.nextInt(3); l++)
        () {
          final p = rng.nextInt(productos.length);
          return {
            'id': 'ld${i}_$l',
            'venta_id': 'vd$i',
            'producto_id': 'pd$p',
            'nombre_libre': null,
            'precio_aplicado': productos[p].$3,
            'cantidad': rng.nextInt(5) == 0 ? 2 : 1,
            'nota': null,
            'updated_at': momento.toIso8601String(),
          };
        }(),
    ];
    ventas.add({
      'id': 'vd$i',
      'fecha_hora': momento.toIso8601String(),
      'estado': 'activa',
      'metodo_pago': rng.nextInt(4) == 0 ? 'sinpe' : 'efectivo',
      'updated_at': momento.toIso8601String(),
      'lineas': lineas,
    });
  }
  return {
    'categorias': [
      for (final c in categorias.entries) {'id': c.key, 'nombre': c.value, 'updated_at': marca},
    ],
    'productos': [
      for (var i = 0; i < productos.length; i++)
        {
          'id': 'pd$i',
          'nombre': productos[i].$1,
          'categoria_id': productos[i].$2,
          'precio_base': productos[i].$3,
          'updated_at': marca,
        },
    ],
    'ventas': ventas,
  };
}

Future<void> main() async {
  _salida = Platform.environment['CAPTURAS_OUT']!;
  _driver = await FlutterDriver.connect();
  await Future<void>.delayed(const Duration(seconds: 3));

  final carga = await _cmd('cargar_base_pruebas', {'json': jsonEncode(_demo())});
  if (carga['ok'] == false) throw StateError('Carga de la demo: $carga');

  // Ventas de hoy por el mismo camino que la caja, para que Reportes no
  // arranque en cero.
  final precios = [for (final p in _demo()['productos'] as List) p['precio_base']];
  final rng = Random(7);
  for (var v = 0; v < 18; v++) {
    final p = rng.nextInt(precios.length);
    await _cmd('seed_venta', {
      'lineas': [
        {'productoId': 'pd$p', 'precio': precios[p], 'cantidad': 1 + rng.nextInt(2)},
      ],
    });
  }

  // La editorial del README: oscuro con oro (el metal cobrizo de la paleta),
  // claro con peltre, y Reportes en los dos para el corte diagonal.
  await _tema('Oscuro', 'Oro');
  await _tocar('Venta rápida');
  await _capturar('venta-oscuro-oro');
  await _tocar('Reportes');
  await _capturar('_reportes-oscuro');

  await _tema('Claro', 'Peltre');
  await _tocar('Venta rápida');
  await _capturar('venta-claro-peltre');
  await _tocar('Reportes');
  await _capturar('_reportes-claro');

  await _driver.close();
}
