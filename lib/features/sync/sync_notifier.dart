import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../auth/device_identity_service.dart';
import '../auth/sesion_notifier.dart';
import '../producto/categoria_notifier.dart';
import '../producto/producto_notifier.dart';
import '../caja/caja_notifier.dart';
import '../reportes/reportes_provider.dart';
import '../configuracion/preferencias_notifier.dart';
import '../venta/libro_ventas.dart';
import '../venta/venta_notifier.dart';
import 'device_discovery_service.dart';
import 'sync_client.dart';
import 'sync_group_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_server.dart';

enum FaseSync { idle, syncing, error }

/// Lo que la pantalla necesita saber de la sincronización.
///
/// Los pares y el último fallo van **dentro del estado**, no en campos privados
/// del notifier. Estaban fuera, y el resultado era una pantalla que mentía:
/// los dos aparatos sincronizaban correctamente —misma base en los dos— y los
/// dos seguían diciendo "Buscando otros dispositivos…". Como la fase no
/// cambiaba (`syncing` todo el rato), Riverpod no tenía motivo para reconstruir
/// el widget, y el texto se quedaba con lo que hubiera en el primer build.
///
/// Con los datos acá, cualquier cambio en los pares es un estado distinto y la
/// pantalla se entera sola. Es la misma lección del refresco tras sincronizar:
/// un dato que cambia en memoria sin avisar es un dato que la pantalla no
/// tiene.
@immutable
class EstadoSync {
  const EstadoSync({required this.fase, this.pares = 0, this.mismoRol = 0, this.fallo});

  const EstadoSync.detenida() : this(fase: FaseSync.idle);

  final FaseSync fase;

  /// Cuántos aparatos se ven ahora mismo, **sin contarse a uno mismo**.
  final int pares;

  /// De esos, cuántos comparten rol. Solo decide quién orquesta; la
  /// sincronización va con todos (decisión 0036).
  final int mismoRol;

  /// El último error de conexión, con dirección y puerto. `null` si no ha
  /// fallado nada desde que se activó.
  final String? fallo;

  bool get activa => fase == FaseSync.syncing;

  EstadoSync copyWith({FaseSync? fase, int? pares, int? mismoRol, String? fallo}) => EstadoSync(
    fase: fase ?? this.fase,
    pares: pares ?? this.pares,
    mismoRol: mismoRol ?? this.mismoRol,
    fallo: fallo ?? this.fallo,
  );

  @override
  bool operator ==(Object other) =>
      other is EstadoSync &&
      other.fase == fase &&
      other.pares == pares &&
      other.mismoRol == mismoRol &&
      other.fallo == fallo;

  @override
  int get hashCode => Object.hash(fase, pares, mismoRol, fallo);
}

/// Fachada Riverpod-facing: compone DeviceDiscoveryService + SyncServer +
/// SyncClient + SyncGroupCoordinator (decisiones 0019/0022). Expone estado
/// a la UI y si todos los dispositivos conocidos están sincronizados
/// (consultado por `ProductoNotifier.purgar`, decisión 0015).
///
/// Estado real de esta implementación: descubrimiento (0021), transporte
/// (0022, servidor HTTP + cliente) y sync **intra-grupo** (pares del mismo
/// rol, pairwise) ya funcionan de verdad. Lo que **falta** es el protocolo
/// de coordinación *entre* grupos (Gerente ↔ Registradora vía sus
/// orquestadores electos — el paso 3/4 del diseño de 0007): hoy cada
/// dispositivo solo sincroniza con pares de su propio rol, no cruza a la
/// otra red. Por eso [todosLosDispositivosSincronizados] sigue devolviendo
/// `false`: sin el handshake entre orquestadores, un Gerente y una
/// Registradora nunca terminan de verse entre sí, y ese caso es
/// justamente el que le importa a la purga (0015).
///
/// Tampoco se llama a [iniciarSync] automáticamente desde ningún lado
/// todavía (ej. al abrir la app) — es una decisión de producto pendiente
/// (¿siempre en segundo plano? ¿solo cuando el usuario lo activa?), no
/// bloquea que el transporte ya funcione.
class SyncNotifier extends Notifier<EstadoSync> {
  final _discovery = BonsoirDeviceDiscoveryService();
  final _coordinator = const SyncGroupCoordinator();
  final _deviceIdentity = DeviceIdentityService();
  SyncServer? _server;

