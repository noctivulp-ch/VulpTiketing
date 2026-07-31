// Laboratorio del feedback táctil. NO es parte de la app.
//
// Vive en test_driver/ por la misma razón que el diagnóstico: así no puede
// entrar en un build de release. No importa nada de `lib/features/` — solo el
// tema, que es lo que se está probando.
//
// Uso:
//   flutter run -t test_driver/lab_toque.dart -d <dispositivo>
//
// Sirve para decidir textura, ritmo y tintes tocando de verdad, en el aparato
// y con la luz real, en vez de discutirlo leyendo código. Cuando una
// combinación convence, el panel imprime la receta lista para pegar en
// `buildBentoTheme` (parámetro `toque`).
//
// Cada superficie de prueba es una de las que existen en la app —pozo,
// pozo seleccionado, botón, fondo de bandeja— porque el toque se ve distinto
// según lo que tenga debajo, y ese fue justamente el malentendido que hizo
// falta aclarar: sobre un elemento oscuro el mismo tono se lee cálido y sobre
// uno claro se lee blanco.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_ink.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

void main() => runApp(const LabToqueApp());

class LabToqueApp extends StatefulWidget {
  const LabToqueApp({super.key});

  @override
  State<LabToqueApp> createState() => _LabToqueAppState();
}

class _LabToqueAppState extends State<LabToqueApp> {
  BentoToqueReceta _receta = const BentoToqueReceta();
  AcentoTinte _acento = AcentoTinte.cobre;
  Brightness _brillo = Brightness.dark;

  @override
  void initState() {
    super.initState();
    _restaurar();
  }

  // Los ajustes sobreviven a cerrar la app. Se perdieron una vez al salir sin
  // querer, y encontrar de nuevo una combinación a ojo cuesta más que
  // guardarla.
  Future<void> _restaurar() async {
    final prefs = await SharedPreferences.getInstance();
    final textura = prefs.getString('textura');
    if (!mounted) return;
    setState(() {
      _acento = AcentoTinte.values.firstWhere(
        (a) => a.name == prefs.getString('acento'),
        orElse: () => _acento,
      );
      _brillo = prefs.getBool('oscuro') ?? true ? Brightness.dark : Brightness.light;
      _receta = BentoToqueReceta(
        textura: BentoToqueTextura.values.firstWhere(
          (t) => t.name == textura,
          orElse: () => _receta.textura,
        ),
        duracion: Duration(
          milliseconds: prefs.getInt('duracion') ?? _receta.duracion.inMilliseconds,
        ),
        opacidad: prefs.getDouble('opacidad') ?? _receta.opacidad,
        fusion: prefs.getDouble('fusion') ?? _receta.fusion,
        borde: prefs.getDouble('borde') ?? _receta.borde,
        separacion: prefs.getDouble('separacion') ?? _receta.separacion,
      );
    });
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('textura', _receta.textura.name);
    await prefs.setInt('duracion', _receta.duracion.inMilliseconds);
    await prefs.setDouble('opacidad', _receta.opacidad);
    await prefs.setDouble('fusion', _receta.fusion);
    await prefs.setDouble('borde', _receta.borde);
    await prefs.setDouble('separacion', _receta.separacion);
    await prefs.setString('acento', _acento.name);
    await prefs.setBool('oscuro', _brillo == Brightness.dark);
  }

