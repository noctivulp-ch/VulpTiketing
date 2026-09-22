import 'package:flutter/material.dart';

import 'bento_theme.dart';

/// Un icono de la casa: la cara que puede tomar un producto sin sacar una foto.
///
/// Reemplaza a las figuras abstractas que había antes. Eran distintas entre sí y
/// estables, que era lo que se buscaba, pero no **significaban** nada: un
/// triángulo y dos círculos no dicen "café", así que para encontrar algo en la
/// lista había que leer el nombre igual — la imagen solo ocupaba sitio. Un icono
/// de taza se reconoce antes de leer, que es justo lo que tiene que hacer una
/// imagen en una carta de cuarenta productos.
///
/// Siguen sin ocupar disco y sin entrar en el backup: es un `IconData` de la
/// fuente que la app ya carga, no un archivo.
class IconoDeProducto {
  const IconoDeProducto(this.clave, this.icono, this.etiqueta);

  /// Lo que va en la referencia, después del prefijo. En español y estable:
  /// renombrar la etiqueta no puede cambiarle la cara a un producto.
  final String clave;

  final IconData icono;

  /// Para el diálogo del banco. Un icono suelto es adivinable, pero veinte
  /// juntos se parecen entre sí más de lo que uno cree.
  final String etiqueta;
}

/// El catálogo, en el orden en que se ofrece.
///
/// Salen de la carta de la soda, no de un set genérico de comida: primero lo que
/// más se vende —bebidas y casados— y al final lo suelto. Ese orden es el que
/// decide cuáles se ven sin desplazar en el diálogo.
const iconosDeProducto = <IconoDeProducto>[
  IconoDeProducto('cafe', Icons.local_cafe, 'Café'),
  IconoDeProducto('refresco', Icons.local_drink, 'Refresco'),
  IconoDeProducto('batido', Icons.blender, 'Batido'),
  IconoDeProducto('gaseosa', Icons.local_bar, 'Gaseosa'),
  IconoDeProducto('agua', Icons.water_drop, 'Agua'),
  IconoDeProducto('casado', Icons.rice_bowl, 'Casado'),
  IconoDeProducto('sopa', Icons.ramen_dining, 'Sopa'),
  IconoDeProducto('carne', Icons.kebab_dining, 'Carne'),
  IconoDeProducto('plato', Icons.set_meal, 'Plato'),
  IconoDeProducto('hamburguesa', Icons.lunch_dining, 'Hamburguesa'),
  IconoDeProducto('sandwich', Icons.brunch_dining, 'Sándwich'),
  IconoDeProducto('desayuno', Icons.free_breakfast, 'Desayuno'),
  IconoDeProducto('reposteria', Icons.bakery_dining, 'Repostería'),
  IconoDeProducto('bocas', Icons.tapas, 'Bocas'),
  IconoDeProducto('postre', Icons.icecream, 'Postre'),
  IconoDeProducto('abarrote', Icons.shopping_bag, 'Abarrote'),
];

/// Cuando la clave no está en el catálogo. Pasa con las referencias que dejaron
/// las figuras abstractas (`abs:figura-7`) y con una base traída de una versión
/// más nueva que trajera un icono que aquí todavía no existe.
const iconoDeProductoPorDefecto = IconoDeProducto('otro', Icons.restaurant, 'Otro');

/// Qué palabra en el nombre de una categoría delata qué icono le toca.
///
/// Son **principios de palabra**, no fragmentos sueltos, y por eso aguantan el
/// plural: "arroc" alcanza tanto "arroz" como "arroces", que es como está
/// escrita la categoría de verdad. Buscar el fragmento en cualquier posición
/// era peor de lo que parece — "te" casaba dentro de "reposTEría" y dejaba la
/// repostería con cara de café.
///
/// El orden importa: gana la primera que coincida, así que lo específico va
/// antes que lo general — "Batidos en Leche" tiene que dar batido, no leche.
const _pistasDeCategoria = <String, String>{
  'batido': 'batido',
  'frappe': 'batido',
  'refresco': 'refresco',
  'fresco': 'refresco',
  'natural': 'refresco',
  'gaseosa': 'gaseosa',
  'soda': 'gaseosa',
  'cerveza': 'cerveza',
  'birra': 'cerveza',
  'licor': 'licor',
  'vino': 'licor',
  'ron': 'licor',
  'guaro': 'licor',
  'jugo': 'jugo',
  'zumo': 'jugo',
  'agua': 'agua',
  'cafe': 'cafe',
  'te': 'te',
  'infusion': 'te',
  'leche': 'batido',
  'arroc': 'casado',
  'arroz': 'casado',
  'casado': 'casado',
  'almuerzo': 'casado',
  'plato': 'plato',
  'sopa': 'sopa',
  'caldo': 'sopa',
  'olla': 'sopa',
  'carne': 'carne',
  'pollo': 'carne',
  'pescado': 'plato',
  'marisco': 'plato',
  'hamburguesa': 'hamburguesa',
  'sandwich': 'sandwich',
  'emparedado': 'sandwich',
  'desayuno': 'desayuno',
  'gallo': 'desayuno',
  'pinto': 'desayuno',
  'pan': 'reposteria',
  'reposteria': 'reposteria',
  'postre': 'postre',
  'dulce': 'postre',
  'helado': 'postre',
  'boca': 'bocas',
  'empanada': 'bocas',
  'tamal': 'bocas',
  'frito': 'bocas',
  'abarrote': 'abarrote',
  'pizza': 'pizza',
  'pasta': 'pasta',
  'fideo': 'pasta',
  'ensalada': 'ensalada',
  'verdura': 'ensalada',
  'vegetal': 'ensalada',
  'fruta': 'fruta',
  'huevo': 'huevo',
  'queque': 'torta',
  'torta': 'torta',
  'pastel': 'torta',
  'galleta': 'galleta',
  'ropa': 'ropa',
  'camisa': 'ropa',
  'pantalon': 'ropa',
  'zapato': 'calzado',
  'calzado': 'calzado',
  'tenis': 'calzado',
  'ferreter': 'ferreteria',
  'herramienta': 'ferreteria',
  'tornillo': 'ferreteria',
  'pintura': 'ferreteria',
  'farmacia': 'farmacia',
  'medicamento': 'farmacia',
  'medicina': 'farmacia',
  'limpieza': 'limpieza',
  'jabon': 'limpieza',
  'detergente': 'limpieza',
  'mascota': 'mascotas',
  'perro': 'mascotas',
  'gato': 'mascotas',
  'papeler': 'papeleria',
  'cuaderno': 'papeleria',
  'util': 'papeleria',
  'electron': 'electronica',
  'celular': 'electronica',
  'cable': 'electronica',
  'belleza': 'belleza',
  'cosmetic': 'belleza',
  'maquillaje': 'belleza',
  'jugete': 'juguete',
  'juguete': 'juguete',
  'flor': 'flores',
  'servicio': 'servicio',
  'reparacion': 'servicio',
  'arreglo': 'servicio',
  // Al final del todo: son el cajón de sastre, y cualquiera de ellas ganaría a
  // una pista específica si estuviera antes.
  //
  // Entre ellas el orden también cuenta: "Comidas Rápidas" tiene las dos, y con
  // `comida` delante salía un plato de restaurante en vez de la hamburguesa.
  'rapida': 'hamburguesa',
  'bebida': 'refresco',
  'trago': 'refresco',
  'comida': 'plato',
  'extra': 'bocas',
  'acompan': 'bocas',
};

