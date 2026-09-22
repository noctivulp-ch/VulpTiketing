import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_fotos.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/monto_editable.dart';
import '../../../core/ui/bento_falla.dart';
import '../../auth/sesion_notifier.dart';
import '../../sync/sync_notifier.dart';
import '../categoria_model.dart';
import '../categoria_notifier.dart';
import '../producto_model.dart';
import '../producto_notifier.dart';
import '../producto_query_provider.dart';
import '../variante_model.dart';
import 'banco_imagenes_dialog.dart';
import 'imagen_del_banco_vista.dart';

const _uuid = Uuid();

/// Formulario de crear/editar Producto — Ventana 3
/// (docs/pantallas/flujo-descripcion.md#ventana-3--crud-de-producto).
///
/// **La imagen se elige acá y solo acá**: es gestión de inventario. En las
/// pantallas de venta no hay foto — se probó al diseñarlas y una por tarjeta
/// dejaba el nombre y el precio, que es lo que se lee al cobrar, sin sitio.
///
/// Se elige del **banco** (decisión 0033): figuras de fábrica que no pesan, más
/// las fotos que se hayan sumado desde la galería o la cámara. El banco **no
/// viaja** en el backup ni en la sincronización, así que un producto cuya foto
/// no está en este aparato se ve con su figura propia — lo mismo que uno que
/// nunca eligió imagen. Nada se rompe y nada miente.
class ProductoFormDialog extends ConsumerStatefulWidget {
  const ProductoFormDialog({super.key, this.producto});

  /// Null = crear. No-null = editar.
  final Producto? producto;

  @override
  ConsumerState<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends ConsumerState<ProductoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _precioController;
  String? _categoriaId;
  bool _guardando = false;

  /// La referencia elegida, tal como irá a `producto.imagen`.
  String? _imagen;

  /// Las variantes en edición, cada una con sus dos campos (0039).
  final List<_VarianteEnEdicion> _variantes = [];

  /// Id de la variante por defecto. Con variantes, el campo de precio deja
  /// de ser un número y pasa a ser esta elección: el precio base del producto
  /// es el de la elegida.
  String? _porDefecto;

