# Corte vertical de F1: la lista cerrada (D-0111)

> Qué entra en F1 y qué no. Es la vara con la que se decide si una tarea de F1 suma al corte o se
> pospone a F2. Fuentes: [vision.md](vision.md), [supuestos.md](../detalle/supuestos.md),
> [catalogo-productos.md](catalogo-productos.md), [armado-y-trampas.md](armado-y-trampas.md),
> [roles-tripulacion.md](roles-tripulacion.md), `docs/decisiones/2026-10-04-*.md`.
> Los números viven en `company_tuning.gd` y en los `.tres`, no acá.

## 1. Qué es el corte

**Un día completo jugable, con arte gris**: llega el palet → se guarda en estantería → entran pedidos →
se arman las cajas → se despacha una salida → se entrega en Barrio Centro → se vuelve → se cierra el día
con ganancia. Dos jugadores como mínimo; uno solo también tiene que poder.

Regla de la fase (README de la expansión): **no se arranca F2 sin este corte cerrado y medido**, con
bots y benchmarks, no con playtesting.

## 2. Qué entra (lista cerrada)

| # | Ítem | Alcance exacto en F1 | Tareas |
|---|---|---|---|
| 1 | **Modo Empresa** | Modo nuevo al lado de Entrega y Endless (S1); esos dos no cambian | D-0214, D-2014 |
| 2 | **Estado de la empresa** | `CompanyState`, `company_tuning.gd`, plata inicial 500, reputación 50, un slot de guardado | D-0202, D-0206 |
| 3 | **Reloj del día** | 08:00 a 20:00, 1 h = 90 s reales, el cierre espera a la salida en curso | D-0203, D-0219, D-0319 |
| 4 | **Galpón por defecto** | Layout fijo que ya funciona sin construir nada: dársena, recepción, estantes, armado, despacho (el modo construcción es F1 **ampliación**, no núcleo) | D-0620, D-0911, D-0918 |
| 5 | **Un proveedor** | 1 camión por día a las 08:30 con lo pedido el día anterior; espera 3 h de juego | D-0218, D-0601, D-0602 |
| 6 | **Productos** | Los 10 de `data/contents/` (jarrón, lámpara, torre de vidrio, torta, masa madre, bidón, gallina, cachorro, fuegos artificiales, jaula del mapache), cada uno con su trampa | D-0204, D-0116 |
| 7 | **Stock** | Palet físico de hasta 24 unidades, descarga con zorra o autoelevador, estantes con hueco etiquetado, picking a mano | D-0604 a D-0609, D-0611 |
| 8 | **Pedidos** | 6 + 2 por jugador por día (tope 16), 1 a 3 productos, ventana de 4 h de juego, tablero en el galpón | D-0210, D-0801 a D-0804, D-0807 |
| 9 | **Armado** | Cajas S, M, L y XL en grilla de celdas de 0,2 m, relleno, cinta, etiqueta, calidad `Q` y trampa según [armado-y-trampas.md](armado-y-trampas.md); sellos solo los que pide el pedido | D-0212, D-0217, D-0701 a D-0712 |
| 10 | **Despacho y carga** | Dejar la caja armada en la zona de salida la asocia a la salida; se carga la camioneta actual | D-0716, D-0717, D-0809 |
| 11 | **Camioneta actual** | La de hoy, sin cambios de manejo; nada de flota nueva | D-0207 |
| 12 | **Mapa** | Mundo continuo con solo **Barrio Centro** (gris) y **Campo** (la ruta de hoy como zona) abiertos; portón del galpón como inicio de la salida; GPS a la próxima parada; 3 a 6 casas por salida | D-0301 a D-0309, D-0311, D-0314, D-0315 |
| 13 | **Entrega** | `DeliveryHouse` y puerta del cliente como hoy, que además compara contenido contra el pedido | D-0213, D-0340, D-0815 |
| 14 | **Cierre del día** | Cobro, alquiler (100), penalidades, resumen, guardado | D-0320, D-0501 a D-0510, D-0508 |
| 15 | **Roles de la tripulación** | Sin clases fijas; la regla de 2 min sin caja ni volante y la camioneta que sale con pocas cajas con 1 jugador | D-0110, D-0316 |
| 16 | **Red** | Host autoritativo, eventos de negocio por RPC confiable, join tardío, `PROTOCOL_VERSION` nuevo | D-2001 a D-2008 |
| 17 | **Calidad** | `bot_company_day`, `bench_company`, sin fugas, QA de red par y trío | D-2011 a D-2013, D-2016, D-2017 |

## 3. Qué NO entra (se posterga con motivo)

