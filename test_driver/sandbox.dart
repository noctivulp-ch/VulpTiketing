// Banco de pruebas de estilo — SOLO desarrollo, sin funcion.
//
// Existe para decidir un look mirandolo y toqueteandolo, no imaginandolo:
// elementos de distintos tamanos y formas, cada color del sistema editable en
// vivo, y exportacion de la configuracion resultante a un archivo para que
// quede como especificacion exacta en vez de interpretada de una captura.
//
// Vive fuera de lib/ a proposito (igual que test_driver/app.dart): no entra en
// produccion ni en la navegacion de la app.
//
// Correr:
//   VULP_WINDOW_TITLE="vulpedebug — sandbox" \
//     flutter run -t test_driver/sandbox.dart -d linux
//
// Cada muestra de texto reporta su contraste WCAG real contra la superficie
// que tiene debajo: el tallado se consigue acercando el glifo al color de su
// fondo, y eso BAJA el contraste por definicion, asi que la decision estetica
// conviene tomarse con el numero delante.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

void main() {
  // Permite capturar el sandbox desde el bridge (`GET /screenshot`, renderizado
  // por el motor) sin depender del foco ni del monitor.
  // `enableTextEntryEmulation: false` es obligatorio: con el default el teclado
  // fisico queda muerto, y aca hay campos de texto que se escriben a mano.
  enableFlutterDriverExtension(enableTextEntryEmulation: false);
  runApp(const SandboxApp());
}

// --- Tokens editables --------------------------------------------------------
// Las claves son el contrato con la exportacion: lo que se escribe en el JSON
// usa estos mismos nombres, que son los de `BentoLaca` y el `ColorScheme`.
const kBandeja = 'bandeja';
const kPozo = 'pozo';
const kPozoContacto = 'pozoContacto';
const kBorde = 'bordePozo';
const kTextoEnPozo = 'textoEnPozo';
const kTexto2EnPozo = 'textoSecundarioEnPozo';
const kTextoEnBandeja = 'textoEnBandeja';
const kTexto2EnBandeja = 'textoAtenuadoEnBandeja';
const kAcento = 'acento';
const kSobreAcento = 'sobreAcento';

const _ordenTokens = [
  kBandeja,
  kPozo,
  kPozoContacto,
  kBorde,
  kTextoEnPozo,
  kTexto2EnPozo,
  kTextoEnBandeja,
  kTexto2EnBandeja,
  kAcento,
  kSobreAcento,
];

/// Contra que superficie se mide el contraste de cada token, para poder
/// reportarlo mientras se edita.
const _fondoDeReferencia = {
  kTextoEnPozo: kPozo,
  kTexto2EnPozo: kPozo,
  kTextoEnBandeja: kBandeja,
  kTexto2EnBandeja: kBandeja,
  kBorde: kBandeja,
  kSobreAcento: kAcento,
  kAcento: kPozo,
  kPozoContacto: kPozo,
  kPozo: kBandeja,
  kBandeja: kPozo,
};

/// Umbral por token: texto necesita 4.5 (AA), un borde o superficie solo 3.0
/// (WCAG 1.4.11) o menos si es una diferencia de material.
const _umbralDe = {
  kTextoEnPozo: 4.5,
  kTexto2EnPozo: 4.5,
  kTextoEnBandeja: 4.5,
  kTexto2EnBandeja: 4.5,
  kSobreAcento: 4.5,
  kAcento: 4.5,
  kBorde: 3.0,
  kPozo: 1.2,
  kBandeja: 1.2,
  kPozoContacto: 1.14,
};

class SandboxApp extends StatefulWidget {
  const SandboxApp({super.key});

  @override
  State<SandboxApp> createState() => _SandboxAppState();
}

class _SandboxAppState extends State<SandboxApp> {
  Brightness _brillo = Brightness.dark;
  AcentoTinte _metal = AcentoTinte.oro;

  /// Desplazamiento en px de las capas de luz y sombra del tallado. Arranca
  /// alto a proposito: con 1px el efecto era invisible y no se podia juzgar.
  double _profundidad = 2;

