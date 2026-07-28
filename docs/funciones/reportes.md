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

- **Drill-down**: tocar un turno dentro del período consultado muestra el desglose de ese turno (ventas individuales), con navegación "← Volver" hacia el nivel anterior.
- **Exportar item puntual**: mantener presionado un ítem específico exporta directo a PDF, sin preguntar formato.
- **Exportar período completo**: un botón siempre visible exporta el rango actualmente seleccionado (día/semana/mes/año), preguntando PDF o CSV.
- Los rankings (más/menos vendido) son solo deslizantes — exportarlos queda fuera de alcance hasta que se pida explícitamente.
- *Nota de implementación:* candidatos de librería cuando se implemente — `pdf` + `printing` para PDF, CSV como texto plano sin librería especial. Ninguno agregado a `pubspec.yaml` todavía.

## Pendiente

Cómo tratar las **líneas libres** (sin Producto de catálogo — [decisión 0016](../decisiones/0016-linea-libre-en-venta.md)) en el ranking de "más/menos vendido": ¿se agrupan bajo un "Personalizado", se listan individualmente por `nombre_libre`, o se excluyen del ranking? No bloquea el resto de reportes, se resuelve al implementar esta pantalla.
