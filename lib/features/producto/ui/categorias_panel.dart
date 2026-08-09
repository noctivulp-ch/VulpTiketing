import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_icono_producto.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../categoria_model.dart';
import '../categoria_notifier.dart';
import '../producto_notifier.dart';

const _uuid = Uuid();

/// Gestión de categorías: crear, renombrar y sacar de la carta.
///
/// Antes solo se podían **crear**, y desde el `+` del formulario de producto —
/// o sea que para arreglar una categoría mal escrita había que editarla en el
/// archivo del catálogo y volver a importarlo. Renombrar y descontinuar no
/// existían en la app pese a estar resueltos en `CategoriaNotifier` desde el
/// principio: era un hueco de interfaz, no de lógica.
///
/// El `+` del formulario de producto se queda: crear al vuelo mientras se da de
/// alta un producto es un camino distinto del de sentarse a ordenar la carta, y
/// obligar a salir a Configuración para inventar una categoría sería peor.
class PanelCategorias extends ConsumerStatefulWidget {
  const PanelCategorias({super.key});

  @override
  ConsumerState<PanelCategorias> createState() => _PanelCategoriasState();
}

class _PanelCategoriasState extends ConsumerState<PanelCategorias> {
  final _nuevaController = TextEditingController();
  bool _ocupado = false;

  @override
  void dispose() {
    _nuevaController.dispose();
    super.dispose();
  }

  /// Cuántos productos —de la carta o fuera de ella— apuntan a esta categoría.
  ///
  /// Se cuentan **todos**, no solo los activos: un producto descontinuado sigue
  /// perteneciendo a su categoría, y si se recontinúa mañana tiene que volver a
  /// su sitio.
  ///
  /// Va con `watch` y no con `read`: leer un provider que nadie está observando
  /// devuelve su estado inicial sin llegar a cargarlo, así que los conteos
  /// salían todos en cero.
  int _cuantosUsan(String categoriaId) {
    final productos = ref.watch(productoNotifierProvider).valueOrNull ?? const [];
    return productos.where((p) => p.categoriaId == categoriaId).length;
  }

  Future<void> _crear() async {
    final nombre = _nuevaController.text.trim();
    if (nombre.isEmpty) return;

    if (_yaExiste(nombre)) {
      mostrarAviso(context, 'Ya hay una categoría con ese nombre');
      return;
    }

    setState(() => _ocupado = true);
    await ref
        .read(categoriaNotifierProvider.notifier)
        .crear(Categoria(id: _uuid.v4(), nombre: nombre, updatedAt: DateTime.now()));
    if (!mounted) return;
    _nuevaController.clear();
    setState(() => _ocupado = false);
    mostrarAviso(context, '✓ Categoría creada');
  }

  /// Nombre repetido, ignorando mayúsculas y espacios de sobra.
  ///
  /// Dos categorías que se llaman igual no son un error de la base —cada una
  /// tiene su id— pero sí lo son en la pantalla: quien las ve no puede saber en
  /// cuál está poniendo el producto.
  bool _yaExiste(String nombre, {String? exceptoId}) {
    final actuales = ref.read(categoriaNotifierProvider).valueOrNull ?? const [];
    final buscado = nombre.trim().toLowerCase();
    return actuales.any((c) => c.id != exceptoId && c.nombre.trim().toLowerCase() == buscado);
  }

