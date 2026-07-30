# 0025 — Libros de ventas rodantes en archivos SQLite adjuntables

## Estado

Propuesta — diseño acordado con el usuario, pendiente de implementar.

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

### 6. El sync solo intercambia el libro abierto

Con el modelo de libros, el problema del sync cambia de forma y se simplifica.

El sync actual vuelca las tablas **completas** en cada intercambio. Si siguiera
haciéndolo sobre todos los libros, cada sync mandaría el historial entero — que
es exactamente el precipicio de 435 MB que se midió.

Como un libro cerrado **nunca cambia**, no hay nada que sincronizar en él más
que una vez:

- El sync de rutina intercambia **solo el libro abierto**, que está acotado a un
  año por construcción.
- Un dispositivo nuevo que entra al grupo pide además los libros cerrados que le
  falten, una única vez, identificados por el índice.
- Un libro solo se cierra cuando su contenido ya fue sincronizado con los pares
  conocidos, para no dejar a otro dispositivo sin ventas que nunca vio.

Ese último punto usa la misma señal que la
[decisión 0015](0015-purgar-producto-borrado-fisico-condicional.md) definió para
purgar productos y que hoy devuelve siempre `false`. Implementarla habilita las
dos cosas.

Nótese que el riesgo del diseño anterior —que el otro dispositivo reinsertara lo
archivado y revirtiera el vaciado en silencio— **desaparece**: no hay filas
borradas que puedan volver.

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
