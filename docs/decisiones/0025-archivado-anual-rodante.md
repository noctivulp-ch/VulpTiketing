# 0025 — Libros de ventas rodantes en archivos SQLite adjuntables

## Estado

Aceptada — implementada el 2026-07-30 (esquema v3). El sync selectivo por libro
y el backup con restauración selectiva quedan pendientes; ver Consecuencias.

## Contexto

Las pruebas de estrés ([informe](../INFORME-ESTRES-2026-07-30.md)) midieron que
`venta` y `linea_venta` **solo crecen** y nada las purga nunca. Con los arreglos
de rendimiento ya aplicados, los reportes aguantan, pero quedaron dos
precipicios que no se arreglan con consultas más rápidas:

| Con 5 años de volumen alto (360 MB) | Medido |
|---|---|
| Payload de un sync | 435 MB, pico de RSS de 1,7 GB |
| Exportar un `.tiketback` | 35 s, pico de 1,5 GB |

En una tablet de gama baja, los dos son cierre por falta de memoria. El problema
no es la velocidad de una consulta: es que la app carga en memoria conjuntos que
crecen sin techo.

## Decisión

Las ventas se escriben en **libros**: archivos SQLite fechados que la app puede
leer sin restaurarlos. Cuando un libro acumula un año de días con actividad, se
cierra y se abre otro. Ningún dato se mueve ni se borra jamás.

### 1. El formato de archivo es SQLite, no uno propio

La propuesta original del usuario era "un formato propio legible en caliente".
Se descartó inventarlo: sería el tercer formato del proyecto (después de
`.tiketdata` y `.tiketback`), con su parser, su versionado y sus modos de
corrupción propios.

Un archivo `.db` **con el mismo esquema** da lo mismo y más:

- **Lectura en caliente literal**: `ATTACH DATABASE` permite consultar la base
  viva y un archivo en una sola sentencia SQL. Verificado con `sqflite`, el
  paquete real de la app:
  ```sql
  ATTACH DATABASE 'archivo-2026.db' AS a2026;
  SELECT SUM(total) FROM (
    SELECT precio_aplicado * cantidad AS total FROM linea_venta
    UNION ALL
    SELECT precio_aplicado * cantidad AS total FROM a2026.linea_venta
  );
  ```
- Cero código de serialización nuevo, y por lo tanto cero bugs nuevos de
  serialización en datos contables.
- Ya viene indexado y compacto; reutiliza `AppDatabase.esquema` tal cual.
- SQLite adjunta hasta 10 bases a la vez: un archivo por año da 10 años, y se
  adjuntan **bajo demanda**, solo cuando una consulta pide ese período.

### 2. El año se cuenta en días con actividad, no por calendario

Un libro se cierra cuando acumuló **365 días en los que hubo al menos una
venta** — no 365 días corridos desde que se creó, ni el 31 de diciembre.

Dos razones: si el negocio cierra dos meses, esos días no tienen por qué
"gastar" el libro; y el 31 de diciembre es justo la peor fecha para que la app
haga algo inesperado.

### 3. No se archiva nada: se cierra un libro y se abre otro

Modelo del usuario, y reemplaza al que había diseñado. La diferencia es
importante: **no hay borrado en ningún momento.**

El diseño anterior era "las ventas viven en la tabla y al cumplirse el año se
copian a un archivo y se borran de la tabla". Eso tiene un paso peligroso —
copiar y después borrar— que obliga a verificar entre medio para no perder
datos.

En este, las ventas **nacen ya en su libro fechado** y nunca se mueven:

- Las ventas se escriben en un `.db` nombrado con su **fecha de inicio**.
- Se le sigue escribiendo hasta acumular **365 días CON ENTRADAS** — no 365 días
  de calendario desde su creación. Si el negocio cierra dos meses, esos días no
  cuentan.
- Al llegar al día 366, su primera venta abre un **libro nuevo** con su propia
  fecha de inicio, y el anterior se cierra: pasa a llamarse
  `fechaInicio_fechaFinal.db`, donde la final es la de su última entrada.

