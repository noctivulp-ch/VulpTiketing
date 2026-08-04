import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_tallado.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../producto/producto_model.dart';
import '../venta_en_curso_notifier.dart';
import 'casilla_sinpe.dart';

/// Overlay de cobro de un solo producto (0018 cantidad default 1, precio
/// editable con el base como punto de partida, cambio con debounce 400 ms
/// — ver decisiones ya cerradas en flujo-descripcion.md).
///
/// Vive en su propio archivo y es público para poder probarlo a los tamaños
/// reales del aparato sin montar Ventana 1 entera: montar la pantalla en un
/// `testWidgets` deja la bandeja cargando, así que el overlay se quedaba sin
/// una sola prueba de layout — y ahí fue donde apareció el desborde.
class CobroRapidoOverlay extends ConsumerStatefulWidget {
  const CobroRapidoOverlay({super.key, required this.producto});

  final Producto producto;

  @override
  ConsumerState<CobroRapidoOverlay> createState() => _CobroRapidoOverlayState();
}

class _CobroRapidoOverlayState extends ConsumerState<CobroRapidoOverlay> {
  bool _sinpe = false;
  late final TextEditingController _precioController;
  final _recibidoController = TextEditingController();
  int _cantidad = 1;
  double? _cambio;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _precioController = TextEditingController(text: widget.producto.precioBase.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _precioController.dispose();
    _recibidoController.dispose();
    super.dispose();
  }

