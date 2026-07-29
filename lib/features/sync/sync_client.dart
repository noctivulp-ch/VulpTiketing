import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'device_discovery_service.dart';
import 'row_upserter.dart';
import 'sync_server.dart' show tablasSincronizables;

/// Consume `GET /sync/exportar` de un peer y aplica sus filas via
/// [RowUpserter] (decisión 0022). Un solo lado hace el pull; sincronizar
/// "de verdad" en ambas direcciones es simplemente que los dos
/// dispositivos hagan esto — uno con el otro, no requiere que el servidor
/// también reciba datos.
class SyncClient {
  SyncClient(this._db);

  final Database _db;
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
      final datos = jsonDecode(cuerpo) as Map<String, dynamic>;

      for (final tabla in tablasSincronizables) {
        await _upserter.aplicar(tabla, _comoFilas(datos[tabla]));
      }
    } finally {
      cliente.close(force: true);
    }
  }

  List<Map<String, Object?>> _comoFilas(dynamic lista) {
    return List<Map<String, Object?>>.from(
      (lista as List).map((fila) => Map<String, Object?>.from(fila as Map)),
    );
  }
}
