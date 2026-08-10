// Navegacion por el ARBOL DE SEMANTICA, no por coordenadas.
//
// El problema que resuelve: manejar la app desde fuera tocando pixeles es
// lento, fragil y no automatizable. Cada pantalla hay que fotografiarla,
// mirarla y calcular donde cae cada boton; las coordenadas cambian con el
// modelo, con la barra del sistema y con cualquier ajuste de layout; y un tap
// mal calculado puede caer en "Restaurar todo".
//
// La solucion no es una tabla de botones registrados a mano —eso se queda
// viejo en cuanto alguien agrega una pantalla— sino leer el arbol que Flutter
// YA construye para accesibilidad. Ahi esta, sin que nadie lo mantenga:
//
//   - todo lo que se puede tocar, con su etiqueta;
//   - que acciones acepta cada cosa (tap, longPress, scroll, ...);
//   - si esta habilitado, marcado, si es campo de texto;
//   - donde esta en pantalla, por si hace falta.
//
// Y lo mas importante: **se dispara por el mismo camino que el dedo**.
// `SemanticsAction.tap` sobre un nodo ejecuta el mismo callback que un toque
// real — es lo que usan TalkBack y VoiceOver. No es un atajo que puentea la UI:
// es la UI, accionada por su otra puerta.
//
// Consecuencia buscada: un boton nuevo aparece solo. Nadie tiene que acordarse
// de registrarlo, porque nadie lo registro nunca.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

/// Mantiene la semantica encendida mientras el harness este vivo.
///
/// Flutter solo construye el arbol si alguien lo pide —un lector de pantalla, o
/// esto—. Sin esta llamada el arbol esta vacio y todo devuelve cero nodos, que
/// es un fallo especialmente confuso: parece que la pantalla no tiene botones.
SemanticsHandle? _handle;

void encenderSemantica() {
  _handle ??= SemanticsBinding.instance.ensureSemantics();
}

/// Un elemento con el que se puede interactuar.
class NodoInteractuable {
  const NodoInteractuable({
    required this.id,
    required this.etiqueta,
    required this.acciones,
    required this.rect,
    required this.habilitado,
    this.valor,
    this.marcado,
    this.esCampoDeTexto = false,
    this.enfocado = false,
  });

  final int id;
  final String etiqueta;
  final List<String> acciones;
  final List<double> rect;
  final bool habilitado;
  final String? valor;
  final bool? marcado;
  final bool esCampoDeTexto;
  final bool enfocado;

  Map<String, dynamic> aJson() => {
    'id': id,
    'etiqueta': etiqueta,
    'acciones': acciones,
    'rect': rect,
    'habilitado': habilitado,
    if (valor != null && valor!.isNotEmpty) 'valor': valor,
    if (marcado != null) 'marcado': marcado,
    if (esCampoDeTexto) 'campoDeTexto': true,
    if (enfocado) 'enfocado': true,
  };
}

/// Las acciones que interesan de un nodo, con nombres cortos.
///
/// Se filtran a proposito: el arbol trae ademas cosas de accesibilidad pura
/// —mover el cursor por caracteres, anunciar el foco— que no son maneras de
/// "usar" la app y solo harian ruido en la lista.
const _accionesUtiles = <SemanticsAction, String>{
  SemanticsAction.tap: 'tap',
  SemanticsAction.longPress: 'longPress',
  SemanticsAction.scrollLeft: 'scrollLeft',
  SemanticsAction.scrollRight: 'scrollRight',
  SemanticsAction.scrollUp: 'scrollUp',
  SemanticsAction.scrollDown: 'scrollDown',
  SemanticsAction.increase: 'increase',
  SemanticsAction.decrease: 'decrease',
  SemanticsAction.dismiss: 'dismiss',
  SemanticsAction.setText: 'setText',
};

/// Todo lo interactuable de la pantalla actual, en orden de lectura.
///
/// El orden importa para que la lista sea util a ojo: se devuelve de arriba a
/// abajo y de izquierda a derecha, que es como se lee la pantalla, y no en el
/// orden en que el arbol resulte estar armado.
List<NodoInteractuable> listarInteractuables() {
  encenderSemantica();
  final raiz = _raiz();
  if (raiz == null) return const [];

  final encontrados = <NodoInteractuable>[];
  _recorrer(raiz, encontrados, Matrix4.identity());

  encontrados.sort((a, b) {
    // Misma fila si sus centros verticales estan a menos de 24 px: si no, dos
    // botones lado a lado se ordenan por un pixel de diferencia y la lista
    // sale en zigzag.
    final dy = (a.rect[1] - b.rect[1]);
    if (dy.abs() > 8) return dy < 0 ? -1 : 1;
    return a.rect[0].compareTo(b.rect[0]);
  });
  return encontrados;
}

