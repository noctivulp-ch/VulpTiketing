import 'package:flutter/material.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/monto_editable.dart';
import '../../producto/producto_model.dart';
import '../../producto/variante_model.dart';

/// Cómo se escribe el precio de una variante donde se elige: sin decimales,
/// como en la carta. `montoParaEditar` es para escribirlo, no para leerlo.
String _precioDe(Variante v) => '₡${v.precio.toStringAsFixed(0)}';

/// Pregunta cuál variante, con una opción grande por cada una.
///
/// Es el selector de la decisión 0039 para el Panel de venta, donde tocar un
/// producto lo agrega sin más pasos: con variantes hace falta UNA pregunta, y
/// es esta. Devuelve `null` si se cancela — el producto no se agrega.
///
/// Los botones son de 48 dp de alto y a todo el ancho: al cobrar se pulsa con
/// el pulgar y sin mirar dos veces, y una lista de radios chicos ahí es un
/// error por cada cinco ventas.
Future<Variante?> elegirVariante(BuildContext context, Producto producto) {
  return showDialog<Variante>(
    context: context,
    builder: (dialogContext) => BentoDialogo(
      titulo: Text(producto.nombre),
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // La por defecto va llena y las demás tonales: se ve cuál es la
          // habitual sin leer, y sigue siendo un toque elegir cualquiera.
          for (final (i, v) in producto.variantes.indexed) ...[
            if (i > 0) const SizedBox(height: BentoSpacing.unidad),
            if (v.id == producto.variantePorDefecto?.id)
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, v),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Row(
                  children: [
                    Expanded(child: Text(v.nombre, overflow: TextOverflow.ellipsis)),
                    Text(_precioDe(v)),
                  ],
                ),
              )
            else
              FilledButton.tonal(
                onPressed: () => Navigator.pop(dialogContext, v),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Row(
                  children: [
                    Expanded(child: Text(v.nombre, overflow: TextOverflow.ellipsis)),
                    Text(_precioDe(v)),
                  ],
                ),
              ),
          ],
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        ],
        derecha: const [],
      ),
    ),
  );
}

/// El mismo selector, pero DENTRO de una pantalla: una fila de opciones donde
/// una queda marcada. Es el que usa el cobro rápido, que ya es un cuadro con
/// precio y cantidad y no necesita otro diálogo encima.
///
/// Abre con la variante **por defecto** marcada: es la que se cobra de un
/// toque, y cambiar de tamaño es la excepción. Antes abría sin nada elegido
/// para no cobrar el pequeño a quien pidió el grande; al existir una por
/// defecto —elegida por el Gerente en el producto— esa es la decisión.
class SelectorDeVariante extends StatelessWidget {
  const SelectorDeVariante({
    super.key,
    required this.variantes,
    required this.elegida,
    required this.onElegir,
  });

  final List<Variante> variantes;
  final Variante? elegida;
  final ValueChanged<Variante> onElegir;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: BentoSpacing.unidad,
      runSpacing: BentoSpacing.unidad,
      children: [
        for (final v in variantes)
          ChoiceChip(
            label: Text('${v.nombre} · ${_precioDe(v)}'),
            selected: elegida?.id == v.id,
            onSelected: (_) => onElegir(v),
          ),
      ],
    );
  }
}

/// Lo que dice el precio de un producto en una lista o tarjeta de venta.
///
/// Con variantes es el de la **por defecto** —que es `precio_base`—, sin
/// "desde": es lo que se cobra si no se dice otra cosa, y lo que se contesta
/// a quien pregunta cuánto vale. Los otros precios se ven al elegir.
String precioParaMostrar(Producto producto, {int decimales = 0}) =>
    '₡${producto.precioBase.toStringAsFixed(decimales)}';

/// El texto con el que se rellena el campo de precio al elegir una variante.
String precioEditableDe(Variante v) => montoParaEditar(v.precio);
