import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/features/sync/sync_notifier.dart';

/// Lo que la pantalla muestra de la sincronización tiene que estar DENTRO del
/// estado observable.
///
/// El fallo que motivó esto lo vio el dueño: los dos aparatos sincronizaban
/// correctamente —misma base en los dos, comprobado— y las dos pantallas
/// seguían diciendo "Buscando otros dispositivos…". Los pares vivían en campos
/// privados del notifier, y como la fase no cambiaba (`syncing` todo el rato),
/// Riverpod no tenía motivo para reconstruir el widget.
///
/// Es la misma lección del refresco tras sincronizar, en otro sitio: un dato
/// que cambia en memoria sin avisar es un dato que la pantalla no tiene.
void main() {
  test('dos estados con distintos pares NO son iguales', () {
    // La comprobación que importa: si fueran iguales, Riverpod se saltaría la
    // reconstrucción y la pantalla se quedaría con lo de antes. Es exactamente
    // lo que pasaba.
    const buscando = EstadoSync(fase: FaseSync.syncing);
    const conUno = EstadoSync(fase: FaseSync.syncing, pares: 1);

    expect(buscando == conUno, isFalse);
  });

  test('aparecer un fallo también cambia el estado', () {
    const sinFallo = EstadoSync(fase: FaseSync.syncing, pares: 1);
    final conFallo = sinFallo.copyWith(fallo: '192.168.1.5:4321 — sin ruta');

    expect(sinFallo == conFallo, isFalse);
  });

  test('el mismo estado sí es igual: no se reconstruye porque sí', () {
    // La otra mitad. Sin `==` bien puesto, cada ronda repintaría la pantalla
    // aunque no hubiera novedades.
    const a = EstadoSync(fase: FaseSync.syncing, pares: 2, mismoRol: 1);
    const b = EstadoSync(fase: FaseSync.syncing, pares: 2, mismoRol: 1);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('detenida arranca sin pares ni fallo', () {
    const estado = EstadoSync.detenida();

    expect(estado.activa, isFalse);
    expect(estado.pares, 0);
    expect(estado.fallo, isNull);
  });

  test('cambiar de fase conserva los pares', () {
    // Al pasar a error no hay que perder lo que ya se sabía de la red: es
    // justo cuando más falta hace para diagnosticar.
    const activa = EstadoSync(fase: FaseSync.syncing, pares: 3, mismoRol: 2);
    final enError = activa.copyWith(fase: FaseSync.error);

    expect(enError.pares, 3);
    expect(enError.mismoRol, 2);
  });
}
