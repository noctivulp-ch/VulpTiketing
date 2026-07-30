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

Resultado: **152 µs/fila, constante entre niveles**. Y verificado que un archivo
`.tiketdata` corrupto ya no deja el catálogo a medias.

### Backup: el pico de memoria bajó 4,3×
`lib/features/import_export/tiketback_service.dart`

| Medición (base de 360 MB) | Antes | Después |
|---|---|---|
| Exportar — pico de RSS | **+6.343 MB** | **+1.463 MB** |
| Exportar — tiempo | 44.147 ms | 35.541 ms |
| Restaurar — pico de RSS | — | +1.093 MB |

La causa era una línea: `writeAsBytes([...salt, ...cipherText, ...mac])`. Ese
literal con spreads construye una `List<int>` genérica, y en Dart **cada elemento
de una `List<int>` ocupa 8 bytes** en el arreglo interno, no 1 — más el realojado
al crecer. Para 360 MB eran ~2,9 GB solo en esa lista, y con la duplicación al
crecer llegaba a 6,3 GB.

Reemplazado por `BytesBuilder`, que acumula en `Uint8List` (un byte por byte) y
que además ya se usaba en `_empaquetar` unas líneas más abajo — la inconsistencia
estaba dentro del mismo archivo.

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
| B — catálogo grande | `catalogo_volumen_test.dart` | ✅ incluido en B/E |
| C — sincronización | `sync_volumen_test.dart` | ✅ 8/8 en realista + alto |
| D — backup `.tiketback` | `backup_volumen_test.dart` | ⚠️ falla a propósito en nivel alto |
| E — catálogo `.tiketdata` | `catalogo_volumen_test.dart` | ✅ 7/7 |
| F — tensión y concurrencia | `tension_test.dart` | ✅ 5/5 |

**Grupo F** — 1.000 ventas seguidas a 0,85 ms cada una **sin degradación**; 200
ciclos de invalidación de providers sin romper nada; 20 lecturas de reporte
concurrentes con escrituras, todas internamente coherentes. Ese grupo existe
porque los dos bugs más graves del proyecto salieron de ahí y los dos tenían la
misma causa (Riverpod reutiliza la instancia del Notifier), y ninguna prueba los
veía porque ninguna **repetía** la operación.

**Grupos B y E** — el catálogo no es un problema a ninguna escala razonable:

| Caso | Filtrar por tecla (p90) | Importar `.tiketdata` |
|---|---|---|
| 40 productos (el real) | 0 ms | — |
| 500 productos | 0 ms | 107 ms (85 KB) |
| 5.000 productos | 1 ms | 849 ms (853 KB) |

Verificado además que un `.tiketdata` **corrupto no deja el catálogo a medias**,
lo que confirma que la transacción que agregué a `RowUpserter` revierte bien; y
que reimportar el mismo archivo no duplica productos.

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

## 3.bis Las dos pruebas que quedan en rojo, y por qué está bien

No las dejé pasando a la fuerza. Son las dos señales que quiero que veas:

1. **`ventas_volumen_test` — reporte del día en nivel realista.** Ya cumple
   (38 ms contra 100 ms de presupuesto), así que esta pasa. ✅
2. **`backup_volumen_test` — exportar en nivel alto.** Falla por superar el umbral
   de catástrofe de 30 s: tarda 35 s con una base de 360 MB. Es correcto que
   falle — **respaldar cinco años de datos no es viable en una tablet**, ni en
   tiempo ni en memoria (1,5 GB de pico). Aflojar el umbral escondería el
   problema; la salida real es el archivado anual.

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

#### Lo que las mediciones le agregan a tu idea

Tu intuición apunta a algo que los números confirman: **el archivado no es solo
por espacio, es lo que mantiene sano al sync.** Un año de datos ya genera un
payload de sync de 55 MB; cinco años, 435 MB. Si la base viva nunca pasa de un
año, ese precipicio no llega nunca — el archivado resuelve el problema de sync
de refilón, sin tocar el protocolo.