  List<PeerVisible> _paresDelMismoRol = [];
  String? _miDeviceId;

  /// Últimos pares vistos, para poder repasarlos sin esperar a que el
  /// descubrimiento vuelva a emitir.
  List<PeerVisible> _ultimosPares = [];

  /// El último error de sincronización, para que la pantalla pueda decirlo.
  /// `null` mientras no haya fallado nada.
  String? _ultimoFallo;
  Timer? _ronda;
  SyncClient? _cliente;
  bool _sincronizando = false;

  /// Cada cuánto se vuelve a preguntar a los pares ya conocidos.
  ///
  /// Antes NO existía: el sync se disparaba solo cuando el stream de
  /// descubrimiento emitía, o sea al aparecer o desaparecer un aparato. Medido
  /// con cuatro: se importaba el catálogo en un Gerente y el otro se quedaba
  /// vacío indefinidamente, porque la membresía no había cambiado. Había que
  /// apagar y encender el interruptor para que pasara algo.
  ///
  /// Quince segundos porque lo que se sincroniza es una venta de mostrador: que
  /// tarde un cuarto de minuto en aparecer en el otro aparato no molesta a
  /// nadie, y preguntar más seguido gasta batería en cinco teléfonos a la vez.
  static const _cadaRonda = Duration(seconds: 15);

  @override
  EstadoSync build() {
    // Se restaura en segundo plano: `build` es síncrono y leer la preferencia
    // —y arrancar el servidor— no lo es. Arranca detenida y se enciende sola si
    // corresponde, que es lo que se ve en pantalla de todas formas.
    Future.microtask(_restaurarSiEstabaEncendida);
    return const EstadoSync.detenida();
  }