Cerrar un libro es dejar de escribirle. No hay copia, no hay borrado, no hay
paso que verificar. Es estrictamente más simple y más seguro que mover filas.

Consecuencia sobre la estructura de archivos:

| Archivo | Contenido | Cambia |
|---|---|---|
| `vulp_tiketing.db` | catálogo, categorías, configuración | sí |
| `ventas-<inicio>.db` | el libro abierto, recibiendo ventas | sí |
| `ventas-<inicio>_<final>.db` | libros cerrados | **nunca** |

### 3.bis Índice, además del nombre del archivo

El nombre `inicio_final.db` es bueno para una persona que mira la carpeta. Pero
que la app **dependa de leer nombres de archivo** para saber qué período tiene
cada libro es frágil: un renombrado interrumpido o un archivo movido a mano la
dejan sin saber qué tiene.

Se mantiene la convención de nombres *y además* una tabla índice en
`vulp_tiketing.db` con qué libro cubre qué rango y cuántos días con entradas
lleva. El nombre es para el humano; el índice es la fuente de verdad de la app.

### 4. Los archivos viven solo en el almacenamiento interno

Decisión del usuario: no se pide al usuario una carpeta al archivar. El camino
de salida de los datos sigue siendo uno solo, el `.tiketback` cifrado
([decisión 0006](0006-encriptacion-backup.md)) — coherente con que en Android no
se respalda nada a la nube (ver [datos.md](../arquitectura/datos.md)).

Consecuencia asumida: en Android, desinstalar borra también los archivos
históricos. La protección es el backup, no el sistema operativo.

### 5. Un solo backup con todo, y restauración selectiva

Decisión del usuario: **todos los `.db` van en el mismo `.tiketback`**. Son datos
de la misma app; partir el respaldo en uno por libro complica la restauración sin
necesidad.

Se había propuesto lo contrario —un backup por libro, hecho una vez— para
esquivar el costo medido de respaldar 360 MB (35 s, pico de 1,5 GB). Esa
propuesta resolvía el problema equivocado: **ese pico es un defecto de
implementación, no una consecuencia de que el backup sea grande.** Hoy el backup
carga todo en memoria de una vez; ya bajó de 6,3 GB a 1,5 GB al corregir una
línea, y escribiéndolo por trozos baja a memoria constante sin importar el
tamaño. El arreglo va en cómo se escribe el backup, no en partirlo.

Como el backup pasa a contener piezas separables, **restaurar admite elegir qué
traer**:

- **Todo** — como funciona hoy.
- **Solo el menú** — catálogo y categorías, sin tocar las ventas. Es el caso de
  copiar la carta a otro dispositivo o recuperarla tras un error de edición.
- **Solo las ventas** — los libros, sin pisar el catálogo actual.

Un libro cerrado nunca cambia, así que restaurarlo es idempotente por
construcción.

**Implementado el 2026-07-30.** La regla que quedó, en una frase: *restaurar
siempre reemplaza; el alcance dice qué*. Es coherente con la
[decisión 0017](0017-restaurar-backup-reemplazo-total.md) y hace el resultado
predecible. No hay modo fusionar: para el menú esa vía ya existe por otro camino
(`.tiketdata` en modo fusionar), y mezclar dos contabilidades por fecha daría un
híbrido que nadie pidió.

Un detalle de implementación que vale registrar: "solo el menú" **no** puede
reemplazar el archivo `vulp_tiketing.db`, porque ahí vive también
`libro_ventas`. Pisarlo dejaría los libros locales fuera del índice: las ventas
seguirían en disco pero la app dejaría de verlas, que para el usuario es
indistinguible de perderlas. Por eso ese alcance opera a nivel de filas
(`DELETE` + `INSERT` desde el backup adjunto como `respaldo`) y no de archivos.

El formato del bundle pasó a ser autodescriptivo (magic `VTBK`, versión, y un
manifiesto JSON de piezas) porque el par de largos fijos anterior solo admitía
dos partes. Los `.tiketback` del formato viejo se siguen leyendo: se distinguen
por no tener el magic.

**Resuelto (formato 3, escritura por trozos).** Medido con la base de 5 años:

