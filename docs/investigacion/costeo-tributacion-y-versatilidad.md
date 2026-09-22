# Cómo se costea y se tributa un negocio pequeño en Costa Rica — y qué le falta a la app

**Fecha de la investigación: 2026-09-21.** Cada dato lleva la fecha de su
fuente; en tributación un año es una vida (TRIBU-CR reemplazó a ATV en
octubre de 2025, el simplificado se reformó ese mismo mes, y la canasta básica
está en revisión en 2026). **Antes de apoyarse en una cifra de acá, comprobar
que siga vigente.**

Por qué existe este documento: el módulo de costeo (0040) se escribió a partir
de la hoja `Tablas/` sin investigar antes cómo se calcula esto en un negocio
ni cómo funcionan los impuestos. El dueño lo señaló. Esto es lo que debió
leerse primero, y lo que cambia en la app a raíz de ello.

---

## 1. Cómo se costea comida

- **Food cost** = costo de ingredientes del plato ÷ precio de venta × 100.
  Sano entre **28 y 35 %**; arriba de 38 % hay desperdicio, precios de
  proveedor sin control o platos mal costeados. Sin inventario integrado a la
  caja, el costo real suele ser 5–10 puntos más alto de lo que se cree.
  ([Alegra: contabilidad de restaurantes en CR](https://blog.alegra.com/costa-rica/contabilidad-restaurantes-costa-rica/), 2026)
- Nuestro modelo calcula al revés (precio desde el costo con margen objetivo).
  Es equivalente, pero **no muestra el food cost %**, que es la cifra del
  oficio. Se agrega.

## 2. Cómo se valora un insumo

- El método normal es el **promedio ponderado móvil**: con cada compra,
  `costo unitario = (valor en existencia + valor comprado) / (unidades en
  existencia + unidades compradas)`. Amortigua los saltos de precio y es el
  que aceptan las normas contables.
  ([Gerencie](https://www.gerencie.com/metodo-del-promedio-ponderado.html),
  [MRPeasy](https://www.mrpeasy.com/blog/es/costo-promedio-ponderado/))
- El insumo se registra **una vez** (maestro: nombre, unidad base, merma,
  proveedor) y **cada compra es una entrada** con fecha, cantidad, contenido y
  precio pagado. De las entradas salen el costo actual, cuánto se compró por
  mes y por insumo, y la comparación contra lo consumido según ventas ×
  recetas (que es cómo se detecta la merma real).
- Lo que la app tenía —un `precio_compra` congelado que se edita a mano— es
  la versión de hoja de cálculo. Peor, y sin historial.

## 3. Impuestos en Costa Rica (2026)

### Dos regímenes

| | Régimen de Tributación **Simplificada** (RTS) | Régimen **general** |
|---|---|---|
| Para quién | 22 actividades (sodas, panaderías, comercio minorista, salones…); compras anuales ≤ 186 salarios base = **₡85.969.200** en 2026; ≤ 5 empleados; un solo local | Todos los demás |
| IVA en la venta | **No se cobra explícito** al cliente; sin factura electrónica obligatoria por venta | 13 % comida preparada y bebidas; canasta básica **1 %**; 2 % (medicinas, insumos agrícolas, educación privada); 4 % (salud privada, boletos aéreos); exentos |
| Cómo se paga | **Compras del trimestre × factor** de la actividad. Soda/restaurante: **ISR 2,5 % + IVA 3,0 %**; salón 3,0 % + 2,5 %; comercio minorista 1,25 % + 0,5 % | D-150 mensual de IVA; renta anual sobre utilidad |
| Cuándo | D-105-2 en TRIBU-CR: 15 de abril, julio, octubre y enero | IVA antes del 15 de cada mes |
| Multa | ₡231.100 por declarar tarde (2026) | — |

Fuentes: [Alegra: régimen simplificado](https://blog.alegra.com/costa-rica/regimen-simplificado/)
(actualizado 2026-07-10, de donde salen los factores y fechas),
[Alegra: IVA en alimentos por régimen](https://blog.alegra.com/costa-rica/iva-en-alimentos-diferencia-regimenes/),
[Plaxp: tarifas de IVA](https://plaxp.com/iva-en-costa-rica),
[KPMG: reforma del RTS, dic. 2025](https://kpmg.com/us/en/taxnewsflash/news/2025/12/costa-rica-amendments-simplified-tax-regime-regulations.html).
Una fuente anterior daba 4 % de IVA para restaurantes; la de julio de 2026
dice 3,0 %. **Comprobar el factor vigente en el decreto antes de declarar.**

Ejemplo (soda en RTS, compras del trimestre ₡3.000.000): ISR ₡75.000 + IVA
₡90.000 = **₡165.000**.

**Lo que esto cambia en la app:** en el RTS el impuesto se calcula **sobre las
compras**, no sobre las ventas. El libro de compras de insumos no es solo
para costear: **es la base imponible de una soda**. Sumar las compras del
trimestre × factores es la declaración.

### Un negocio de servicios digitales (el caso del dueño: apps por Patreon)

- **Exportación de servicios**: si el cliente está fuera de Costa Rica y el
  servicio se consume fuera, IVA al **0 %**.
  ([Siempre al día: IVA en servicios digitales](https://siemprealdia.co/costa-rica/impuestos/iva-en-servicios-digitales-transfronterizos-costa-rica/), 2026)
- **Renta 2026** para trabajador independiente / actividad lucrativa, por
  tramos anuales: hasta ₡4.315.000 exento; 10 % hasta 6.445.000; 15 % hasta
  10.751.000; 20 % hasta 21.545.000; 25 % el exceso.
  ([Siempre al día: renta 2026](https://siemprealdia.co/costa-rica/impuestos/impuesto-sobre-la-renta-en-costa-rica/),
  [ATC: tramos 2026](https://www.atcauditores.com/nuevos-tramos-de-renta-2026-en-costa-rica-cambios-en-salarios-utilidades-y-creditos-fiscales/))
- **CCSS**: afiliación como trabajador independiente (cuota sobre el ingreso
  declarado). Es un costo fijo mensual del negocio.
- **Comisión de plataforma**: Patreon cobra un porcentaje del precio más
  procesamiento de pago: es exactamente "comisión de medios de pago" del
  modelo.
- La renta por tramos es **sobre la utilidad**, no sobre el precio: queda
  fuera del cálculo de precio y entra en el resumen anual, si se quiere.

## 4. Qué pide un trabajo de desarrollo empresarial

Lo que evalúan: estructura de costos (fijos vs. variables), costo unitario,
margen de contribución, **punto de equilibrio en unidades y en colones**,
proyección de ingresos y, a veces, flujo de caja.
([HubSpot](https://blog.hubspot.es/sales/punto-equilibrio-empresa),
[Pymes Futuro](https://www.pymesfuturo.com/puntodequilibrio.htm))

El modelo ya da todo eso salvo el punto de equilibrio **en colones**
(`unidades × precio promedio`) y una **proyección** (escenarios pesimista /
realista / optimista, que la hoja sí tenía). Se agregan.

Para un negocio de software, el ajuste conceptual: el desarrollo es **costo
hundido**, no se produce por unidad. Se lleva como **costo fijo amortizado**
(horas × tarifa ÷ meses) y la receta queda vacía; el punto de equilibrio sale
en *patrocinadores por mes*, que es la cifra correcta.

## 5. Qué le falta a la app para ser versátil sin perder la base

Criterio del dueño: *"hacer más versátil la app sin desprestigiar su
funcionalidad base"*. Lo de la soda no se toca; se agrega lo que otro negocio
necesita, apagable.

| Falta | Para quién | Tamaño |
|---|---|---|
| **Libro de compras de insumos** con promedio ponderado móvil; totales por mes, por insumo y por trimestre | Soda (costeo real y base del RTS), cualquiera con inventario | Grande — es el cambio de fondo |
| **Impuestos flexibles**: tasa por producto (13/4/2/1/exento), comisión por medio de pago, régimen (simplificado con factores / general) en Ajustes | Soda, comercio, servicios | Mediano |
| **Moneda opcional**: símbolo y decimales | Patreon (USD), cualquiera fuera de CR | Mediano, transversal |
| **Food cost %** y **equilibrio en colones**, escenarios | Todos; el trabajo de la U | Chico |
| **Elegir las ventanas de venta** en Configuración: las dos, solo Venta Rápida, solo Panel | Negocios sin mostrador o sin carrito | Chico |
| **Perfil de negocio de servicios**: artículos sin receta sin alerta, costo por hora, amortización como fijo | Patreon, consultoría | Chico sobre lo anterior |
| **Importar ventas** (CSV de Patreon u otra plataforma) | Patreon | Mediano; después |

Orden: como lo maneja el dueño — *que exista → mejorar → optimizar → pulir*.
Cada pieza con su ADR, migración probada y pruebas.
