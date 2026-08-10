import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nav/retroceso.dart';
import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../../import_export/ui/tiketback_panels.dart';
import '../../import_export/ui/tiketdata_panel.dart';
import '../../sync/sync_notifier.dart';
import '../../../core/theme/bento_efectos.dart';
import '../../../core/theme/bento_fotos.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/bento_falla.dart';
import '../preferencias_notifier.dart';
import '../../producto/ui/categorias_panel.dart';
import 'cambiar_contrasena_panel.dart';
import 'token_mcp_panel.dart';

enum _Opcion {
  contrasena,
  exportarBackup,
  restaurarBackup,
  catalogo,
  sincronizacion,
  cerrarSesion,
  ordenProducto,
  acento,
  modoTema,
  optimizacion,
  categorias,
  tokenMcp,
}

/// Ventana 5 — ver docs/pantallas/flujo-descripcion.md#ventana-5--configuración.
/// Grid deslizante de tiles (boceto en prototipos-ascii.md): agregar una
/// opción nueva a futuro es una celda más, el grid nunca se satura porque
/// hace scroll vertical — mismo principio que el rail de navegación del
/// Dashboard.
///
/// Cada tile es una opción seleccionable (no un disparador de diálogo): el
/// panel de abajo muestra el contenido de la opción elegida. La app evita
/// overlays/menús emergentes en la medida de lo posible — Cambiar
/// contraseña, Exportar/Restaurar backup y Catálogo eran `AlertDialog`/
/// `SimpleDialog` antes, ahora son paneles inline (ver
/// cambiar_contrasena_panel.dart, tiketback_panels.dart, tiketdata_panel.dart).
class ConfiguracionScreen extends ConsumerStatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  ConsumerState<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends ConsumerState<ConfiguracionScreen> {
  _Opcion? _seleccion;

  @override
  Widget build(BuildContext context) {
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

    final ancho = BentoAncho.de(context);

    // La rejilla de tiles, con cada uno ocupando 2 de las 6 columnas: 3 por
    // fila en cualquier tamaño. Antes era un `GridView` con `shrinkWrap` y
    // `NeverScrollableScrollPhysics` dentro de una `Column`: a 360 dp eran unos
    // 880 dp de alto que NO scrolleaban, así que la pantalla se desbordaba y el
    // panel de detalle se quedaba sin espacio.
    final rejilla = BentoCuadricula(
      hijos: [
        for (final tile in <Widget>[
          _TileConfiguracion(
            icono: Icons.lock_outline,
            etiqueta: 'Contraseña',
            seleccionado: _seleccion == _Opcion.contrasena,
            onTap: () => setState(() => _seleccion = _Opcion.contrasena),
          ),
          _TileConfiguracion(
            icono: Icons.save_outlined,
            etiqueta: 'Exportar',
            seleccionado: _seleccion == _Opcion.exportarBackup,
            onTap: () => setState(() => _seleccion = _Opcion.exportarBackup),
          ),
          if (esGerente)
            _TileConfiguracion(
              icono: Icons.restore_outlined,
              etiqueta: 'Restaurar',
              seleccionado: _seleccion == _Opcion.restaurarBackup,
              onTap: () => setState(() => _seleccion = _Opcion.restaurarBackup),
            ),
          if (esGerente)
            _TileConfiguracion(
              icono: Icons.folder_open_outlined,
              etiqueta: 'Catálogo',
              seleccionado: _seleccion == _Opcion.catalogo,
              onTap: () => setState(() => _seleccion = _Opcion.catalogo),
            ),
          _TileConfiguracion(
            icono: Icons.wifi_tethering,
            etiqueta: 'Sincronizar',
            seleccionado: _seleccion == _Opcion.sincronizacion,
            onTap: () => setState(() => _seleccion = _Opcion.sincronizacion),
          ),
          _TileConfiguracion(
            icono: Icons.logout,
            etiqueta: 'Cerrar sesión',
            seleccionado: _seleccion == _Opcion.cerrarSesion,
            onTap: () => setState(() => _seleccion = _Opcion.cerrarSesion),
          ),
          _TileConfiguracion(
            icono: Icons.sort,
            etiqueta: 'Orden',
            seleccionado: _seleccion == _Opcion.ordenProducto,
            onTap: () => setState(() => _seleccion = _Opcion.ordenProducto),
          ),
          _TileConfiguracion(
            icono: Icons.palette_outlined,
            etiqueta: 'Acento',
            seleccionado: _seleccion == _Opcion.acento,
            onTap: () => setState(() => _seleccion = _Opcion.acento),
          ),
          _TileConfiguracion(
            icono: Icons.brightness_6_outlined,
            etiqueta: 'Tema',
            seleccionado: _seleccion == _Opcion.modoTema,
            onTap: () => setState(() => _seleccion = _Opcion.modoTema),
          ),
          // Junto a Catálogo, que es lo otro que toca la forma del inventario.
          // Solo Gerente, igual que Catálogo: renombrar o sacar una categoría
          // reordena la carta que ve todo el mundo.
          if (esGerente)
            _TileConfiguracion(
              icono: Icons.label_outline,
              etiqueta: 'Categorías',
              seleccionado: _seleccion == _Opcion.categorias,
              onTap: () => setState(() => _seleccion = _Opcion.categorias),
            ),
          _TileConfiguracion(
            icono: Icons.speed_outlined,
            etiqueta: 'Optimización',
            seleccionado: _seleccion == _Opcion.optimizacion,
            onTap: () => setState(() => _seleccion = _Opcion.optimizacion),
          ),
          // Solo el Gerente: es la llave que deja manejar la app entera desde
          // fuera, o sea cobrar y borrar en nombre de quien la tenga.
          if (esGerente)
            _TileConfiguracion(
              icono: Icons.vpn_key_outlined,
              // "Herramientas" se parte en "Herramienta / s": el tile mide
              // ~101 dp a 360 y las etiquetas de esta rejilla son de una
              // palabra corta. El icono de llave ya dice de qué va.
              etiqueta: 'Acceso',
              seleccionado: _seleccion == _Opcion.tokenMcp,
              onTap: () => setState(() => _seleccion = _Opcion.tokenMcp),
            ),
        ])
          BentoCelda(compacto: 2, medio: 2, amplio: 2, hijo: tile),
      ],
    );

    final panel = BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
      child: _panelPara(_seleccion),
    );

