# 0037 — Corte de caja, y la jornada en dos turnos

**Estado:** Aceptada
**Fecha:** 2026-08-10

## Contexto

Cuadrar la caja en la soda se hacía a mano, con la app solo como fuente del
total vendido. El dueño describió el flujo real:

> Antes de abrir se anota el monto de apertura. A medio día más o menos se hace
> una cuenta para ver que el monto coincida con los pagos anotados, para el
> cambio de turno. Al cerrar se hace un conteo de cierre. Durante el cambio de
> turno (entre las 12 y las 2:30) y en el cierre se suele guardar la mayor parte
> del efectivo y se deja una cantidad para los vueltos.

Dos cosas de esa descripción mandan el diseño entero:

1. **El monto de la caja cambia tres veces al día**, y cada vez el número nuevo
   es con lo que sigue trabajando la caja — no un histórico que se acumula.
2. **El momento del cambio de turno no es una hora fija.** Cae entre las 12 y
   las 2:30 según el día.

Al mismo tiempo, el reparto de la jornada que tenía la app —mañana (12 h), tarde
(6 h) y noche (6 h)— no se correspondía con nada de eso: hay **un** cambio de
turno, no dos, y los tramos eran de distinto tamaño, así que compararlos entre sí
no decía nada.

## Decisión

### Un cuadro de corte de caja, hermano del total y no parte suya

En Reportes del Gerente, debajo del total del día:

```
┌─────────────────────┐
│  Caja Inicial       │
│  ₡15 000.00         │
│                     │
│  Caja Total         │
│  ₡35 000.00         │
│                     │
│  Toca: Cierre       │
└─────────────────────┘
```

- **Caja Inicial** — lo que quedó en el cajón en el último corte.
- **Caja Total** — lo que **debería** haber ahora: `Caja Inicial + efectivo
  cobrado desde ese corte`. Es el número contra el que se compara el conteo a
  mano.

**El total del día sigue como estaba y no se toca.** Lo dejó claro el dueño: ese
dato reúne los ingresos de la tienda por efectivo *y* SINPE, y es lo que mide
cuánto vendió el negocio. El corte contesta otra pregunta —cuánto hay en el
cajón— y por eso solo mira efectivo. Se parecen lo suficiente para que
confundirlos sea fácil, y confundirlos significa cuadrar el cajón contra un
número que incluye transferencias que nunca entraron en él.

### El efectivo se cuenta desde el último corte, no desde que abrió el día

Es la consecuencia de que en el cambio de turno se guarde la plata. Si el
esperado sumara el día entero, después del corte de medio día quedaría por
encima de lo que hay en el cajón **para siempre**, y el cuadro sería inútil justo
la mitad del día en que más se usa.

Ejemplo, con los números de la prueba: 40 000 en efectivo por la mañana; a las
13:00 se cuenta, se guardan 35 000 y quedan 15 000 para vueltos; por la tarde
entran 20 000. Lo esperado es **35 000**, no 75 000.

De ahí que `monto` sea **lo que queda**, no lo que se contó: después de un
corte, ese número es la caja inicial del tramo siguiente.

### El orden lo manda el corte anterior, nunca el reloj

Los tres momentos se ven siempre —así se sabe en qué punto va la jornada— pero
solo responde el que toca: apertura habilita medio día, y medio día habilita
cierre. La regla no puede ser horaria porque la hora del cambio de turno varía
cada día.

La comprobación está en dos sitios a propósito: el botón deshabilitado es
comodidad de la pantalla, y `CajaNotifier.registrar` la repite porque es lo que
impide que un cierre entre sin apertura. Un corte fuera de orden dejaría la caja
inicial apuntando a un tramo que nunca existió.

### Un corte no se edita ni se borra — salvo el último

`CajaNotifier` tiene **solo `registrar`**. Se cuenta, se valida y se da por
cerrado — así lo describió el dueño. Darle `actualizar` o `eliminar` "por
consistencia" con otros notifiers sería inventarle un ciclo de vida que no tiene
([0009](0009-cruds-independientes-por-entidad.md)) y, peor, permitiría reescribir
un conteo ya cerrado: exactamente lo que un corte de caja existe para impedir.

**La rigidez falló en el primer uso, y hubo que abrir una excepción.** Un cierre
se anotó con un 5 y quince ceros; el día quedó cerrado en
₡5 000 000 000 000 000, con los tres cortes hechos y sin nada que "tocara", así
que no había forma de arreglarlo desde la app. Un dedazo no puede inutilizar la
jornada.

Ahora el **último** corte se puede volver a anotar, y solo el último: los
anteriores ya sirvieron de frontera para el efectivo que se contó después, y
cambiarlos movería tramos que ya se cuadraron. La corrección:

