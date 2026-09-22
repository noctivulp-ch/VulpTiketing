import 'package:costeo/costeo.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_falla.dart';
import '../config_costeo_model.dart';
import '../costeo_notifiers.dart';
import '../costo_de_insumos_provider.dart';
import 'formato_costeo.dart';
import '../../../core/moneda.dart';

/// Los parámetros del negocio. Se guardan con un botón, no campo a campo: son
/// números que se piensan juntos, y cada uno mueve todos los precios.
///
/// Dos pozos: el negocio (margen, merma, mano de obra, redondeo, reparto) y
/// los impuestos y comisiones (0042): régimen, sus factores o tasas, y qué
/// cobra cada medio de pago. En simplificado se muestra el trimestre en
/// curso ya calculado — es lo que se declara.
class AjustesCosteoPanel extends ConsumerStatefulWidget {
  const AjustesCosteoPanel({super.key});

  @override
  ConsumerState<AjustesCosteoPanel> createState() => _AjustesCosteoPanelState();
}

class _AjustesCosteoPanelState extends ConsumerState<AjustesCosteoPanel> {
  final _formKey = GlobalKey<FormState>();
  final _dias = TextEditingController();
  final _margen = TextEditingController();
  final _merma = TextEditingController();
  final _tarifa = TextEditingController();
  final _redondeo = TextEditingController();
  final _factorIva = TextEditingController();
  final _factorRenta = TextEditingController();
  final _tasaIva = TextEditingController();
  final _comisionEfectivo = TextEditingController();
  final _comisionSinpe = TextEditingController();
  c.MetodoReparto _reparto = c.MetodoReparto.unidad;
  Regimen _regimen = Regimen.simplificado;
  TipoNegocio _tipo = TipoNegocio.produccion;
  bool _cargado = false;

  void _cargar(ConfigCosteoRegistro r) {
    if (_cargado) return;
    _cargado = true;
    _dias.text = '${r.config.diasAbiertosMes}';
    _margen.text = porcentajeParaEditar(r.config.margenObjetivo);
    _merma.text = porcentajeParaEditar(r.config.mermaPorDefecto);
    _tarifa.text = numero(r.config.tarifaManoObraHora);
    _redondeo.text = numero(r.config.redondeoPrecio);
    _reparto = r.config.metodoReparto;
    _regimen = r.regimen;
    _tipo = r.tipoNegocio;
    _factorIva.text = porcentajeParaEditar(r.factorIvaCompras);
    _factorRenta.text = porcentajeParaEditar(r.factorRentaCompras);
    _tasaIva.text = porcentajeParaEditar(r.tasaIvaPorDefecto);
    _comisionEfectivo.text = porcentajeParaEditar(r.comisionEfectivo);
    _comisionSinpe.text = porcentajeParaEditar(r.comisionSinpe);
  }

