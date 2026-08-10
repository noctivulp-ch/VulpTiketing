import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../ajustes_android_service.dart';

/// Estado de los ajustes del sistema, releído cada vez que se vuelve a la app.
///
/// No se cachea entre visitas: el usuario sale a Ajustes, concede la exención y
/// vuelve. Si el estado se guardara, al volver seguiría diciendo que falta.
final estadoDeAjustesProvider = FutureProvider<EstadoDeAjustes>(
  (ref) => const AjustesAndroidService().estado(),
);

/// Atajos a los ajustes de Android que la app necesita.
///
/// La app no puede concederse permisos a sí misma; esto solo deja al usuario en
/// la pantalla correcta. Que es casi todo el problema: la exención de batería
/// está a cinco toques de profundidad y se llama distinto en cada marca
/// —"Optimización de batería", "Inicio automático", "Aplicaciones protegidas"—,
/// y sin ella el sistema mata la sincronización al apagarse la pantalla. La caja
/// deja de compartir ventas y **nada en la app avisa** de que dejó de hacerlo.
class PanelAjustesSistema extends ConsumerStatefulWidget {
  const PanelAjustesSistema({super.key});

  @override
  ConsumerState<PanelAjustesSistema> createState() => _PanelAjustesSistemaState();
}

class _PanelAjustesSistemaState extends ConsumerState<PanelAjustesSistema>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Al volver de Ajustes se relee. Sin esto, quien acaba de conceder la
    // exención vuelve a una pantalla que sigue diciéndole que falta, y lo
    // razonable es concluir que no funcionó.
    if (estado == AppLifecycleState.resumed) ref.invalidate(estadoDeAjustesProvider);
  }

  Future<void> _abrir(AjusteAndroid ajuste) async {
    final ok = await const AjustesAndroidService().abrir(ajuste);
    if (!mounted) return;
    if (!ok) {
      mostrarAviso(context, '✗ Este teléfono no tiene esa pantalla — buscala en Ajustes');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final servicio = const AjustesAndroidService();

    if (!servicio.disponible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Permisos del sistema', style: textos.titleMedium),
          const SizedBox(height: BentoSpacing.unidad / 2),
          Text('Esto es solo de Android. Acá no hay nada que conceder.', style: textos.bodySmall),
        ],
      );
    }

    final estado = ref.watch(estadoDeAjustesProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Permisos del sistema', style: textos.titleMedium),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Text(
          'Atajos a los ajustes de Android. La app no puede concederse nada a sí '
          'misma: cada uno abre la pantalla donde se marca.',
          style: textos.bodySmall,
        ),
        const SizedBox(height: BentoSpacing.unidad),
        for (final ajuste in AjusteAndroid.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_icono(ajuste)),
            title: Text(ajuste.etiqueta),
            subtitle: Text(ajuste.explicacion),
            isThreeLine: true,
            // Solo la batería se puede consultar; en las demás no se dibuja
            // nada, porque un tilde que no sabe lo que dice es peor que ninguno.
            trailing: ajuste == AjusteAndroid.bateria && estado != null
                ? Icon(estado.sinOptimizacionDeBateria ? Icons.check_circle : Icons.error_outline)
                : const Icon(Icons.open_in_new),
            onTap: () => _abrir(ajuste),
          ),
        if (estado != null && !estado.sinOptimizacionDeBateria) ...[
          const SizedBox(height: BentoSpacing.unidad),
          Text(
            'La optimización de batería está activa: la sincronización se va a '
            'cortar cuando la pantalla se apague.',
            style: textos.bodySmall,
          ),
        ],
        if (estado != null && estado.fabricante.isNotEmpty) ...[
          const SizedBox(height: BentoSpacing.gapCelda),
          Text(
            // El fabricante importa de verdad: en un Huawei o un Xiaomi la
            // exención de Android no basta, hay una lista propia aparte. Decirlo
            // acá evita el diagnóstico de "la sincronización no funciona" cuando
            // lo que pasa es que la ROM la está matando.
            'Aparato ${estado.fabricante}, Android API ${estado.version}. '
            'Algunas marcas tienen además su propia lista de apps protegidas, '
            'fuera de estos ajustes: si la sincronización se corta con la '
            'pantalla apagada pese a la exención, es ahí.',
            style: textos.bodySmall,
          ),
        ],
      ],
    );
  }

  IconData _icono(AjusteAndroid ajuste) => switch (ajuste) {
    AjusteAndroid.bateria => Icons.battery_saver_outlined,
    AjusteAndroid.permisos => Icons.shield_outlined,
    AjusteAndroid.datosEnSegundoPlano => Icons.cloud_sync_outlined,
    AjusteAndroid.abrirPorDefecto => Icons.file_open_outlined,
  };
}
