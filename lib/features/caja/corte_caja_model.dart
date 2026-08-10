/// Un conteo de la caja: el monto que queda en ella en un momento del día.
///
/// El flujo real de la soda, tal como lo describió el dueño:
///
/// 1. **Antes de abrir** se anota el monto con el que arranca la caja.
/// 2. **A media jornada** se cuenta para ver que el efectivo cuadre con lo
///    cobrado, se guarda la mayor parte y se deja una cantidad para vueltos.
/// 3. **Al cerrar** se cuenta otra vez y se guarda casi todo.
///
/// De ahí las dos cosas que definen esta entidad:
///
/// - **`monto` es lo que QUEDA**, no lo que se contó. Después de un corte, ese
///   número es la caja inicial del tramo siguiente. Si guardara el conteo, el
///   número dejaría de servir para comparar en el corte siguiente.
/// - **El orden no lo manda el reloj.** El cambio de turno cae entre las 12 y
///   las 2:30 según el día, así que lo que habilita el corte de medio día es
///   haber anotado la apertura, no que sea una hora determinada.
enum MomentoCorte { apertura, medioDia, cierre }

/// El nombre con el que se llama a cada momento.
///
/// Vive junto al enum y no en la pantalla porque también lo usa el archivo
/// exportado: dos listas de nombres separadas acaban diciendo cosas distintas.
String nombreDeMomento(MomentoCorte momento) => switch (momento) {
  MomentoCorte.apertura => 'Apertura',
  MomentoCorte.medioDia => 'Medio Día',
  MomentoCorte.cierre => 'Cierre',
};

/// El corte que toca anotar después de [ya], o `null` si el día está cerrado.
///
/// Es la regla de orden en un solo sitio: la pantalla la usa para saber qué
/// botón habilitar y el notifier para rechazar un registro fuera de turno. Con
/// la regla escrita dos veces, un botón habilitado de más se convertiría en un
/// dato inconsistente.
MomentoCorte? siguienteMomento(Set<MomentoCorte> ya) {
  for (final momento in MomentoCorte.values) {
    if (!ya.contains(momento)) return momento;
  }
  return null;
}

class CorteCaja {
  const CorteCaja({
    required this.id,
    required this.dia,
    required this.momento,
    required this.monto,
    required this.fechaHora,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;

  /// El día al que pertenece, sin hora: `2026-08-10`.
  final String dia;

  final MomentoCorte momento;

  /// Lo que queda en la caja tras el corte.
  final double monto;

  /// Cuándo se anotó. Es lo que separa las ventas de antes del corte de las de
  /// después, que es de donde sale la caja esperada.
  final DateTime fechaHora;

  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory CorteCaja.fromMap(Map<String, Object?> map) {
    return CorteCaja(
      id: map['id'] as String,
      dia: map['dia'] as String,
      momento: MomentoCorte.values.byName(map['momento'] as String),
      monto: (map['monto'] as num).toDouble(),
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'dia': dia,
      'momento': momento.name,
      'monto': monto,
      'fecha_hora': fechaHora.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }
}

/// La clave de día que usa la tabla, para no formatearla a mano en cada sitio.
String diaDe(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';
