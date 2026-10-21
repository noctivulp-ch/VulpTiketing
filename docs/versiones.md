# Registro de versiones

Qué se instaló en los aparatos del negocio, cuándo, y qué llevaba dentro.

Existe porque desde la primera instalación en producción **la app tiene datos
reales que no se pueden perder**: ventas cobradas, cortes de caja y el catálogo
de la carta. Sin este registro, "qué versión corre el teléfono de la caja" es una
suposición, y una migración se planea a ciegas.

## Reglas desde la 1.0.0

Las puso el dueño al publicar: *"cualquier cosa que se cambie o agregue desde
ahora se tiene que planear como un update con datos reales y críticos presentes,
existan o no"*.

1. **Nunca se borran datos de un aparato en producción.** Ni `pm clear`, ni
   desinstalar, ni `reset_datos`. Los scripts de prueba se niegan a tocar los
   seriales de producción — ver `scripts/pruebas-sync/comun.sh`.
2. **Cada cambio de esquema es una migración probada sobre una base vieja de
   verdad**, no sobre un esquema recreado. Es lo que ya hace
   `test/migracion_esquema_test.dart`, y de acá en adelante es obligatorio.
3. **Se sube `version` en `pubspec.yaml`** y se anota acá antes de instalar. El
   número de compilación sube siempre, aunque la versión semántica no cambie:
   es lo único que distingue dos instalaciones.
4. **Un cambio en `esquemaSync` obliga a actualizar todos los aparatos a la
   vez.** Un aparato viejo queda rechazado y deja de compartir ventas; en la
   app no se ve nada raro, así que hay que saberlo de antemano.
5. **Antes de instalar, respaldo.** Se exporta un `.tiketback` del aparato y se
   guarda fuera de él. Restaurar es la única salida si una migración sale mal.
6. **La clave de firma no se cambia.** Un APK firmado con otra clave no se
   instala encima: Android exige desinstalar, y eso borra las ventas.

## Versiones

### 1.1.0 (build 2) — **en desarrollo, no instalada**

Sube el esquema de datos a **v9** y el de sincronización a **5**: hay que
actualizar todos los aparatos a la vez, y como todavía ninguno lleva ventas de
verdad, este es el momento barato de hacerlo.

| Función | Detalle |
|---|---|
| Variantes de producto | Tamaños, cortes, con o sin papas: nombre y precio dentro del producto ([0039](decisiones/0039-variantes-de-producto-como-json.md)). Una por defecto (su precio es el base, preseleccionada al cobrar), orden fijado por el Gerente; selector al vender; ranking por variante |
| Reportes leen libros cerrados | Reportes, calendario y exportación cruzan todos los libros del rango ([0025](decisiones/0025-archivado-anual-rodante.md)). Antes el primer año cerrado habría salido "sin ventas" |
| Categorías desde Catálogo | Botón flotante que rota entre productos y categorías; sale de Configuración |
| Panel de agregar en teléfono | Abierto cubre todo el sitio del carrito; la barra de cobro no se mueve |
| Ventanas de venta | Configuración → Ventanas de venta: las dos, solo Rápida o solo Panel, por aparato |
| Moneda opcional | Símbolo y decimales en Configuración → Moneda, de presentación; colones enteros de fábrica ([0043](decisiones/0043-moneda-opcional.md)) |
| Texto neutro e iconos | Sin "soda" en pantalla; 23 iconos de categoría más (pizza, ropa, ferretería, farmacia…) con sus pistas |
| Costeo de recetas | Ventana 6, solo Gerente ([0040](decisiones/0040-costeo-de-recetas-como-modulo.md)): insumos, costos fijos, parámetros, receta por artículo (variantes incluidas), precio sugerido y margen real con volumen de ventas reales. Informa; "Aplicar" es explícito y por artículo. Esquema **v7** (cinco tablas sincronizables). **Compras de insumos** en el libro, con costo promedio ponderado de 90 días y totales por mes y trimestre ([0041](decisiones/0041-libro-de-compras-de-insumos.md)). **Impuestos**: régimen simplificado (factores sobre compras) o general (IVA por producto), comisión por medio de pago ponderada por el mix real ([0042](decisiones/0042-impuestos-flexibles-y-regimen.md)); esquema v8. **Food cost**, punto de equilibrio en dinero y escenarios ±20 %. **Tipo de negocio** producción / servicios (v9), con calculadora de amortización en Fijos |

Migraciones: `producto.variantes` (v5 → v6, `ALTER TABLE`), las cinco tablas del costeo (v6 → v7, vacías) y
`linea_venta.variante` en cada libro al adjuntarlo. Un `.tiketdata` de la
1.0.0 se importa sin cambios (probado con un catálogo en el formato de la
1.0.0, `test/fixtures/catalogo-1.0.0.tiketdata`).