  /// Cuanto se funde el glifo con su superficie. 0 = color de texto normal
  /// (legible, tallado sutil); 1 = exactamente el color del fondo (el glifo
  /// desaparece y solo lo definen sus bordes: el tallado "puro", precioso e
  /// ilegible). El punto util esta en el medio y es lo que hay que calibrar.
  double _fusion = 0.55;

  /// Intensidad de la luz y la sombra de la incision, como fraccion hacia
  /// blanco y hacia negro. Separadas de `profundidad` porque son dos ejes
  /// distintos: cuanto se desplaza y cuanto contrasta.
  double _luzIntensidad = 0.45;
  double _sombraIntensidad = 0.80;

  Map<String, Color> _colores = {};
  String _tokenActivo = kBandeja;
  final _detalle = TextEditingController();
  String? _ultimaExportacion;

  @override
  void initState() {
    super.initState();
    _resincronizar();
  }

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  /// Vuelve a leer todos los colores del tema real. Se llama al arrancar y al
  /// cambiar de modo o metal, porque el tema de referencia cambio.
  void _resincronizar() {
    final tema = buildBentoTheme(_metal, brightness: _brillo);
    final laca = tema.extension<BentoLaca>()!;
    final scheme = tema.colorScheme;
    _colores = {
      kBandeja: laca.bandeja,
      kPozo: laca.pozo,
      kPozoContacto: laca.pozoContacto,
      kBorde: laca.paredCresta,
      kTextoEnPozo: scheme.onSurface,
      kTexto2EnPozo: scheme.onSurfaceVariant,
      kTextoEnBandeja: laca.textoEnBandeja,
      kTexto2EnBandeja: laca.textoAtenuadoEnBandeja,
      kAcento: scheme.primary,
      kSobreAcento: scheme.onPrimary,
    };
  }

  /// Construye el tema con los colores editados encima del tema real, para que
  /// todo lo que no se toca (tipografia, radios, paddings) siga siendo el de la
  /// app y no una copia que se desincroniza.
  ThemeData _temaEditado() {
    final base = buildBentoTheme(_metal, brightness: _brillo);
    final c = _colores;
    return base.copyWith(
      scaffoldBackgroundColor: c[kBandeja],
      colorScheme: base.colorScheme.copyWith(
        surface: c[kPozo],
        onSurface: c[kTextoEnPozo],
        onSurfaceVariant: c[kTexto2EnPozo],
        primary: c[kAcento],
        onPrimary: c[kSobreAcento],
        primaryContainer: c[kAcento],
        onPrimaryContainer: c[kSobreAcento],
        outline: c[kBorde],
        surfaceContainerLowest: c[kPozo],
        surfaceContainerLow: c[kPozo],
        surfaceContainer: c[kPozo],
        surfaceContainerHigh: c[kPozo],
        surfaceContainerHighest: c[kPozo],
      ),
      cardTheme: base.cardTheme.copyWith(color: c[kPozo]),
      extensions: [
        BentoLaca(
          bandeja: c[kBandeja]!,
          paredCresta: c[kBorde]!,
          pozo: c[kPozo]!,
          pozoContacto: c[kPozoContacto]!,
          textoEnBandeja: c[kTextoEnBandeja]!,
          textoAtenuadoEnBandeja: c[kTexto2EnBandeja]!,
        ),
      ],
    );
  }

