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
- **Exportar item puntual / período completo**: aún **no implementado** — mantener presionado un ítem específico exportaría directo a PDF; un botón siempre visible exportaría el rango completo preguntando PDF o CSV. Candidatos de librería: `pdf` + `printing` para PDF, CSV como texto plano. Research aparte, no bloquea el resto de Reportes.
- Los rankings (más/menos vendido) son solo deslizantes — exportarlos queda fuera de alcance hasta que se pida explícitamente.

## Líneas libres en el ranking — resuelto

Las **líneas libres** ([decisión 0016](../decisiones/0016-linea-libre-en-venta.md)) se **excluyen** del ranking de más/menos vendido, pero **sí cuentan** para los totales de dinero (hero, turnos). Razonamiento: el ranking existe para decisiones de catálogo/inventario ("qué producto vender más"), y una línea libre por definición no es un producto de catálogo — incluirla individualmente (por `nombre_libre`) ensuciaría el ranking con entradas de cantidad 1 sin valor informativo; agruparla bajo un "Personalizado" perdería toda información útil. Excluirla del ranking es lo único de las tres opciones que no comprometía el propósito del ranking.