SemanticsNode? _raiz() => WidgetsBinding.instance.pipelineOwner.semanticsOwner?.rootSemanticsNode;

/// Cuantos pixeles fisicos hay por unidad logica. El arbol de semantica trabaja
/// en fisicos; la lista se devuelve en logicos, que son los que usa el layout y
/// los que aparecen en el codigo.
double get _escala => WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

void _recorrer(SemanticsNode nodo, List<NodoInteractuable> salida, Matrix4 heredada) {
  final transform = heredada.multiplied(nodo.transform ?? Matrix4.identity());

  // Un nodo oculto no se puede tocar, y devolverlo haria que el harness
  // intentara accionar algo que el usuario no ve. Pasa de verdad: el
  // `IndexedStack` del shell tiene las cinco pantallas construidas a la vez.
  final datos = nodo.getSemanticsData();
  final invisible = datos.hasFlag(SemanticsFlag.isHidden) || nodo.rect.isEmpty;

  if (!invisible) {
    final acciones = [
      for (final entrada in _accionesUtiles.entries)
        if (datos.hasAction(entrada.key)) entrada.value,
    ];
    if (acciones.isNotEmpty) {
      final esquina = MatrixUtils.transformPoint(transform, nodo.rect.topLeft);
      final opuesta = MatrixUtils.transformPoint(transform, nodo.rect.bottomRight);
      salida.add(
        NodoInteractuable(
          id: nodo.id,
          etiqueta: _etiquetaDe(datos),
          acciones: acciones,
          rect: [
            (esquina.dx / _escala).roundToDouble(),
            (esquina.dy / _escala).roundToDouble(),
            ((opuesta.dx - esquina.dx) / _escala).roundToDouble(),
            ((opuesta.dy - esquina.dy) / _escala).roundToDouble(),
          ],
          habilitado:
              !datos.hasFlag(SemanticsFlag.hasEnabledState) ||
              datos.hasFlag(SemanticsFlag.isEnabled),
          valor: datos.value,
          marcado: datos.hasFlag(SemanticsFlag.hasCheckedState)
              ? datos.hasFlag(SemanticsFlag.isChecked)
              : (datos.hasFlag(SemanticsFlag.hasToggledState)
                    ? datos.hasFlag(SemanticsFlag.isToggled)
                    : null),
          esCampoDeTexto: datos.hasFlag(SemanticsFlag.isTextField),
          enfocado: datos.hasFlag(SemanticsFlag.isFocused),
        ),
      );
    }
  }

  nodo.visitChildren((hijo) {
    _recorrer(hijo, salida, transform);
    return true;
  });
}

/// El texto con el que una persona llamaria a este elemento.
///
/// Se prueba etiqueta, luego tooltip, luego valor: un `IconButton` sin texto
/// visible suele traer solo tooltip, y un campo de texto vacio solo su
/// `labelText`. Sin este orden, media pantalla saldria con la etiqueta en
/// blanco y no habria forma de referirse a ella.
String _etiquetaDe(SemanticsData datos) {
  for (final candidato in [datos.label, datos.tooltip, datos.value, datos.hint]) {
    final limpio = _sinRepetidos(candidato);
    if (limpio.isNotEmpty) return limpio;
  }
  return '';
}

/// Junta las lineas de una etiqueta quitando las repetidas consecutivas.
///
/// Red de seguridad: la causa conocida —el relieve del tallado— ya se arreglo
/// en su widget con `ExcludeSemantics`, pero cualquier otro efecto que repinte
/// el mismo texto volveria a duplicar la etiqueta, y una lista con
/// "Guardar / Guardar / Guardar" es ilegible.
String _sinRepetidos(String texto) {
  final vistas = <String>[];
  for (final linea in texto.split('\n')) {
    final limpia = linea.trim();
    if (limpia.isEmpty) continue;
    if (vistas.isEmpty || vistas.last != limpia) vistas.add(limpia);
  }
  return vistas.join(' · ');
}

