import 'package:costeo/costeo.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
import '../config_costeo_model.dart';
import '../costeo_provider.dart';
import 'articulo_detalle.dart';
import 'formato_costeo.dart';

/// El resultado: el negocio arriba y cada artículo debajo, con lo que hoy se
/// cobra contra lo que dice el modelo. Informa; el único botón que escribe
/// vive en el detalle y es por artículo (0040 §4).
class ArticulosCosteados extends ConsumerWidget {
  const ArticulosCosteados({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costeo = ref.watch(costeoProvider);
    return costeo.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => BentoFalla(
        mensaje: 'No se pudo calcular el costeo.',
        error: e,
        onReintentar: () => ref.invalidate(costeoProvider),
      ),
      data: (datos) {
        final r = datos.resultado;
        return ListView(
          padding: const EdgeInsets.all(BentoSpacing.gapCelda),
          children: [
            _Negocio(costeo: datos),
            const SizedBox(height: BentoSpacing.gapCelda),
            for (final a in r.articulos) ...[
              _FilaArticulo(
                calculado: a,
                catalogo: datos.articulos[a.articulo.id]!,
                conFoodCost: datos.registro.tipoNegocio == TipoNegocio.produccion,
                onTap: () => mostrarDetalleArticulo(context, a.articulo.id),
              ),
              const SizedBox(height: BentoSpacing.unidad),
            ],
            if (r.articulos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(BentoSpacing.rim),
                child: Text('El catálogo está vacío: no hay qué costear.', textAlign: TextAlign.center),
              ),
          ],
        );
      },
    );
  }
}

/// Las cifras del negocio a precios ACTUALES y volumen del mes: es lo que
/// pasa hoy, no lo que pasaría con los precios sugeridos.
class _Negocio extends StatelessWidget {
  const _Negocio({required this.costeo});
  final Costeo costeo;