  Future<void> _renombrar(Categoria categoria) async {
    final controller = TextEditingController(text: categoria.nombre);
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogo) => BentoDialogo(
        titulo: const Text('Renombrar categoría'),
        contenido: TextField(controller: controller, autofocus: true),
        acciones: BentoAcciones(
          izquierda: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogo, controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
          derecha: [
            TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('Cancelar')),
          ],
        ),
      ),
    );
    // Se libera DESPUÉS del cuadro, no aquí: `showDialog` devuelve en cuanto se
    // llama a `pop`, pero el diálogo sigue en pantalla mientras dura la
    // animación de cierre y su `TextField` vuelve a construirse. Liberarlo en
    // este punto reventaba con "A TextEditingController was used after being
    // disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    if (nombre == null || nombre.isEmpty || nombre == categoria.nombre || !mounted) return;

    if (_yaExiste(nombre, exceptoId: categoria.id)) {
      mostrarAviso(context, 'Ya hay una categoría con ese nombre');
      return;
    }

    // Los productos NO se tocan: apuntan al id, no al nombre. Renombrar
    // "Arroces" a "Arroz" los deja a todos donde estaban, que es justo lo que
    // se espera de un renombrado.
    //
    // Y con `copyWith`, no construyendo una `Categoria` a mano: así se hacía
    // antes y el icono elegido se perdía en silencio, porque el constructor no
    // lo pide.
    await ref
        .read(categoriaNotifierProvider.notifier)
        .actualizar(categoria.copyWith(nombre: nombre, updatedAt: DateTime.now()));
    if (mounted) mostrarAviso(context, '✓ Categoría renombrada');
  }

  /// Elegir a mano el icono de una categoría.
  ///
  /// El acierto por nombre está bien y sigue siendo el defecto, pero no es
  /// infalible: sale de una tabla de palabras, y una categoría que el negocio
  /// llame "Especiales" o "Lo de la casa" no tiene de dónde adivinarse. Una
  /// categoría con la cara equivocada es peor que una sin cara — dice algo que
  /// no es.
  Future<void> _elegirIcono(Categoria categoria) async {
    final elegido = await showDialog<String>(
      context: context,
      builder: (dialogo) => _DialogoDeIcono(
        actual: categoria.icono,
        automatico: iconoDeCategoria(categoria.nombre).clave,
      ),
    );
    if (elegido == null || !mounted) return;

    await ref
        .read(categoriaNotifierProvider.notifier)
        .actualizar(
          categoria.copyWith(
            // Cadena vacía = "volver al automático". Se distingue de `null`
            // —que es cancelar— porque volver al automático es una elección.
            icono: (valor: elegido.isEmpty ? null : elegido),
            updatedAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    // Los productos que no tienen imagen propia llevan el icono de su
    // categoría: si no se refresca, la carta sigue con el anterior.
    ref.invalidate(productoNotifierProvider);
    mostrarAviso(context, elegido.isEmpty ? '✓ Icono automático' : '✓ Icono cambiado');
  }

  Future<void> _descontinuar(Categoria categoria) async {
    final usan = _cuantosUsan(categoria.id);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => BentoDialogo(
        titulo: Text('Sacar "${categoria.nombre}"'),
        // Se dice CUÁNTOS productos quedan sin categoría, no un "¿estás
        // seguro?" genérico: el número es lo que permite decidir, y sin él la
        // pregunta no da ninguna información que el usuario no tuviera ya.
        contenido: Text(
          usan == 0
              ? 'No hay productos en esta categoría. Se puede sacar sin más.'
              : 'Hay $usan producto${usan == 1 ? '' : 's'} en esta categoría. '
                    'No se borran: quedan sin categoría y se les puede poner otra '
                    'desde Inventario.',
        ),
        acciones: BentoAcciones(
          izquierda: [
            FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Sacar')),
          ],
          derecha: [
            TextButton(
              onPressed: () => Navigator.pop(dialogo, false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    await ref.read(categoriaNotifierProvider.notifier).descontinuar(categoria.id);
    if (!mounted) return;
    // El catálogo agrupa por categoría, así que lo que acaba de quedar huérfano
    // tiene que reordenarse ya: si no, los productos siguen bajo un título que
    // ya no existe.
    ref.invalidate(productoNotifierProvider);
    mostrarAviso(context, '✓ Categoría fuera de la carta');
  }

  @override
  Widget build(BuildContext context) {
    final categorias = ref.watch(categoriaNotifierProvider);
    final textos = Theme.of(context).textTheme;

    return BentoPanel(
      titulo: 'Categorías',
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Agrupan los productos en la carta y deciden qué icono les toca '
            'cuando no tienen imagen propia.',
            style: textos.bodySmall,
          ),
          const SizedBox(height: BentoSpacing.gapCelda),
          switch (categorias) {
            AsyncData(:final value) when value.isEmpty => Text(
              'Todavía no hay ninguna. Creá la primera abajo.',
              style: textos.bodySmall,
            ),
            AsyncData(:final value) => Column(
              children: [
                for (final categoria in value)
                  _FilaCategoria(
                    categoria: categoria,
                    productos: _cuantosUsan(categoria.id),
                    onRenombrar: () => _renombrar(categoria),
                    onElegirIcono: () => _elegirIcono(categoria),
                    onDescontinuar: () => _descontinuar(categoria),
                  ),
              ],
            ),
            AsyncError() => Text('No se pudo cargar la lista.', style: textos.bodySmall),
            _ => const Center(child: CircularProgressIndicator()),
          },
          const SizedBox(height: BentoSpacing.gapCelda),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nuevaController,
                  decoration: const InputDecoration(labelText: 'Nueva categoría', isDense: true),
                  onSubmitted: (_) => _ocupado ? null : _crear(),
                ),
              ),
              const SizedBox(width: BentoSpacing.unidad),
              FilledButton(onPressed: _ocupado ? null : _crear, child: const Text('Crear')),
            ],
          ),
        ],
      ),
      acciones: const [],
    );
  }
}

