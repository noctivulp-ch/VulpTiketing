# 0043 — Moneda opcional: símbolo y decimales, de presentación

**Estado:** Aceptada
**Fecha:** 2026-09-21

## Contexto

La app escribía `₡` a mano en dieciséis sitios y redondeaba a enteros o a
dos decimales según la pantalla. Para una soda está bien (0012: colones
enteros); para el negocio del dueño —apps por Patreon, en dólares con
centavos— no. Punto 3 de la [idea 5](../ideas-abiertas.md).

## Decisión

`Moneda(simbolo, decimales)` en `core/moneda.dart`, colones enteros de
fábrica. **Es de presentación y captura**: la base sigue guardando `REAL`
sin moneda y no se convierte nada; cambiarla no reescribe una venta, cambia
cómo se leen y se teclean los números.

- Vive en **preferencias del aparato**, no en el sync: los dos aparatos de un
  negocio se ponen igual una vez. Configuración → Moneda: símbolo libre (1–4
  caracteres) y decimales en enteros o centavos, con la muestra al lado.
- Llega a todo widget por el árbol (`MonedaScope` en la raíz, `Moneda.de(context)`),
  incluidos los que no leen providers; sin scope vale colones, así que las
  pruebas de widget sueltas siguen valiendo. Al PDF llega por parámetro:
  el servicio no tiene contexto.
- Una sola forma de escribir dinero: `Moneda.formatear(monto)`. Los costos
  por unidad del costeo fuerzan dos decimales aunque la moneda vaya en
  enteros — el gramo de harina cuesta 4,64.
- Efecto colateral bueno: las pantallas que mostraban `₡3000.00` en colones
  ahora muestran `₡3000`, que es como se escribe.

## Alternativas descartadas

- **Moneda en el sync** (tabla del negocio): la moneda no es un dato, es una
  forma de escribir; y mezclar aparatos con distinta moneda no es un caso.
- **Conversión de tipo de cambio**: fuera de alcance. Quien cobra en dólares
  anota dólares; el libro es una foto.

## Consecuencias

- `ReporteExportService(moneda:)`; `colones(context, v)` en el costeo.
- Sin migración: preferencias, no esquema.