### 1.0.0 (build 1) — 2026-08-10 · **publicada**

Primera instalación en producción. Aparato: teléfono de la soda
(`0600NX265V005032`, Android 12).

Antes de esta versión los tres aparatos llevaban la build del harness de
desarrollo, con un token permanente de control remoto. Esta es la primera sin
él.

Qué lleva:

| Función | Detalle |
|---|---|
| Venta rápida y panel de venta | Cobro por efectivo o SINPE, líneas libres, notas |
| Catálogo | Productos y categorías, con iconos por categoría y banco de imágenes |
| Reportes | Día, semana, mes y año; dos turnos de 12 h; exportación a PDF y CSV |
| Corte de caja | Apertura, medio día y cierre, con la caja esperada calculada |
| Sincronización | Par a par por la red local, ronda cada 15 s, LWW por `updated_at` |
| Respaldo | `.tiketback` cifrado y `.tiketdata` de catálogo, abribles desde el explorador |
| Roles | Gerente y Registradora, contraseñas de fábrica `Gen@1359#` y `1359` |

Esquema de datos: **v5** (`categoria`, `producto`, `libro_ventas`, `corte_caja`,
más `venta` y `linea_venta` en los libros anuales).
Esquema de sincronización: **4**.

Firmada con **clave propia**, creada para esta instalación (ver abajo). El
aparato entró en producción con la base vacía: se instaló antes de que hubiera
nada que perder, que era el único momento en que la decisión de la clave se podía
tomar sin coste.

Comprobado en el aparato tras instalar:

- `versionName=1.0.0`, `versionCode=1`.
- Firma `BF:A6:4B:7E:A7:06:C2:83…`, la del keystore propio y no la de depuración.
- `run-as` responde **"package not debuggable"**: es la prueba de que es un
  release de verdad y de que el token permanente de desarrollo —compilado bajo
  `!kReleaseMode`— no está dentro.

Lo que queda pendiente y afecta a la próxima actualización:

- Bluetooth como respaldo de la red, solo anotado.
- La app de escritorio no se ha usado de verdad: se probó su sincronización, no
  su día a día.

Sincronización verificada con tres aparatos —la PC, el P30 de la estación y el
P30 personal— en las tres formas que puede tomar la soda:

| Caso | Resultado |
|---|---|
| PC ↔ teléfono, uno a uno | catálogo, venta de ida y venta de vuelta |
| PC de Gerente, dos teléfonos de cajas | 11 ventas iguales en los tres, mismo conjunto |
| Teléfono de Gerente, PC y teléfono de cajas | igual, y el borrado propagado a las dos cajas |

En las dos últimas se comprobó además lo que con dos aparatos no existe: que lo
de una caja llegue a la **otra caja** y no solo al Gerente, que tres cobrando a la
vez converjan sin perder ni duplicar, y que descontinuar en el Gerente saque el
producto de las dos cartas sin tocar las ventas.

## La clave de firma

**Resuelta el 2026-08-10, antes de la primera instalación con datos.**

| | |
|---|---|
| Keystore | `~/.claves/vulptiketing/vulptiketing-release.p12` |
| Formato | PKCS12 (JKS está obsoleto y `keytool` lo avisa) |
| Alias | `vulptiketing` |
| Clave | RSA 4096, válida hasta **2056** |
| Huella SHA-256 | `BF:A6:4B:7E:A7:06:C2:83:76:CE:A4:07:31:59:C8:67:C1:94:2C:77:D0:69:50:A9:D8:77:17:BF:8C:DA:91:A3` |
| Contraseña | `~/.claves/vulptiketing/contrasena.txt`, permisos 600 |

**Hay que respaldar el keystore y su contraseña fuera de esta computadora.** Sin
ellos no se puede firmar una actualización, y sin firma que coincida Android exige
desinstalar — con las ventas dentro. Es el único archivo del proyecto que no se
puede reconstruir.

El keystore vive **fuera de la carpeta del proyecto** a propósito: un archivo de
firma dentro del código acaba en un zip, en un respaldo compartido o en un commit.
`android/key.properties` lo apunta y está en `.gitignore`.

Por qué no se dejó la de depuración: vive en `~/.android/debug.keystore`, se
regenera sola si se borra y es la misma que trae cualquier SDK de Android. Si
cambiaba, la única vía para actualizar era desinstalar.

Si `android/key.properties` no está, el release se firma con la de depuración y
Gradle lo avisa al compilar. Sirve para probar en otra máquina; **ese APK no se
instala encima del de producción**.
