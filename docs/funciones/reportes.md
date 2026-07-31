# Reportes

Ver también: [ventas](ventas.md) · [roles-y-auth](roles-y-auth.md) · [../../features/Reports.feature](../../features/Reports.feature)

## Turnos horarios

Los reportes agrupan ventas por hora del día en tres turnos fijos (no configurables, salvo que se pida lo contrario más adelante):

| Turno | Rango horario |
|-------|---------------|
| Mañana | 00:00 – 11:59 |
| Tarde | 12:00 – 17:59 |
| Noche | 18:00 – 23:59 |

No hay corte de caja estricto — el turno es solo una agrupación temporal para el reporte, no un evento de apertura/cierre operativo (ver [ventas](ventas.md)).

## Permisos por rol

- **Gerente**: consulta por turno/día arbitrario, reportes semanal/mensual/anual, totales y ranking de productos más/menos vendidos.
- **Registradora**: solo semana actual, día actual, y desglose de turno del día actual.

Igual que en [Operations](../../features/Operations.feature), la restricción a la Registradora es de alcance de datos (no necesita ver histórico completo para su función), no una medida de seguridad estricta — ver [roles-y-auth](roles-y-auth.md).

## Interactividad y exportación

Ver bocetos completos en [pantallas/prototipos-ascii.md](../pantallas/prototipos-ascii.md#ventana-4--reportes-revisada--confirmada-como-reporte-unificado-interactivo-y-exportable).

- **Drill-down**: implementado — tocar un turno dentro del período consultado muestra el desglose de ese turno (ventas individuales), con navegación "← Volver" hacia el nivel anterior. El desglose por turno solo aplica al rango "Día" (no tiene sentido mostrar 3 tiles de turno para "todo el mes").
- **Selector de rango**: Día/Semana (Gerente y Registradora) + Mes/Año (solo Gerente). Para Gerente, "Día" admite elegir una fecha arbitraria (selector de fecha); Registradora queda fija al día/semana actual simplemente porque no tiene ese selector — no hace falta lógica de permisos aparte para eso.
- **Exportar el período**: **implementado**. Se mantiene presionado el total y se elige PDF o CSV; el archivo se guarda con el selector nativo, igual que el backup. Exporta exactamente lo que está en pantalla —mismo período, mismo total— porque recibe el reporte ya calculado en vez de volver a consultar.
  - **CSV y no `.xlsx`**: se abre igual en Excel, LibreOffice y Google Sheets, se puede mirar con un editor de texto si algo sale mal, y no arrastra una dependencia para escribir un formato binario. Lleva BOM y saltos CRLF: sin eso, Excel en Windows —el destino más probable— lo abre en una sola columna y con los acentos rotos.
  - **El PDF incrusta su fuente.** Las de fábrica del generador no tienen el símbolo del colón, así que los montos salían sin moneda avisando solo por consola. Se incrusta Noto Sans recortada a los caracteres del reporte: 42 KB en vez de 1,2 MB (`scripts/generar-fuente-pdf.sh`).
  - **Si la lista viene recortada, el archivo lo dice.** Un reporte que omite ventas sin avisar es peor que no exportar: alguien cuadraría caja contra un total incompleto sin saberlo.
- **Elegir el período**: **implementado** para los cuatro rangos. Antes solo el día tenía selector, así que semana, mes y año eran siempre los actuales y no había forma de mirar el mes pasado — que es justo lo que se hace al cerrar cuentas. Cada rango usa la forma que le corresponde: calendario para día y semana, cuadrícula de meses para mes, lista de años para año. Los períodos que todavía no empezaron quedan deshabilitados.
- Los rankings (más/menos vendido) son solo deslizantes — exportarlos queda fuera de alcance hasta que se pida explícitamente.

## Líneas libres en el ranking — resuelto

Las **líneas libres** ([decisión 0016](../decisiones/0016-linea-libre-en-venta.md)) se **excluyen** del ranking de más/menos vendido, pero **sí cuentan** para los totales de dinero (hero, turnos). Razonamiento: el ranking existe para decisiones de catálogo/inventario ("qué producto vender más"), y una línea libre por definición no es un producto de catálogo — incluirla individualmente (por `nombre_libre`) ensuciaría el ranking con entradas de cantidad 1 sin valor informativo; agruparla bajo un "Personalizado" perdería toda información útil. Excluirla del ranking es lo único de las tres opciones que no comprometía el propósito del ranking.
