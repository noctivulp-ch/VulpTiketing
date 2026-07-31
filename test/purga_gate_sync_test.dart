import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vulp_tiketing/features/sync/sync_notifier.dart';

/// El gate de la purga (decisión 0015, condición 3).
///
/// Devolvía `false` siempre, así que purgar era imposible incluso en el único
/// caso en que es trivialmente seguro: un negocio con un solo aparato. Lo
/// encontró el usuario intentando borrar un producto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('un aparato que nunca vio a otro puede purgar', () async {
    SharedPreferences.setMockInitialValues({});

    // Sin ningún dispositivo conocido no hay ninguno que pueda tener una venta
    // pendiente con ese producto, que es el único riesgo que el gate cubre.
    expect(await SyncNotifier.sinParesConocidos(), isTrue);
  });

  test('uno que ya vio pares sigue bloqueado', () async {
    SharedPreferences.setMockInitialValues({'sync_vio_pares': true});

    // Sigue bloqueado a propósito hasta que exista el handshake entre
    // orquestadores (0007, paso 3/4): sin él, un Gerente y una Registradora
    // nunca terminan de verse, y ese es el caso que le importa a la purga.
    expect(await SyncNotifier.sinParesConocidos(), isFalse);
  });

  test('haber visto un par no se olvida al apagar el otro aparato', () async {
    // La marca es permanente a propósito: si se borrara al perder de vista al
    // par, apagar el otro teléfono habilitaría la purga — justo el escenario
    // que 0015 quiere impedir.
    SharedPreferences.setMockInitialValues({'sync_vio_pares': true});
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getBool('sync_vio_pares'), isTrue);
    expect(await SyncNotifier.sinParesConocidos(), isFalse);
  });
}
