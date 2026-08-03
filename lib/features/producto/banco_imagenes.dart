import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/bento_icono_producto.dart';
import 'imagen_producto_service.dart';

const _uuid = Uuid();

/// Una imagen del banco: o un icono de la casa, o una foto guardada.
///
/// Las dos se referencian con una cadena que va a `producto.imagen`, y ese texto
/// es la única forma de saber cuál es cuál — no hay tabla ni columna extra. Con
/// prefijo `ico:` es un icono; sin él, el nombre de un archivo del banco.
/// Elegir el prefijo y no una columna nueva mantiene el esquema, el sync y el
/// backup exactamente como estaban.
sealed class ImagenDelBanco {
  const ImagenDelBanco();

  /// Lo que se guarda en `producto.imagen`.
  String get referencia;

  /// Lee una referencia guardada. Lo que no se entienda cae a `null`, y un
  /// producto sin imagen reconocible se ve sin ella: una referencia rota no
  /// puede dejar la lista en blanco.
  static ImagenDelBanco? de(String? referencia) {
    if (referencia == null || referencia.isEmpty) return null;
    for (final prefijo in IconoDelBanco.prefijos) {
      if (referencia.startsWith(prefijo)) {
        return IconoDelBanco(referencia.substring(prefijo.length));
      }
    }
    return FotoDelBanco(referencia);
  }
}

/// Un icono de la casa. No ocupa disco: es un glifo de la fuente que la app ya
/// carga, elegido por su [clave].
class IconoDelBanco extends ImagenDelBanco {
  const IconoDelBanco(this.clave);

  static const prefijo = 'ico:';

  /// Se lee `abs:` además del prefijo actual, y no se escribe nunca: es el que
  /// usaban las figuras abstractas, y el aparato ya tiene productos guardados
  /// con él. Dejar de entenderlo les borraría la imagen a todos de golpe.
  static const prefijos = [prefijo, 'abs:'];

  final String clave;

  @override
  String get referencia => '$prefijo$clave';
}

/// Una foto que alguien agregó desde la galería o la cámara.
class FotoDelBanco extends ImagenDelBanco {
  const FotoDelBanco(this.archivo);

  /// Solo el nombre, nunca la ruta: el directorio de datos cambia entre
  /// instalaciones y sistemas, y una ruta absoluta guardada en la base deja de
  /// resolver en cuanto el aparato es otro — o el mismo, reinstalado.
  final String archivo;

  @override
  String get referencia => archivo;
}

/// El banco de imágenes: de dónde elige su cara un producto.
///
/// Trae **iconos de la casa** —no hay que agregar nada para tener de dónde
/// elegir, y no pesan— y deja **sumar fotos** desde la galería o la cámara. Las
/// fotos se guardan una vez y sirven para todos los productos que las quieran:
/// es un banco, no un adjunto por producto.
///
/// **No entra en el backup** (decisión 0033). El `.tiketback` es la copia de la
/// contabilidad; meterle las fotos lo multiplicaría de tamaño para proteger algo
/// que no es un dato contable, y que además se puede volver a sacar con la
/// cámara. Un producto cuya foto no está en este aparato se ve sin imagen,
/// exactamente igual que uno que nunca tuvo.
class BancoDeImagenes {
  const BancoDeImagenes();

  /// Cuántos iconos de la casa ofrece.
  int get iconosDeFabrica => iconosDeProducto.length;

  /// Los iconos de la casa, siempre los mismos y en el mismo orden.
  List<IconoDelBanco> iconos() => [
    for (final icono in iconosDeProducto) IconoDelBanco(icono.clave),
  ];

  Future<Directory> carpeta() async {
    final base = await getApplicationDocumentsDirectory();
    final carpeta = Directory(p.join(base.path, 'banco-imagenes'));
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    return carpeta;
  }

  /// Las fotos agregadas, de la más nueva a la más vieja.
  ///
  /// La última agregada primero porque es la que se acaba de sacar: quien viene
  /// de la cámara la quiere ahí, no al final de una cuadrícula.
  Future<List<FotoDelBanco>> fotos() async {
    final carpeta = await this.carpeta();
    final archivos = carpeta.listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return [for (final f in archivos) FotoDelBanco(p.basename(f.path))];
  }

  Future<File?> archivoDe(FotoDelBanco foto) async {
    final archivo = File(p.join((await carpeta()).path, foto.archivo));
    return await archivo.exists() ? archivo : null;
  }

  /// Toma una foto o la elige de la galería, la achica y la suma al banco.
  ///
  /// Devuelve `null` si se cancela. El achicado es el mismo de
  /// [ImagenProductoService]: el destino es una miniatura, no un archivo de
  /// impresión.
  Future<FotoDelBanco?> agregar(ImageSource origen, {ImagePicker? selector}) async {
    final elegida = await (selector ?? ImagePicker()).pickImage(
      source: origen,
      // El recorte lo hace el propio selector cuando puede: pedir la imagen ya
      // limitada evita cargar en memoria una foto de doce megapíxeles solo para
      // reducirla después.
      maxWidth: ImagenProductoService.ladoMaximo.toDouble(),
      imageQuality: 85,
    );
    if (elegida == null) return null;

    final nombre = '${_uuid.v4()}${p.extension(elegida.path).toLowerCase()}';
    await File(elegida.path).copy(p.join((await carpeta()).path, nombre));
    return FotoDelBanco(nombre);
  }

  /// Saca una foto del banco.
  ///
  /// No se comprueba si algún producto la estaba usando: el que la tuviera se
  /// queda con una referencia que no resuelve, y eso ya se ve como una figura.
  /// Bloquear el borrado obligaría a recorrer el catálogo entero para contestar
  /// una pregunta que el usuario ya contestó al tocar "quitar".
  Future<void> borrar(FotoDelBanco foto) async {
    try {
      await File(p.join((await carpeta()).path, foto.archivo)).delete();
    } catch (_) {}
  }
}

final bancoDeImagenesProvider = Provider<BancoDeImagenes>((ref) => const BancoDeImagenes());

/// Lo que hay ahora en el banco. Se invalida al agregar o borrar.
final fotosDelBancoProvider = FutureProvider<List<FotoDelBanco>>(
  (ref) => ref.read(bancoDeImagenesProvider).fotos(),
);
