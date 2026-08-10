import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../archivo_entrante_service.dart';
import '../tiketback_notifier.dart';
import '../tiketdata_notifier.dart';
import '../tiketdata_service.dart';

/// Atiende el archivo con el que se abrió la app, si hubo uno.
///
/// **Siempre pregunta.** Tocar un archivo en el explorador es un gesto barato y
/// fácil de dar por error; lo que hay detrás no lo es: un catálogo puede
/// reemplazar la carta entera y un respaldo pisa la base completa. Abrir la app
/// aplicando lo que sea sin preguntar convertiría un toque accidental en una
/// pérdida de datos.
///
/// Se llama con la sesión ya abierta, no en el arranque: importar o restaurar
/// requiere saber quién es, y el archivo espera —el lado nativo lo guarda hasta
/// que se recoge.
Future<void> atenderArchivoEntrante(BuildContext context, WidgetRef ref) async {
  final entrante = await const ArchivoEntranteService().recoger();
  if (entrante == null || !context.mounted) return;

  try {
    switch (entrante.clase) {
      case ClaseDeArchivo.catalogo:
        await _atenderCatalogo(context, ref, entrante);
      case ClaseDeArchivo.respaldo:
        await _atenderRespaldo(context, ref, entrante);
    }
  } finally {
    // La copia se borra pase lo que pase, incluso si se canceló: es una copia y
    // el original sigue donde estaba, así que volver a tocarlo la rehace. Un
    // respaldo del negocio olvidado en la caché es una copia de los datos que
    // nadie sabe que existe.
    try {
      File(entrante.ruta).deleteSync();
    } on FileSystemException {
      // El sistema pudo haber limpiado la caché ya. No hay nada que hacer ni
      // nada que contar.
    }
  }
}

Future<void> _atenderCatalogo(BuildContext context, WidgetRef ref, ArchivoEntrante entrante) async {
  final modo = await showDialog<ModoImportacion>(
    context: context,
    builder: (dialogo) => BentoDialogo(
      titulo: const Text('Importar catálogo'),
      contenido: Text(
        'Se abrió "${entrante.nombre}".\n\n'
        'Fusionar deja lo que ya hay y agrega o actualiza lo que venga. '
        'Reemplazar deja el catálogo exactamente como el del archivo: lo que no '
        'esté en él se saca de la carta.',
      ),
      acciones: BentoAcciones(
        izquierda: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogo, ModoImportacion.fusionar),
            child: const Text('Fusionar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogo, ModoImportacion.reemplazar),
            child: const Text('Reemplazar'),
          ),
        ],
        derecha: [
          TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('Cancelar')),
        ],
      ),
    ),
  );
  if (modo == null || !context.mounted) return;

  final resultado = await ref
      .read(tiketdataNotifierProvider.notifier)
      .importarCatalogo(modo, rutaYaElegida: entrante.ruta);
  if (!context.mounted) return;
  mostrarAviso(
    context,
    resultado == ResultadoTiketdata.ok
        ? '✓ Catálogo importado'
        : '✗ No se pudo importar "${entrante.nombre}"',
  );
}

Future<void> _atenderRespaldo(BuildContext context, WidgetRef ref, ArchivoEntrante entrante) async {
  final contrasena = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoRespaldo(nombre: entrante.nombre),
  );
  if (contrasena == null || !context.mounted) return;

  final resultado = await ref
      .read(tiketbackNotifierProvider.notifier)
      .restaurar(contrasena, rutaYaElegida: entrante.ruta);
  if (!context.mounted) return;
  mostrarAviso(context, switch (resultado) {
    ResultadoTiketback.ok => '✓ Respaldo restaurado — cerrá y volvé a abrir la app',
    ResultadoTiketback.contrasenaIncorrecta => '✗ Contraseña incorrecta',
    _ => '✗ No se pudo restaurar "${entrante.nombre}"',
  });
}

/// Pide la contraseña del respaldo, diciendo antes qué va a pasar.
///
/// La contraseña es la del archivo, no la de la app: un `.tiketback` se cifra al
/// exportarlo con una que se elige en ese momento. Confundirlas es el error
/// probable acá, así que se dice.
class _DialogoRespaldo extends StatefulWidget {
  const _DialogoRespaldo({required this.nombre});

  final String nombre;

  @override
  State<_DialogoRespaldo> createState() => _DialogoRespaldoState();
}

class _DialogoRespaldoState extends State<_DialogoRespaldo> {
  final _contrasena = TextEditingController();

  @override
  void dispose() {
    _contrasena.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;

    return BentoDialogo(
      titulo: const Text('Restaurar respaldo'),
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Se abrió "${widget.nombre}".\n\n'
            'Restaurar REEMPLAZA todo lo que hay en este aparato: productos, '
            'categorías y ventas. No se puede deshacer.',
            style: textos.bodyMedium,
          ),
          const SizedBox(height: BentoSpacing.gapCelda),
          TextField(
            controller: _contrasena,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña del respaldo',
              helperText: 'La que se eligió al exportarlo, no la de la app',
            ),
          ),
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [
          FilledButton(
            onPressed: () {
              final clave = _contrasena.text;
              if (clave.isEmpty) return;
              Navigator.pop(context, clave);
            },
            child: const Text('Restaurar'),
          ),
        ],
        derecha: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