  @override
  void dispose() {
    for (final c in [_dias, _margen, _merma, _tarifa, _redondeo, _factorIva, _factorRenta, _tasaIva, _comisionEfectivo, _comisionSinpe]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar(ConfigCosteoRegistro actual) async {
    if (!_formKey.currentState!.validate()) return;
    final config = c.ConfigCosteo(
      diasAbiertosMes: int.parse(_dias.text.trim()),
      margenObjetivo: parsearPorcentaje(_margen.text)!,
      mermaPorDefecto: parsearPorcentaje(_merma.text)!,
      tarifaManoObraHora: parsearNumero(_tarifa.text)!,
      redondeoPrecio: parsearNumero(_redondeo.text)!,
      metodoReparto: _reparto,
    );
    final registro = actual.copyWith(
      config: config,
      regimen: _regimen,
      tipoNegocio: _tipo,
      factorIvaCompras: parsearPorcentaje(_factorIva.text)!,
      factorRentaCompras: parsearPorcentaje(_factorRenta.text)!,
      tasaIvaPorDefecto: parsearPorcentaje(_tasaIva.text)!,
      comisionEfectivo: parsearPorcentaje(_comisionEfectivo.text)!,
      comisionSinpe: parsearPorcentaje(_comisionSinpe.text)!,
    );
    // La peor comisión posible más el margen y, en general, la peor fracción
    // de IVA: si eso llega a 1 no hay precio posible para algún artículo.
    final peorComision = registro.comisionSinpe > registro.comisionEfectivo ? registro.comisionSinpe : registro.comisionEfectivo;
    final peorIva = _regimen == Regimen.general ? registro.tasaIvaPorDefecto / (1 + registro.tasaIvaPorDefecto) : 0;
    if (config.margenObjetivo + peorComision + peorIva >= 1) {
      mostrarAviso(context, '✗ Margen, comisión e IVA juntos no pueden llegar al 100 % del precio');
      return;
    }
    await ref.read(configCosteoProvider.notifier).guardar(registro);
    if (mounted) mostrarAviso(context, '✓ Parámetros guardados');
  }

  String? _porcentaje(String? v) {
    final n = parsearNumero(v ?? '');
    if (n == null) return 'Número inválido';
    if (n < 0 || n >= 100) return 'Entre 0 y 99';
    return null;
  }

  String? _positivo(String? v) {
    final n = parsearNumero(v ?? '');
    if (n == null) return 'Número inválido';
    if (n < 0) return 'No puede ser negativo';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configCosteoProvider);
    return config.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => BentoFalla(mensaje: 'No se pudieron leer los parámetros.', error: e),
      data: (registro) {
        _cargar(registro);
        final textos = Theme.of(context).textTheme;
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(BentoSpacing.gapCelda),
            children: [
              BentoPozo(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('El negocio', style: textos.titleMedium),
                    const SizedBox(height: BentoSpacing.unidad / 2),
                    Text(
                      'Cada uno mueve todos los precios sugeridos. El margen es sobre el PRECIO: '
                      '60 % es que de cada 100 vendidos, 60 son utilidad.',
                      style: textos.bodySmall,
                    ),
                    const SizedBox(height: BentoSpacing.unidad),
                    Text('De qué vive', style: textos.labelLarge),
                    RadioGroup<TipoNegocio>(
                      groupValue: _tipo,
                      onChanged: (t) => setState(() => _tipo = t!),
                      child: const Column(
                        children: [
                          RadioListTile(
                            value: TipoNegocio.produccion,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Producción'),
                            subtitle: Text('Comida, cosas hechas: cada unidad consume insumos y minutos'),
                          ),
                          RadioListTile(
                            value: TipoNegocio.servicios,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Servicios / digital'),
                            subtitle: Text(
                              'Licencias, horas, apps: sin receta es lo normal. El desarrollo o el equipo '
                              'se lleva como costo fijo amortizado (en Fijos hay una calculadora)',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BentoSpacing.unidad),
                    _campo(_margen, 'Margen objetivo (%)', _porcentaje),
                    _campo(_merma, 'Merma por defecto (%)', _porcentaje, ayuda: 'Cuando el insumo no declara la suya'),
                    _campo(_tarifa, 'Tarifa de mano de obra por hora ${Moneda.de(context).entreParentesis}', _positivo,
                        ayuda: 'Cero si nadie se la paga, pero el modelo la pide: si el producto no aguanta '
                            'pagar el trabajo que lleva, no es rentable'),
                    _campo(_redondeo, 'Redondeo del precio ${Moneda.de(context).entreParentesis}', _positivo,
                        ayuda: 'El precio sugerido sube al múltiplo: con 50, 2.703 pasa a 2.750'),
                    _campo(_dias, 'Días abiertos al mes', (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      return (n == null || n < 1 || n > 31) ? 'Entre 1 y 31' : null;
                    }, entero: true),
                    const SizedBox(height: BentoSpacing.unidad),
                    Text('Reparto de costos fijos', style: textos.labelLarge),
                    RadioGroup<c.MetodoReparto>(
                      groupValue: _reparto,
                      onChanged: (r) => setState(() => _reparto = r!),
                      child: const Column(
                        children: [
                          RadioListTile(
                            value: c.MetodoReparto.unidad,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Por unidad'),
                            subtitle: Text('Cada unidad vendida absorbe lo mismo'),
                          ),
                          RadioListTile(
                            value: c.MetodoReparto.tiempo,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Por tiempo'),
                            subtitle: Text('Según los minutos de producción: el horno lo paga quien lo ocupa'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BentoSpacing.pared),
              BentoPozo(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Impuestos y comisiones', style: textos.titleMedium),
                    const SizedBox(height: BentoSpacing.unidad / 2),
                    Text(
                      'Comprobar las cifras con el decreto vigente antes de declarar: cambian, y esto es una '
                      'libreta, no un contador.',
                      style: textos.bodySmall,
                    ),
                    const SizedBox(height: BentoSpacing.unidad),
                    Text('Régimen', style: textos.labelLarge),
                    RadioGroup<Regimen>(
                      groupValue: _regimen,
                      onChanged: (r) => setState(() => _regimen = r!),
                      child: const Column(
                        children: [
                          RadioListTile(
                            value: Regimen.simplificado,
                            contentPadding: EdgeInsets.zero,
                            title: Text('Simplificado'),
                            subtitle: Text('El impuesto sale de las COMPRAS del trimestre × factores. Sin IVA en la venta'),
                          ),
                          RadioListTile(
                            value: Regimen.general,
                            contentPadding: EdgeInsets.zero,
                            title: Text('General'),
                            subtitle: Text('IVA dentro del precio de cada producto, según su tasa'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BentoSpacing.unidad),
                    if (_regimen == Regimen.simplificado) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _campo(_factorIva, 'Factor IVA (%)', _porcentaje, ayuda: 'Sobre compras')),
                          const SizedBox(width: BentoSpacing.unidad),
                          Expanded(child: _campo(_factorRenta, 'Factor renta (%)', _porcentaje, ayuda: 'Sobre compras')),
                        ],
                      ),
                      _TrimestreSimplificado(registro: registro),
                    ] else
                      _campo(_tasaIva, 'IVA por defecto (%)', _porcentaje,
                          ayuda: 'El de un producto que no dice otra cosa. Cada producto puede llevar la suya: 13, 4, 2, 1 o exento'),
                    const SizedBox(height: BentoSpacing.unidad),
                    Text('Comisión por medio de pago', style: textos.labelLarge),
                    const SizedBox(height: BentoSpacing.unidad / 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _campo(_comisionEfectivo, 'Efectivo (%)', _porcentaje)),
                        const SizedBox(width: BentoSpacing.unidad),
                        Expanded(child: _campo(_comisionSinpe, 'SINPE / transferencia (%)', _porcentaje, ayuda: 'Lo que cobre el banco o la plataforma')),
                      ],
                    ),
                    Text(
                      'La comisión que usa el cálculo es el promedio de estas dos ponderado por cómo se '
                      'cobró de verdad en los últimos 30 días.',
                      style: textos.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BentoSpacing.gapCelda),
              FilledButton(onPressed: () => _guardar(registro), child: const Text('Guardar parámetros')),
            ],
          ),
        );
      },
    );
  }

  Widget _campo(
    TextEditingController controlador,
    String etiqueta,
    String? Function(String?) validar, {
    String? ayuda,
    bool entero = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: BentoSpacing.unidad),
    child: TextFormField(
      controller: controlador,
      decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, helperMaxLines: 3),
      keyboardType: TextInputType.numberWithOptions(decimal: !entero),
      validator: validar,
    ),
  );
}

/// Lo que se declara este trimestre en simplificado, con lo comprado hasta
/// hoy: compras × (factor IVA + factor renta). Con los factores GUARDADOS,
/// no con los del formulario sin guardar.
class _TrimestreSimplificado extends ConsumerWidget {
  const _TrimestreSimplificado({required this.registro});
  final ConfigCosteoRegistro registro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = DateTime.now();
    final inicio = DateTime(hoy.year, ((hoy.month - 1) ~/ 3) * 3 + 1);
    final fin = DateTime(inicio.year, inicio.month + 3);
    final compras = ref.watch(totalComprasProvider((inicio, fin))).valueOrNull;
    final textos = Theme.of(context).textTheme;
    if (compras == null) return const SizedBox.shrink();
    final iva = compras * registro.factorIvaCompras;
    final renta = compras * registro.factorRentaCompras;
    return Padding(
      padding: const EdgeInsets.only(bottom: BentoSpacing.unidad),
      child: Text(
        'Trimestre en curso: compras ${colones(context, compras)} → IVA ${colones(context, iva)} + renta ${colones(context, renta)} '
        '= ${colones(context, iva + renta)} a declarar (con los factores guardados). Se declara el 15 del mes siguiente al trimestre.',
        style: textos.bodySmall,
      ),
    );
  }
}