| | Antes | Ahora |
|---|---|---|
| Exportar, pico de RSS | +1.701 MB | **+138 MB** |
| Restaurar, pico de RSS | +181 MB | **+0 MB** |
| Exportar, tiempo | 38 s | 28,6 s |

El backup pasa a escribirse en marcos de 4 MB cifrados por separado, así que el
pico deja de depender del tamaño total. Confirma lo que este apartado
sospechaba: el pico era de implementación, no del tamaño.

Antes de tocar nada se aisló dónde se iba el costo
(`scripts/medir_costo_backup.dart`), y el resultado corrigió el diagnóstico:
derivar la clave son 238 ms fijos, pero **AES-GCM en Dart puro va a 10,7 MB/s**
— o sea 34 s de los 36 eran cifrado, no copias de memoria. Los trozos arreglan
la memoria y no podían arreglar el tiempo. Para eso se agregó
`cryptography_flutter`, que en Android e iOS delega en el cifrado del sistema y
usa las instrucciones AES del procesador; en escritorio cae de vuelta a Dart
puro, y por eso la medición de arriba casi no se mueve. El formato no cambia:
AES-256-GCM es el mismo algoritmo lo implemente quien lo implemente.

Partir el archivo en marcos abre dos manipulaciones que no existían cuando todo
iba en un solo bloque, y las dos son silenciosas:

- **reordenar** marcos — cada uno verificaría bien por separado y la
  contabilidad restaurada quedaría mezclada, con el archivo pareciendo íntegro;
- **truncar** el archivo — restaurarías medio año creyendo que están todas las
  ventas.

Se cierran metiendo el número de marco y la marca de "último" en los datos
autenticados (AAD). Hay una prueba por cada una. Y al restaurar, las piezas van
primero a una carpeta de paso y solo se mueven a su lugar cuando **todos** los
marcos verificaron: ni una contraseña mala ni un archivo cortado pueden dejar el
dispositivo a medio restaurar.

Compatibilidad: se leen los tres formatos. Detectarlos tiene un detalle que no
es obvio — **solo v3 lleva el magic en claro**; en v1 y v2 el archivo empieza
con la sal aleatoria y el `VTBK` de v2 viajaba dentro del cifrado, así que los
dos son indistinguibles hasta descifrarlos.

### 6. El sync solo intercambia el libro abierto

Con el modelo de libros, el problema del sync cambia de forma y se simplifica.

El sync actual vuelca las tablas **completas** en cada intercambio. Si siguiera
haciéndolo sobre todos los libros, cada sync mandaría el historial entero — que
es exactamente el precipicio de 435 MB que se midió.

Como un libro cerrado **nunca cambia**, no hay nada que sincronizar en él más
que una vez:

- El sync de rutina intercambia **solo el libro abierto**, que está acotado a un
  año por construcción. — *Implementado el 2026-07-30.*
- Un dispositivo nuevo que entra al grupo pide además los libros cerrados que le
  falten, una única vez, identificados por el índice. — **No es implementable
  tal como está escrito; ver la corrección abajo.**
- Un libro solo se cierra cuando su contenido ya fue sincronizado con los pares
  conocidos, para no dejar a otro dispositivo sin ventas que nunca vio. —
  *Pendiente:* depende de `todosLosDispositivosSincronizados`, que la
  [decisión 0015](0015-purgar-producto-borrado-fisico-condicional.md) definió y
  que hoy devuelve siempre `false` a mano.

Nótese que el riesgo del diseño anterior —que el otro dispositivo reinsertara lo
archivado y revirtiera el vaciado en silencio— **desaparece**: no hay filas
borradas que puedan volver.

#### Corrección (2026-07-30): los libros son POR DISPOSITIVO

Al implementar quedó a la vista un supuesto falso de esta sección. Cada aparato
crea sus libros por su cuenta, con su propio UUID y su propia fecha de corte, y
rota cuando **sus** días con ventas llegan a 365. Dos aparatos nunca comparten
un archivo, ni un id, ni un rango. Así que *"los libros cerrados que le falten,
identificados por el índice"* no está definido: los índices no son comparables.