/// El icono que le toca a un producto por su **categoría**, cuando nadie le
/// eligió uno.
///
/// Sale del nombre de la categoría y no de una columna nueva: las categorías
/// las escribe el negocio ("Arroces", "Batidos en Leche"), y pedirle además que
/// le asigne un dibujo a cada una sería trabajo de configuración para llegar al
/// mismo sitio. Una categoría cuyo nombre no diga nada reconocible cae al icono
/// neutro, que es exactamente lo que había antes.
///
/// Es solo el **defecto**: lo que el producto tenga elegido siempre manda.
IconoDeProducto iconoDeCategoria(String? nombreCategoria) {
  if (nombreCategoria == null) return iconoDeProductoPorDefecto;
  final palabras = _sinTildes(
    nombreCategoria.toLowerCase(),
  ).split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty);

  for (final pista in _pistasDeCategoria.entries) {
    if (palabras.any((palabra) => palabra.startsWith(pista.key))) {
      return iconoDeProductoDe(pista.value);
    }
  }
  return iconoDeProductoPorDefecto;
}

/// "Café" y "Cafe" tienen que dar lo mismo: el nombre lo escribe una persona a
/// mano y el acento no puede decidir si el producto tiene cara o no.
String _sinTildes(String texto) {
  const con = 'áéíóúüñ';
  const sin = 'aeiouun';
  var salida = texto;
  for (var i = 0; i < con.length; i++) {
    salida = salida.replaceAll(con[i], sin[i]);
  }
  return salida;
}

/// El icono de una clave guardada.
///
/// Las referencias viejas `figura-N` se reparten por el catálogo en vez de caer
/// todas en "Otro": ya había productos con figura elegida en el aparato, y
/// dejarlos a todos con el mismo icono neutro se vería como que se perdió lo
/// que alguien eligió. No acierta el significado —nadie puede—, pero conserva
/// que sean distintos entre sí, que es lo que aquellas figuras daban.
IconoDeProducto iconoDeProductoDe(String clave) {
  for (final icono in iconosDeProducto) {
    if (icono.clave == clave) return icono;
  }
  final vieja = RegExp(r'^figura-(\d+)$').firstMatch(clave);
  if (vieja != null) {
    return iconosDeProducto[int.parse(vieja.group(1)!) % iconosDeProducto.length];
  }
  return iconoDeProductoPorDefecto;
}

/// Pinta un icono de la casa sobre el rebaje del pozo.
///
/// Ocupa lo que le den: la miniatura del carrito, la celda de Venta Rápida y la
/// vista previa del formulario son el mismo widget a distinto tamaño.
class BentoIconoProducto extends StatelessWidget {
  const BentoIconoProducto({super.key, required this.clave, this.apagada = false});

  final String clave;

  /// Para lo que está fuera de la carta: el mismo icono, sin fuerza.
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, restricciones) {
        final lado = restricciones.biggest.shortestSide;
        return ColoredBox(
          color: laca.pozoContacto,
          child: Center(
            child: Icon(
              iconoDeProductoDe(clave).icono,
              // Poco más de la mitad del hueco: con el icono a tamaño completo
              // el dibujo toca los bordes del rebaje y deja de leerse como algo
              // puesto dentro del compartimento.
              size: lado * 0.55,
              color: apagada ? laca.textoAtenuadoEnBandeja : acento,
            ),
          ),
        );
      },
    );
  }
}