- **conserva el id**, para que la sincronización la vea como la misma fila
  corregida y no como un corte nuevo — con un id nuevo, el otro teléfono acabaría
  con dos cortes del mismo momento;
- **conserva la hora**, porque es la frontera del tramo: el conteo se hizo a esa
  hora aunque el dedazo se arregle dos minutos después;
- **avanza `updated_at`**, o la corrección no ganaría el LWW y el número
  equivocado volvería en la ronda siguiente.

En el diálogo, el corte que toca va en botón relleno y el corregible en
contorneado: corregir es la salida de emergencia, no el camino normal.

### Tabla propia en la base principal, y viaja por sincronización

`corte_caja` (v4 → v5): `id`, `dia`, `momento`, `monto`, `fecha_hora`,
`updated_at`, `deleted_at`.

- **En la base principal, no en el libro de ventas.** Son tres filas al día —mil
  al año— y el libro existe para lo que crece sin techo
  ([0025](0025-archivado-anual-rodante.md)). Meterlas ahí obligaría a abrir
  libros viejos para leer un número de hoy.
- **`dia` va suelto** (`2026-08-10`) además de `fecha_hora`. Es redundante a
  propósito: la regla de orden es por día, y comparar una fecha suelta es más
  barato y menos delicado que recortar un instante con zona horaria en cada
  consulta.
- **Se sincroniza.** Si el Gerente mira los reportes en su teléfono y la caja se
  cuenta en el de la caja, el corte tiene que estar en los dos o el cuadro diría
  que la apertura no se anotó.

`esquemaSync` sube a 4. Un aparato viejo no tiene la tabla, así que pediría
`corte_caja` y fallaría a mitad de ronda; rechazarlo por versión lo dice en la
pantalla en vez de dejar rondas fallando en silencio. **Implica actualizar todos
los aparatos**, no se puede dejar uno atrás.

### La jornada pasa a dos turnos de 12 horas

`Turno { primero, segundo }`, con el corte en las 12:00. Los nombres —**Primer
turno** y **Segundo turno**— los eligió el dueño entre varias propuestas: son
neutros respecto a la hora, así que siguen sirviendo si algún día la soda abre en
otro horario.

Dos mitades iguales dan la comparación que sí se usa (cuánto entró antes del
cambio y cuánto después) y calzan con los tres cortes: apertura → medio día es el
primer turno, medio día → cierre el segundo.

El corte horario se queda en las 12 en punto y no en la hora real del cambio de
turno porque esa hora varía. Para cuadrar la caja está el corte de medio día, que
se anota cuando toca.

No hay datos que migrar: el turno se calcula desde `fecha_hora`, nunca se guardó.

### Los cortes salen en el archivo exportado, hasta donde sirven

Lo pidió el dueño: son datos útiles, no solo una ayuda de pantalla.

| Formato | Hasta dónde |
|---|---|
| CSV (Excel) | día, semana y **mes** |
| PDF | solo el **día** |
| — | el **anual queda fuera** de los dos |

El CSV es la hoja que ve el contador, y ahí una tabla de noventa cortes con su
fecha se lee y se cruza. El PDF es el papel de cerrar la jornada; un PDF mensual
con noventa filas de conteos no es lo que nadie va a mirar.

Por eso la tabla del CSV **lleva fecha** y la del PDF no: el CSV mezcla días y sin
la fecha no se sabría a cuál pertenece cada conteo.

La columna se llama **"Queda en caja"** y no "Monto". Sin esa palabra, quien abra
el archivo dentro de un mes suma la columna y obtiene un número que no es ningún
dinero que haya existido: son tres fotos del mismo cajón en momentos distintos.

### "Menos vendidos" sale de la pantalla del Gerente

Su sitio lo ocupa el cuadro de caja, que se usa todos los días. El dato **sigue
calculándose**, la Registradora lo sigue viendo y sigue en el reporte exportado,
donde no compite por espacio con nada.

## Lo que queda fuera

- **No hay tope al monto.** Se evaluó rechazar cifras absurdas y se prefirió la
  corrección: un tope es un número inventado que algún día estorbará, y corregir
  arregla también los errores que caen dentro del rango.
- **No se guarda el monto contado**, solo el que queda. El diálogo pide un
  número, como lo dibujó el dueño. Registrar las dos cifras permitiría dejar
  constancia de un descuadre; no se pidió y no se inventa.
- **Solo se anotan sobre el día de hoy.** Mirando un día pasado el cuadro no
  aparece: anotar el conteo de ayer no tiene lectura, y dejar el gesto
  disponible invita a hacerlo por costumbre.
