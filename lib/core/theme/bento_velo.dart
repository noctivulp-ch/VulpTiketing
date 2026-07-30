import 'package:flutter/material.dart';

import 'bento_theme.dart';

/// Margen propio de la app por encima del inset del sistema.
///
/// La zona alta de la pantalla es territorio ajeno: ahí caen la muesca de la
/// cámara y las notificaciones que bajan. Nada importante puede vivir en ese
/// borde, aunque el sistema diga que el inset "termina" antes.
const double bentoMargenSuperior = 24;

/// Cuánto hay que dejar libre arriba: el inset real del aparato más el margen
/// propio.
double bentoInsetSuperior(BuildContext context) =>
    MediaQuery.paddingOf(context).top + bentoMargenSuperior;

/// Franja degradada en el borde superior, del color de la bandeja a
/// transparente.
///
/// No corta el contenido: lo deja pasar POR DEBAJO. Un `SafeArea` empuja todo
/// hacia abajo y deja un borde muerto; con el velo, una lista que sube se
/// desvanece contra el canto de la bandeja en vez de cortarse en seco.
///
/// El color es el de la bandeja y no negro fijo: en modo oscuro la bandeja ya
/// es casi negra —que es el efecto que se pidió— y en modo claro un velo negro
/// sería una mancha. Lo que se quiere decir es "el contenido se mete bajo el
/// canto de la bandeja", y eso lo dice el color de la bandeja en los dos modos.
///
/// Es `IgnorePointer`: es decoración, nunca se come un toque.
class BentoVeloSuperior extends StatelessWidget {
  const BentoVeloSuperior({super.key});

  @override
  Widget build(BuildContext context) {
    final bandeja = lacaDe(context).bandeja;
    return IgnorePointer(
      child: SizedBox(
        height: bentoInsetSuperior(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Opaco arriba y transparente abajo, con la mayor parte del
              // desvanecido en el último tramo: si el degradado empezara a
              // aclararse enseguida, el texto que pasa por debajo se leería a
              // medias justo donde está la muesca.
              colors: [bandeja, bandeja, bandeja.withValues(alpha: 0)],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
