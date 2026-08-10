import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/bento_theme.dart';
import 'bento_aviso.dart';

/// Un enlace, con la pinta de un enlace.
///
/// Va en el **color del acento elegido** y **subrayado**. Las dos cosas juntas y
/// no una: el color solo no basta —quien no distingue ese tono ve texto normal—
/// y el subrayado es lo que hace la pista independiente del color. Es la regla
/// de siempre de accesibilidad, y acá además el acento cambia según el tinte que
/// tenga puesto el aparato.
///
/// El acento es `colorScheme.primary`, que es el metal del tinte. Medido contra
/// el pozo en los tres tintes y las dos luminosidades: el peor caso da 5,28:1,
/// por encima del 4,5:1 que pide un texto. Hay una prueba que lo vigila, porque
/// es justo lo que se rompe al añadir un tinte nuevo.
///
/// El objetivo táctil llega a 48 dp aunque el texto sea más bajo: un enlace de
/// una línea de `bodySmall` mide ~16 dp, y eso no se acierta con el dedo.
class BentoEnlace extends StatelessWidget {
  const BentoEnlace({
    super.key,
    required this.texto,
    required this.url,
    required this.onAbrir,
    this.estilo,
    this.descripcion,
  });

  /// Lo que se lee. Puede no ser la dirección: en la firma del autor es su
  /// nombre.
  final String texto;

  /// A dónde va. Se usa para copiarlo cuando no hay con qué abrirlo, así que el
  /// toque siempre sirve para algo.
  final String url;

  /// Quién lo abre. Se recibe en vez de llamar al servicio acá adentro para no
  /// atar un widget de `core/` a un servicio de `features/`.
  final Future<bool> Function() onAbrir;

  final TextStyle? estilo;

  /// Lo que oye quien usa un lector de pantalla. Sin esto se anuncia el texto
  /// tal cual, y "NoctiVulp" no dice que al tocarlo se abre una página.
  final String? descripcion;

  Future<void> _abrir(BuildContext context) async {
    final ok = await onAbrir();
    if (!context.mounted || ok) return;
    // Si no hay navegador que la abra, al menos queda copiada. Un aviso de "no
    // se pudo" a secas deja al usuario sin nada que hacer.
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) mostrarAviso(context, 'Enlace copiado');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = estilo ?? Theme.of(context).textTheme.bodyMedium;
    final deEnlace = (base ?? const TextStyle()).copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      // El subrayado en el mismo color que el texto: heredado, `decorationColor`
      // se queda en el color por defecto y la línea sale de otro tono.
      decorationColor: scheme.primary,
    );

    return Semantics(
      link: true,
      label: descripcion ?? texto,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _abrir(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              // Aire vertical para que el subrayado no toque lo de abajo.
              padding: const EdgeInsets.symmetric(vertical: BentoSpacing.unidad / 2),
              child: Text(texto, style: deEnlace),
            ),
          ),
        ),
      ),
    );
  }
}