  Future<void> _exportar() async {
    final destino = File(
      Platform.environment['VULP_SANDBOX_OUT'] ??
          '${Platform.environment['HOME']}/.cache/vulptiketing/sandbox-config.json',
    );
    await destino.parent.create(recursive: true);

    final datos = {
      'exportado': DateTime.now().toIso8601String(),
      'modo': _brillo.name,
      'metal': _metal.name,
      'tallado': {
        'profundidad': _profundidad,
        'fusionConElFondo': _fusion,
        'luzIntensidad': _luzIntensidad,
        'sombraIntensidad': _sombraIntensidad,
      },
      'colores': {
        for (final t in _ordenTokens) t: _hex(_colores[t]!),
      },
      'contrastes': {
        for (final t in _ordenTokens)
          t: {
            'contra': _fondoDeReferencia[t],
            'ratio': double.parse(
              _contraste(_colores[t]!, _colores[_fondoDeReferencia[t]!]!).toStringAsFixed(2),
            ),
            'minimo': _umbralDe[t],
          },
      },
      'detalle': _detalle.text,
    };

    await destino.writeAsString(const JsonEncoder.withIndent('  ').convert(datos));
    setState(() => _ultimaExportacion = destino.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_colores.isEmpty) return const SizedBox.shrink();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _temaEditado(),
      home: _SandboxScreen(
        brillo: _brillo,
        metal: _metal,
        profundidad: _profundidad,
        fusion: _fusion,
        luzIntensidad: _luzIntensidad,
        sombraIntensidad: _sombraIntensidad,
        colores: _colores,
        tokenActivo: _tokenActivo,
        detalle: _detalle,
        ultimaExportacion: _ultimaExportacion,
        onBrillo: (v) => setState(() {
          _brillo = v;
          _resincronizar();
        }),
        onMetal: (v) => setState(() {
          _metal = v;
          _resincronizar();
        }),
        onProfundidad: (v) => setState(() => _profundidad = v),
        onFusion: (v) => setState(() => _fusion = v),
        onLuz: (v) => setState(() => _luzIntensidad = v),
        onSombra: (v) => setState(() => _sombraIntensidad = v),
        onToken: (v) => setState(() => _tokenActivo = v),
        onColor: (token, color) => setState(() => _colores[token] = color),
        onResincronizar: () => setState(_resincronizar),
        onExportar: _exportar,
      ),
    );
  }
}

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _deHex(String texto) {
  var s = texto.trim().replaceAll('#', '');
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final alto = la > lb ? la : lb;
  final bajo = la > lb ? lb : la;
  return (alto + 0.05) / (bajo + 0.05);
}

/// Los tres tratamientos a comparar, mas el plano como linea base.
enum Tratamiento {
  plano,

  /// Incision: el borde de arriba queda en sombra y el de abajo atrapa luz,
  /// como una letra grabada en la superficie con luz desde arriba.
  tallado,

  /// Lo contrario: el glifo sobresale de la superficie. Se incluye para
  /// comparar, porque a veces lo que uno cree "hundido" es en realidad esto.
  realzado,
}

/// Aplica el tratamiento de profundidad a CUALQUIER hijo (texto, icono, forma)
/// apilando dos copias tintadas y desplazadas detras del original.
///
/// `ColorFiltered` con `srcATop` respeta el alfa del hijo, asi que funciona
/// igual para un glifo de texto, un icono de Material o un SVG — no hace falta
/// una version por tipo de widget.
class Tallado extends StatelessWidget {
  const Tallado({
    super.key,
    required this.child,
    required this.tratamiento,
    required this.profundidad,
    required this.luz,
    required this.sombra,
  });

  final Widget child;
  final Tratamiento tratamiento;
  final double profundidad;
  final Color luz;
  final Color sombra;

  @override
  Widget build(BuildContext context) {
    if (tratamiento == Tratamiento.plano || profundidad <= 0) return child;

    final invertir = tratamiento == Tratamiento.realzado;
    final dy = profundidad;

    Widget capa(Color color, double desplazamiento) {
      return Transform.translate(
        offset: Offset(0, desplazamiento),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcATop),
          child: child,
        ),
      );
    }

    return Stack(
      children: [
        capa(invertir ? luz : sombra, invertir ? dy : -dy),
        capa(invertir ? sombra : luz, invertir ? -dy : dy),
        child,
      ],
    );
  }
}

