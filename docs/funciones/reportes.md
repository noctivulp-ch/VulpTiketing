# Reportes

Ver también: [ventas](ventas.md) · [roles-y-auth](roles-y-auth.md) · [../../features/Reports.feature](../../features/Reports.feature)

## Turnos horarios

Los reportes agrupan ventas en dos turnos fijos de 12 horas ([decisión 0037](../decisiones/0037-corte-de-caja-y-jornada-en-dos-turnos.md)):

| Turno | Rango horario |
|-------|---------------|
| Primer turno | 00:00 – 11:59 |
| Segundo turno | 12:00 – 23:59 |

Eran tres tramos desiguales —mañana de 12 h, tarde y noche de 6— y no se correspondían con cómo trabaja la soda: hay **un** cambio de turno, en algún punto entre las 12 y las 2:30 de la tarde. Dos mitades iguales dan la comparación que sí se usa: cuánto entró antes del cambio y cuánto después.

El turno sigue siendo una agrupación temporal calculada desde `fecha_hora`, no un evento operativo. Lo operativo es el **corte de caja**, que es otra cosa y se anota a mano (abajo).

## Corte de caja

Debajo del total, y solo para el **Gerente** en el rango de **día**, hay un cuadro con dos números:

| | Qué es |
|---|---|
| **Caja Inicial** | Lo que quedó en el cajón en el último corte anotado |
| **Caja Total** | Lo que **debería** haber ahora: `Caja Inicial + efectivo cobrado desde ese corte` |

**No sustituye al total del día ni se confunde con él.** El total reúne los ingresos de la tienda por efectivo *y* SINPE — cuánto vendió el negocio. El corte contesta cuánto hay en el cajón, así que solo mira efectivo: una transferencia nunca entró ahí.

Se anota tocando el cuadro: pide el monto que **queda** en la caja y en qué momento del día se está —Apertura, Medio Día, Cierre—. Los tres se ven siempre, pero solo se puede pulsar el que toca: la apertura habilita el medio día y el medio día habilita el cierre. La regla no es horaria porque la hora del cambio de turno varía cada día.

Los cortes **salen en el archivo exportado**: en CSV hasta el mes (con fecha, porque mezcla días) y en PDF solo el día. El anual queda fuera de los dos. La columna se llama "Queda en caja" y no se suma: son fotos del mismo cajón en momentos distintos.

El **último** corte se puede volver a anotar para corregir un dedazo —el diálogo dice qué monto va a reemplazar—; los anteriores quedan cerrados. Solo se anota sobre el día de hoy. El detalle del razonamiento está en la [decisión 0037](../decisiones/0037-corte-de-caja-y-jornada-en-dos-turnos.md).

## Permisos por rol

- **Gerente**: consulta por turno/día arbitrario, reportes semanal/mensual/anual, totales, ranking de más vendidos y el **corte de caja**. **No** ve el ranking de menos vendidos en pantalla: su sitio lo ocupa el corte de caja, que se usa todos los días — el dato sigue calculándose y sigue en el reporte exportado.
- **Registradora**: solo semana actual, día actual, y desglose de turno del día actual. Ve los dos rankings y **no** el corte de caja.

Igual que en [Operations](../../features/Operations.feature), la restricción a la Registradora es de alcance de datos (no necesita ver histórico completo para su función), no una medida de seguridad estricta — ver [roles-y-auth](roles-y-auth.md).

## Interactividad y exportación

