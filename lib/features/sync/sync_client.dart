import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../venta/libro_ventas.dart';
import 'device_discovery_service.dart';
import 'row_upserter.dart';
import 'sync_server.dart' show esquemaSync, tablasSincronizables, versionProtocoloSync;

/// Se recibió un payload que esta app no debe aplicar.
class SyncIncompatible implements Exception {
  SyncIncompatible(this.motivo);
  final String motivo;

  @override
  String toString() => 'SyncIncompatible: $motivo';
}

/// Consume `GET /sync/exportar` de un peer y aplica sus filas via
/// [RowUpserter] (decisión 0022). Un solo lado hace el pull; sincronizar
/// "de verdad" en ambas direcciones es simplemente que los dos
/// dispositivos hagan esto — uno con el otro, no requiere que el servidor
/// también reciba datos.
class SyncClient {
  SyncClient(this._db, {this.libros});

  final Database _db;

  /// Opcional: sin él, las ventas que lleguen se aplican igual pero no se
  /// actualiza el índice de libros. Las pruebas de volumen, que corren sobre
  /// una base sin libros, lo omiten.
  final LibroVentasService? libros;
  late final _upserter = RowUpserter(_db);

  Future<void> sincronizarCon(PeerVisible peer) async {
    final cliente = HttpClient();
    try {
      final peticion = await cliente.getUrl(
        Uri.http('${peer.direccion}:${peer.puerto}', '/sync/exportar'),
      );
      final respuesta = await peticion.close();
      if (respuesta.statusCode != 200) {
        throw HttpException('Respuesta ${respuesta.statusCode} de ${peer.deviceId}');
      }
      final cuerpo = await respuesta.transform(utf8.decoder).join();
      final sobre = jsonDecode(cuerpo) as Map<String, dynamic>;
      final tablas = _validar(sobre, peer);

      // Deja adjunto el libro que va a recibir las ventas remotas. Sin esto,
      // un dispositivo que todavía no vendió nada no tiene tabla `venta` donde
      // escribirlas.
      await libros?.prepararPara(_db, DateTime.now());

      for (final tabla in tablasSincronizables) {
        await _upserter.aplicar(tabla, _comoFilas(tablas[tabla]));
      }

      // Las ventas que entraron por acá no pasaron por `prepararPara`, así que
      // el libro no contó sus días. Recontar deja el índice describiendo lo que
      // el libro realmente tiene.
      await libros?.recontarDias(_db);
    } finally {
      cliente.close(force: true);
    }
  }

  /// Un peer en otra versión no es un peer con el que mezclar filas.
  ///
  /// Mezclar a ciegas datos de dos esquemas distintos no da un error visible:
  /// da una contabilidad que no es la de ninguno de los dos aparatos, y nadie
  /// se entera hasta que los números no cuadran.
  Map<String, dynamic> _validar(Map<String, dynamic> sobre, PeerVisible peer) {
    final version = sobre['version'];
    if (version != versionProtocoloSync) {
      throw SyncIncompatible(
        'protocolo $version de ${peer.deviceId}, esta app habla $versionProtocoloSync',
      );
    }
    final esquema = sobre['esquema'];
    if (esquema != esquemaSync) {
      throw SyncIncompatible(
        'esquema $esquema de ${peer.deviceId}, esta app usa $esquemaSync',
      );
    }
    return sobre['tablas'] as Map<String, dynamic>;
  }

  List<Map<String, Object?>> _comoFilas(dynamic lista) {
    return List<Map<String, Object?>>.from(
      (lista as List).map((fila) => Map<String, Object?>.from(fila as Map)),
    );
  }
}