La unidad de sincronización es la **fila**, no el archivo. Un libro es un
contenedor local, no una entidad compartida. Por eso `libro_ventas` está
deliberadamente fuera de `tablasSincronizables`: describe los archivos de este
dispositivo, y propagarlo dejaría al otro con filas apuntando a archivos que no
existen.

Lo que sí quedó implementado y es correcto: el volcado se limita a las ventas
del libro abierto, el cliente prepara su propio libro antes de aplicarlas, y
después recuenta los días desde el contenido real (`recontarDias`) en vez de
incrementar — porque el sync reenvía las mismas filas y un contador incremental
acumularía error.

**Lo que falta decidir**, y por qué no se resolvió sobre la marcha: si el
aparato A ya tiene una venta en un libro **cerrado** y B se la manda desde su
libro **abierto**, `RowUpserter` no la encuentra en el libro abierto de A, la
inserta, y esa venta queda en dos libros de A. Un reporte que adjunte ambos la
cuenta dos veces. Ocurre en el solape cercano a una rotación, cuando un aparato
estuvo apagado un tiempo largo. Corromper contabilidad en silencio es peor que
no compartir el histórico, así que el intercambio de libros cerrados espera un
ADR propio.

## Alternativas descartadas

- **Formato propio**: ver punto 1. Más código, más riesgo, menos capacidad —
  ATTACH ya da lectura en caliente.
- **Resúmenes precalculados por día** (una tabla `resumen_dia` escrita al
  guardar cada venta): da reportes históricos instantáneos para siempre, pero
  duplica el modelo de datos y no reduce el tamaño de la base ni el del sync.
  Queda como complemento posible si mirar años anteriores resulta frecuente; no
  reemplaza al archivado.
- **No archivar y optimizar más**: descartado por medición. El problema es de
  memoria por conjuntos sin techo, no de velocidad de consulta.

## Consecuencias

- El libro abierto no supera un año de días con actividad: sync y backup dejan
  de crecer sin límite.
- **No existe un momento de borrado.** El riesgo de perder datos al archivar,
  que el diseño anterior tenía que mitigar con verificaciones, desaparece por
  construcción.
- Los reportes del período vivo no cambian en nada.
- Un reporte que pide años anteriores adjunta el archivo correspondiente,
  consulta, y lo suelta. Es más lento que el período vivo, y está bien: es una
  consulta ocasional.
- Hay que definir qué pasa si una consulta cruza el borde (por ejemplo "últimos
  12 meses" un día que quedan 11 meses vivos): la consulta adjunta el archivo
  más reciente y hace `UNION ALL`.
- El primer cierre de libro ocurre recién al cumplirse 365 días con actividad,
  así que hay tiempo — pero **la separación de las ventas a su propio `.db`
  conviene hacerla antes**, porque mover ventas de la base actual a un libro
  fechado es exactamente la migración con riesgo que este diseño evita para
  siempre después. Cuanto antes se haga, menos datos hay que mover una única vez.
- La marca `archivado_hasta` conviene que exista en el esquema antes de que haya
  varios dispositivos en producción, para no migrar con datos repartidos.

## Addendum (2026-07-31) — el libro se crea al abrir la app, no con la primera venta

Como estaba, el primer libro nacía al cobrar la primera venta. Hasta ese
momento no había nada adjunto, así que `SELECT ... FROM linea_venta` no
resolvía contra ninguna base y **Reportes reventaba en toda instalación nueva**
con `no such table: linea_venta`. Es el primer día de uso de cualquier negocio,
no un caso borde: se abre la app, se mira Reportes, todavía no se cobró nada.

`adjuntarAbierto` ahora crea el libro si no existe. Crear uno vacío no adelanta
ninguna decisión de archivado: es el mismo archivo que habría creado la primera
venta, con las mismas tablas y sin filas.

Cubierto por `test/base_recien_instalada_test.dart`, incluido que abrir la app
dos veces no genere un segundo libro — eso llenaría el índice de archivos
vacíos y dejaría sin sentido el rodaje.