class _FilaCategoria extends StatelessWidget {
  const _FilaCategoria({
    required this.categoria,
    required this.productos,
    required this.onRenombrar,
    required this.onElegirIcono,
    required this.onDescontinuar,
  });

  final Categoria categoria;
  final int productos;
  final VoidCallback onRenombrar;
  final VoidCallback onElegirIcono;
  final VoidCallback onDescontinuar;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: BentoSpacing.unidad),
      child: BentoPozo(
        // Tocar la fila renombra: es lo que se viene a hacer acá nueve de cada
        // diez veces, y esconderlo tras un icono de lápiz de 24 px lo haría
        // menos alcanzable que sacarla de la carta.
        onTap: onRenombrar,
        padding: const EdgeInsets.symmetric(
          horizontal: BentoSpacing.unidad,
          vertical: BentoSpacing.unidad / 2,
        ),
        child: Row(
          children: [
            // El mismo icono que van a llevar sus productos, y se TOCA para
            // cambiarlo: así se ve de antemano qué cara le toca a la categoría
            // y se corrige ahí mismo cuando el acierto automático falla.
            //
            // Con sus 48 dp aunque el dibujo mida 20: un objetivo del tamaño
            // del glifo no se acierta con el pulgar.
            Tooltip(
              message: 'Elegir icono',
              child: InkWell(
                onTap: onElegirIcono,
                borderRadius: BorderRadius.circular(BentoRadius.pozo),
                child: SizedBox(
                  width: bentoObjetivoTactilMin,
                  height: bentoObjetivoTactilMin,
                  child: Icon(
                    iconoDeProductoDe(
                      categoria.icono ?? iconoDeCategoria(categoria.nombre).clave,
                    ).icono,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: BentoSpacing.unidad / 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(categoria.nombre, style: textos.bodyLarge, maxLines: 2),
                  Text(
                    [
                      if (productos == 0)
                        'Sin productos'
                      else
                        '$productos producto${productos == 1 ? '' : 's'}',
                      // Solo se dice cuando el icono se eligió a mano: "icono
                      // automático" en todas las filas sería ruido, porque es
                      // lo normal.
                      if (categoria.icono != null) 'icono propio',
                    ].join(' · '),
                    style: textos.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.block),
              tooltip: 'Sacar de la carta',
              onPressed: onDescontinuar,
            ),
          ],
        ),
      ),
    );
  }
}

/// Elegir el icono de una categoría a mano.
///
/// Devuelve la clave elegida, `''` para volver al automático, o `null` si se
/// cancela. Los tres son distintos: volver al automático es una elección, no un
/// cancelar, y es la que deshace un cambio del que uno se arrepiente.
class _DialogoDeIcono extends StatelessWidget {
  const _DialogoDeIcono({required this.actual, required this.automatico});

  /// Lo que la categoría tiene elegido, o `null` si va por nombre.
  final String? actual;

  /// El que saldría del nombre. Se marca como tal para que se entienda que
  /// **no elegir** también es una opción con resultado, no un hueco.
  final String automatico;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BentoDialogo(
      titulo: const Text('Icono de la categoría'),
      contenido: SizedBox(
        width: 420,
        child: BentoCuadricula(
          separacion: BentoSpacing.unidad,
          hijos: [
            for (final icono in iconosDeProducto)
              BentoCelda.fija(
                1,
                hijo: AspectRatio(
                  aspectRatio: 1,
                  child: Tooltip(
                    message: icono.clave == automatico
                        ? '${icono.etiqueta} (el automático)'
                        : icono.etiqueta,
                    child: BentoPozo(
                      onTap: () => Navigator.pop(context, icono.clave),
                      seleccionado: icono.clave == actual,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        icono.icono,
                        // El que saldría solo se distingue aunque no esté
                        // elegido: sin eso, "volver al automático" es un botón
                        // que no dice a qué se vuelve.
                        color: icono.clave == (actual ?? automatico)
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      acciones: BentoAcciones(
        izquierda: [
          if (actual != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Automático'),
            ),
        ],
        derecha: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
