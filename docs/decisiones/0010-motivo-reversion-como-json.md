# 0010 — Motivo de reversión de Venta como JSON en columna TEXT

**Fecha:** 2026-07-26
**Estado:** Aceptada

## Contexto

Al revertir una Venta se necesita registrar un motivo. Un solo string plano alcanza para el detalle libre, pero probablemente se quiera distinguir el **tipo** de motivo (devolución, pedido erróneo, otro) además del texto, y potencialmente más campos a futuro (quién revirtió, cuándo) sin tener que agregar columnas nuevas cada vez.

## Decisión

Guardar el motivo como JSON serializado en una columna `TEXT` (SQLite no tiene un tipo `JSON` nativo, pero acepta y sirve texto igual de bien; desde SQLite 3.38 además trae funciones JSON integradas — `json_extract`, `json_set`, etc. — para consultarlo directamente en SQL si hiciera falta).

Forma sugerida:
```json
{
  "tipo": "devolucion",
  "detalle": "cliente pidió cambio, producto equivocado",
  "revertido_por": "<usuario>",
  "revertido_en": "2026-07-26T18:32:00-06:00"
}
```

## Alternativas descartadas

- Una columna de texto plano sin estructura — pierde la capacidad de filtrar/reportar por tipo de motivo sin parsear texto libre.
- Una tabla aparte `motivos_reversion` — sobre-ingeniería para un campo que solo aplica a ventas revertidas (caso minoritario).

## Consecuencias

- Confirmar al implementar si el SQLite empaquetado por el plugin Flutter elegido (sqflite / sqlite3) trae las funciones JSON habilitadas; si no, decodificar el JSON del lado de Dart tras leer la fila es igual de viable para el volumen de datos de una soda pequeña.
- Esta columna solo se puebla cuando `estado = revertida`; para una venta activa queda `NULL`.
