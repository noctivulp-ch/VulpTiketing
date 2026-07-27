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
