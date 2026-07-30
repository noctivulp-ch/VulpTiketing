// Banco de pruebas de estilo — SOLO desarrollo, sin funcion.
//
// Existe para decidir un look mirandolo, no imaginandolo: elementos de
// distintos tamanos y formas, y el mismo texto/icono bajo varios tratamientos
// de profundidad, con controles en vivo. Adivinar la intensidad correcta desde
// el codigo es exactamente lo que fallo antes.
//
// Vive fuera de lib/ a proposito (igual que test_driver/app.dart): no entra en
// produccion ni en la navegacion de la app.
//
// Correr:
//   VULP_WINDOW_TITLE="vulpedebug — sandbox" \
//     flutter run -t test_driver/sandbox.dart -d linux
//
// Cada muestra de texto imprime su contraste WCAG real contra la superficie
// que tiene debajo, para que la decision estetica se tome sabiendo el costo de
// legibilidad — el tallado se logra acercando el glifo al color del fondo, y
// eso baja el contraste por definicion.
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

void main() {
  // Solo para poder capturar el sandbox desde el bridge (`GET /screenshot`,
  // renderizado por el motor) sin depender del foco ni del monitor.
  // `enableTextEntryEmulation: false` es obligatorio: con el default, mover los
  // sliders con el raton seguiria funcionando pero el teclado quedaria muerto.
  enableFlutterDriverExtension(enableTextEntryEmulation: false);
  runApp(const SandboxApp());
}

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
  /// Es mas facil bajarlo desde algo evidente que buscarlo desde cero.
  double _profundidad = 2;

  /// Cuanto se funde el glifo con su superficie. 0 = color de texto normal
  /// (legible, tallado sutil); 1 = exactamente el color del fondo (el glifo
  /// desaparece y solo lo definen sus bordes: el tallado "puro", precioso e
  /// ilegible). El punto util esta en el medio y es lo que hay que calibrar.
  double _fusion = 0.55;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildBentoTheme(_metal, brightness: _brillo),
      home: _SandboxScreen(
        brillo: _brillo,
        metal: _metal,
        profundidad: _profundidad,
        fusion: _fusion,
        onBrillo: (v) => setState(() => _brillo = v),
        onMetal: (v) => setState(() => _metal = v),
        onProfundidad: (v) => setState(() => _profundidad = v),
        onFusion: (v) => setState(() => _fusion = v),
      ),
    );
  }
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
/// igual para un glifo de texto, un icono de Material o un SVG — no hay que
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

    // Tallado: sombra arriba, luz abajo (la incision recibe luz desde arriba,
    // asi que su pared superior queda oscura y el fondo del surco iluminado).
    // Realzado: al reves.
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

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final alto = la > lb ? la : lb;
  final bajo = la > lb ? lb : la;
  return (alto + 0.05) / (bajo + 0.05);
}

class _SandboxScreen extends StatelessWidget {
  const _SandboxScreen({
    required this.brillo,
    required this.metal,
    required this.profundidad,
    required this.fusion,
    required this.onBrillo,
    required this.onMetal,
    required this.onProfundidad,
    required this.onFusion,
  });

  final Brightness brillo;
  final AcentoTinte metal;
  final double profundidad;
  final double fusion;
  final ValueChanged<Brightness> onBrillo;
  final ValueChanged<AcentoTinte> onMetal;
  final ValueChanged<double> onProfundidad;
  final ValueChanged<double> onFusion;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final scheme = Theme.of(context).colorScheme;

    // El glifo se acerca al color de su fondo segun `fusion`. Ese acercamiento
    // ES el tallado, y tambien ES la perdida de contraste: por eso cada
    // muestra reporta su ratio.
    Color glifoEn(Color fondo, Color base) => Color.lerp(base, fondo, fusion)!;

    // Luz y sombra de la incision, derivadas del fondo y no hardcodeadas, para
    // que el tratamiento funcione igual sobre pozo (rojo/verde) y sobre
    // bandeja (negro/blanco).
    Color luzDe(Color fondo) =>
        Color.lerp(fondo, Colors.white, brillo == Brightness.dark ? 0.45 : 0.95)!;
    Color sombraDe(Color fondo) =>
        Color.lerp(fondo, Colors.black, brillo == Brightness.dark ? 0.80 : 0.45)!;

    return Scaffold(
      body: BentoBandeja(
        child: ListView(
          children: [
            _Controles(
              brillo: brillo,
              metal: metal,
              profundidad: profundidad,
              fusion: fusion,
              onBrillo: onBrillo,
              onMetal: onMetal,
              onProfundidad: onProfundidad,
              onFusion: onFusion,
            ),
            const SizedBox(height: BentoSpacing.pared),

            _Seccion(
              titulo: 'Texto sobre POZO — mismo texto, tres tratamientos',
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
              titulo: 'Texto directamente sobre la BANDEJA (sin pozo)',
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
              titulo: 'Iconos — el punto que planteaste: hoy flotan encima',
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
              titulo: 'Formas y tamanos distintos — el grid asimetrico',
              child: SizedBox(
                height: 260,
                child: Row(
                  children: [
                    // Hero grande con un numero, que es el caso de Reportes.
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
                    // Columna de celdas chicas apiladas.
                    Expanded(
                      child: Column(
                        children: [
                          for (final etiqueta in ['1x1', '1x1', '1x1'])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: BentoSpacing.pared),
                                child: BentoPozo(
                                  child: Center(child: _Etiqueta(etiqueta)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: BentoSpacing.pared),
                    // Formas no rectangulares: circulo y pill, para ver si el
                    // tallado aguanta fuera del rectangulo.
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
              titulo: 'Escala tipografica completa, toda tallada',
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

            const SizedBox(height: BentoSpacing.rim),
          ],
        ),
      ),
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
        // El numero es el punto: el tallado bonito y el texto legible tiran
        // en direcciones opuestas, asi que conviene verlo medido.
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

class _Controles extends StatelessWidget {
  const _Controles({
    required this.brillo,
    required this.metal,
    required this.profundidad,
    required this.fusion,
    required this.onBrillo,
    required this.onMetal,
    required this.onProfundidad,
    required this.onFusion,
  });

  final Brightness brillo;
  final AcentoTinte metal;
  final double profundidad;
  final double fusion;
  final ValueChanged<Brightness> onBrillo;
  final ValueChanged<AcentoTinte> onMetal;
  final ValueChanged<double> onProfundidad;
  final ValueChanged<double> onFusion;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
      child: Wrap(
        spacing: BentoSpacing.gapGrupo,
        runSpacing: BentoSpacing.gapCelda,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<Brightness>(
            segments: const [
              ButtonSegment(value: Brightness.light, label: Text('Claro')),
              ButtonSegment(value: Brightness.dark, label: Text('Oscuro')),
            ],
            selected: {brillo},
            onSelectionChanged: (s) => onBrillo(s.first),
          ),
          SegmentedButton<AcentoTinte>(
            segments: const [
              ButtonSegment(value: AcentoTinte.oro, label: Text('Oro')),
              ButtonSegment(value: AcentoTinte.cobre, label: Text('Cobre')),
              ButtonSegment(value: AcentoTinte.peltre, label: Text('Peltre')),
            ],
            selected: {metal},
            onSelectionChanged: (s) => onMetal(s.first),
          ),
          _Deslizador(
            etiqueta: 'profundidad',
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
        ],
      ),
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
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Etiqueta('$etiqueta: ${valor.toStringAsFixed(2)}'),
          Slider(
            value: valor,
            min: min,
            max: max,
            divisions: divisiones,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