Ver bocetos completos en [pantallas/prototipos-ascii.md](../pantallas/prototipos-ascii.md#ventana-4--reportes-revisada--confirmada-como-reporte-unificado-interactivo-y-exportable).

- **Drill-down**: implementado — tocar un turno dentro del período consultado muestra el desglose de ese turno (ventas individuales, cada una con **qué se vendió**: "2× Casado, Fresco", no "2 línea(s)"), con navegación "← Volver" hacia el nivel anterior. El desglose por turno solo aplica al rango "Día" (no tiene sentido mostrar tiles de turno para "todo el mes").
- **Selector de rango**: Día/Semana (Gerente y Registradora) + Mes/Año (solo Gerente). Para Gerente, "Día" admite elegir una fecha arbitraria (selector de fecha); Registradora queda fija al día/semana actual simplemente porque no tiene ese selector — no hace falta lógica de permisos aparte para eso.
- **Exportar el período o un turno**: **implementado**. Se mantiene presionado el total —o la celda de un turno— y se elige PDF o CSV. El archivo va a **Descargas › VulpTiketing**, sin selector: se dice en el aviso dónde quedó ([decisión 0029](../decisiones/0029-exportar-a-descargas-por-mediastore.md)). Exporta exactamente lo que está en pantalla —mismo período, mismo total— porque recibe el reporte ya calculado en vez de volver a consultar.
  - **Una fila por LÍNEA, no por venta.** Hasta 2026-08-02 el archivo decía "2 línea(s)" y no había forma de saber qué se había vendido: el nombre no está en `linea_venta` —la línea de catálogo guarda `producto_id` y la libre `nombre_libre` ([decisión 0016](../decisiones/0016-linea-libre-en-venta.md))— y la consulta no lo resolvía. El CSV lleva Fecha, Hora, Producto, Cantidad, Precio unitario, Subtotal, Nota e id de venta; ese id agrupa las líneas, porque sin él dos ventas de la misma hora se confunden al ordenar la tabla en Excel.
  - **El PDF abre con lo más vendido** (top 10) antes del detalle: es lo que se mira primero para decidir qué reponer. Se calcula sobre las mismas ventas que van en el detalle, no consultando de nuevo, para que el archivo cuadre consigo mismo.
  - **CSV y no `.xlsx`**: se abre igual en Excel, LibreOffice y Google Sheets, se puede mirar con un editor de texto si algo sale mal, y no arrastra una dependencia para escribir un formato binario. Lleva BOM y saltos CRLF: sin eso, Excel en Windows —el destino más probable— lo abre en una sola columna y con los acentos rotos.
  - **El PDF incrusta su fuente.** Las de fábrica del generador no tienen el símbolo del colón, así que los montos salían sin moneda avisando solo por consola. Se incrusta Noto Sans recortada a los caracteres del reporte: 42 KB en vez de 1,2 MB (`scripts/generar-fuente-pdf.sh`).
  - **Exportando un turno no se incluye la tabla por turnos**: con dos ceros y su propio total repetido, no informa nada. Y sus ventas ya vienen en el reporte de pantalla, así que no hay consulta extra — a diferencia del período completo, que sí carga el detalle bajo demanda.
  - **El archivo lleva TODAS las ventas del período, sin tope.** El límite de `limiteDetalleRango` (300) es de la PANTALLA —nadie desplaza 5.000 filas en un teléfono—; aplicarlo al exportar era un error: nadie manda a su contador un informe que dice "incluye las 300 más recientes de 2.847". El CSV se escribe **lote a lote directo al archivo**, así que el consumo no depende del tamaño del período.
  - **Las páginas del PDF se calculan del contenido.** El generador aborta a las 20 páginas por defecto (`PdfTooBigPageException`) y por eso exportar el año fallaba. No se pone un tope arbitrario —eso solo mueve el problema— sino una cota superior imposible de superar: una página por fila más diez. Estimar el promedio fue el primer intento y se quedó corto.
- **Elegir el período**: **implementado** para los cuatro rangos. Antes solo el día tenía selector, así que semana, mes y año eran siempre los actuales y no había forma de mirar el mes pasado — que es justo lo que se hace al cerrar cuentas. Cada rango usa la forma que le corresponde: calendario para día y semana, cuadrícula de meses para mes, lista de años para año. Los períodos que todavía no empezaron quedan deshabilitados.
  - **Los períodos con ventas llevan una marca.** Un punto bajo el número, en las cuatro escalas. Sin eso, elegir era prueba y error: tocar un día, esperar la carga y ver "sin ventas" — en una soda que abre seis días por semana, buscar el martes de hace tres semanas se volvía adivinanza. Sale de **una** consulta por año (`PeriodosConDatos`), de la que se derivan día, semana, mes y año sin una consulta por celda. Las ventas revertidas no marcan: mandarían a un día que el reporte muestra en cero.
  - **La semana se elige entera.** El selector resalta los siete días del bloque y tocar cualquiera lo elige. `showDatePicker` pedía *"elegí un día de la semana"*, que es una pregunta que nadie se hace — y además no sabe marcar días ni resaltar semanas, por eso el calendario es propio (`CalendarioPeriodo`).
- Los rankings de la pantalla (más/menos vendido) son solo deslizantes. **El PDF sí lleva el suyo** —el top 10 de lo más vendido del período exportado—: ahí no cuesta nada y es lo primero que se mira en un reporte impreso.

## Líneas libres en el ranking — resuelto

Las **líneas libres** ([decisión 0016](../decisiones/0016-linea-libre-en-venta.md)) se **excluyen** del ranking de más/menos vendido, pero **sí cuentan** para los totales de dinero (hero, turnos). Razonamiento: el ranking existe para decisiones de catálogo/inventario ("qué producto vender más"), y una línea libre por definición no es un producto de catálogo — incluirla individualmente (por `nombre_libre`) ensuciaría el ranking con entradas de cantidad 1 sin valor informativo; agruparla bajo un "Personalizado" perdería toda información útil. Excluirla del ranking es lo único de las tres opciones que no comprometía el propósito del ranking.