    // Los tiles a la izquierda y el detalle a la derecha cuando hay ancho de
    // sobra —escritorio— y también cuando el ALTO escasea.
    //
    // Acostado era peor que en escritorio: apilado, tocar un tile abría un
    // panel que quedaba entero fuera de la vista, así que no pasaba nada
    // visible. Con 360 dp de alto no hay sitio debajo de la rejilla para nada.
    final ladoALado = ancho == BentoAncho.amplio || bentoEstaAcostado(context);

    final cuerpo = ladoALado
        ? BentoCuadricula(
            llenarAlto: true,
            hijos: [
              // En escritorio la rejilla se conforma con un tercio; acostado
              // necesita la mitad, porque con un tercio de 800 dp cada tile
              // queda en 80 y "Contraseña" se parte en "Contr / aseña".
              BentoCelda.fija(
                ancho == BentoAncho.amplio ? 2 : 3,
                hijo: SingleChildScrollView(child: rejilla),
              ),
              BentoCelda.fija(
                ancho == BentoAncho.amplio ? 4 : 3,
                hijo: SingleChildScrollView(child: panel),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rejilla,
              const SizedBox(height: BentoSpacing.gapCelda),
              panel,
            ],
          );

    return RetrocesoCierra(
      activo: _seleccion != null,
      alRetroceder: () => setState(() => _seleccion = null),
      child: Scaffold(
        body: SafeArea(
          child: ladoALado
              ? Padding(padding: _margenPagina(context), child: cuerpo)
              // La página entera scrollea, que es el arreglo del desborde.
              : SingleChildScrollView(padding: _margenPagina(context), child: cuerpo),
        ),
      ),
    );
  }

  /// Margen de la página, con el espacio reservado del borde superior.
  EdgeInsets _margenPagina(BuildContext context) => EdgeInsets.fromLTRB(
    BentoSpacing.gapCelda,
    bentoInsetSuperior(context),
    BentoSpacing.gapCelda,
    BentoSpacing.gapCelda,
  );

  Widget _panelPara(_Opcion? opcion) {
    switch (opcion) {
      case null:
        return const Center(child: Text('Elegí una opción arriba'));
      case _Opcion.contrasena:
        return const PanelCambiarContrasena();
      case _Opcion.exportarBackup:
        return const PanelExportarBackup();
      case _Opcion.restaurarBackup:
        return const PanelRestaurarBackup();
      case _Opcion.catalogo:
        return const PanelCatalogo();
      case _Opcion.sincronizacion:
        return const _PanelSincronizacion();
      case _Opcion.cerrarSesion:
        return const _PanelCerrarSesion();
      case _Opcion.ordenProducto:
        return const _PanelOrdenProducto();
      case _Opcion.acento:
        return const _PanelAcento();
      case _Opcion.modoTema:
        return const _PanelModoTema();
      case _Opcion.categorias:
        return const PanelCategorias();
      case _Opcion.optimizacion:
        return const _PanelOptimizacion();
      case _Opcion.tokenMcp:
        return const PanelTokenMcp();
    }
  }
}

