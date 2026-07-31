/// LWW puro: dadas dos versiones de una fila con el mismo id, decide cual
/// prevalece comparando "updated_at". No sabe nada de red, mDNS, ni
/// topologia de sync (decision 0019) — por eso es reutilizable tal cual por
/// TiketdataNotifier para el merge de .tiketdata (decision 0017).
class RowSyncEngine {
  const RowSyncEngine();

  /// Compara dos filas por su campo 'updated_at' (ISO-8601). Si son
  /// iguales, gana [local] (no hay necesidad de reemplazar sin cambio real).
  Map<String, Object?> resolver({
    required Map<String, Object?> local,
    required Map<String, Object?> remota,
  }) {
    final localUpdatedAt = DateTime.parse(local['updated_at'] as String);
    final remotaUpdatedAt = DateTime.parse(remota['updated_at'] as String);
    return remotaUpdatedAt.isAfter(localUpdatedAt) ? remota : local;
  }

  /// Aplica resolver() a un conjunto de filas remotas contra las locales
  /// existentes (indexadas por id). Filas remotas con id nuevo (sin
  /// contraparte local) se agregan tal cual.
  List<Map<String, Object?>> fusionar({
    required List<Map<String, Object?>> locales,
    required List<Map<String, Object?>> remotas,
  }) {
    final porId = {for (final fila in locales) fila['id'] as String: fila};
    for (final remota in remotas) {
      final id = remota['id'] as String;
      final local = porId[id];
      porId[id] = local == null ? remota : resolver(local: local, remota: remota);
    }
    return porId.values.toList();
  }
}