Eso cambia mi recomendación de "conviene" a "es el camino". Y sugiere un detalle
de diseño: el archivado debería **correr antes** de que el año cierre del todo,
no justo el 31 de diciembre, porque el 31 es el día con menos ganas de que la app
haga algo raro.

#### Cómo lo propondría concretamente

- **Cuándo avisa:** al abrir la app, si hay ventas de un año anterior al
  corriente. No al llegar a una fecha: si el negocio no abrió la app en enero, el
  aviso lo espera.
- **Qué hace, en orden:** exporta un `.tiketback` del período → **verifica que
  se puede restaurar** (el backup no sirve si no se comprobó) → recién entonces
  borra las filas de ese período → deja registro de qué se archivó y dónde.
- **Qué NO hace:** borrar sin confirmación explícita, ni borrar sin que el
  archivo esté en un destino que el usuario eligió. Es la operación más
  destructiva de la app; aplica la convención del proyecto de que nada
  irreversible ocurre con un solo toque.
- **El catálogo no se archiva nunca:** productos y categorías se quedan. Solo
  `venta` y `linea_venta`.
- **Un riesgo real a resolver antes:** el archivado borra filas que otros
  dispositivos todavía podrían tener. Con el sync actual (volcado completo y LWW
  por `updated_at`), el otro dispositivo **volvería a insertar** las ventas
  archivadas en el próximo sync, deshaciendo el vaciado. Así que el archivado
  necesita coordinarse con el sync — probablemente archivar solo cuando todos los
  dispositivos conocidos ya sincronizaron ese período, que es exactamente la
  señal que la decisión 0015 ya definió para la purga de productos y que hoy
  devuelve siempre `false`.

Ese último punto es importante: **el archivado y el sync no son independientes**,
y conviene decidirlos juntos.

### c) Sync incremental — el próximo precipicio, y es de memoria

Esto es lo más urgente después de lo ya corregido. Medido:

| Nivel | Payload | Serializar | Pico de RSS |
|---|---|---|---|
| Realista (1 año) | 55,2 MB | 516 ms | **+247 MB** |
| Alto (5 años) | **434,9 MB** | 3.598 ms | **+1.688 MB** |

`SyncServer` serializa las 4 tablas **completas** en un solo string JSON en
memoria, en cada sync. A 5 años eso es un string de 435 MB y un pico de 1,7 GB.
En una tablet de gama baja con 2–3 GB de RAM total, **eso es un cierre por falta
de memoria**, no una lentitud.

Y no se arregla del lado del servidor solamente: el cliente hace `jsonDecode` de
todo el cuerpo, así que el dispositivo que *recibe* tiene el mismo pico. Los dos
extremos de un sync son tablets.

Lo bueno: `RowUpserter.aplicar` quedó en **152 µs/fila constante** entre niveles,
lo que confirma que la transacción que agregué funciona. Aplicar un dataset
completo de 5 años serían ~7 minutos, aceptable para el único caso en que ocurre
(un dispositivo nuevo entrando al grupo por primera vez).

**Por qué no lo implementé anoche.** La decisión 0022 ya previó el sync
incremental como extensión, pero hacerlo bien necesita algo que hoy no existe:
una marca de agua por par (*"de este dispositivo ya tengo todo hasta tal
`updated_at`"*), que hay que decidir dónde vive y cómo se comporta cuando un par
se reinstala. Es un cambio de protocolo entre dispositivos, no un refactor
interno.

Consideré un arreglo a medias —que el servidor emita la respuesta en streaming
en vez de armar el string completo— y lo descarté a propósito: solo cubre la
mitad del problema (el cliente sigue igual), y armar el JSON a mano por trozos en
el área de código donde un error de comas o de escapado **corrompe datos de
sync** no es algo para hacer a las 2 de la mañana sin poder consultarte. Preferí
medirlo bien y dejártelo documentado.

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
