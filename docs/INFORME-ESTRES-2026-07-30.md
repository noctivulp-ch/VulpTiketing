# Informe de pruebas de estrés — noche del 30/07/2026

Trabajo autónomo mientras dormías. Todo está commiteado y con puntos de retorno.
Lo que necesita tu decisión está al final, en **Decisiones pendientes**.

---

## Resumen en una línea

La app se volvía **inusable con un solo año de uso real**, no con diez. Ya está
corregido y medido: el reporte del día pasó de **5.940 ms a 38 ms** (156×), y el
anual de **no terminar en 4 minutos a 527 ms**.

---

## 1. El hallazgo grave

Las pruebas de estrés midieron el nivel **realista** — un año de volumen con la
mezcla sesgada a los items baratos que señalaste: 117.000 ventas, 234.000
líneas.

| Medición | Al empezar | Ahora | Mejora |
|---|---|---|---|
| Reporte del día | **5.940 ms** | **38 ms** | 156× |
| Reporte del año | **no terminaba** (>4 min, el runner moría) | **527 ms** | — |
| Guardar una venta | 2 ms | 1 ms | sin regresión |
| Listar historial | 1.403 ms | 1.409 ms | sin cambio |

La causa eran tres cosas sumadas, no una:

1. **N+1 de consultas.** `reportes_provider` traía las ventas del rango y hacía
   **una consulta por venta** para sus líneas, más una consulta por producto
   para su nombre. El reporte del día escaneaba 320 × 234.000 filas; el anual,
   117.000 × 234.000 ≈ **27 mil millones**.
2. **Cero índices.** El esquema v1 solo tenía claves primarias. Confirmado en la
   base real: `.indexes` no devolvía nada.
3. **Memoria retenida sin motivo.** `ventasPorTurno` se llenaba siempre, aunque
   su propia documentación dijera "solo cuando rango == dia", así que un reporte
   anual retenía todas las ventas del año con todas sus líneas.

---

## 2. Qué cambié

### Reportes: agregar en SQL en vez de en Dart
`lib/features/reportes/reportes_provider.dart`

Tres consultas agregadas de tamaño fijo (totales por turno, ranking con el
nombre resuelto en el mismo JOIN) más el drill-down **solo** cuando el rango es
día.

Costo asumido: la clasificación de turno ahora existe dos veces, en `turnoDe`
(Dart) y en un `CASE` de SQL. `test/reportes_provider_test.dart` es el precio de
esa duplicación — siembra una venta por cada hora del día y compara las dos
implementaciones, así que cambiar un corte en un lado y no en el otro falla.

### Esquema v2: cuatro índices
`lib/core/db/app_database.dart`

Decisión de arquitectura, tomada bajo tu condición: hay punto de retorno y se
queda **porque midió mejor**.

| | Sin índices | Con índices |
|---|---|---|
| Reporte del día | 280 ms ❌ | **38 ms** ✓ |
| Guardar una venta | 2 ms | 1 ms |
| Reporte del año | 501 ms | 527 ms (ruido) |

Los cuatro índices corresponden a consultas que existen **hoy**: el JOIN de
reportes, el filtro de rango, el `ORDER BY` del historial y el `GROUP BY` del
ranking. No hubo contrapartida medible en escritura, que era el riesgo real.

**La migración se verificó donde importa**: sobre una base v1 **con datos**, que
es el caso de la tablet del negocio. Una migración que solo corriera en
`onCreate` dejaría al usuario real sin índices para siempre y en silencio.
Probado en `test/migracion_esquema_test.dart` y también de punta a punta en la
base real (v1 sin índices → v2 con los cuatro, conservando las 15 ventas, 36
líneas y 39 productos).

> Detalle útil: la migración **no** corre al abrir la app, porque la base se abre
> en forma diferida y la pantalla de Login no la toca. Corre al primer acceso
> real (iniciar sesión). No es un bug, pero conviene saberlo al verificar.

### Dos defectos de correctitud, de paso

- **Los rankings ya no se solapan.** Eran la lista **completa** ordenada al
  revés, así que un producto salía como el más *y* el menos vendido a la vez —
  es exactamente el defecto que viste en pantalla. Ahora son top-10 y los menos
  vendidos excluyen lo que ya está en los más vendidos.
- **El drill-down solo se calcula para el día.**

### `RowUpserter` en una transacción
`lib/features/sync/row_upserter.dart`

Sin transacción, un fallo a mitad de un sync dejaba **medio merge aplicado** sin
forma de saber qué filas — un merge a medias es peor que uno que no ocurrió. Y
cada sentencia era su propio commit con fsync: cientos de miles de commits al
disco en un sync grande.

---

## 3. La suite de estrés

Vive en **`test_estres/`**, fuera de `test/`, así `flutter test` sin argumentos
sigue tardando ~5 s. Misma convención que `test_driver/`.

```fish
export PATH="$HOME/fvm/default/bin:$PATH"
flutter test test_estres/                                  # todo
flutter test test_estres/ventas_volumen_test.dart          # un grupo
VULP_ESTRES_NIVELES=realista flutter test test_estres/     # un nivel
```

### La escalera de volúmenes

Derivada de tus datos, no de números redondos: ingreso de ₡120–150 mil/día
contra el catálogo real, donde los 8 items de alta rotación promedian ₡875 (no
₡2.313, que era mi error inicial de usar el promedio plano del menú).

| Nivel | Escenario | Ventas | Líneas | Trato |
|---|---|---|---|---|
| Realista | 1 año @ 320/día | 117 k | 234 k | presupuesto **duro** |
| Alto | 5 años @ 500/día | 913 k | 1,8 M | caracterización |
| Techo | 5 años @ 2.000/día | 3,7 M | 7,3 M | caracterización |
| Absoluto | 10 años @ 2.000/día | 7,3 M | 14,6 M | punto de quiebre |

