import 'package:costeo/costeo.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_falla.dart';
import '../costeo_notifiers.dart';
import 'formato_costeo.dart';

/// Los parámetros del negocio. Se guardan con un botón, no campo a campo: son
/// siete números que se piensan juntos, y cada uno mueve todos los precios.
class AjustesCosteoPanel extends ConsumerStatefulWidget {
  const AjustesCosteoPanel({super.key});

  @override
  ConsumerState<AjustesCosteoPanel> createState() => _AjustesCosteoPanelState();
}

class _AjustesCosteoPanelState extends ConsumerState<AjustesCosteoPanel> {
  final _formKey = GlobalKey<FormState>();
  final _dias = TextEditingController();
  final _margen = TextEditingController();
  final _comision = TextEditingController();
  final _merma = TextEditingController();
  final _tarifa = TextEditingController();
  final _redondeo = TextEditingController();
  c.MetodoReparto _reparto = c.MetodoReparto.unidad;
  bool _cargado = false;

  void _cargar(c.ConfigCosteo config) {
    if (_cargado) return;
    _cargado = true;
    _dias.text = '${config.diasAbiertosMes}';
    _margen.text = porcentajeParaEditar(config.margenObjetivo);
    _comision.text = porcentajeParaEditar(config.comisionMediosPago);
    _merma.text = porcentajeParaEditar(config.mermaPorDefecto);
    _tarifa.text = numero(config.tarifaManoObraHora);
    _redondeo.text = numero(config.redondeoPrecio);
    _reparto = config.metodoReparto;
  }

  @override
  void dispose() {
    for (final c in [_dias, _margen, _comision, _merma, _tarifa, _redondeo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final config = c.ConfigCosteo(
      diasAbiertosMes: int.parse(_dias.text.trim()),
      margenObjetivo: parsearPorcentaje(_margen.text)!,
      comisionMediosPago: parsearPorcentaje(_comision.text)!,
      mermaPorDefecto: parsearPorcentaje(_merma.text)!,
      tarifaManoObraHora: parsearNumero(_tarifa.text)!,
      redondeoPrecio: parsearNumero(_redondeo.text)!,
      metodoReparto: _reparto,
    );
    if (config.divisor <= 0) {
      mostrarAviso(context, '✗ Margen + comisión no pueden llegar al 100 %');
      return;
    }
    await ref.read(configCosteoProvider.notifier).guardar(config);
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
      data: (cfg) {
        _cargar(cfg);
        final textos = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(BentoSpacing.gapCelda),
          children: [
            BentoPozo(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Parámetros del negocio', style: textos.titleMedium),
                    const SizedBox(height: BentoSpacing.unidad / 2),
                    Text(
                      'Cada uno mueve todos los precios sugeridos. El margen es sobre el PRECIO: '
                      '60 % es que de cada ₡100 vendidos, ₡60 son utilidad.',
                      style: textos.bodySmall,
                    ),
                    const SizedBox(height: BentoSpacing.gapCelda),
                    _campo(_margen, 'Margen objetivo (%)', _porcentaje),
                    _campo(_comision, 'Comisión de medios de pago (%)', _porcentaje,
                        ayuda: 'Datáfono, SINPE con comisión, plataformas de entrega'),
                    _campo(_merma, 'Merma por defecto (%)', _porcentaje,
                        ayuda: 'Cuando el insumo no declara la suya'),
                    _campo(_tarifa, 'Tarifa de mano de obra por hora (₡)', _positivo,
                        ayuda: 'Cero si nadie se la paga, pero el modelo la pide: si el producto no aguanta '
                            'pagar el trabajo que lleva, no es rentable'),
                    _campo(_redondeo, 'Redondeo del precio (₡)', _positivo,
                        ayuda: 'El precio sugerido sube al múltiplo: 50 → ₡2.750, no ₡2.703'),
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
                    const SizedBox(height: BentoSpacing.gapCelda),
                    FilledButton(onPressed: _guardar, child: const Text('Guardar parámetros')),
                  ],
                ),
              ),
            ),
          ],
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
