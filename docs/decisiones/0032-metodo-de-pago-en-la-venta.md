# 0032 — Método de pago en la venta, con referencia opcional anotada después

**Estado:** Aceptada
**Fecha:** 2026-08-03

## Contexto

En la soda se cobra de dos formas: **efectivo**, que es lo normal, y **SINPE**.
La app solo sabía de la primera, así que al cerrar el mes no había forma de
cuadrar lo que entró por transferencia contra el estado de cuenta del banco.

El flujo real lo describió el dueño: *"durante la venta se marca como sinpe y
después se pueda agregar el identificador de la transferencia de forma
opcional"*. Es exactamente cómo funciona el mostrador — al cobrar hay cola, y
nadie transcribe un número de doce dígitos con el cliente delante.

## Decisión

**Dos columnas en `venta`**, no una tabla aparte:

- `metodo_pago TEXT NOT NULL DEFAULT 'efectivo' CHECK (IN ('efectivo','sinpe'))`
- `referencia_pago TEXT` — nulo mientras no se anote

**Una casilla, no un selector de dos opciones.** Efectivo es lo que pasa si
nadie hace nada. Pedir que se elija en cada venta lo que nueve de cada diez veces
es lo mismo agrega un toque por venta a cambio de nada.

**La referencia se anota después**, tocando la venta en el detalle de Reportes.
Solo las de SINPE se tocan: una venta en efectivo no tiene referencia que
agregar, y abrir un diálogo vacío sería una promesa rota. Guardar en blanco la
borra — alguien anota mal un número y tiene que poder dejarlo como estaba.

### La excepción a la decisión 0009

La [0009](0009-cruds-independientes-por-entidad.md) dice que Venta solo se crea o
se revierte, nunca se edita. `anotarReferenciaDePago` **escribe sobre una venta
guardada**, y es deliberado:

- La referencia es un dato **del cobro**, no de la venta: no cambia importes,
  líneas ni estado.
- Lo que 0009 protege es que una venta no se pueda "arreglar" después. Eso sigue
  igual: no hay `actualizar()` ni `eliminar()`, y esta operación escribe **una
  sola columna**.
- Revertir ya mutaba la venta de forma acotada y explícita. Esta es la segunda
  excepción del mismo tipo, y las dos están nombradas.

## Alternativas descartadas

- **Tabla `pago` 1:1 con venta.** Es lo que sugirió el dueño ("puede ser una
  tabla intermedia o similar") y sería más ortodoxo para 0009: Pago como entidad
  propia sí admitiría actualizarse. Se descartó por el costo alrededor — el sync
  tendría que aprender una quinta tabla (`tablasSincronizables`), cada libro
  tendría que crearla y migrarla, y toda consulta de ventas cargaría con una
  junta. Para una relación 1:1 **obligatoria** con dos campos, la tabla paga
  complejidad en cinco sitios para no dar nada hoy. Si algún día hace falta un
  pago **mixto** —parte efectivo, parte transferencia—, la tabla se agrega
  entonces y estas columnas se migran a ella.
- **Guardar la referencia al cobrar, obligatoria.** Es lo que rompería el flujo:
  con cola, o se inventa un número o se deja de usar SINPE en la app.
- **Un campo de texto libre "detalle de pago".** `venta.detalle` ya existe sin
  usar y habría servido, pero un texto libre no se puede sumar: "cuánto entró por
  SINPE" dejaría de ser una consulta y pasaría a ser una lectura a ojo.

## Consecuencias

- Los libros ya escritos se ponen al día **al adjuntarlos**, no en la migración
  de la base principal: un libro es un archivo suelto que puede venir de otro
  aparato o de un backup viejo, y esa migración solo ve el libro abierto de este
  dispositivo. `ADD COLUMN` con `DEFAULT` no reescribe filas en SQLite, así que
  es instantáneo incluso con 100.000 ventas.
- El sync no cambia: `venta` ya se sincroniza entera y LWW resuelve la anotación
  posterior por `updated_at`.
- El backup tampoco: copia los archivos.
- Reportes gana **cuánto entró por SINPE** (agregado en SQL, como el resto), y el
  desglose solo se muestra si hubo alguna: "SINPE ₡0" en un día de puro efectivo
  es una línea que no dice nada.
- Las exportaciones llevan `Pago` y `Referencia`. En el PDF solo se nombra lo que
  **no** es lo normal: repetir "Efectivo" en doscientas filas es ruido.