/// Apagar adorno para ganar fluidez, efecto por efecto.
///
/// Es una decisión POR APARATO: el teléfono viejo de la caja puede necesitar
/// apagar el relieve y la tablet del mostrador no. Por eso vive en las
/// preferencias locales y no viaja en el backup ni en la sincronización.
class _PanelOptimizacion extends ConsumerWidget {
  const _PanelOptimizacion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencias = ref.watch(preferenciasNotifierProvider).valueOrNull;
    final apagados = preferencias?.efectosApagados ?? const <EfectoPesado>{};
    final sinFotos = preferencias?.fotosApagadasEn ?? const <VentanaConFotos>{};
    final textos = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Optimización', style: textos.titleMedium),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Text(
          'Apagar un efecto no cambia lo que la app hace, solo cómo se ve. '
          'En un aparato lento se nota al desplazar listas largas.',
          style: textos.bodySmall,
        ),
        const SizedBox(height: BentoSpacing.unidad),
        for (final efecto in EfectoPesado.values)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !apagados.contains(efecto),
            title: Text(efecto.etiqueta),
            subtitle: Text(efecto.explicacion),
            isThreeLine: true,
            onChanged: (activo) => ref
                .read(preferenciasNotifierProvider.notifier)
                .cambiarEfecto(efecto, activo: activo),
          ),
        const SizedBox(height: BentoSpacing.gapCelda),
        Text('Fotos de productos', style: textos.titleSmall),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Text(
          'Una por ventana, porque no cuestan lo mismo en cada una. Apagadas, '
          'el producto se sigue viendo con el icono de su categoría: se ahorra '
          'cargar la foto, no se pierde de qué es cada cosa.',
          style: textos.bodySmall,
        ),
        const SizedBox(height: BentoSpacing.unidad),
        for (final ventana in VentanaConFotos.values)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !sinFotos.contains(ventana),
            title: Text(ventana.etiqueta),
            subtitle: Text(ventana.explicacion),
            isThreeLine: true,
            onChanged: (activo) => ref
                .read(preferenciasNotifierProvider.notifier)
                .cambiarFotos(ventana, activo: activo),
          ),
      ],
    );
  }
}

/// Tile del grid de Configuración: ícono grande + etiqueta corta, tolera
/// texto porque es una pantalla de uso raro (no compite con el criterio
/// "sin leer" de las pantallas de venta — ver prototipos-ascii.md). El
/// estado `seleccionado` resalta cual opcion esta mostrando su panel abajo.
class _TileConfiguracion extends StatelessWidget {
  const _TileConfiguracion({
    required this.icono,
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // La selección la marca la CRESTA del pozo (se engorda y pasa al metal), no
    // un relleno de `primaryContainer`. Rellenar la celda la levantaba de la
    // bandeja y la hacía leer como un botón — el acento no se usa como fondo,
    // solo como borde de selección y acción primaria (DESIGN.md, regla 4).
    return BentoPozo(
      onTap: onTap,
      seleccionado: seleccionado,
      // Padding de pared en vez de celda: a 360 dp el tile mide ~101 dp, y con
      // 16 de padding a cada lado quedaban ~69 dp de texto — "Sincronización"
      // no entraba y Flutter la partía a MITAD DE PALABRA ("Sincronizac/ión").
      // Las etiquetas ademas se acortaron a una palabra donde se podia: el
      // icono ya dice de que se trata y esta pantalla es de uso raro.
      padding: const EdgeInsets.all(BentoSpacing.pared),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 32, color: seleccionado ? scheme.primary : null),
          const SizedBox(height: BentoSpacing.unidad),
          Text(
            etiqueta,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Descubrimiento (0021) y transporte (0022: servidor HTTP + cliente) ya
/// son reales — al activar el switch, este dispositivo publica su servicio
/// mDNS, levanta su servidor de sync y sincroniza con cada par del mismo
/// rol que descubre. Lo que falta es la coordinacion *entre* grupos
/// Qué está pasando con la sincronización, en una línea.
///
/// Distingue tres situaciones que antes se veían casi igual, y esa confusión
/// costó una tarde: "0 dispositivos visibles — este es el orquestador" se lee
/// como que la red funciona, cuando es justo el caso en el que hay que
/// sospechar. Y una sincronización que fallaba contra el mismo aparato en cada
/// ronda se veía idéntica a una que no tenía nada que traer.
String _estadoDeSync(EstadoSync estado, {required bool esOrquestador}) {
  if (!estado.activa) return 'Detenida — actívala para sincronizar con otros dispositivos';

  final partes = <String>[];
  if (estado.pares == 0) {
    partes.add('Buscando otros dispositivos…');
  } else {
    partes.add('${estado.pares} dispositivo(s) a la vista');
    if (estado.mismoRol > 0 && esOrquestador) {
      partes.add('este es el orquestador de su grupo');
    }
  }

  // El último error, si lo hubo. Es lo que convierte "no pasa nada" en algo
  // accionable sin tener que enchufar el teléfono a una computadora.
  final fallo = estado.fallo;
  if (fallo != null) partes.add('último fallo: $fallo');

  return partes.join(' · ');
}

/// (Gerente ↔ Registradora vía orquestadores, 0007) — ver nota en
/// SyncNotifier.
///
/// Limitacion conocida: el contador de pares visibles no se refresca en
/// vivo (SyncNotifier no emite un nuevo `state` cuando cambian los pares,
/// solo cuando cambia idle/syncing/error) — apagar y prender vuelve a leer
/// el valor actual.
class _PanelSincronizacion extends ConsumerWidget {
  const _PanelSincronizacion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(syncNotifierProvider);
    final notifier = ref.read(syncNotifierProvider.notifier);
    final activo = estado.activa;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Sincronización', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.unidad),
        Text(_estadoDeSync(estado, esOrquestador: notifier.esOrquestadorDeMiGrupo)),
        const SizedBox(height: BentoSpacing.gapCelda),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(activo ? 'Sincronización activa' : 'Sincronización detenida'),
          value: activo,
          onChanged: (v) => v ? notifier.iniciarSync() : notifier.detenerSync(),
        ),
      ],
    );
  }
}