  void _cambiar(VoidCallback cambio) {
    setState(cambio);
    _guardar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = buildBentoTheme(_acento, brightness: _brillo, toque: _receta);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: tema,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(BentoSpacing.pared),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _Superficies(receta: _receta)),
                const SizedBox(height: BentoSpacing.pared),
                Expanded(
                  child: _Controles(
                    receta: _receta,
                    acento: _acento,
                    brillo: _brillo,
                    onReceta: (r) => _cambiar(() => _receta = r),
                    onAcento: (a) => _cambiar(() => _acento = a),
                    onBrillo: (b) => _cambiar(() => _brillo = b),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Superficies extends StatelessWidget {
  const _Superficies({required this.receta});

  final BentoToqueReceta receta;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final superficies = [
      BentoPozo(
        onTap: () {},
        child: const Center(child: Text('Pozo', textAlign: TextAlign.center)),
      ),
      BentoPozo(
        onTap: () {},
        seleccionado: true,
        child: const Center(child: Text('Pozo elegido', textAlign: TextAlign.center)),
      ),
      FilledButton(
        onPressed: () {},
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(double.infinity)),
        child: const Text('Botón', textAlign: TextAlign.center),
      ),
      // El fondo de bandeja también recibe toques (la banda de navegación vive
      // ahí), y ahí el contraste es el peor caso.
      Material(
        color: laca.bandeja,
        child: InkWell(
          onTap: () {},
          child: Center(
            child: Text(
              'Bandeja',
              textAlign: TextAlign.center,
              style: TextStyle(color: laca.textoEnBandeja),
            ),
          ),
        ),
      ),
    ];

    // Dos por fila de pie y cuatro acostado: en columnas de 90 dp la onda no se
    // aprecia, que es justamente lo que hay que mirar acá.
    return LayoutBuilder(
      builder: (context, restricciones) {
        final porFila = restricciones.maxWidth < 600 ? 2 : 4;
        return GridView.count(
          crossAxisCount: porFila,
          mainAxisSpacing: BentoSpacing.pared,
          crossAxisSpacing: BentoSpacing.pared,
          childAspectRatio: restricciones.maxWidth / porFila / (restricciones.maxHeight / 2),
          physics: const NeverScrollableScrollPhysics(),
          children: superficies,
        );
      },
    );
  }
}

class _Controles extends StatelessWidget {
  const _Controles({
    required this.receta,
    required this.acento,
    required this.brillo,
    required this.onReceta,
    required this.onAcento,
    required this.onBrillo,
  });

  final BentoToqueReceta receta;
  final AcentoTinte acento;
  final Brightness brillo;
  final ValueChanged<BentoToqueReceta> onReceta;
  final ValueChanged<AcentoTinte> onAcento;
  final ValueChanged<Brightness> onBrillo;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      child: ListView(
        children: [
          Wrap(
            spacing: BentoSpacing.unidad,
            runSpacing: BentoSpacing.unidad,
            children: [
              SegmentedButton<BentoToqueTextura>(
                showSelectedIcon: false,
                segments: [
                  for (final t in BentoToqueTextura.values)
                    ButtonSegment(value: t, label: Text(t.name)),
                ],
                selected: {receta.textura},
                onSelectionChanged: (s) => onReceta(receta.copyWith(textura: s.first)),
              ),
              SegmentedButton<AcentoTinte>(
                showSelectedIcon: false,
                segments: [
                  for (final a in AcentoTinte.values) ButtonSegment(value: a, label: Text(a.name)),
                ],
                selected: {acento},
                onSelectionChanged: (s) => onAcento(s.first),
              ),
              SegmentedButton<Brightness>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Brightness.dark, label: Text('oscuro')),
                  ButtonSegment(value: Brightness.light, label: Text('claro')),
                ],
                selected: {brillo},
                onSelectionChanged: (s) => onBrillo(s.first),
              ),
            ],
          ),
          _Dial(
            nombre: 'duración',
            valor: receta.duracion.inMilliseconds.toDouble(),
            min: 80,
            max: 900,
            sufijo: 'ms',
            onCambio: (v) => onReceta(receta.copyWith(duracion: Duration(milliseconds: v.round()))),
          ),
          _Dial(
            nombre: 'opacidad',
            valor: receta.opacidad,
            min: 0.05,
            max: 1,
            onCambio: (v) => onReceta(receta.copyWith(opacidad: v)),
          ),
          _Dial(
            nombre: 'fusión del relleno',
            valor: receta.fusion,
            min: 0,
            max: 1,
            onCambio: (v) => onReceta(receta.copyWith(fusion: v)),
          ),
          _Dial(
            nombre: 'separación del tono',
            valor: receta.separacion,
            min: 0,
            max: 1,
            onCambio: (v) => onReceta(receta.copyWith(separacion: v)),
          ),
          _Dial(
            nombre: 'cresta en el frente',
            valor: receta.borde,
            min: 0,
            max: 1,
            onCambio: (v) => onReceta(receta.copyWith(borde: v)),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          SelectableText(receta.toString(), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.nombre,
    required this.valor,
    required this.min,
    required this.max,
    required this.onCambio,
    this.sufijo = '',
  });

  final String nombre;
  final double valor;
  final double min;
  final double max;
  final ValueChanged<double> onCambio;
  final String sufijo;

  @override
  Widget build(BuildContext context) {
    final texto = sufijo.isEmpty ? valor.toStringAsFixed(2) : '${valor.round()}$sufijo';
    return Row(
      children: [
        SizedBox(width: 150, child: Text('$nombre  $texto')),
        Expanded(
          child: Slider(value: valor, min: min, max: max, onChanged: onCambio),
        ),
      ],
    );
  }
}