  bool get _esEdicion => widget.producto != null;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.producto?.nombre ?? '');
    _precioController = TextEditingController(
      text: widget.producto == null ? '' : montoParaEditar(widget.producto!.precioBase),
    );
    _categoriaId = widget.producto?.categoriaId;
    _imagen = widget.producto?.imagen;
    for (final v in widget.producto?.variantes ?? const <Variante>[]) {
      _variantes.add(_VarianteEnEdicion.de(v));
    }
    _porDefecto = widget.producto?.variantePorDefecto?.id;
  }

  void _agregarVariante() {
    setState(() {
      final nueva = _VarianteEnEdicion.nueva();
      _variantes.add(nueva);
      // La primera que se agrega hereda el sitio del precio base: es lo que se
      // vendía hasta ahora, así que es lo que se vende por defecto.
      if (_variantes.length == 1) {
        nueva.precio.text = _precioController.text;
        _porDefecto = nueva.id;
      }
    });
  }

  /// Sube o baja una variante un puesto. El orden del formulario ES el orden
  /// de la caja —chips y selector lo repiten tal cual— y no se ordena por
  /// nombre ni por precio en ningún sitio: la memoria muscular necesita que
  /// "el segundo botón" sea siempre el mismo, y eso lo decide el Gerente.
  void _moverVariante(_VarianteEnEdicion v, int paso) {
    final i = _variantes.indexOf(v);
    final destino = i + paso;
    if (destino < 0 || destino >= _variantes.length) return;
    setState(() {
      _variantes.removeAt(i);
      _variantes.insert(destino, v);
    });
  }

  void _quitarVariante(_VarianteEnEdicion v) {
    setState(() {
      _variantes.remove(v);
      v.dispose();
      if (_porDefecto == v.id) _porDefecto = _variantes.firstOrNull?.id;
      // Al quitar la última, el precio base vuelve a ser un número: el de la
      // que era por defecto, para no dejar el campo en blanco.
      if (_variantes.isEmpty && _precioController.text.isEmpty) {
        _precioController.text = v.precio.text;
      }
    });
  }

  /// Las variantes tal como van a guardarse. Se llama después de validar, así
  /// que los precios ya parsean.
  List<Variante> _variantesParaGuardar() => [
    for (final v in _variantes)
      Variante(
        id: v.id,
        nombre: v.nombre.text.trim(),
        precio: double.parse(v.precio.text),
        porDefecto: v.id == (_porDefecto ?? _variantes.first.id),
      ),
  ];

  /// El precio base que se guarda: el del campo sin variantes, o el de la
  /// variante por defecto con ellas. Nunca los dos a la vez.
  double _precioBaseParaGuardar() {
    if (_variantes.isEmpty) return double.parse(_precioController.text);
    final porDefecto = _variantes.firstWhere(
      (v) => v.id == _porDefecto,
      orElse: () => _variantes.first,
    );
    return double.parse(porDefecto.precio.text);
  }

  Future<void> _elegirImagen() async {
    final elegida = await elegirDelBanco(context);
    // `null` es cancelar y no cambia nada; `''` es "sin imagen", que sí es una
    // elección: deja al producto sin cara propia.
    if (elegida == null || !mounted) return;
    setState(() => _imagen = elegida.isEmpty ? null : elegida);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    for (final v in _variantes) {
      v.dispose();
    }
    super.dispose();
  }

  /// Devuelve el producto a la carta y cierra: lo que se quería hacer ya está
  /// hecho, y dejar el formulario abierto invitaría a un "Guardar" que no
  /// agrega nada.
  Future<void> _reactivar() async {
    setState(() => _guardando = true);
    await ref.read(productoNotifierProvider.notifier).recontinuar(widget.producto!.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Borrado FÍSICO, con las tres condiciones de la decisión 0015 — de ahí que
  /// el resultado pueda ser un "no se puede" y no un simple ok.
  ///
  /// El gate de sincronización llega como parámetro y no se lee acá adentro,
  /// para no acoplar el formulario a SyncNotifier (0019).
  Future<void> _eliminar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('¿Eliminar el producto?'),
        contenido: Text(
          '"${widget.producto!.nombre}" se borra de verdad, no se puede deshacer. '
          'Si tuvo ventas alguna vez, no se va a poder: su historial lo necesita.',
        ),
        acciones: BentoAcciones(
          izquierda: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
          ],
          derecha: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    final sincronizado = await ref.read(dispositivoSinParesProvider.future);
    if (!mounted) return;
    final resultado = await ref
        .read(productoNotifierProvider.notifier)
        .purgar(widget.producto!.id, todosLosDispositivosSincronizados: sincronizado);
    if (!mounted) return;

    setState(() => _guardando = false);
    switch (resultado) {
      case PurgarResultado.ok:
        Navigator.of(context).pop();
      case PurgarResultado.tieneVentasAsociadas:
        mostrarAviso(context, '✗ Tiene ventas: no se puede borrar');
      case PurgarResultado.faltaSincronizar:
        mostrarAviso(context, '✗ Falta sincronizar los otros aparatos');
    }
  }

  Future<void> _crearCategoria() async {
    final controller = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('Nueva categoría'),
        contenido: TextField(controller: controller, autofocus: true),
        acciones: BentoAcciones(
          izquierda: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
          derecha: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (nombre == null || nombre.isEmpty || !mounted) return;

    final categoria = Categoria(id: _uuid.v4(), nombre: nombre, updatedAt: DateTime.now());
    await ref.read(categoriaNotifierProvider.notifier).crear(categoria);
    if (mounted) setState(() => _categoriaId = categoria.id);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final ahora = DateTime.now();
    final notifier = ref.read(productoNotifierProvider.notifier);
    final precio = _precioBaseParaGuardar();

    if (_esEdicion) {
      await notifier.actualizar(
        Producto(
          id: widget.producto!.id,
          nombre: _nombreController.text.trim(),
          imagen: _imagen,
          categoriaId: _categoriaId,
          precioBase: precio,
          variantes: _variantesParaGuardar(),
          updatedAt: ahora,
          // Preserva deletedAt tal cual estaba — editar un producto NO debe
          // reactivar uno descontinuado por accidente (no existe una acción
          // explícita de "reactivar" todavía, esto habría sido una puerta
          // trasera silenciosa para hacerlo).
          deletedAt: widget.producto!.deletedAt,
        ),
      );
    } else {
      await notifier.crear(
        Producto(
          id: _uuid.v4(),
          nombre: _nombreController.text.trim(),
          imagen: _imagen,
          categoriaId: _categoriaId,
          precioBase: precio,
          variantes: _variantesParaGuardar(),
          updatedAt: ahora,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriaNotifierProvider);

    final formulario = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlDeImagen(
            // Sin elegir nada se ve LO MISMO que va a verse en el catálogo, no
            // un cuadro vacío: así se sabe de antemano cómo va a quedar el
            // producto en la lista, y elegir imagen pasa a ser una decisión en
            // vez de un hueco por llenar.
            imagen: _imagen,
            iconoDeSuCategoria: ref.watch(iconosDeCategoriaProvider)[_categoriaId],
            ocupado: _guardando,
            onElegir: _elegirImagen,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          TextFormField(
            controller: _nombreController,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          // Los campos con contorno necesitan aire entre sí: la etiqueta
          // flotante se dibuja SOBRE el borde superior, y pegados, "Precio
          // base" caía encima de la línea de abajo del campo Nombre.
          const SizedBox(height: BentoSpacing.unidad),
          // Sin variantes, el precio es un número. Con variantes el número
          // sería letra muerta —se cobra el de la variante—, así que el campo
          // se convierte en el señalador de cuál es la por defecto (abajo, en
          // la lista): su precio pasa a ser el precio base.
          if (_variantes.isEmpty)
            TextFormField(
              controller: _precioController,
              decoration: const InputDecoration(labelText: 'Precio base (₡)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requerido';
                if (double.tryParse(v) == null) return 'Número inválido';
                return null;
              },
            ),
          if (_variantes.isEmpty) const SizedBox(height: BentoSpacing.unidad),
          categoriasAsync.when(
            data: (categorias) {
              // El producto puede apuntar a una categoría que ya no está —
              // pasa tras importar un catálogo con reemplazo, o cuando la
              // sincronización trae un borrado. Sin esta entrada extra, el
              // `DropdownButton` REVIENTA la pantalla entera con un assert
              // ("exactly one item with value X"), y editar el producto para
              // arreglarlo se vuelve imposible: justo lo que hace falta.
              //
              // Se muestra en vez de caer a "Sin categoría" en silencio: que
              // el dato esté roto tiene que verse, y elegir otra categoría lo
              // corrige al guardar.
              final huerfana = _categoriaId != null && !categorias.any((c) => c.id == _categoriaId);
              return Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _categoriaId,
                      // El desplegable ocupa el ancho que le den y recorta lo
                      // que sobre. Sin esto se dimensiona por su etiqueta más
                      // larga y se sale de la caja: "(categoría eliminada)"
                      // ya desbordaba 4,4 px, y un nombre de categoría largo
                      // haría lo mismo.
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      // Con elipsis, no cortado en seco: `isExpanded` recorta
                      // por el ancho disponible y sin esto un nombre largo
                      // termina a mitad de palabra, sin señal de que sigue.
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Sin categoría', overflow: TextOverflow.ellipsis),
                        ),
                        for (final c in categorias)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                          ),
                        if (huerfana)
                          DropdownMenuItem(
                            value: _categoriaId,
                            child: const Text(
                              'Categoría eliminada',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoriaId = v),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nueva categoría',
                    onPressed: _crearCategoria,
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (e, st) => BentoFalla(
              mensaje: 'No se pudieron cargar las categorías.',
              error: e,
              onReintentar: () => ref.invalidate(categoriaNotifierProvider),
            ),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          _EditorDeVariantes(
            variantes: _variantes,
            porDefecto: _porDefecto,
            onPorDefecto: (id) => setState(() => _porDefecto = id),
            ocupado: _guardando,
            onAgregar: _agregarVariante,
            onQuitar: _quitarVariante,
            onMover: _moverVariante,
            // Se valida contra las demás: dos variantes con el mismo nombre
            // se venderían como la misma, y el ranking las juntaría.
            nombreRepetido: (v) => _variantes.any(
              (otra) =>
                  otra != v &&
                  otra.nombre.text.trim().toLowerCase() == v.nombre.text.trim().toLowerCase(),
            ),
          ),
        ],
      ),
    );

    // Borrar de verdad es solo del Gerente. La lista del catálogo ya lo tenía
    // así, pero este diálogo ofrecía "Eliminar" a cualquiera: la Registradora
    // abría un producto descontinuado y podía purgarlo. Un borrado físico no se
    // deshace ni se recupera del otro teléfono —se propaga como borrado—, y una
    // caja no tiene por qué poder hacer eso. Descontinuar sí: eso es la
    // operación reversible que le corresponde.
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

    // Cancelar y Guardar en la MISMA fila, Cancelar a la izquierda. Antes iban
    // apilados los dos en la columna derecha, así que el sitio al que va el
    // pulgar sin mirar caía en Cancelar la mitad de las veces.
    //
    // Reactivar y Eliminar bajan a las filas siguientes de la izquierda: quedan
    // lejos de donde se pulsa para guardar, que es justo donde no se quiere un
    // borrado.
    final acciones = BentoAcciones(
      izquierda: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (_esEdicion && !widget.producto!.activo) ...[
          TextButton(onPressed: _guardando ? null : _reactivar, child: const Text('Reactivar')),
          if (esGerente)
            TextButton(onPressed: _guardando ? null : _eliminar, child: const Text('Eliminar')),
        ],
      ],
      derecha: [
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );

    return BentoDialogo(
      titulo: Text(_esEdicion ? 'Editar producto' : 'Nuevo producto'),
      contenido: formulario,
      acciones: acciones,
    );
  }
}

/// La imagen del producto en el formulario: vista previa y "elegir del banco".
class _ControlDeImagen extends StatelessWidget {
  const _ControlDeImagen({
    required this.imagen,
    required this.iconoDeSuCategoria,
    required this.ocupado,
    required this.onElegir,
  });

  final String? imagen;
  final String? iconoDeSuCategoria;
  final bool ocupado;
  final VoidCallback onElegir;

  /// Cuánto ocupa la vista previa. Un cuadro y no una franja ancha: es lo que se
  /// va a ver en la lista, y mostrarlo con otra forma prometería algo que
  /// después no se cumple.
  static const _lado = 72.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _lado,
          height: _lado,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BentoRadius.pozo),
            child: ImagenDelBancoVista(
              referencia: imagen,
              ventana: VentanaConFotos.inventario,
              iconoDeSuCategoria: iconoDeSuCategoria,
            ),
          ),
        ),
        const SizedBox(width: BentoSpacing.gapCelda),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: ocupado ? null : onElegir,
              icon: const Icon(Icons.image_outlined),
              label: Text(imagen == null ? 'Elegir imagen' : 'Cambiar imagen'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Una variante mientras se edita: sus dos campos y el id que conserva.
///
/// El id se mantiene al editar para que el costeo, que apunta a la variante
/// por id, no pierda la receta cuando se corrige el nombre (0039).
class _VarianteEnEdicion {
  _VarianteEnEdicion._(this.id, String nombre, String precio)
    : nombre = TextEditingController(text: nombre),
      precio = TextEditingController(text: precio);

  factory _VarianteEnEdicion.de(Variante v) =>
      _VarianteEnEdicion._(v.id, v.nombre, montoParaEditar(v.precio));

  factory _VarianteEnEdicion.nueva() => _VarianteEnEdicion._(_uuid.v4(), '', '');

  final String id;
  final TextEditingController nombre;
  final TextEditingController precio;

  void dispose() {
    nombre.dispose();
    precio.dispose();
  }
}

/// La lista de variantes del formulario: una fila por variante con nombre,
/// precio y quitar, y un botón para sumar otra.
///
/// Sin cabecera ni explicación cuando no hay ninguna: la mayoría de los
/// productos no tiene, y un bloque vacío con título en cada formulario sería
/// ruido en el caso normal. El botón solo ya dice qué es.
class _EditorDeVariantes extends StatelessWidget {
  const _EditorDeVariantes({
    required this.variantes,
    required this.porDefecto,
    required this.onPorDefecto,
    required this.ocupado,
    required this.onAgregar,
    required this.onQuitar,
    required this.onMover,
    required this.nombreRepetido,
  });

  final List<_VarianteEnEdicion> variantes;

  /// Cuál lleva el precio base. El radio de cada fila es el señalador que
  /// reemplaza al campo numérico mientras haya variantes.
  final String? porDefecto;
  final ValueChanged<String> onPorDefecto;
  final bool ocupado;
  final VoidCallback onAgregar;
  final ValueChanged<_VarianteEnEdicion> onQuitar;

  /// Un puesto hacia arriba (−1) o hacia abajo (+1).
  final void Function(_VarianteEnEdicion, int) onMover;
  final bool Function(_VarianteEnEdicion) nombreRepetido;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // Un solo grupo para todos los radios: la marcada es la por defecto.
    return RadioGroup<String>(
      groupValue: variantes.isEmpty ? null : (porDefecto ?? variantes.first.id),
      onChanged: ocupado ? (_) {} : (id) => onPorDefecto(id!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (variantes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: BentoSpacing.unidad / 2),
              child: Text(
                'Variantes · la marcada es la que se cobra si no se elige otra',
                style: tema.textTheme.bodySmall,
              ),
            ),
          for (final v in variantes) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: BentoSpacing.unidad),
                  child: Radio<String>(value: v.id),
                ),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: v.nombre,
                    decoration: const InputDecoration(labelText: 'Variante'),
                    validator: (texto) {
                      if (texto == null || texto.trim().isEmpty) {
                        return 'Requerido';
                      }
                      if (nombreRepetido(v)) return 'Repetida';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: BentoSpacing.unidad),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: v.precio,
                    decoration: const InputDecoration(labelText: 'Precio (₡)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (texto) {
                      if (texto == null || texto.trim().isEmpty) {
                        return 'Requerido';
                      }
                      if (double.tryParse(texto) == null) return 'Inválido';
                      return null;
                    },
                  ),
                ),
                // Subir, bajar y quitar, compactos: tres acciones en una fila
                // que ya lleva dos campos. Las flechas se apagan en los
                // extremos, así el orden se lee también en qué se puede tocar.
                Padding(
                  padding: const EdgeInsets.only(top: BentoSpacing.unidad / 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        tooltip: 'Subir',
                        visualDensity: VisualDensity.compact,
                        onPressed: ocupado || variantes.first == v ? null : () => onMover(v, -1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 18),
                        tooltip: 'Bajar',
                        visualDensity: VisualDensity.compact,
                        onPressed: ocupado || variantes.last == v ? null : () => onMover(v, 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Quitar variante',
                        visualDensity: VisualDensity.compact,
                        onPressed: ocupado ? null : () => onQuitar(v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: BentoSpacing.unidad),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: ocupado ? null : onAgregar,
              icon: const Icon(Icons.add),
              label: Text(variantes.isEmpty ? 'Agregar variante' : 'Otra variante'),
            ),
          ),
        ],
      ),
    );
  }
}