El techo son 2.000 ventas/día = una venta cada 25 segundos, 14 horas sin un
hueco: volumen de franquicia de comida rápida, irrazonable para una soda pero
alcanzable de verdad.

### Grupos

| Grupo | Archivo | Estado |
|---|---|---|
| A — acumulación de ventas | `ventas_volumen_test.dart` | ✅ 6/6 en realista |
| C — sincronización | `sync_volumen_test.dart` | ⏳ corriendo al cerrar |
| D — backup `.tiketback` | `backup_volumen_test.dart` | escrito, sin correr |
| F — tensión y concurrencia | `tension_test.dart` | ✅ 5/5 |
| B — catálogo grande | pendiente | no escrito |
| E — catálogo `.tiketdata` | pendiente | no escrito |

**Grupo F**, resultados: 1.000 ventas seguidas a 0,85 ms cada una sin
degradación; 200 ciclos de invalidación de providers sin romper nada; 20
lecturas de reporte concurrentes con escrituras, todas internamente coherentes.
Ese grupo existe porque los dos bugs más graves del proyecto salieron de ahí y
los dos tenían la misma causa (Riverpod reutiliza la instancia del Notifier), y
ninguna prueba los veía porque ninguna **repetía** la operación.

### Dos decisiones de método que valen

- **El generador usa `AppDatabase.esquema`**, el DDL real ahora público, en vez
  de duplicarlo como hacían las pruebas existentes. Un esquema de prueba que
  puede divergir del real en silencio no prueba nada — y con la migración v2 eso
  habría pasado enseguida.
- **Las bases cacheadas van a disco real** (`~/.cache/vulptiketing/estres/`), no
  a `/tmp`. En Linux `/tmp` es tmpfs, o sea RAM: medir I/O ahí habría dado
  números irrealmente buenos, justo al revés del objetivo, que es una tablet con
  almacenamiento lento.

---

## 4. Decisiones pendientes

### a) Paginación del historial de ventas

`VentaNotifier` carga **todo** el historial sin paginar. Medido: 1.409 ms y
+71 MB para 116.801 ventas. Proyectado al nivel techo (3,7 M ventas): ~45 s y
~2,2 GB — inviable en una tablet.

Los índices no ayudan acá: el costo no está en la consulta sino en materializar
116.000 objetos Dart. **El arreglo es paginación**, y cambia la API pública de
`VentaNotifier`. No lo toqué porque cambia cómo la UI consume ese provider, y eso
se decide junto con el rediseño de interfaz que sigue.

### b) Tu idea del vaciado anual — y creo que es la correcta

Lo planteaste antes de dormir y coincido: a estos volúmenes la respuesta correcta
probablemente **no** sea una consulta más rápida, sino no tener diez años de
líneas de venta en la tabla caliente. Hoy `venta` y `linea_venta` **solo crecen**
— nada purga ni archiva nunca.

Tres formas de hacerlo, de menos a más invasiva:

**Opción 1 — Archivado asistido (la que recomiendo).**
Al cerrar el año, la app propone: *"Tenés 117.000 ventas de 2026. ¿Archivarlas?"*
Exporta un `.tiketback` del año (ya tenemos backup cifrado funcionando), verifica
que se puede restaurar, y **solo entonces** borra esas filas de la base viva.
- A favor: reutiliza lo que ya existe; la base viva no crece nunca más allá de un
  año; el usuario mantiene control y una copia.
- En contra: los reportes históricos exigen restaurar el archivo. Habría que ver
  si eso importa — para decisiones de negocio se suele mirar el año corriente y
  comparar contra el anterior.

**Opción 2 — Resúmenes precalculados por día.**
Una tabla `resumen_dia` con total, total por turno y cantidades por producto. Se
escribe al guardar cada venta. Los reportes de mes y año leen resúmenes en vez de
líneas.
- A favor: los reportes históricos siguen disponibles para siempre y son
  instantáneos, sin importar el volumen.
- En contra: los datos quedan en dos lugares y hay que mantenerlos coherentes;
  las líneas viejas siguen ocupando espacio.

**Opción 3 — Las dos.** Resúmenes para consultar historia, archivado para las
líneas de detalle. Es lo más robusto y lo más trabajo.

Mi recomendación: **empezar por la 1**, porque resuelve el crecimiento sin
inventar un segundo modelo de datos, y usa piezas ya probadas. La 2 se puede
agregar después si resulta que sí querés mirar años viejos con frecuencia.

Hay una pregunta que solo vos podés contestar y que decide entre 1 y 2:
**¿con qué frecuencia vas a querer mirar reportes de años anteriores?**

### c) Sync incremental

`SyncServer` serializa las 4 tablas **completas** en un solo JSON en memoria, en
cada sync. La decisión 0022 ya lo previó como extensión futura. El grupo C está
midiendo cuánto pesa; con el resultado se decide si urge pasar a incremental por
`updated_at`.

---

## 5. Puntos de retorno

| Tag | Qué marca |
|---|---|
| `base-visual-1` | el sistema visual aprobado, antes de iterar composición |
| `pre-indices` | antes de la migración de esquema v2 |

```fish
git reset --hard pre-indices     # deshacer los índices
git diff pre-indices             # ver qué cambió desde ahí
```

Estado: **59 pruebas normales pasando**, `flutter analyze` limpio, build de Linux
correcto, y la app verificada corriendo con la base real migrada.
