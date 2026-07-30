# 0025 — Archivado anual rodante en archivos SQLite adjuntables

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

La base **viva** contiene una ventana rodante de un año. Lo anterior se mueve
automáticamente a archivos SQLite que la app puede leer sin restaurarlos.

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

### 2. La ventana se cuenta en días, no por fecha de calendario

Se archiva lo que tiene más de 365 días, se evalúe cuando se evalúe. No se
espera al 31 de diciembre.

Dos razones: el negocio puede no abrir la app ese día, y el 31 de diciembre es
justo la peor fecha para que la app haga algo inesperado.

### 3. Archivar es mudar, no borrar — así que no pide confirmación

Argumento del usuario, y es correcto: si el archivo `.db` queda en el
almacenamiento interno de la app, **no se pierde nada**. La convención del
proyecto de "nada irreversible sin confirmación" no aplica porque no es
irreversible: es un cambio de ubicación, invisible salvo que una consulta pida
años anteriores.

Lo que sí exige es que la mudanza sea **segura**, y eso lo garantiza la app, no
el usuario:

1. Escribir el archivo con las filas del período.
2. **Verificar**: que el archivo abre, que la cantidad de filas coincide y que
   la suma de importes coincide con lo que se va a borrar.
3. Recién entonces borrar de las tablas vivas, en una transacción.
4. Registrar la marca de archivado.

Si cualquier paso falla, no se borra nada y se reintenta la próxima vez.

### 4. Los archivos viven solo en el almacenamiento interno

Decisión del usuario: no se pide al usuario una carpeta al archivar. El camino
de salida de los datos sigue siendo uno solo, el `.tiketback` cifrado
([decisión 0006](0006-encriptacion-backup.md)) — coherente con que en Android no
se respalda nada a la nube (ver [datos.md](../arquitectura/datos.md)).

Consecuencia asumida: en Android, desinstalar borra también los archivos
históricos. La protección es el backup, no el sistema operativo.

### 5. Los archivos entran al backup, pero una sola vez

Un archivo, una vez cerrado, **nunca cambia**. Eso permite que el backup no
repita trabajo:

- El backup de rutina cubre la base viva (un año, acotada).
- Cada archivo recibe su propio `.tiketback` cuando se crea, una única vez.

Así ninguna operación de respaldo crece sin techo, que era el segundo
precipicio medido. Si el backup incluyera todo cada vez, el archivado habría
resuelto el sync pero no el backup.

### 6. La marca `archivado_hasta`, sin la cual el sync deshace todo

Este es el punto que el archivado no resuelve solo, y por eso se decide junto.

Con el sync actual (volcado completo y LWW por `updated_at`), si este
dispositivo archiva y borra las ventas de 2026, el otro dispositivo **todavía
las tiene** y en el próximo sync se las devuelve. El vaciado se revierte solo, en
silencio.

Se agrega una marca `archivado_hasta` que los dispositivos intercambian y
respetan:

- Cada dispositivo publica hasta qué fecha tiene archivado.
- Al aplicar filas remotas, se **descartan** las que caen antes del
  `archivado_hasta` local: no son datos nuevos, son datos ya guardados en otro
  lado.
- Un dispositivo solo archiva un período cuando ese período ya fue sincronizado
  con los pares que conoce, para no archivar ventas que otro todavía no vio.

Este último punto usa la misma señal que la
[decisión 0015](0015-purgar-producto-borrado-fisico-condicional.md) definió para
purgar productos y que hoy devuelve siempre `false`. Implementarla habilita las
dos cosas.

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

- La base viva no supera un año: sync y backup dejan de crecer sin límite.
- Los reportes del período vivo no cambian en nada.
- Un reporte que pide años anteriores adjunta el archivo correspondiente,
  consulta, y lo suelta. Es más lento que el período vivo, y está bien: es una
  consulta ocasional.
- Hay que definir qué pasa si una consulta cruza el borde (por ejemplo "últimos
  12 meses" un día que quedan 11 meses vivos): la consulta adjunta el archivo
  más reciente y hace `UNION ALL`.
- El primer archivado ocurre recién al cumplirse un año de uso, así que hay
  tiempo para implementarlo — pero la marca `archivado_hasta` conviene que exista
  en el esquema **antes** de que haya varios dispositivos en producción, para no
  tener que migrar con datos repartidos.