/// El nodo que corresponde a lo pedido, o `null`.
///
/// Se busca por id exacto si se da un numero, y si no por etiqueta: primero
/// coincidencia exacta, luego "contiene". Lo exacto va antes a proposito —
/// con "Cerrar" hay un tile y un boton dentro del panel, y quedarse con el
/// primero que contenga el texto es como se acaba tocando el equivocado.
NodoInteractuable? buscar({int? id, String? etiqueta}) {
  final nodos = listarInteractuables();
  if (id != null) {
    for (final nodo in nodos) {
      if (nodo.id == id) return nodo;
    }
    return null;
  }
  if (etiqueta == null) return null;

  final buscado = etiqueta.trim().toLowerCase();
  for (final nodo in nodos) {
    if (nodo.etiqueta.toLowerCase() == buscado) return nodo;
  }
  for (final nodo in nodos) {
    if (nodo.etiqueta.toLowerCase().contains(buscado)) return nodo;
  }
  return null;
}

/// Dispara una accion sobre un nodo, por el mismo camino que el dedo.
///
/// Devuelve `false` si el nodo no existe o no acepta esa accion — no se
/// inventa un toque por coordenada como respaldo: si el arbol dice que eso no
/// se puede tocar, forzarlo estaria probando algo que el usuario no puede
/// hacer.
bool accionar(int id, String accion, {Object? argumento}) {
  final owner = WidgetsBinding.instance.pipelineOwner.semanticsOwner;
  if (owner == null) return false;

  final cual = _accionesUtiles.entries
      .where((e) => e.value == accion)
      .map((e) => e.key)
      .firstOrNull;
  if (cual == null) return false;

  final nodo = buscar(id: id);
  if (nodo == null || !nodo.acciones.contains(accion)) return false;

  owner.performAction(id, cual, argumento);
  return true;
}

/// Un resumen de la pantalla para orientarse sin una captura.
///
/// Incluye los textos NO interactuables —titulos, totales, avisos— porque son
/// los que dicen si la accion anterior hizo lo que tenia que hacer. Una lista
/// de botones sola no distingue "se guardo" de "fallo".
List<String> textosVisibles() {
  encenderSemantica();
  final raiz = _raiz();
  if (raiz == null) return const [];
  final textos = <String>[];
  void recorrer(SemanticsNode nodo) {
    final datos = nodo.getSemanticsData();
    if (!datos.hasFlag(SemanticsFlag.isHidden) && !nodo.rect.isEmpty) {
      final texto = datos.label.trim();
      if (texto.isNotEmpty) textos.add(texto);
    }
    nodo.visitChildren((hijo) {
      recorrer(hijo);
      return true;
    });
  }

  recorrer(raiz);
  return textos;
}

/// El tamaño logico de la pantalla, para que quien lea la lista sepa contra
/// que se estan midiendo los rectangulos.
Map<String, double> medidaDePantalla() {
  final vista = WidgetsBinding.instance.platformDispatcher.views.first;
  final escala = vista.devicePixelRatio;
  return {
    'ancho': vista.physicalSize.width / escala,
    'alto': vista.physicalSize.height / escala,
    'escala': escala,
  };
}

/// Espera a que aparezca algo con esta etiqueta.
///
/// Hace falta porque una accion puede abrir un dialogo, cargar de la base o
/// animar una transicion, y devolver la lista de inmediato daria la pantalla
/// anterior. El harness no puede adivinar cuanto tarda cada cosa.
Future<bool> esperarEtiqueta(
  String etiqueta, {
  Duration limite = const Duration(seconds: 5),
}) async {
  final hasta = DateTime.now().add(limite);
  while (DateTime.now().isBefore(hasta)) {
    if (buscar(etiqueta: etiqueta) != null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Deja pasar los frames necesarios para que la pantalla se asiente.
///
/// No es un `sleep` fijo: se espera al final del frame, que es cuando el arbol
/// de semantica ya se reconstruyo. Un `sleep` corto devolvia a veces la
/// pantalla vieja, y uno largo hacia lento cada paso.
Future<void> asentar({int frames = 3}) async {
  for (var i = 0; i < frames; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
  // Un respiro extra para lo que dispara I/O (una consulta a SQLite tras un
  // toque). Corto: si hiciera falta mas, para eso esta `esperarEtiqueta`.
  await Future<void>.delayed(const Duration(milliseconds: 120));
}

/// Todo lo que el harness necesita saber de la pantalla actual.
Future<Map<String, dynamic>> instantanea() async {
  await asentar();
  return {
    'pantalla': medidaDePantalla(),
    'interactuables': [for (final nodo in listarInteractuables()) nodo.aJson()],
    'textos': textosVisibles(),
  };
}