class _PanelCerrarSesion extends ConsumerStatefulWidget {
  const _PanelCerrarSesion();

  @override
  ConsumerState<_PanelCerrarSesion> createState() => _PanelCerrarSesionState();
}

class _PanelCerrarSesionState extends ConsumerState<_PanelCerrarSesion> {
  bool _confirmando = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Cerrar sesión', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.unidad),
        if (_confirmando) ...[
          const Text('¿Seguro que querés cerrar sesión?'),
          const SizedBox(height: BentoSpacing.gapCelda),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _confirmando = false),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: BentoSpacing.unidad),
              FilledButton(
                onPressed: () => ref.read(sesionNotifierProvider.notifier).cerrarSesion(),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ] else
          FilledButton(
            onPressed: () => setState(() => _confirmando = true),
            child: const Text('Cerrar sesión'),
          ),
      ],
    );
  }
}

class _PanelOrdenProducto extends ConsumerWidget {
  const _PanelOrdenProducto();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferenciasAsync = ref.watch(preferenciasNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Orden de productos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.gapCelda),
        preferenciasAsync.when(
          data: (prefs) => SegmentedButton<OrdenProducto>(
            segments: const [
              ButtonSegment(value: OrdenProducto.alfabetico, label: Text('Alfabético')),
              ButtonSegment(value: OrdenProducto.precio, label: Text('Precio')),
              ButtonSegment(value: OrdenProducto.categoria, label: Text('Categoría')),
            ],
            selected: {prefs.ordenProducto},
            onSelectionChanged: (seleccion) =>
                ref.read(preferenciasNotifierProvider.notifier).cambiarOrden(seleccion.first),
          ),
          loading: () => const CircularProgressIndicator(),
          error: (e, st) => BentoFalla(
            mensaje: 'No se pudieron cargar las preferencias.',
            error: e,
            onReintentar: () => ref.invalidate(preferenciasNotifierProvider),
          ),
        ),
      ],
    );
  }
}

class _PanelAcento extends ConsumerWidget {
  const _PanelAcento();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferenciasAsync = ref.watch(preferenciasNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Acento', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.gapCelda),
        preferenciasAsync.when(
          data: (prefs) => SegmentedButton<AcentoTinte>(
            segments: const [
              ButtonSegment(value: AcentoTinte.oro, label: Text('Oro')),
              ButtonSegment(value: AcentoTinte.jade, label: Text('Jade')),
              ButtonSegment(value: AcentoTinte.peltre, label: Text('Peltre')),
            ],
            selected: {prefs.acento},
            onSelectionChanged: (seleccion) =>
                ref.read(preferenciasNotifierProvider.notifier).cambiarAcento(seleccion.first),
          ),
          loading: () => const SizedBox.shrink(),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

class _PanelModoTema extends ConsumerWidget {
  const _PanelModoTema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferenciasAsync = ref.watch(preferenciasNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Modo de tema', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.gapCelda),
        preferenciasAsync.when(
          data: (prefs) => SegmentedButton<ModoTema>(
            segments: const [
              ButtonSegment(value: ModoTema.claro, label: Text('Claro')),
              ButtonSegment(value: ModoTema.oscuro, label: Text('Oscuro')),
              ButtonSegment(value: ModoTema.sistema, label: Text('Sistema')),
            ],
            selected: {prefs.modoTema},
            onSelectionChanged: (seleccion) =>
                ref.read(preferenciasNotifierProvider.notifier).cambiarModoTema(seleccion.first),
          ),
          loading: () => const SizedBox.shrink(),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}
