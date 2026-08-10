/// Quién es esta app y qué versión es.
///
/// Escrito a mano y **vigilado por una prueba**: `test/version_test.dart` lee
/// `pubspec.yaml` y falla si estos valores no coinciden con los de ahí. Es lo
/// que evita el problema de siempre con las constantes duplicadas —quedarse
/// vieja sin que nadie lo note— y ahorra una dependencia nativa solo para leer
/// el número de versión.
///
/// El nombre visible no es el del paquete. `pubspec.yaml` dice
/// `vulp_tiketing` porque un nombre de paquete Dart no admite mayúsculas ni
/// espacios; lo que se le muestra a la gente es **VulpTiketing**.
library;

const nombreApp = 'VulpTiketing';

/// La versión semántica, sin el número de compilación.
const versionApp = '1.0.0';

/// El número de compilación: lo que sube en cada instalación entregada.
///
/// Sirve para saber qué build corre un teléfono cuando algo no cuadra. Dos
/// aparatos con la misma versión y distinto build no tienen el mismo código.
const compilacionApp = 1;

/// Quien la hizo, con el nombre corto que usa como desarrollador.
const autorApp = 'NoctiVulp';

/// A dónde lleva el toque sobre el nombre del autor.
///
/// La app es a medida para un familiar y no cobra nada; el enlace es una marca
/// de autoría, no una invitación a pagar. Va **sin decoración de enlace** a
/// propósito: en la pantalla se lee como una firma, no como un botón.
const enlaceAutor =
    'https://patreon.com/NoctiVulp'
    '?utm_medium=unknown&utm_source=join_link'
    '&utm_campaign=creatorshare_creator&utm_content=copyLink';
