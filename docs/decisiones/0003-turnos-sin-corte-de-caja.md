# 0003 — Turnos horarios fijos, sin corte de caja

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Reports.feature menciona reportes por "Morning/Afternoon/Night" sin definir los límites horarios, y no estaba claro si existe un evento de apertura/cierre de caja.

## Decisión

- La función principal de la app es contabilidad, no manejo de caja — no hay apertura/cierre de caja ni conciliación de efectivo.
- Los turnos son bandas horarias fijas usadas solo para agrupar reportes:
  - Mañana: 00:00–11:59
  - Tarde: 12:00–17:59
  - Noche: 18:00–23:59

## Consecuencias

Los reportes se calculan agrupando por el timestamp de la venta contra estas bandas, sin necesidad de un estado de "caja abierta/cerrada" en el modelo de datos.
