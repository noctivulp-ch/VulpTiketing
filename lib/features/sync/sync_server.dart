import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite/sqflite.dart';

/// Tablas sincronizables — incluye Venta/LineaVenta (a diferencia de
/// `.tiketdata`, que solo comparte catálogo). Se manda todo el contenido de
/// cada tabla en cada sync, sin filtrar por fecha: para el volumen de una
/// soda pequeña esto es simple y suficientemente rápido en LAN — no hay
/// necesidad real de una consulta incremental por "updated_at desde X"
/// todavía (se puede agregar después sin romper el contrato del endpoint).
const tablasSincronizables = ['categoria', 'producto', 'venta', 'linea_venta'];

/// Servidor HTTP embebido para sync entre dispositivos (decisión 0022).
/// Expone `GET /sync/exportar` con el contenido completo de las tablas
/// sincronizables, incluyendo filas con `deleted_at` (a diferencia de
/// `.tiketdata`) — la sync real necesita propagar tombstones (0005).
///
/// Puro Dart vía `shelf` — sin código nativo por plataforma. Se enlaza a
/// un puerto dinámico (el SO elige uno libre), nunca uno fijo — ver
/// decisión 0022 y `DeviceDiscoveryService.anunciar`.
///
/// Sin autenticación a propósito: coherente con el modelo de amenaza ya
/// establecido (0002) — la red local se asume de dispositivos de
/// confianza del mismo negocio, el objetivo es evitar terceros, no
/// defender contra un adversario dentro de la misma LAN.
class SyncServer {
  SyncServer(this._db);

  final Database _db;
  HttpServer? _servidor;

  int? get puerto => _servidor?.port;

  /// Devuelve el puerto real asignado por el sistema operativo.
  Future<int> iniciar() async {
    final handler = const Pipeline().addHandler(_manejarPeticion);
    _servidor = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    return _servidor!.port;
  }

  Future<void> detener() async {
    await _servidor?.close(force: true);
    _servidor = null;
  }

  Future<Response> _manejarPeticion(Request request) async {
    if (request.method != 'GET' || request.url.path != 'sync/exportar') {
      return Response.notFound('not found');
    }

    final datos = <String, Object?>{};
    for (final tabla in tablasSincronizables) {
      datos[tabla] = await _db.query(tabla);
    }
    return Response.ok(
      jsonEncode(datos),
      headers: {'content-type': 'application/json'},
    );
  }
}
