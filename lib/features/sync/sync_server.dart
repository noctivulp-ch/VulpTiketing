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
///
/// `venta` y `linea_venta` resuelven contra el LIBRO ABIERTO, que está adjunto
/// ([decisión 0025](../../../docs/decisiones/0025-archivado-anual-rodante.md)).
/// Eso acota el volcado a un año por construcción en vez de a la vida entera
/// del negocio, y es la razón de que esta lista siga siendo la misma de antes.
///
/// `libro_ventas` NO está y no debe estarlo: describe los ARCHIVOS de este
/// dispositivo, con sus nombres y sus fechas de corte, que son suyos y de nadie
/// más. Propagarlo dejaría al otro aparato con filas apuntando a archivos que
/// no existen. Además no tiene `updated_at`, que `RowSyncEngine` exige.
const tablasSincronizables = ['categoria', 'producto', 'venta', 'linea_venta'];

/// Tablas que viven en el libro adjunto y por lo tanto pueden no existir: una
/// instalación sin ninguna venta todavía no tiene libro.
const _tablasDelLibro = {'venta', 'linea_venta'};

/// Versión del protocolo de sync. Subirla cuando cambie la FORMA del payload.
const versionProtocoloSync = 1;

/// Versión del esquema de datos que viaja dentro. Dos dispositivos en
/// versiones distintas no deben mezclar filas: en v2 las ventas vivían en la
/// base principal y en v3 en un libro, y aplicar unas sobre otras a ciegas
/// produce una contabilidad que no es la de ninguno de los dos.
const esquemaSync = 3;

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

    final tablas = <String, Object?>{};

    // Dentro de una transacción: cerrar un libro hace `DETACH DATABASE` sobre
    // ESTA misma conexión, y si cayera entre dos consultas la tabla
    // desaparecería a mitad del volcado. La transacción serializa las dos
    // cosas en la conexión.
    await _db.transaction((txn) async {
      final hayLibro = await _existeTablaDeVentas(txn);
      for (final tabla in tablasSincronizables) {
        // Sin libro abierto no existe `venta`. Antes eso lanzaba `no such
        // table`, el handler devolvía 500 y el cliente se comía la excepción
        // en silencio — con lo cual un dispositivo recién instalado tampoco
        // sincronizaba su CATÁLOGO. Un aparato sin ventas simplemente no tiene
        // ventas que ofrecer; no es un error.
        if (_tablasDelLibro.contains(tabla) && !hayLibro) {
          tablas[tabla] = const <Map<String, Object?>>[];
          continue;
        }
        tablas[tabla] = await txn.query(tabla);
      }
    });

    return Response.ok(
      jsonEncode({'version': versionProtocoloSync, 'esquema': esquemaSync, 'tablas': tablas}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Si `venta` es resoluble, en la base que sea.
  ///
  /// Se recorren los esquemas que `PRAGMA database_list` reporta en vez de
  /// consultar `libro.sqlite_master` directo: si el libro no está adjunto, ese
  /// nombre calificado lanza, y "no hay libro" es justo el caso que se quiere
  /// detectar. De paso funciona igual con las ventas en `main`, que es como
  /// están las bases de las pruebas de volumen.
  Future<bool> _existeTablaDeVentas(DatabaseExecutor db) async {
    final esquemas = (await db.rawQuery('PRAGMA database_list')).map((f) => f['name'] as String);
    for (final esquema in esquemas) {
      final r = await db.rawQuery(
        "SELECT COUNT(*) c FROM $esquema.sqlite_master WHERE type='table' AND name='venta'",
      );
      if (r.first['c'] == 1) return true;
    }
    return false;
  }
}
