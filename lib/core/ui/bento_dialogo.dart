import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/bento_theme.dart';

/// Por debajo de este alto la pantalla se considera acostada.
///
/// Es alto y no orientación a propósito: lo que escasea acostado es el alto, y
/// una tablet apaisada de 800 dp no tiene el problema que sí tiene un teléfono
/// de 360.
const double bentoAltoAcostado = 520;

bool bentoEstaAcostado(BuildContext context) =>
    MediaQuery.sizeOf(context).height < bentoAltoAcostado;

/// El diálogo de la app: mismo cuerpo en las dos orientaciones, con las acciones
/// DEBAJO de pie y AL COSTADO acostado.
///
/// Acostado el alto es el recurso escaso —los campos ya se lo comen— así que las
/// acciones se van a donde sobra espacio. Dejarlas en `actions` las manda debajo,
/// que es exactamente lo que no entra: el formulario de producto desbordaba 95 px
/// por eso.
class BentoDialogo extends StatelessWidget {
  const BentoDialogo({
    super.key,
    required this.titulo,
    required this.contenido,
    required this.acciones,
    this.anchoAcostado = 560,
  });

  final Widget titulo;
  final Widget contenido;
  final BentoAcciones acciones;

  /// Cuánto ancho toma el diálogo acostado. Sin acotarlo, el contenido y la
  /// columna de acciones se reparten el ancho de la pantalla entera.
  final double anchoAcostado;

  @override
  Widget build(BuildContext context) {
    final acostado = bentoEstaAcostado(context);

    // El scroll lo pone ESTE widget dentro del contenido, en vez de usar
    // `AlertDialog(scrollable: true)`.
    //
    // `scrollable` envuelve todo en un `IntrinsicWidth`, y un `GridView`
    // —aunque sea `shrinkWrap`— no sabe dar dimensiones intrínsecas:
    // "RenderShrinkWrappingViewport does not support returning intrinsic
    // dimensions", y el diálogo sale VACÍO. Pasó en el aparato con el
    // calendario y con las cuadrículas de mes y de año: no se veía nada, solo
    // el velo.
    //
    // Con el scroll acá dentro se consigue lo mismo que se buscaba —que el
    // contenido ceda cuando el teclado se come el alto, en vez de que el
    // diálogo se parta— sin medir nada intrínseco.
    return AlertDialog(
      title: titulo,
      content: acostado
          ? ConstrainedBox(
              // `maxWidth` y no un ancho fijo: acostado la pantalla siempre da
              // más de 560, pero fijarlo obligaría al diálogo a ese ancho aun
              // cuando la ventana sea menor.
              constraints: BoxConstraints(maxWidth: anchoAcostado),
              // El scroll envuelve la FILA entera, contenido y acciones juntos.
              // Envolviendo solo el contenido, con el teclado abierto la
              // columna de acciones seguía pidiendo su alto y desbordaba: lo
              // que tiene que ceder acostado es el bloque completo.
              child: SingleChildScrollView(
                child: Row(
                  // `start` y no `stretch`: dentro de un scroll el alto es
                  // ilimitado, y estirar a un infinito no significa nada.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: contenido),
                    const SizedBox(width: BentoSpacing.pared),
                    // `IntrinsicWidth`: la cuadrícula de acciones necesita un
                    // ancho acotado para repartir sus dos columnas dentro de
                    // una fila.
                    IntrinsicWidth(child: acciones),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(child: contenido),
      actions: acostado ? null : [acciones],
    );
  }
}

/// Las acciones de un diálogo en dos columnas, fila por fila.
///
/// Dos columnas y no una `Row` con todos los botones: en 360 dp cuatro no
/// entran de ancho, y cuando no entran `AlertDialog` los apila alineados a la
/// derecha, perdiendo de qué habla cada uno.
///
/// Cómo se reparten:
/// - **Formulario con acciones sobre el objeto** (editar un producto fuera de
///   la carta): a la izquierda lo que le pasa al objeto —reactivar, eliminar—;
///   a la derecha lo que le pasa al formulario —cancelar, guardar—. Dos filas.
/// - **Confirmación de dos botones**: a la izquierda la acción, a la derecha
///   cancelar. Una fila, que es lo que ya hacía y lo que se espera de un
///   "¿seguro?".
class BentoAcciones extends StatelessWidget {
  const BentoAcciones({super.key, this.izquierda = const [], required this.derecha});

  /// Columna izquierda. Puede estar vacía.
  final List<Widget> izquierda;

  /// Columna derecha. Siempre lleva la salida del diálogo.
  final List<Widget> derecha;

  @override
  Widget build(BuildContext context) {
    final filas = math.max(izquierda.length, derecha.length);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < filas; i++)
          Padding(
            // Aire entre filas: pegados, los botones se leen como un bloque y
            // cuesta ver cuál es cuál.
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : BentoSpacing.unidad,
              bottom: BentoSpacing.unidad / 2,
            ),
            child: Row(
              children: [
                // Dos columnas del MISMO ancho, no dos botones repartidos con
                // `spaceBetween`: así cada uno se colocaba según su propio largo
                // y las columnas quedaban descuadradas entre filas.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: i < izquierda.length ? izquierda[i] : const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: BentoSpacing.gapCelda),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: i < derecha.length ? derecha[i] : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Un paso de un panel inline de Configuración: título, algo de contenido y sus
/// acciones.
///
/// Misma regla que [BentoDialogo] y por el mismo motivo, pero para lo que NO es
/// un diálogo: los paneles de Configuración —catálogo, backup, restaurar,
/// contraseña— apilaban sus botones debajo del texto, y acostado eso es lo que
/// no entra. Acá van al costado.
///
/// La columna de acciones se lleva 2 de 5 partes en vez de medir su contenido:
/// estos botones llevan frases enteras ("Reemplazar — descontinúa lo que no
/// venga en el archivo") y un `IntrinsicWidth` les habría dado media pantalla.
class BentoPanel extends StatelessWidget {
  const BentoPanel({super.key, required this.titulo, this.contenido, required this.acciones});

  final String titulo;

  /// Explicación, campos, lo que el paso necesite. Puede no haber.
  final Widget? contenido;

  /// En el orden en que se leen. Acostado quedan en columna al costado; de pie,
  /// apilados debajo, que es como estaban.
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final cuerpo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleMedium),
        if (contenido != null) ...[const SizedBox(height: BentoSpacing.gapCelda), contenido!],
      ],
    );

    final botones = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < acciones.length; i++) ...[
          if (i > 0) const SizedBox(height: BentoSpacing.unidad),
          acciones[i],
        ],
      ],
    );

    if (!bentoEstaAcostado(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          cuerpo,
          const SizedBox(height: BentoSpacing.gapCelda),
          botones,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: cuerpo),
        const SizedBox(width: BentoSpacing.pared),
        Expanded(flex: 2, child: botones),
      ],
    );
  }
}