| Queda fuera | Va a | Por qué |
|---|---|---|
| Empleados y automatización (grupos 10 y 11) | F2 | En F1 nadie trabaja solo; el galpón se congela si todos salen (S4) |
| Modo construcción del galpón (D-0901 a D-0910) | F1 ampliación / F2 | El layout por defecto alcanza para cerrar el corte |
| Hitos, licencias y desbloqueos (grupo 04) | F2 | En F1 Centro y Campo están abiertos desde el día 1; el sistema de hitos solo se prepara (D-0306) |
| Suburbio, Puerto, Islas, Montaña, Nieve y Volcán | F2 a F4 | Una zona nueva sin cerrar el corte multiplica el riesgo |
| Bici, carrito, lancha, avioneta y 4x4 | F2 a F4 | Una sola camioneta; `VehicleDefinition` existe pero solo con ella |
| Heladera, frío y calor simulados (D-0616, D-0617) | F2 | El campo `temperatura` existe y se ignora (catálogo de productos) |
| Más de 10 productos y más de 1 proveedor | F2 | Con 10 hay trampa de sobra para validar el bucle |
| Préstamos, seguros, impuestos, mercado | F2 | Economía mínima: compra, venta, alquiler, penalidades |
| Arte final, audio nuevo y VFX del grupo 19 | F5 | Gris permitido (§5) |
| Pantallas de carga entre zonas | nunca | Mapa continuo: no hay (decisión del mapa continuo) |

## 4. Criterio de cierre (lo mide el bot, no una persona)

El corte está **cerrado** cuando `tools/bot_company_day.gd` (D-2016), con **2 jugadores simulados**, en
headless:

1. recibe el palet del proveedor y lo guarda en estantes;
2. toma pedidos del tablero y **arma 6 cajas** (calidad `Q` calculada, trampa asignada);
3. despacha **una salida** a Barrio Centro con las cajas armadas, entrega las casas y **vuelve** al galpón;
4. cierra el día con **ganancia > 0** (ingresos − costos − alquiler);
5. termina sin ningún `ERROR` ni `SCRIPT ERROR` en el log.

Y además, medido en la misma corrida:

| Chequeo | Umbral | Tarea que lo mide |
|---|---|---|
| `bench_company`: FPS, draw calls, cuerpos físicos, nodos | presupuesto de D-2012 (galpón por defecto ≥ 90 FPS, ≤ 900 draw calls, ≤ 400 cuerpos, ≤ 6000 nodos) | D-2011, D-2012 |
| Sin fugas | huérfanos 0 y objetos que crecen < 2 % entre el día 2 y el 10 | D-2013 |
| Un solo jugador completa el día | el mismo bot con 1 jugador cierra con ganancia > 0 | D-2016 |
| Par y trío en red | `net_pair` y `net_trio` en modo Empresa sin desincronización | D-2017 |
| Ningún frame > 50 ms al manejar de Centro a Campo por la carga de celdas | `test_world_cells_company` | D-0303 |
| Tests viejos de Entrega y Endless siguen verdes | CI completo | — |

Mientras alguna tarea del §2 no exista, el bot la **simula con un stub marcado** y el hueco queda como
issue; el corte no se declara cerrado con stubs.

## 5. Arte gris permitido

Todo el corte puede ir con **placeholders por código** (mallas primitivas, `CSGBox3D` horneado o
`assets/models/cargo/sm_cargo_box_cube.glb` escalado), sin Blender ni ComfyUI. Lo que no es gris: los 10
modelos de producto, la camioneta, las casas y la puerta del cliente, que **ya existen** y se
reutilizan. Cada placeholder lleva su archivo en `arte-pendiente/<ID>.md` (modelo, medidas, pivote, uso).

## 6. Orden dentro del corte

El de [detalle/README.md](../detalle/README.md): decisiones y diseño → esqueleto de datos y red → galpón
jugable → stock → pedidos → armado → economía → salida y vuelta → cierre con el bot. Un PR por tarea,
sin esperar el corte para mezclar: cada pieza trae su test con prefijo `test_company_` (filtro
`tools/run-tests.sh company`).

## 7. Qué lo rompería (para vigilar)

- Si el armado en grilla es incómodo con mando, el día se alarga: D-0720 (tutorial) y el balance de
  D-0541 lo miden; no se agranda el corte para arreglarlo.
- Si el galpón + Centro pasan el presupuesto de D-2012, se recorta decorado de Centro, no el bucle.
- Si D-0214 (escena del mundo) tarda, las tareas de stock y armado se prueban en la escena del depósito
  actual, que ya existe: el corte no se bloquea por la escena.
