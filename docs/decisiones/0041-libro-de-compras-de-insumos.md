# 0041 — Compras de insumos como entradas del libro, con costo promedio ponderado

**Estado:** Aceptada
**Fecha:** 2026-09-21

## Contexto

El costeo (0040) nació con un `precio_compra` congelado por insumo, editado a
mano. El dueño lo vio en cuanto lo probó: *"si durante el mes voy comprando
harina, dos paquetes de 5 kg a 2.000 y uno de 2,5 kg a 1.000, eso se debe
poder anotar en los insumos y que se vaya registrando cada mes, similar a
como se registra en ventas"*. Y la
[investigación](../investigacion/costeo-tributacion-y-versatilidad.md) le dio
la razón dos veces: el método contable normal es el promedio ponderado de las
compras, y en el régimen simplificado **el impuesto se calcula sobre las
compras del trimestre** — el libro de compras es la base imponible de una soda.

## Decisión

### 1. El insumo se registra una vez; cada compra es una entrada

`insumo` sigue siendo el maestro (nombre, unidad base, merma, proveedor).
`contenido_por_compra` y `precio_compra` pasan a ser el **precio de arranque**:
lo que se usa mientras no haya compras anotadas, para no obligar a inventar una
compra al dar de alta. En cuanto entra la primera compra real, dejan de contar.

Una compra es una fila de `compra_insumo`: fecha, insumo, cuántas
presentaciones, cuánto trae cada una (en unidad base), cuánto se pagó por todo,
notas. Con el ejemplo del dueño son dos entradas: `2 × 5.000 g por ₡4.000` y
`1 × 2.500 g por ₡1.000`.

### 2. Las compras viven en el mismo libro rodante que las ventas

`compra_insumo` es una tabla del **libro** (`ventas-<inicio>.db`), no de la
base principal. El libro pasa a ser el libro del negocio: lo que entra y lo
que sale. Así las compras heredan sin un mecanismo nuevo: la rotación por
días con actividad, la lectura de libros cerrados (`LectorDeLibros`), el
respaldo y el sync (`compra_insumo` entra en `tablasSincronizables` como
tabla del libro). Un libro viejo gana la tabla al adjuntarse:
`ponerAlDiaEsquemaDeLibro` ahora también crea tablas que falten, no solo
columnas.

### 3. El costo del insumo es el promedio ponderado de sus compras recientes

```
costo por unidad base = Σ pagado / Σ (presentaciones × contenido)
```
sobre las compras de los **últimos 90 días**. Si no hay ninguna en la ventana,
la última compra que exista; si no hay compras, el precio de arranque. La
pantalla dice de cuál de las tres salió.

Es el **promedio ponderado de compras**, no el móvil sobre existencias: el
móvil exige saber cuánto queda en bodega, y eso pide descontar consumo
(ventas × recetas), que es la siguiente etapa. Noventa días amortigua los
saltos y sigue al mercado; se ajusta si la práctica dice otra cosa.

### 4. Los totales de compras son un dato de primera

Por mes y por trimestre calendario, a través de todos los libros: es lo que
se declara en el simplificado (`compras × factor`) y lo que dice cuánto se
gasta. Se muestran en la sección Insumos.

## Alternativas descartadas

- **Un libro de compras aparte**, con su propio índice y rotación: dos
  mecanismos iguales para lo mismo. Las compras y las ventas son las dos
  caras del mismo mes.
- **Tabla en la base principal**: crece sin techo; es exactamente lo que la
  máquina de escribir evita.
- **Costo = última compra**: un solo precio malo (una oferta, una urgencia)
  mueve todos los platos. El promedio lo amortigua.

## Consecuencias

- `CompraInsumoNotifier`: anotar, corregir, anular (marca, no borra).
- `costoDeInsumosProvider` (derivado): costo y origen por insumo, y totales
  por mes y trimestre. El costeo (0040) toma de ahí el `Insumo` puro.
- La sección Insumos gana la lista de compras por insumo y el botón "Anotar
  compra"; el formulario de insumo llama "precio de arranque" a lo que antes
  era el precio.
- Etapa siguiente ya prevista: consumo teórico (ventas × recetas) contra
  compras → merma real; y los factores del simplificado en Ajustes (0042).
