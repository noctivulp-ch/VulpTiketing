# 0028 — Las acciones de un diálogo van al costado cuando la pantalla está acostada

**Estado:** Aceptada
**Fecha:** 2026-08-02

## Contexto

Los diálogos de la app ponían sus botones donde los pone `AlertDialog`: en una
fila debajo del contenido, y apilados cuando esa fila no entra a lo ancho.

Acostado —un teléfono de 800×360— eso no funciona. El alto es el recurso escaso
y los campos ya se lo comen: el formulario de producto desbordaba **95 px** por
tener cuatro botones debajo. Y el apilado que hace `AlertDialog` cuando no
entran de ancho alinea los cuatro a la derecha, con lo que se pierde de qué
habla cada uno: "Reactivar" y "Eliminar" le pasan al **producto**, "Cancelar" y
"Guardar" le pasan al **formulario**.

El overlay de cobro rápido de Ventana 1 tenía la otra cara del problema: entraba,
pero dentro de un `SingleChildScrollView`. Cobrar terminaba pidiendo un gesto de
desplazamiento para llegar a "Completado", justo en el momento en que hay cola.

Esto se resolvió primero a mano en `producto_form_dialog.dart`, y quedó ahí: el
resto de los emergentes siguió como estaba.

## Decisión

Todos los diálogos de la app usan `BentoDialogo` + `BentoAcciones`
(`lib/core/ui/bento_dialogo.dart`):

- **De pie** (alto ≥ 520 dp): el contenido arriba, las acciones debajo.
- **Acostado** (alto < 520 dp): el contenido a la izquierda y las acciones en
  una columna **al costado**, dentro del `content` — no en `actions`, que es
  justamente lo que las manda abajo.

Las acciones son siempre una cuadrícula de **dos columnas del mismo ancho**, la
misma en las dos orientaciones: a la izquierda lo que le pasa al objeto, a la
derecha lo que le pasa al diálogo. Lo único que cambia acostado es dónde se
coloca el bloque, no cómo se organiza.

Una confirmación de dos botones ocupa una sola fila de esa cuadrícula (acción a
la izquierda, cancelar a la derecha): apilar dos botones no aporta nada y no es
lo que se espera de un "¿seguro?".

El umbral de 520 dp es **alto**, no orientación: lo que escasea acostado es el
alto, y una tablet apaisada de 800 dp no tiene este problema. Es el mismo número
que ya usaba Reportes.

## Alternativas descartadas

- **Dejar que `AlertDialog` apile**: es lo que ya hacía, y es lo que desbordaba.
- **Un `SingleChildScrollView` en cada diálogo**: entra siempre, sí, pero
  convierte cada confirmación en un gesto de más. Es la solución que tenía el
  cobro rápido y la que el usuario señaló como inaceptable para el uso real.
- **Repetir el patrón en cada diálogo** (que es como estaba tras arreglar el
  formulario de producto): ocho copias del mismo `Row` + `IntrinsicWidth`, y la
  garantía de que el noveno diálogo se escribiría sin él.

## Consecuencias

- Un diálogo nuevo hereda el comportamiento por construcción; no hay que
  acordarse.
- `test/dialogos_acostados_test.dart` fija las tres propiedades: al costado
  acostado, abajo de pie, y las columnas a escuadra entre filas.
- Migrados: formulario de producto, eliminar producto, nueva categoría, purgar
  producto, editar línea, línea libre, elegir formato de exportación, elegir mes
  y elegir año. El overlay de cobro rápido no usa `BentoDialogo` —es una bandeja
  propia, con su retícula— pero sigue la misma regla a mano.