class _SandboxScreen extends StatelessWidget {
  const _SandboxScreen({
    required this.brillo,
    required this.metal,
    required this.profundidad,
    required this.fusion,
    required this.luzIntensidad,
    required this.sombraIntensidad,
    required this.colores,
    required this.tokenActivo,
    required this.detalle,
    required this.ultimaExportacion,
    required this.onBrillo,
    required this.onMetal,
    required this.onProfundidad,
    required this.onFusion,
    required this.onLuz,
    required this.onSombra,
    required this.onToken,
    required this.onColor,
    required this.onResincronizar,
    required this.onExportar,
  });

  final Brightness brillo;
  final AcentoTinte metal;
  final double profundidad;
  final double fusion;
  final double luzIntensidad;
  final double sombraIntensidad;
  final Map<String, Color> colores;
  final String tokenActivo;
  final TextEditingController detalle;
  final String? ultimaExportacion;
  final ValueChanged<Brightness> onBrillo;
  final ValueChanged<AcentoTinte> onMetal;
  final ValueChanged<double> onProfundidad;
  final ValueChanged<double> onFusion;
  final ValueChanged<double> onLuz;
  final ValueChanged<double> onSombra;
  final ValueChanged<String> onToken;
  final void Function(String token, Color color) onColor;
  final VoidCallback onResincronizar;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final scheme = Theme.of(context).colorScheme;

    Color glifoEn(Color fondo, Color base) => Color.lerp(base, fondo, fusion)!;
    Color luzDe(Color fondo) => Color.lerp(fondo, Colors.white, luzIntensidad)!;
    Color sombraDe(Color fondo) => Color.lerp(fondo, Colors.black, sombraIntensidad)!;