  @override
  Widget build(BuildContext context) {
    final r = costeo.resultado;
    final laca = lacaDe(context);
    final textos = Theme.of(context).textTheme;
    final equilibrioDia = r.unidadesEquilibrioDia(costeo.config.diasAbiertosMes);

    Widget cifra(String etiqueta, String valor) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: textos.bodySmall),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: textos.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    return BentoPozo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Últimos $diasDeVolumen días, a los precios de hoy', style: textos.bodySmall),
          const SizedBox(height: BentoSpacing.unidad / 2),
          BentoTextoTallado(
            'Utilidad ${colones(context, r.utilidadMes)}',
            sobre: laca.pozo,
            nivel: TalladoNivel.marcado,
            estilo: textos.headlineSmall,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          Row(
            children: [
              cifra('Ingreso', colones(context, r.ingresoMes)),
              cifra('Costos fijos', colones(context, r.costosFijosMes)),
              cifra('Margen neto', porcentaje(r.margenNetoPromedio)),
            ],
          ),
          const SizedBox(height: BentoSpacing.unidad),
          Row(
            children: [
              cifra('Unidades', '${r.totalUnidadesMes}'),
              cifra('Equilibrio', r.unidadesEquilibrio == null ? '—' : '${r.unidadesEquilibrio!.ceil()} u'),
              cifra('Por día', equilibrioDia == null ? '—' : '${equilibrioDia.ceil()} u'),
            ],
          ),
          const SizedBox(height: BentoSpacing.unidad),
          // Las dos cifras que piden un plan de negocio y el oficio: cuánto hay
          // que VENDER en dinero para no perder, y qué parte de cada venta se
          // va en ingredientes.
          Row(
            children: [
              cifra('Equilibrio en dinero', r.ingresoEquilibrio == null ? '—' : colones(context, r.ingresoEquilibrio!)),
              // El food cost es del oficio de la comida; en servicios no dice nada.
              if (costeo.registro.tipoNegocio == TipoNegocio.produccion)
                cifra('Food cost', r.foodCostPromedio == null ? '—' : porcentaje(r.foodCostPromedio)),
            ],
          ),
          if (r.impuestoSobrePrecioMes > 0) ...[
            const SizedBox(height: BentoSpacing.unidad / 2),
            Text('IVA dentro de lo vendido: ${colones(context, r.impuestoSobrePrecioMes)}', style: textos.bodySmall),
          ],
          if (r.colchon != null) ...[
            const SizedBox(height: BentoSpacing.unidad / 2),
            Text(
              r.colchon! >= 0
                  ? 'La venta puede caer ${porcentaje(r.colchon)} antes de entrar en pérdida.'
                  : 'Falta ${porcentaje(-r.colchon!)} de venta para cubrir los costos fijos.',
              style: textos.bodySmall,
            ),
          ],
          const SizedBox(height: BentoSpacing.unidad),
          // Escenarios sobre el volumen. Los costos fijos no escalan: con un
          // 20 % menos de venta la utilidad puede caer mucho más que un 20 %,
          // y eso es lo que hay que ver antes de que pase.
          _Escenarios(resultado: r),
          for (final a in r.alertasGlobales) ...[
            const SizedBox(height: BentoSpacing.unidad / 2),
            Text('⚠ ${a.mensaje}', style: textos.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _Escenarios extends StatelessWidget {
  const _Escenarios({required this.resultado});
  final c.ResultadoCosteo resultado;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    if (resultado.totalUnidadesMes <= 0) return const SizedBox.shrink();
    final escenarios = [
      ('Si cae 20 %', resultado.escenario(0.8)),
      ('Como va', resultado.escenario(1.0)),
      ('Si sube 20 %', resultado.escenario(1.2)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Escenarios del mes', style: textos.labelLarge),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Row(
          children: [
            for (final (nombre, e) in escenarios)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre, style: textos.bodySmall),
                    Text('${e.unidades} u · ${colones(context, e.ingreso)}', style: textos.bodySmall),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        colones(context, e.utilidad),
                        style: textos.titleSmall?.copyWith(color: e.utilidad < 0 ? error : null, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilaArticulo extends StatelessWidget {
  const _FilaArticulo({required this.calculado, required this.catalogo, required this.conFoodCost, required this.onTap});
  final c.ArticuloCosteado calculado;
  final ArticuloDelCatalogo catalogo;
  final bool conFoodCost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    final a = calculado;
    final margenBajo = a.alertas.contains(c.Alerta.margenBajoObjetivo) || a.alertas.contains(c.Alerta.seVendeAPerdida);
    final avisos = a.alertas.where((x) => x != c.Alerta.margenBajoObjetivo && x != c.Alerta.seVendeAPerdida).toList();

    return BentoPozo(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(catalogo.nombre, style: textos.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text(colones(context, a.articulo.precioActual), style: textos.titleSmall),
            ],
          ),
          const SizedBox(height: BentoSpacing.unidad / 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Costo ${colones(context, a.costoTotalUnidad)} · sugerido ${colones(context, a.precioFinal)}',
                  style: textos.bodySmall,
                ),
              ),
              Text(
                a.margenReal == null
                    ? 'sin precio'
                    : 'margen ${porcentaje(a.margenReal)}${a.foodCost == null || !conFoodCost ? '' : ' · fc ${porcentaje(a.foodCost)}'}',
                style: textos.bodySmall?.copyWith(
                  color: margenBajo ? error : null,
                  fontWeight: margenBajo ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
          if (avisos.isNotEmpty) ...[
            const SizedBox(height: BentoSpacing.unidad / 2),
            Text(
              avisos.map((x) => x.esError ? '✗ ${x.mensaje}' : '· ${x.mensaje}').join('\n'),
              style: textos.bodySmall?.copyWith(color: avisos.any((x) => x.esError) ? error : null),
            ),
          ],
        ],
      ),
    );
  }
}