  Future<void> _restaurarSiEstabaEncendida() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keySyncActivo) ?? false) await iniciarSync();
  }

  /// Guarda que este aparato VIO a otro alguna vez. Se escribe cuando el
  /// descubrimiento encuentra un par y no se borra: un aparato que ya estuvo
  /// acompañado no vuelve a estar solo por apagar el otro.
  static const _keyVioPares = 'sync_vio_pares';

  /// Si la sincronización quedó encendida la última vez.
  ///
  /// **El defecto es apagado**: una app recién instalada no se pone a hablar
  /// con la red sin que nadie se lo pida. Pero encenderla es una decisión, y se
  /// respeta — antes se perdía en cada arranque y había que volver a activarla
  /// a mano, que en una soda significa que alguien tiene que acordarse cada
  /// mañana.
  ///
  /// No se auto-apaga: solo la apaga quien toca el interruptor.
  static const _keySyncActivo = 'sync_activo';

  /// El gate de purga de la [decisión 0015].
  ///
  /// Distingue dos situaciones que antes se trataban igual:
  ///
  /// - **Este aparato nunca vio a otro.** Entonces no hay ningún dispositivo
  ///   remoto que pueda tener una venta pendiente con el producto, que es el
  ///   único riesgo que el gate existe para cubrir. Purgar es seguro y se
  ///   permite. Es el caso de una soda con un solo teléfono, o sea el normal
  ///   hoy.
  /// - **Ya vio pares.** Sigue en `false` hasta que exista el handshake entre
  ///   orquestadores (paso 3/4 de 0007): sin él, un Gerente y una Registradora
  ///   nunca terminan de verse, y ese es justamente el caso que le importa a la
  ///   purga.
  ///
  /// Antes devolvía `false` siempre, así que purgar era imposible en todos los
  /// casos — incluido aquel en que es trivialmente seguro. La condición 3 de
  /// 0015 dice "todos los dispositivos CONOCIDOS están sincronizados": cuando
  /// no se conoce ninguno, se cumple sola.
  /// Lo consulta la UI por [dispositivoSinParesProvider], no por un campo en
  /// memoria: así no hay una ventana en la que el dato todavía no se leyó y la
  /// respuesta sea la equivocada según cuándo se pregunte.
  static Future<bool> sinParesConocidos() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyVioPares) ?? false);
  }

  Future<void> _marcarQueVioPares() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyVioPares) ?? false) return;
    await prefs.setBool(_keyVioPares, true);
    ref.invalidate(dispositivoSinParesProvider);
  }

  bool get esOrquestadorDeMiGrupo {
    final miDeviceId = _miDeviceId;
    if (miDeviceId == null) return false;
    return _coordinator.esOrquestador(
      miDeviceId: miDeviceId,
      paresVisiblesDelMismoRol: _paresDelMismoRol,
    );
  }

  List<PeerVisible> get paresVisibles => _paresDelMismoRol;

  Future<void> iniciarSync() async {
    final rol = ref.read(sesionNotifierProvider);
    if (rol == null) return;

    final db = await ref.read(databaseProvider.future);
    final miDeviceId = await _deviceIdentity.obtenerOCrear();
    _miDeviceId = miDeviceId;

    final moneda = (await ref.read(preferenciasNotifierProvider.future)).moneda;
    final server = SyncServer(db, moneda: moneda);
    final puerto = await server.iniciar();
    _server = server;
    state = const EstadoSync(fase: FaseSync.syncing);
    // Se recuerda ENCENDIDA para el próximo arranque. Se guarda acá y no al
    // tocar el interruptor porque este es el punto donde de verdad quedó
    // andando: si `iniciarSync` sale antes —sin rol, por ejemplo— no hay nada
    // que recordar.
    (await SharedPreferences.getInstance()).setBool(_keySyncActivo, true);

    await _discovery.anunciar(deviceId: miDeviceId, rol: rol.name, puerto: puerto);

    _cliente = SyncClient(db, libros: await ref.read(libroVentasServiceProvider.future), moneda: moneda);

    // La ronda periódica: repasa los pares YA conocidos aunque no haya cambiado
    // nada en la red.
    _ronda?.cancel();
    _ronda = Timer.periodic(_cadaRonda, (_) => _repasarPares());

    _discovery.descubrirPares().listen((todos) async {
      // FUERA uno mismo. mDNS devuelve también el anuncio propio —comprobado en
      // el log: un aparato resolvía dos servicios y uno era el suyo—, y sin
      // este filtro cada ronda gasta una conexión en hablar consigo mismo.
      //
      // No es solo desperdicio. Con el cerrojo de ronda, si esa conexión se
      // atasca bloquea la ronda entera y el peer de verdad no llega a
      // consultarse nunca. Es la explicación más probable de que la
      // sincronización fallara de forma intermitente y en una sola dirección.
      //
      // Antes pasaba desapercibido porque el filtro por rol recortaba la lista;
      // al sincronizar con todos los pares quedó a la vista.
      final pares = todos.where((p) => p.deviceId != miDeviceId).toList();

      _ultimosPares = pares;
      // Cualquier par cuenta, sea del rol que sea: lo que decide si este
      // aparato está solo es si HAY otro en la red, no si es de su grupo.
      if (pares.isNotEmpty) await _marcarQueVioPares();
      _paresDelMismoRol = pares.where((p) => p.rol == rol.name).toList();
      _publicar();

      // Se sincroniza con TODOS los pares, no solo con los del mismo rol.
      //
      // El diseño original (0007, opción B) separaba dos redes por rol y las
      // unía por un handshake entre orquestadores — el paso 3/4, que nunca se
      // implementó. El resultado medido con cuatro aparatos: un Gerente y una
      // Registradora **se ven por mDNS y no se sincronizan nunca**. La
      // Registradora arrancaba vacía y se quedaba vacía con el catálogo entero
      // a un metro.
      //
      // La separación no era por seguridad: el propio 0007 dice que la opción
      // par-a-par "hubiera sido más simple" y que se eligió la otra para
      // reducir tráfico. A la escala real de una soda —cuatro aparatos, doce
      // conexiones por ciclo— ese ahorro no compra nada, y costaba que la
      // función no existiera.
      //
      // `_paresDelMismoRol` se conserva porque el coordinador de grupo lo sigue
      // usando para elegir orquestador: si algún día hace falta el ahorro, la
      // pieza está.
      await _repasarPares();
    }, onError: (_) => state = state.copyWith(fase: FaseSync.error));
  }

  /// Una pasada por todos los pares conocidos.
  ///
  /// El cerrojo `_sincronizando` evita que la ronda periódica y un evento de
  /// descubrimiento se pisen: dos pasadas a la vez sobre las mismas filas no
  /// corrompen nada —LWW es idempotente— pero duplican el tráfico y las
  /// escrituras justo cuando la red ya está movida.
  Future<void> _repasarPares() async {
    final cliente = _cliente;
    if (cliente == null || _sincronizando || _ultimosPares.isEmpty) return;
    _sincronizando = true;
    var llegoAlgo = false;
    try {
      for (final par in _ultimosPares) {
        try {
          await cliente.sincronizarCon(par);
          llegoAlgo = true;
        } catch (e) {
          // Un peer que se desconecta a mitad de sync no debe tumbar toda la
          // sesión — se reintenta en la próxima ronda (robustez best-effort de
          // 0007: el peor caso es una sync redundante, no una caída).
          //
          // Pero se DEJA RASTRO. Antes era un `catch (_)` mudo, y por eso una
          // sincronización que fallaba siempre contra el mismo peer se veía
          // exactamente igual que una que no tenía nada que traer: la app decía
          // "activa" y no pasaba nada. Costó una tarde de aparatos descubrir
          // que era una dirección `fe80::` inalcanzable.
          _ultimoFallo = '${par.direccion}:${par.puerto} — $e';
          _publicar();
        }
      }
    } finally {
      _sincronizando = false;
    }

    // Lo que entra por sync se escribe DIRECTO en la base, sin pasar por los
    // notifiers, así que la pantalla seguía mostrando lo de antes: medido con
    // dos aparatos, la base del receptor tenía 39 productos y Venta Rápida
    // decía "la bandeja está vacía" hasta reiniciar la app.
    //
    // Se invalida después de la ronda entera y no por peer: con cuatro
    // aparatos, invalidar dentro del bucle reconstruiría el catálogo tres
    // veces seguidas para llegar al mismo sitio.
    if (llegoAlgo) {
      ref.invalidate(productoNotifierProvider);
      ref.invalidate(categoriaNotifierProvider);
      ref.invalidate(ventaNotifierProvider);
      ref.invalidate(reportesProvider);
      ref.invalidate(detalleRangoProvider);
      ref.invalidate(cajaNotifierProvider);
    }
  }

  /// Vuelca a `state` lo que la pantalla mira.
  ///
  /// Hay que llamarlo cada vez que cambien los pares o el último fallo: son
  /// campos privados, y sin esto Riverpod no se entera de que hay algo nuevo
  /// que enseñar.
  void _publicar() {
    state = state.copyWith(
      pares: _ultimosPares.length,
      mismoRol: _paresDelMismoRol.length,
      fallo: _ultimoFallo,
    );
  }

  /// Qué pares se ven ahora y qué fue lo último que falló.
  ///
  /// Lo consulta el panel de Sincronización: sin esto, "activa" es todo lo que
  /// la app sabe decir, y no distingue "no hay nadie" de "no consigo hablar con
  /// el que hay".
  ({int pares, int mismoRol, String? fallo}) get diagnostico =>
      (pares: _ultimosPares.length, mismoRol: _paresDelMismoRol.length, fallo: _ultimoFallo);

  Future<void> detenerSync() async {
    (await SharedPreferences.getInstance()).setBool(_keySyncActivo, false);
    _ronda?.cancel();
    _ronda = null;
    _cliente = null;
    _ultimosPares = [];
    _ultimoFallo = null;
    await _discovery.detener();
    await _server?.detener();
    _server = null;
    _paresDelMismoRol = [];
    state = const EstadoSync.detenida();
  }
}

final syncNotifierProvider = NotifierProvider<SyncNotifier, EstadoSync>(SyncNotifier.new);

/// Si este aparato nunca vio a otro en la red.
///
/// Es el gate de la purga (decisión 0015, condición 3): sin ningún dispositivo
/// conocido no hay ninguno que pueda tener una venta pendiente con el producto,
/// que es el único riesgo que esa condición cubre.
final dispositivoSinParesProvider = FutureProvider<bool>((ref) => SyncNotifier.sinParesConocidos());