    return Scaffold(
      body: BentoBandeja(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel de control fijo a la izquierda: al editar colores conviene
            // no perder de vista las muestras, asi que no va arriba en el flujo.
            SizedBox(
              width: 380,
              child: _PanelControl(
                brillo: brillo,
                metal: metal,
                profundidad: profundidad,
                fusion: fusion,
                luzIntensidad: luzIntensidad,
                sombraIntensidad: sombraIntensidad,
                colores: colores,
                tokenActivo: tokenActivo,
                detalle: detalle,
                ultimaExportacion: ultimaExportacion,
                onBrillo: onBrillo,
                onMetal: onMetal,
                onProfundidad: onProfundidad,
                onFusion: onFusion,
                onLuz: onLuz,
                onSombra: onSombra,
                onToken: onToken,
                onColor: onColor,
                onResincronizar: onResincronizar,
                onExportar: onExportar,
              ),
            ),
            const SizedBox(width: BentoSpacing.pared),
            Expanded(
              child: ListView(
                children: [
                  _Seccion(
                    titulo: 'Texto sobre POZO — tres tratamientos',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in Tratamiento.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: BentoSpacing.pared),
                              child: BentoPozo(
                                child: _MuestraTexto(
                                  tratamiento: t,
                                  profundidad: profundidad,
                                  fondo: laca.pozo,
                                  colorGlifo: glifoEn(laca.pozo, scheme.onSurface),
                                  luz: luzDe(laca.pozo),
                                  sombra: sombraDe(laca.pozo),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Seccion(
                    titulo: 'Texto sobre la BANDEJA (sin pozo)',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in Tratamiento.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
                              child: _MuestraTexto(
                                tratamiento: t,
                                profundidad: profundidad,
                                fondo: laca.bandeja,
                                colorGlifo: glifoEn(laca.bandeja, laca.textoEnBandeja),
                                luz: luzDe(laca.bandeja),
                                sombra: sombraDe(laca.bandeja),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Seccion(
                    titulo: 'Iconos — hoy flotan encima del fondo',
                    child: Row(
                      children: [
                        for (final t in Tratamiento.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: BentoSpacing.pared),
                              child: BentoPozo(
                                child: Column(
                                  children: [
                                    Wrap(
                                      spacing: BentoSpacing.gapCelda,
                                      runSpacing: BentoSpacing.unidad,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        for (final icono in [
                                          Icons.shopping_cart_outlined,
                                          Icons.bar_chart,
                                          Icons.settings_outlined,
                                          Icons.inventory_2_outlined,
                                        ])
                                          Tallado(
                                            tratamiento: t,
                                            profundidad: profundidad,
                                            luz: luzDe(laca.pozo),
                                            sombra: sombraDe(laca.pozo),
                                            child: Icon(
                                              icono,
                                              size: 34,
                                              color: glifoEn(laca.pozo, scheme.onSurface),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: BentoSpacing.unidad),
                                    _Etiqueta(t.name),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Seccion(
                    titulo: 'Formas y tamanos distintos',
                    child: SizedBox(
                      height: 240,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: BentoPozo(
                              padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Etiqueta('hero 3x2'),
                                  const Spacer(),
                                  Tallado(
                                    tratamiento: Tratamiento.tallado,
                                    profundidad: profundidad,
                                    luz: luzDe(laca.pozo),
                                    sombra: sombraDe(laca.pozo),
                                    child: Text(
                                      '₡128 400',
                                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                            color: glifoEn(laca.pozo, scheme.onSurface),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: BentoSpacing.pared),
                          Expanded(
                            child: Column(
                              children: [
                                for (final etiqueta in ['1x1', '1x1'])
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: BentoSpacing.pared),
                                      child: BentoPozo(child: Center(child: _Etiqueta(etiqueta))),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: BentoSpacing.pared),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                BentoPozo(
                                  radio: 100,
                                  padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
                                  child: Center(child: _Etiqueta('circulo')),
                                ),
                                BentoPozo(
                                  radio: 100,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: BentoSpacing.paddingCeldaGrande,
                                    vertical: BentoSpacing.unidad,
                                  ),
                                  child: Center(child: _Etiqueta('pill')),
                                ),
                                BentoPozo(
                                  seleccionado: true,
                                  child: Center(child: _Etiqueta('seleccionado')),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _Seccion(
                    titulo: 'Escala tipografica completa, tallada',
                    child: BentoPozo(
                      padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final par in [
                            ('displaySmall 40', Theme.of(context).textTheme.displaySmall),
                            ('headlineSmall 24', Theme.of(context).textTheme.headlineSmall),
                            ('titleLarge 20', Theme.of(context).textTheme.titleLarge),
                            ('bodyLarge 16', Theme.of(context).textTheme.bodyLarge),
                            ('bodyMedium 14', Theme.of(context).textTheme.bodyMedium),
                            ('bodySmall 12', Theme.of(context).textTheme.bodySmall),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: BentoSpacing.unidad),
                              child: Tallado(
                                tratamiento: Tratamiento.tallado,
                                profundidad: profundidad,
                                luz: luzDe(laca.pozo),
                                sombra: sombraDe(laca.pozo),
                                child: Text(
                                  'Casado con bistec — ${par.$1}',
                                  style: par.$2?.copyWith(
                                    color: glifoEn(laca.pozo, scheme.onSurface),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Botones y acento, que son donde el metal se ve de verdad.
                  _Seccion(
                    titulo: 'Acento en uso',
                    child: BentoPozo(
                      padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
                      child: Wrap(
                        spacing: BentoSpacing.gapCelda,
                        runSpacing: BentoSpacing.unidad,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton(onPressed: () {}, child: const Text('Finalizar venta')),
                          TextButton(onPressed: () {}, child: const Text('Cancelar')),
                          Icon(Icons.check_circle, color: scheme.primary, size: 32),
                          Text('total', style: TextStyle(color: scheme.primary, fontSize: 20)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: BentoSpacing.rim),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelControl extends StatelessWidget {
  const _PanelControl({
    required this.brillo,
    required this.metal,
    required this.profundidad,
    required this.fusion,
    required this.luzIntensidad,
    required this.sombraIntensidad,
    required this.colores,
    required this.tokenActivo,
    required this.detalle,
    required this.ultimaExportacion,
    required this.onBrillo,
    required this.onMetal,
    required this.onProfundidad,
    required this.onFusion,
    required this.onLuz,
    required this.onSombra,
    required this.onToken,
    required this.onColor,
    required this.onResincronizar,
    required this.onExportar,
  });

  final Brightness brillo;
  final AcentoTinte metal;
  final double profundidad;
  final double fusion;
  final double luzIntensidad;
  final double sombraIntensidad;
  final Map<String, Color> colores;
  final String tokenActivo;
  final TextEditingController detalle;
  final String? ultimaExportacion;
  final ValueChanged<Brightness> onBrillo;
  final ValueChanged<AcentoTinte> onMetal;
  final ValueChanged<double> onProfundidad;
  final ValueChanged<double> onFusion;
  final ValueChanged<double> onLuz;
  final ValueChanged<double> onSombra;
  final ValueChanged<String> onToken;
  final void Function(String token, Color color) onColor;
  final VoidCallback onResincronizar;
  final Future<void> Function() onExportar;

  @override
  Widget build(BuildContext context) {
    final activo = colores[tokenActivo]!;
    final hsl = HSLColor.fromColor(activo);
    final fondoRef = colores[_fondoDeReferencia[tokenActivo]!]!;
    final ratio = _contraste(activo, fondoRef);
    final umbral = _umbralDe[tokenActivo]!;

    // Exportar y el detalle van FIJOS al fondo, no dentro del scroll: es la
    // accion principal del banco y quedaba debajo del pliegue.
    return Column(
      children: [
        Expanded(child: _scroll(context, activo, hsl, ratio, umbral)),
        const SizedBox(height: BentoSpacing.pared),
        _detalleYExportar(context),
      ],
    );
  }

  Widget _detalleYExportar(BuildContext context) {
    return BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: detalle,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Detalle',
              hintText: 'Qué te gusta, qué no, dónde aplicarlo y dónde no…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: BentoSpacing.gapCelda),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onExportar,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Exportar'),
                ),
              ),
              const SizedBox(width: BentoSpacing.unidad),
              TextButton(onPressed: onResincronizar, child: const Text('Restaurar')),
            ],
          ),
          if (ultimaExportacion != null) ...[
            const SizedBox(height: BentoSpacing.unidad),
            SelectableText(
              'Guardado en:\n$ultimaExportacion',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scroll(
    BuildContext context,
    Color activo,
    HSLColor hsl,
    double ratio,
    double umbral,
  ) {
    return ListView(
      children: [
        BentoPozo(
          padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<Brightness>(
                segments: const [
                  ButtonSegment(value: Brightness.light, label: Text('Claro')),
                  ButtonSegment(value: Brightness.dark, label: Text('Oscuro')),
                ],
                selected: {brillo},
                onSelectionChanged: (s) => onBrillo(s.first),
              ),
              const SizedBox(height: BentoSpacing.unidad),
              SegmentedButton<AcentoTinte>(
                segments: const [
                  ButtonSegment(value: AcentoTinte.oro, label: Text('Oro')),
                  ButtonSegment(value: AcentoTinte.cobre, label: Text('Cobre')),
                  ButtonSegment(value: AcentoTinte.peltre, label: Text('Peltre')),
                ],
                selected: {metal},
                onSelectionChanged: (s) => onMetal(s.first),
              ),
              const SizedBox(height: BentoSpacing.unidad),
              Text(
                'Cambiar modo o metal recarga los colores del tema y descarta '
                'las ediciones — exportá antes.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BentoSpacing.pared),

        // --- Colores -------------------------------------------------------
        _Seccion(
          titulo: 'Colores',
          child: BentoPozo(
            padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lista de tokens con su muestra: se elige cual editar.
                for (final token in _ordenTokens)
                  InkWell(
                    onTap: () => onToken(token),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: colores[token],
                              borderRadius: BorderRadius.circular(BentoRadius.pozo),
                              border: Border.all(
                                color: token == tokenActivo
                                    ? Theme.of(context).colorScheme.primary
                                    : lacaDe(context).paredCresta,
                                width: token == tokenActivo ? 2 : 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: BentoSpacing.unidad),
                          Expanded(
                            child: Text(
                              token,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: token == tokenActivo
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                            ),
                          ),
                          Text(
                            _hex(colores[token]!),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: BentoSpacing.gapCelda),

                Text(
                  'Editando: $tokenActivo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: BentoSpacing.unidad),
                _SelectorColor(
                  color: activo,
                  onChanged: (c) => onColor(tokenActivo, c),
                ),
                const SizedBox(height: BentoSpacing.gapCelda),
                // El hex queda como salida, no como forma de entrada: sirve
                // para copiar un valor o pegar uno exacto si ya lo tenes.
                _CampoHex(
                  key: ValueKey(tokenActivo),
                  valor: _hex(activo),
                  onValido: (c) => onColor(tokenActivo, c),
                ),
                const SizedBox(height: BentoSpacing.unidad),
                Text(
                  'contraste contra ${_fondoDeReferencia[tokenActivo]}: '
                  '${ratio.toStringAsFixed(2)}:1 (min $umbral)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ratio >= umbral
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ),
          ),
        ),

        // --- Tallado -------------------------------------------------------
        _Seccion(
          titulo: 'Tallado',
          child: BentoPozo(
            padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Deslizador(
                  etiqueta: 'profundidad (px)',
                  valor: profundidad,
                  min: 0,
                  max: 4,
                  divisiones: 16,
                  onChanged: onProfundidad,
                ),
                _Deslizador(
                  etiqueta: 'fusion con el fondo',
                  valor: fusion,
                  min: 0,
                  max: 1,
                  divisiones: 20,
                  onChanged: onFusion,
                ),
                _Deslizador(
                  etiqueta: 'intensidad de la luz',
                  valor: luzIntensidad,
                  min: 0,
                  max: 1,
                  divisiones: 20,
                  onChanged: onLuz,
                ),
                _Deslizador(
                  etiqueta: 'intensidad de la sombra',
                  valor: sombraIntensidad,
                  min: 0,
                  max: 1,
                  divisiones: 20,
                  onChanged: onSombra,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Selector de color visual: area de saturacion/luminosidad con cruz
/// arrastrable, y barra de espectro para el matiz.
///
/// Reemplaza a tres sliders abstractos de HSL, que exigian imaginarse el
/// resultado antes de verlo — inservibles si no andas pensando en numeros.
/// Aca se elige el color mirandolo.
class _SelectorColor extends StatelessWidget {
  const _SelectorColor({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  static const _altoArea = 150.0;
  static const _altoBarra = 26.0;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final radio = BorderRadius.circular(BentoRadius.pozo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Area 2D: horizontal = saturacion, vertical = luminosidad.
        LayoutBuilder(
          builder: (context, limites) {
            final ancho = limites.maxWidth;

            void actualizar(Offset p) {
              final s = (p.dx / ancho).clamp(0.0, 1.0);
              final l = (1 - p.dy / _altoArea).clamp(0.0, 1.0);
              onChanged(hsl.withSaturation(s).withLightness(l).toColor());
            }

            return GestureDetector(
              onPanDown: (d) => actualizar(d.localPosition),
              onPanUpdate: (d) => actualizar(d.localPosition),
              child: SizedBox(
                height: _altoArea,
                width: ancho,
                child: Stack(
                  children: [
                    // Dos degradados superpuestos aproximan el espacio HSL sin
                    // tener que pintar pixel por pixel: saturacion en el eje X,
                    // blanco arriba y negro abajo en el eje Y.
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: radio,
                        gradient: LinearGradient(
                          colors: [
                            HSLColor.fromAHSL(1, hsl.hue, 0, 0.5).toColor(),
                            HSLColor.fromAHSL(1, hsl.hue, 1, 0.5).toColor(),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: radio,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Colors.transparent, Colors.black],
                          stops: [0, 0.5, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hsl.saturation * ancho - 8).clamp(0.0, ancho - 16),
                      top: ((1 - hsl.lightness) * _altoArea - 8).clamp(0.0, _altoArea - 16),
                      child: _Cruz(color: color),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: BentoSpacing.unidad),
        // Barra de matiz.
        LayoutBuilder(
          builder: (context, limites) {
            final ancho = limites.maxWidth;

            void actualizar(Offset p) {
              final h = (p.dx / ancho * 360).clamp(0.0, 359.9);
              onChanged(hsl.withHue(h).toColor());
            }

            return GestureDetector(
              onPanDown: (d) => actualizar(d.localPosition),
              onPanUpdate: (d) => actualizar(d.localPosition),
              child: SizedBox(
                height: _altoBarra,
                width: ancho,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: radio,
                        gradient: LinearGradient(
                          colors: [
                            for (var i = 0; i <= 6; i++)
                              HSLColor.fromAHSL(1, (i * 60) % 360, 1, 0.5).toColor(),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hsl.hue / 360 * ancho - 8).clamp(0.0, ancho - 16),
                      top: (_altoBarra - 16) / 2,
                      child: _Cruz(color: HSLColor.fromAHSL(1, hsl.hue, 1, 0.5).toColor()),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Marcador de posicion del selector. Anillo blanco con borde negro para que
/// se vea sobre cualquier color de fondo, claro u oscuro.
class _Cruz extends StatelessWidget {
  const _Cruz({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26),
        ),
      ),
    );
  }
}

/// Campo hex con estado propio para no pelear con el texto que el usuario esta
/// escribiendo: solo avisa cuando el valor parsea a un color valido.
class _CampoHex extends StatefulWidget {
  const _CampoHex({super.key, required this.valor, required this.onValido});

  final String valor;
  final ValueChanged<Color> onValido;

  @override
  State<_CampoHex> createState() => _CampoHexState();
}

class _CampoHexState extends State<_CampoHex> {
  late final TextEditingController _c = TextEditingController(text: widget.valor);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      decoration: const InputDecoration(
        labelText: 'hex',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        final c = _deHex(v);
        if (c != null) widget.onValido(c);
      },
    );
  }
}

class _MuestraTexto extends StatelessWidget {
  const _MuestraTexto({
    required this.tratamiento,
    required this.profundidad,
    required this.fondo,
    required this.colorGlifo,
    required this.luz,
    required this.sombra,
  });

  final Tratamiento tratamiento;
  final double profundidad;
  final Color fondo;
  final Color colorGlifo;
  final Color luz;
  final Color sombra;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final ratio = _contraste(colorGlifo, fondo);

    Widget muestra(String texto, TextStyle? estilo) {
      return Tallado(
        tratamiento: tratamiento,
        profundidad: profundidad,
        luz: luz,
        sombra: sombra,
        child: Text(texto, style: estilo?.copyWith(color: colorGlifo)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Etiqueta(tratamiento.name),
        const SizedBox(height: BentoSpacing.unidad),
        muestra('₡3 800', tema.headlineSmall),
        const SizedBox(height: BentoSpacing.unidad / 2),
        muestra('Casado con chuleta', tema.bodyLarge),
        const SizedBox(height: BentoSpacing.unidad / 2),
        muestra('etiqueta pequena', tema.bodySmall),
        const SizedBox(height: BentoSpacing.unidad),
        Text(
          '${ratio.toStringAsFixed(2)}:1  ${ratio >= 4.5 ? 'AA' : 'por debajo de AA'}',
          style: tema.bodySmall?.copyWith(
            color: ratio >= 4.5
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: BentoSpacing.gapGrupo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: laca.textoEnBandeja),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          child,
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _Deslizador extends StatelessWidget {
  const _Deslizador({
    required this.etiqueta,
    required this.valor,
    required this.min,
    required this.max,
    required this.divisiones,
    required this.onChanged,
  });

  final String etiqueta;
  final double valor;
  final double min;
  final double max;
  final int divisiones;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Etiqueta('$etiqueta: ${valor.toStringAsFixed(2)}'),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: valor.clamp(min, max),
            min: min,
            max: max,
            divisions: divisiones,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
