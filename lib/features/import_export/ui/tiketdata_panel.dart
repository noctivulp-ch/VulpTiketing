import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../tiketdata_notifier.dart';
import '../tiketdata_service.dart';

String? _mensaje(ResultadoTiketdata resultado, {required bool importando}) {
  switch (resultado) {
    case ResultadoTiketdata.ok:
      return importando ? '✓ Catálogo importado' : '✓ Catálogo exportado';
    case ResultadoTiketdata.cancelado:
      return null;
    case ResultadoTiketdata.error:
      return importando
          ? 'No se pudo importar el catálogo (¿archivo válido?)'
          : 'No se pudo exportar el catálogo';
  }
}

enum _PasoCatalogo { elegirAccion, elegirModo, confirmarReemplazo }

/// Panel inline de Configuración (antes una cadena de `SimpleDialog`/
/// `AlertDialog`: elegir accion -> elegir modo -> confirmar reemplazo). Cada
/// paso ahora es un estado del mismo panel en vez de un dialogo nuevo.
class PanelCatalogo extends ConsumerStatefulWidget {
  const PanelCatalogo({super.key});

  @override
  ConsumerState<PanelCatalogo> createState() => _PanelCatalogoState();
}

class _PanelCatalogoState extends ConsumerState<PanelCatalogo> {
  _PasoCatalogo _paso = _PasoCatalogo.elegirAccion;
  bool _procesando = false;

  void _reiniciar() => setState(() => _paso = _PasoCatalogo.elegirAccion);

  Future<void> _exportar() async {
    setState(() => _procesando = true);
    final (resultado, ruta) = await ref.read(tiketdataNotifierProvider.notifier).exportarCatalogo();
    if (!mounted) return;
    setState(() => _procesando = false);
    final mensaje = resultado == ResultadoTiketdata.ok && ruta != null
        ? '✓ Catálogo en ${p.basename(ruta)}'
        : _mensaje(resultado, importando: false);
    if (mensaje != null) mostrarAviso(context, mensaje);
  }

  Future<void> _importar(ModoImportacion modo) async {
    setState(() => _procesando = true);
    final resultado = await ref.read(tiketdataNotifierProvider.notifier).importarCatalogo(modo);
    if (!mounted) return;
    setState(() => _procesando = false);
    final mensaje = _mensaje(resultado, importando: true);
    if (mensaje != null) mostrarAviso(context, mensaje);
    _reiniciar();
  }

  @override
  Widget build(BuildContext context) {
    switch (_paso) {
      case _PasoCatalogo.elegirAccion:
        return BentoPanel(
          titulo: 'Catálogo (.tiketdata)',
          acciones: [
            FilledButton(
              onPressed: _procesando ? null : _exportar,
              child: const Text('Exportar catálogo actual'),
            ),
            OutlinedButton(
              onPressed: _procesando
                  ? null
                  : () => setState(() => _paso = _PasoCatalogo.elegirModo),
              child: const Text('Importar catálogo'),
            ),
          ],
        );

      case _PasoCatalogo.elegirModo:
        return BentoPanel(
          titulo: '¿Reemplazar o fusionar?',
          acciones: [
            FilledButton(
              onPressed: () => _importar(ModoImportacion.fusionar),
              child: const Text('Fusionar — agrega/actualiza, no toca el resto'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _paso = _PasoCatalogo.confirmarReemplazo),
              child: const Text('Reemplazar — descontinúa lo que no venga en el archivo'),
            ),
            TextButton(onPressed: _reiniciar, child: const Text('Cancelar')),
          ],
        );

      case _PasoCatalogo.confirmarReemplazo:
        return BentoPanel(
          titulo: '¿Reemplazar catálogo?',
          contenido: const Text(
            'Todo producto o categoría activa que no esté en el archivo se descontinuará '
            '(no se borra, queda como descontinuado — se puede revisar en el listado).',
          ),
          acciones: [
            FilledButton(
              onPressed: _procesando ? null : () => _importar(ModoImportacion.reemplazar),
              child: const Text('Continuar'),
            ),
            TextButton(onPressed: _procesando ? null : _reiniciar, child: const Text('Cancelar')),
          ],
        );
    }
  }
}
