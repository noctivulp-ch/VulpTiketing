import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/theme/bento_velo.dart';
import 'ajustes_costeo_panel.dart';
import 'articulos_costeados.dart';
import 'costos_fijos_panel.dart';
import 'insumos_panel.dart';

/// Ventana 6 — Costeo (decisión 0040). Solo Gerente: el dashboard no la monta
/// para la Registradora.
///
/// Cuatro secciones en una fila de segmentos, y el contenido debajo: es la
/// misma idea que Configuración (elegir arriba, ver abajo, sin diálogos para
/// navegar). El orden es el del flujo de trabajo: primero se ve el resultado,
/// y las otras tres son lo que hay que cargar para que el resultado diga algo.
class CosteoScreen extends ConsumerStatefulWidget {
  const CosteoScreen({super.key});

  @override
  ConsumerState<CosteoScreen> createState() => _CosteoScreenState();
}

enum _Seccion { articulos, insumos, costosFijos, ajustes }

class _CosteoScreenState extends ConsumerState<CosteoScreen> {
  _Seccion _seccion = _Seccion.articulos;

  @override
  Widget build(BuildContext context) {
    final contenido = switch (_seccion) {
      _Seccion.articulos => const ArticulosCosteados(),
      _Seccion.insumos => const InsumosPanel(),
      _Seccion.costosFijos => const CostosFijosPanel(),
      _Seccion.ajustes => const AjustesCosteoPanel(),
    };
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              BentoSpacing.gapCelda,
              bentoInsetSuperior(context) + BentoSpacing.unidad,
              BentoSpacing.gapCelda,
              BentoSpacing.unidad,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Seccion>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Seccion.articulos, label: Text('Artículos')),
                  ButtonSegment(value: _Seccion.insumos, label: Text('Insumos')),
                  ButtonSegment(value: _Seccion.costosFijos, label: Text('Fijos')),
                  ButtonSegment(value: _Seccion.ajustes, label: Text('Ajustes')),
                ],
                selected: {_seccion},
                onSelectionChanged: (s) => setState(() => _seccion = s.first),
              ),
            ),
          ),
          Expanded(child: contenido),
        ],
      ),
    );
  }
}