  void _onRecibidoChanged(String valor) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final recibido = double.tryParse(valor);
      final precio = double.tryParse(_precioController.text) ?? 0;
      setState(() {
        _cambio = recibido == null ? null : recibido - (precio * _cantidad);
      });
    });
  }

  Future<void> _completar() async {
    final precio = double.tryParse(_precioController.text) ?? widget.producto.precioBase;
    // Antes de agregar la línea: `marcarSinpe` reemplaza el estado, y hacerlo
    // después de agregar dejaría el método puesto sobre un carrito ya cerrado.
    ref.read(ventaEnCursoNotifierProvider.notifier).marcarSinpe(activo: _sinpe);
    ref
        .read(ventaEnCursoNotifierProvider.notifier)
        .agregarLineaDeCatalogo(
          productoId: widget.producto.id,
          precioAplicado: precio,
          cantidad: _cantidad,
        );
    await ref.read(ventaEnCursoNotifierProvider.notifier).guardar();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final tema = Theme.of(context);
    final total = (double.tryParse(_precioController.text) ?? 0) * _cantidad;

    // Cobro rápido como una BANDEJA propia, no como un `AlertDialog` con campos
    // apilados: era la única superficie de la app que no hablaba el idioma del
    // resto — sin pozos, sin retícula, con los campos sueltos sobre el fondo del
    // diálogo.
    //
    // La jerarquía es la de la venta: qué se cobra arriba, cuánto en grande, y
    // los ajustes en celdas de la misma retícula que Reportes.
    final acostado = bentoEstaAcostado(context);

    final hero = BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.producto.nombre,
            style: tema.textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          BentoTextoTallado(
            '₡${total.toStringAsFixed(2)}',
            sobre: laca.pozo,
            nivel: TalladoNivel.marcado,
            estilo: acostado ? tema.textTheme.headlineSmall : tema.textTheme.displaySmall,
          ),
        ],
      ),
    );

    final cantidad = BentoPozo(
      // Sin padding propio: los dos `IconButton` ya traen sus 48 dp táctiles, y
      // el padding del pozo encima dejaba el control sin sitio en la celda más
      // angosta —desbordaba 11 px a 640 dp de ancho—.
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Menos',
            onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
          ),
          // `Expanded` y no un `Text` suelto: los dos botones ocupan sus 48 dp
          // táctiles pase lo que pase, así que lo único que puede ceder es el
          // número. Suelto, desbordaba 6 px con la celda de 3 columnas.
          Expanded(
            child: Text(
              '$_cantidad',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.titleLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Más',
            onPressed: () => setState(() => _cantidad++),
          ),
        ],
      ),
    );

    final precio = BentoPozo(
      padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.paddingCelda),
      child: TextField(
        controller: _precioController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Precio',
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );

    // Etiqueta arriba y monto abajo, igual que Precio y Recibí — los tres pozos
    // de la retícula se leen entonces con la misma forma.
    //
    // Antes iba todo en una línea ("Cambio: ₡12345.00") con elipsis, y en media
    // fila de 360 dp no entra: el monto se cortaba justo por el final, que es
    // donde están los colones que hay que devolver. Un cambio a medio leer es
    // peor que ninguno — se devuelve mal el vuelto.
    final cambio = BentoPozo(
      padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.paddingCelda),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Cambio', style: tema.textTheme.bodySmall),
          const SizedBox(height: 2),
          // `FittedBox` y no elipsis: con un vuelto de cinco cifras el número
          // se encoge, pero se lee entero. Recortarlo no es una opción para un
          // dato que se cuenta en la mano.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _cambio == null ? '—' : '₡${_cambio!.toStringAsFixed(2)}',
              maxLines: 1,
              style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    final recibido = BentoPozo(
      padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.paddingCelda),
      child: TextField(
        controller: _recibidoController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Recibí',
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onChanged: _onRecibidoChanged,
      ),
    );

    final casillaSinpe = CasillaSinpe(
      activa: _sinpe,
      onCambio: (activo) => setState(() => _sinpe = activo),
    );

    // El cuadro de cobro, en el orden que pidió el dueño:
    //
    //     Recibí │ Precio
    //     Cambio │ SINPE
    //
    // Los dos que se ESCRIBEN arriba y los dos que solo se miran o se marcan
    // abajo, con lo que se teclea en la columna izquierda. Antes iba Cambio
    // antes que Recibí, que dejaba el campo de escribir en diagonal respecto
    // del otro.
    //
    // Acostado el alto es el recurso escaso, así que la retícula se aplana: dos
    // filas en vez de tres, y el mismo emparejamiento arriba/abajo se conserva
    // en las dos últimas columnas. De pie el alto sobra y la jerarquía se lee
    // mejor con el total ocupando su propia fila.
    final celdas = acostado
        ? <BentoCelda>[
            BentoCelda.fija(2, hijo: hero),
            BentoCelda.fija(2, hijo: recibido),
            BentoCelda.fija(2, hijo: precio),
            BentoCelda.fija(2, hijo: cantidad),
            BentoCelda.fija(2, hijo: cambio),
            BentoCelda.fija(2, hijo: casillaSinpe),
          ]
        : <BentoCelda>[
            BentoCelda.fija(6, hijo: hero),
            // Fila propia: dos objetivos táctiles de 48 dp más el número no
            // entran en media fila de 360 dp, y es además el control que más se
            // toca de todo el cobro.
            BentoCelda.fija(6, hijo: cantidad),
            BentoCelda.fija(3, hijo: recibido),
            BentoCelda.fija(3, hijo: precio),
            BentoCelda.fija(3, hijo: cambio),
            BentoCelda.fija(3, hijo: casillaSinpe),
          ];

    final cancelar = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancelar'),
    );
    final completado = FilledButton(onPressed: _completar, child: const Text('Completado'));

    // Los botones quedan SIEMPRE fuera del scroll. Lo que el usuario rechazó no
    // era el scroll en sí, sino tener que desplazarse para llegar a
    // "Completado" — con el teclado abierto no queda alto para nada y algo
    // tiene que ceder, pero nunca la acción de cobrar.
    final contenido = SingleChildScrollView(child: BentoCuadricula(hijos: celdas));

    return Dialog(
      insetPadding: const EdgeInsets.all(BentoSpacing.gapCelda),
      backgroundColor: laca.bandeja,
      child: ConstrainedBox(
        // Más ancho acostado: es lo que sobra, y de ahí sale el sitio para la
        // columna de acciones.
        constraints: BoxConstraints(maxWidth: acostado ? 720 : 460),
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.gapCelda),
          child: acostado
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: contenido),
                    const SizedBox(width: BentoSpacing.pared),
                    // `IntrinsicWidth`: la columna necesita un ancho acotado
                    // para estirar los dos botones al mismo.
                    IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          completado,
                          const SizedBox(height: BentoSpacing.pared),
                          cancelar,
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: contenido),
                    const SizedBox(height: BentoSpacing.pared),
                    Row(
                      children: [
                        Expanded(child: cancelar),
                        const SizedBox(width: BentoSpacing.pared),
                        Expanded(child: completado),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
