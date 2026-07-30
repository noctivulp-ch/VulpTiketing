import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';

/// Por qué el proyecto depende de `cryptography_flutter`.
///
/// Medido con `scripts/medir_costo_backup.dart`: en Dart puro AES-GCM va a
/// **10,7 MB/s**. Con la base de 5 años (360 MB) eso son ~34 s solo de cifrado,
/// o sea el 93% de lo que tardaba exportar un backup. Las copias en memoria ya
/// se resolvieron troceando el archivo; esto ataca lo que quedaba.
///
/// En Android e iOS el paquete delega en el proveedor del sistema, que usa las
/// instrucciones AES del procesador. En Linux, Windows y macOS no trae
/// implementación nativa y **cae de vuelta a Dart puro**, así que ahí no cambia
/// nada. El dispositivo del negocio es una tablet, que es donde sí aplica.
///
/// Verificado en un Huawei P30 lite (Kirin 710, con extensiones AES), en perfil
/// AOT y cifrando trozos de 4 MB: **85,1 MB/s contra 3,6 MB/s en Dart puro —
/// 24 veces**. Se mide con el comando `diagnostico_cifrado` del harness, que
/// corre las dos implementaciones en el mismo aparato; comparar contra el
/// número de una laptop no dice nada.
///
/// Trampa que costó una medición falsa: en Android el paquete solo manda al
/// sistema lo que mide **menos de 20 MB**. Con una carga de 32 MB las dos vías
/// daban 3,6 MB/s y parecía que la dependencia no servía para nada. Ver
/// `TiketbackService._tamanoTrozo`, que depende de ese techo.
///
/// Es transparente para el formato: AES-256-GCM es el mismo algoritmo lo
/// implemente quien lo implemente, así que un `.tiketback` hecho en la tablet
/// se restaura en Linux y al revés.
///
/// No hay que llamar a nada para activarlo — el plugin se registra solo. Esta
/// función existe para poder VERIFICAR qué camino tocó, que es justo lo que no
/// se puede deducir mirando el código.
bool get cifradoNativoDisponible => Cryptography.instance is FlutterCryptography;

/// Deja constancia en el log de qué implementación de cifrado quedó activa.
///
/// Sin esto, "el backup tarda un minuto en la tablet" no se puede distinguir de
/// "el backup tarda un minuto porque cayó al cifrado lento y nadie se enteró".
void reportarCifrado() {
  debugPrint(
    cifradoNativoDisponible
        ? 'Cifrado: implementación del sistema (rápida)'
        : 'Cifrado: Dart puro (~10 MB/s) — esperable en escritorio',
  );
}
