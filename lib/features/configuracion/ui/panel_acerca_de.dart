import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/version.dart';
import '../ajustes_android_service.dart';

/// Qué es esta app, qué versión corre y quién la hizo.
///
/// El número de compilación no es adorno: cuando algo no cuadra en un teléfono,
/// lo primero que hay que saber es si corre el mismo código que los demás. Dos
/// aparatos con la misma versión y distinto build no lo hacen.
///
/// La firma del autor lleva el enlace **embebido, sin decoración**: se lee como
/// una firma y no como un botón. La app es a medida para un familiar y no cobra
/// nada, así que el enlace es una marca de autoría —por si algún día alguien se
/// la apropia—, no una invitación a pagar.
class PanelAcercaDe extends StatelessWidget {
  const PanelAcercaDe({super.key});

  Future<void> _abrirEnlace(BuildContext context) async {
    final ok = await const AjustesAndroidService().abrirEnlace(enlaceAutor);
    if (!context.mounted || ok) return;
    // Si no hay navegador que lo abra, al menos queda la dirección copiada: el
    // toque tiene que servir para algo, y un aviso de "no se pudo" a secas deja
    // al usuario sin nada.
    await Clipboard.setData(const ClipboardData(text: enlaceAutor));
    if (context.mounted) mostrarAviso(context, 'Enlace copiado');
  }

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(nombreApp, style: textos.headlineSmall),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Text('Versión $versionApp (build $compilacionApp)', style: textos.bodyMedium),
        const SizedBox(height: BentoSpacing.gapCelda),
        Text(
          'Inventario, ventas y reportes para una soda. Funciona sin internet y '
          'las cajas se sincronizan entre ellas por la red local.',
          style: textos.bodySmall,
        ),
        const SizedBox(height: BentoSpacing.gapGrupo),
        // Un `InkWell` y no un botón: el objetivo táctil está —los 48 dp los da
        // el alto mínimo— pero no se anuncia como acción. Es una firma.
        InkWell(
          onTap: () => _abrirEnlace(context),
          // La etiqueta de accesibilidad SÍ dice que abre algo. Un enlace
          // invisible es una decisión de diseño para quien ve la pantalla; para
          // quien la escucha con TalkBack sería un elemento que hace algo
          // inesperado al tocarlo, y eso no es discreción, es una trampa.
          child: Semantics(
            link: true,
            label: 'Hecho por $autorApp — abre la página del autor',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Hecho por $autorApp', style: textos.bodyMedium),
              ),
            ),
          ),
        ),
        // Fuera del área tocable: la firma lleva el enlace, esto es una nota al
        // pie. Si entrara en el mismo `InkWell`, tocar la atribución abriría la
        // página del autor, que no es lo que la nota dice que hace.
        Text(motorApp, style: textos.bodySmall),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Text(atribucionApp, style: textos.bodySmall),
      ],
    );
  }
}
