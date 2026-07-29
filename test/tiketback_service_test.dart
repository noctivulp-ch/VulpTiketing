import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vulp_tiketing/features/import_export/tiketback_service.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late String backupPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'orden_producto': 'precio',
      'acento_tinte': 'grisVerdoso',
    });
    tempDir = await Directory.systemTemp.createTemp('tiketback_test_');
    dbPath = '${tempDir.path}/vulp_tiketing.db';
    backupPath = '${tempDir.path}/respaldo.tiketback';
    await File(dbPath).writeAsBytes(utf8.encode('contenido-sqlite-de-prueba'));
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('exportar + restaurar recupera exactamente los mismos bytes de la base de datos', () async {
    final service = TiketbackService();

    await service.exportar(
      contrasenaExportacion: 'clave-correcta',
      rutaBaseDeDatos: dbPath,
      rutaDestino: backupPath,
    );

    // El archivo exportado no debe contener el contenido en texto plano.
    final crudo = await File(backupPath).readAsBytes();
    expect(utf8.decode(crudo, allowMalformed: true).contains('contenido-sqlite-de-prueba'), isFalse);

    // Simula un dispositivo nuevo: la "base de datos" original se borra.
    await File(dbPath).delete();

    await service.restaurar(
      contrasenaExportacion: 'clave-correcta',
      rutaBaseDeDatos: dbPath,
      rutaOrigen: backupPath,
    );

    final restaurado = await File(dbPath).readAsString();
    expect(restaurado, 'contenido-sqlite-de-prueba');

    // Las preferencias tambien deben haberse restaurado.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('orden_producto'), 'precio');
    expect(prefs.getString('acento_tinte'), 'grisVerdoso');
  });

  test('restaurar con la contraseña equivocada lanza SecretBoxAuthenticationError', () async {
    final service = TiketbackService();

    await service.exportar(
      contrasenaExportacion: 'clave-correcta',
      rutaBaseDeDatos: dbPath,
      rutaDestino: backupPath,
    );

    expect(
      () => service.restaurar(
        contrasenaExportacion: 'clave-incorrecta',
        rutaBaseDeDatos: dbPath,
        rutaOrigen: backupPath,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
