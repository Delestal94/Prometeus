# Lista de 30 hitos del modo Empresa (D-0118)

> Qué se logra, qué se gana y cuándo. Es la fuente de los `.tres` de hitos (D-0404, `data/milestones/`) y de
> los tipos que implementan D-0402 y D-0403. Cada distrito cerrado tiene su hito de desbloqueo; los cinco
> primeros enseñan el bucle (D-0412). Fuentes: [grupo 04](../04-progresion-e-hitos.md),
> [distritos.md](distritos.md), [mapa.md](mapa.md), [flota.md](flota.md), [economia.md](economia.md),
> [supuestos.md](../detalle/supuestos.md). Los números viven en los `.tres` y en `company_tuning.gd`, no acá.
> No se usan las tareas tachadas del grupo 04: secretos (D-0421), de tripulación (D-0422), contratos y VIP
> (D-0424, D-0425) ni prestigio (D-0433).

## Reglas de lectura

- **Entrega** = pedido entregado que **pagó más de 0**. La tardanza cuenta (paga −25 %); la caja equivocada o
  rota entera no. Cada pedido suma una vez, sin importar cuántos productos tenga.
- **Condiciones** de un hito: todas deben cumplirse (Y). **`requires`**: otros hitos que ya tienen que estar
  hechos. Un hito cumplido no se pierde (como un bloqueo abierto, mapa continuo punto 7): ni la quiebra
  (D-0510) ni bajar la reputación lo deshacen.
- **Día** = día de cierre en que se espera cumplirlo con juego correcto, para **1 / 2 / 4 jugadores**. Hasta el
  día 20 sale de la curva de [economia.md](economia.md); lo que lleva `~` es **extrapolado** más allá (el
  modelo del §2 sigue valiendo, la plata de cada paso la pongo yo). D-0441 lo mide con bot y lo corrige.
- El `#` ordena por el día de 1 jugador. Los **ids** de `deliveries_25`, `reputation_60` y `deliveries_50` son
  los que ya guardan `data/gates/` y flota.md: no cambian.

## La lista

| # | id | Nombre | Condición (D-0402) | Recompensa (D-0403) | Día 1 / 2 / 4 | Enseña |
|---|---|---|---|---|---|---|
| 1 | `first_delivery` | Primera entrega | `deliveries_total` ≥ 1 | `shop_item` `upgrades` (tienda de mejoras: mejora 1, 450) | 1 / 1 / 1 | El bucle corto: una caja armada sale del galpón, se entrega y se vuelve |
| 2 | `centro_5` | Conocido del barrio | `deliveries_district` `centro` ≥ 5 | `product` lote Centro frágiles | 2 / 1 / 1 | Una salida con varias paradas: leer la dirección, seguir el GPS, entrar en la ventana de 4 h |
| 3 | `first_earnings` | Primer cierre redondo | `money_earned_total` ≥ 2 000 | `money` +150 | 3 / 2 / 2 | El cierre del día: cobros, alquiler (100) y pedir stock para mañana |
| 4 | `clean_hands` | Manos limpias | `no_breakage_days` 2 días, ≥ 3 entregas por día | `cosmetic` `paint_cream` | 3 / 3 / 3 | Armar bien: caja del tamaño justo y relleno |
| 5 | `reputation_55` | Buena fama | `reputation` ≥ 55 | `vehicle` `bike` | 3 / 2 / 2 | La reputación sube con entregas sanas y a tiempo y baja con roturas y errores |
| 6 | `reputation_60` | Se acabó la obra | `reputation` ≥ 60 (o pagar la obra, 150) | `district` `campo`; `product` lote Campo | 4 / 3 / 2 | — |
| 7 | `deliveries_25` | Barrio vecino | `deliveries_total` ≥ 25 | `district` `suburbio`; `vehicle` `van_agile`, `cart`; `shop_item` `permit_suburbio` (1 200); `product` lote Suburbio; `money` +300 | 6 / 4 / 3 | — |
| 8 | `first_employee` | Hora de contratar | `money_earned_total` ≥ 5 000 | `shop_item` `hiring_agency` (D-0413) | 6 / 4 / 3 | — |
| 9 | `first_machine` | Primera máquina | `employees` ≥ 1 | `shop_item` `machine_shop`; `machine` `tape_sealer`, `labeler`, `conveyor` (D-0414, D-1118) | 7 / 5 / 4 | — |
| 10 | `clean_week` | Semana impecable | `no_breakage_days` 5 días, ≥ 4 entregas por día | `product` lote fríos; `money` +300 | 8 / 8 / 8 | — |
| 11 | `shed_stage_2` | Galpón mediano | `money_earned_total` ≥ 10 000 | `shop_item` `shed_stage_2` (800) | 9 / 7 / 5 | — |
| 12 | `deliveries_50` | Habilitación del Puerto | `deliveries_total` ≥ 50 | `district` `puerto`; `shop_item` `license_nautical`; `vehicle` `van_vintage`; `product` lote Puerto; `money` +600 (D-0415) | 10 / 7 / 5 | — |
| 13 | `reputation_70` | Marca conocida | `reputation` ≥ 70 | `supplier` `supplier_express`; `cosmetic` `logo_pack` | 10 / 7 / 5 | — |
| 14 | `employees_3` | Equipo de galpón | `employees` ≥ 3 | `shop_item` `shed_stage_3` (2 000) | 15 / 11 / 9 | — |
| 15 | `centro_40` | Rey del Centro | `deliveries_district` `centro` ≥ 40 | `vehicle` `bike_tandem`, `bike_trailer` | 16 / 12 / 8 | — |
| 16 | `campo_25` | Camino de ripio | `deliveries_district` `campo` ≥ 25 | `vehicle` `offroad`; `shop_item` `license_4x4` (reescribe D-0416) | 17 / 14 / 10 | — |
| 17 | `clean_fortnight` | Diez días sin roturas | `no_breakage_days` 10 días, ≥ 5 entregas por día | `cosmetic` `livery_stripes`; `money` +500 | 17 / 18 / 19 | — |
| 18 | `puerto_12` | Zarpar | `deliveries_district` `puerto` ≥ 12 | `district` `islas`; `vehicle` `boat`; `supplier` `supplier_islas`; `product` lote Islas; `money` +1 200 | 18 / 13 / 10 | — |
| 19 | `suburbio_20` | Vecino de confianza | `deliveries_district` `suburbio` ≥ 20 | `shop_item` `work_gloves`, `grip_boots` (D-0426) | 18 / 13 / 10 | — |
| 20 | `deliveries_100` | Cien paquetes | `deliveries_total` ≥ 100 | `district` `montana`; `vehicle` `plane`; `shop_item` `license_flight`, `aerodrome`; `supplier` `supplier_montana`; `product` lote Montaña; `money` +1 200 | 18 / 14 / 10 | — |
| 21 | `money_30000` | Empresa mediana | `money_earned_total` ≥ 30 000 | `supplier` `supplier_wholesale`; `cosmetic` `uniform_blue` | ~24 / ~19 / ~13 | — |
| 22 | `machines_3` | Línea de armado | `machines` ≥ 3 tipos | `machine` `box_maker`, `padding_dispenser`, `scale` | ~28 / ~21 / ~14 | — |
| 23 | `employees_6` | Plantel completo | `employees` ≥ 6 | `cosmetic` `uniform_orange` | ~40 / ~28 / ~20 | — |
| 24 | `deliveries_250` | Logística seria | `deliveries_total` ≥ 250 | `cosmetic` `paint_gold` | ~41 / ~32 / ~23 | — |
| 25 | `money_60000` | Centro logístico | `money_earned_total` ≥ 60 000 | `shop_item` `shed_stage_4` (5 000); `cosmetic` `livery_premium` | ~45 / ~35 / ~25 | — |
| 26 | `montana_8` | Cumbre a la vista | `deliveries_district` `montana` ≥ 8 | `district` `nieve`; `shop_item` `chains`, `winter_coat`, `cooler`, `license_high_mountain`; `product` lote Nieve; `money` +1 500 (D-0417) | ~68 / ~56 / ~41 | — |
| 27 | `machines_6` | Galpón en marcha | `machines` ≥ 6 tipos | `machine` `sorter`, `picking_robot`, `agv`; `cosmetic` `uniform_overalls` | ~70 / ~50 / ~32 | — |
| 28 | `volcano_permit` | Permiso volcánico | `reputation` ≥ 80 **y** `deliveries_district` `nieve` ≥ 8 | `district` `volcan`; `shop_item` `thermal_suit`, `thermal_boxes`, `license_volcanic`; `product` lote Volcán; `money` +1 500 (D-0418) | ~77 / ~64 / ~46 | — |
| 29 | `volcan_6` | Domador del volcán | `deliveries_district` `volcan` ≥ 6 | `cosmetic` `volcano_trophy`; `money` +1 500 | ~85 / ~70 / ~51 | — |
| 30 | `national_logistics` | Logística Nacional | `reputation` ≥ 90 **y** `deliveries_total` ≥ 400; `requires` los 7 hitos de distrito (6, 7, 12, 18, 20, 26, 28) y `volcan_6` | `cosmetic` `paint_national`; cierra la campaña (D-0438) | ~87 / ~72 / ~53 | — |

Los hitos 1 a 5 son de cinco tipos de condición distintos: sirven también de muestra para el test de D-0401. Un
bot solo los cumple el día 3 (D-0412 pide antes del 5). Con 4 jugadores caen el día 1 y 2: aprenden en paralelo.

**Lotes de producto** (ids de [catalogo-productos.md](catalogo-productos.md); son los 30 nuevos, ninguno repetido):

| Lote | Hito | Productos |
|---|---|---|
| Centro frágiles | 2 | `glass_mirror`, `ceramic_teapot`, `picture_frame` |
| Campo | 6 | `beehive`, `rooster_crate` |
| Suburbio | 7 | `flat_tv`, `crystal_chandelier`, `birthday_cake`, `bicycle`, `mattress`, `potted_plant`, `golf_clubs` |
| Fríos | 10 | `ice_cream_tub`, `flower_bouquet`, `cheese_wheel` |
| Puerto | 12 | `wine_bottles`, `fresh_fish`, `fish_tank` |
| Islas | 18 | `aquarium_lamp`, `seashell_lamp`, `frozen_lobster`, `surfboard` |
| Montaña | 20 | `telescope`, `medicine_vials` |
| Nieve | 26 | `snow_globe`, `hot_stew_pot`, `thermal_soup`, `ski_pair` |
| Volcán | 28 | `lava_cake`, `volcanic_rock_crate` |

Los productos fríos y calientes dependen de D-0616 (heladera); sin ella la temperatura se ignora, como en F1.
Las máquinas se reparten así: el hito 9 ofrece 3 (`tape_sealer`, `labeler`, `conveyor`), el 22 otras 3 y el 27 las
últimas 3, para que `machines` ≥ 6 tipos se pueda comprar antes de pedirlo.

## Cada distrito y su hito

| Distrito | Hito de desbloqueo | Bloqueo ([mapa.md](mapa.md)) | Además del hito | Hito (1 / 2 / 4) | Abre (1 / 2 / 4) |
|---|---|---|---|---|---|
| `parque_industrial`, `centro` | — (abiertos) | — | — | — | 1 / 1 / 1 |
| `suburbio` | 7 `deliveries_25` | `gate_suburbio` (barrera) | `permit_suburbio`, 1 200 | 6 / 4 / 3 | 6 / 5 / 5 |
| `campo` | 6 `reputation_60` | `gate_campo_obra` (calle cortada) | o pagar la obra, 150 | 4 / 3 / 2 | 4 / 3 / 2 |
| `puerto` | 12 `deliveries_50` | `gate_puerto` (barrera portuaria) | `license_nautical` | 10 / 7 / 5 | 10 / 7 / 5 |
| `islas` | 18 `puerto_12` | `gate_islas_agua` (agua) | lancha `boat`, 5 000 | 18 / 13 / 10 | ~18 / ~13 / ~10 |
| `montana` | 20 `deliveries_100` | `gate_montana_altura` (altura) | avioneta `plane` 12 000, `license_flight`, `aerodrome` | 18 / 14 / 10 | ~60 / ~49 / ~36 |
| `nieve` | 26 `montana_8` | `gate_nieve_equipo` (equipo) | `chains`, `winter_coat`, `license_high_mountain` | ~68 / ~56 / ~41 | igual |
| `volcan` | 28 `volcano_permit` | `gate_volcan_equipo` (equipo) | `thermal_suit`, `thermal_boxes`, `license_volcanic` | ~77 / ~64 / ~46 | igual |

- Las ramas son **dos y paralelas**: agua (Puerto → Islas) y aire (Montaña → Nieve → Volcán). Montaña no pide
  Islas: la avioneta cruza sola (`gate_montana_altura`). Nieve pide haber entregado en Montaña y Volcán en
  Nieve, para que nadie llegue al final sin haber pasado por las zonas difíciles.
- **Suburbio y Campo** guardan el hito en el bloqueo (`deliveries_25`, `reputation_60`).
  **Puerto, Islas, Montaña, Nieve y Volcán no lo guardan**: sus bloqueos piden la licencia, la lancha, la avioneta
  o el equipo, y eso solo se ofrece en la tienda después del hito (Puerto, desde D-0124). El hito queda hecho aunque el bloqueo no lo nombre.
- "Abre" es el día en que el bloqueo se puede cruzar. En Montaña, Nieve y Volcán lo marca la plata: la avioneta
  sola son 12 000 y un solitario junta ~350 por día para llaves del mapa.

## Las licencias

Diseño de D-0124. Una licencia es un **papel de la empresa**: se ofrece con un hito, se compra una vez en la
tienda y desde ahí abre un bloqueo del mapa o la compra de un vehículo. No hay examen, ni vencimiento, ni
renovación (D-0537 está recortada, [critica-alcance.md](critica-alcance.md) R3).

### Las cinco

| Licencia | Se ofrece con (día 1 / 2 / 4 jug.) | Precio | Qué abre | Qué no abre |
|---|---|---|---|---|
| `license_nautical` | 12 `deliveries_50` (10 / 7 / 5) | **650** | cruzar `gate_puerto` y comprar `boat` | la lancha misma (5 000) ni `gate_islas_agua` |
| `license_4x4` | 16 `campo_25` (17 / 14 / 10) | **600** | comprar `offroad` | ningún bloqueo: la 4x4 no abre zonas, entrega adentro |
| `license_flight` | 20 `deliveries_100` (18 / 14 / 10) | **1 000** | comprar `plane` | el aeródromo (`aerodrome`, 1 500) se compra aparte y lo pide `gate_montana_altura`, no la compra de la avioneta |
| `license_high_mountain` | 26 `montana_8` | **1 000** | cruzar `gate_nieve_equipo`, junto a `chains` y `winter_coat` | — |
| `license_volcanic` | 28 `volcano_permit` | **1 000** | cruzar `gate_volcan_equipo`, junto a `thermal_suit` y `thermal_boxes` | — |

Total de la campaña: **4 250**, menos que la lancha sola.

### Cómo se obtienen

1. **El hito la ofrece.** La recompensa `shop_item` del hito pone el ítem `license_*` en la tienda (D-0511).
   Antes del hito el ítem no aparece: no hay "comprarla sin el hito" (es el test de D-0407).
2. **Se compra en la tienda del cierre**, como cualquier ítem: cobra el precio con motivo `shop` y queda en el
   resumen del día. Quién puede gastar lo decide D-0518, igual que para el resto de la tienda.
3. **Es de la empresa, no de un jugador.** Maneja el que quiera, entre a la sala cuando entre, y los empleados
   que manejan (grupo 10) también. Un coop de 1-8 no puede tener a uno solo "habilitado" para la lancha: si se
   desconecta, el resto queda varado.
4. **No se pierde nunca.** Ni con la quiebra (D-0510 solo baja los pedidos), ni al vender el vehículo, ni al
   cambiar de base. Se guarda en el save de la empresa.
5. **Lo que la pide lo dice.** En el bloqueo, el aviso de siempre (`WORLD_GATE_NEEDS_EQUIPMENT` con el nombre
   de la licencia); en la tienda, el vehículo sin licencia aparece gris con "Necesita: licencia …" en lugar de
   desaparecer, así se sabe qué falta. El aviso muestra el nombre traducido (`WORLD_SHOP_LICENSE_*`), nunca la
   clave `license_*`.
6. **Primer vuelo guiado** (D-1418): el primer despegue después de comprar `plane` es un tutorial de radio de
   la Jefa ([narrativa-empresa.md](narrativa-empresa.md)), no un examen. No se puede reprobar y se puede saltear.

### Cómo se guarda y se pide (para D-0407)

- **Una licencia es una clave más de `CompanyState.equipment`**, con el prefijo `license_`. No hace falta campo
  nuevo en el save, en el snapshot ni en `CompanyNet`: `equipment` ya viaja y se guarda.
- **`ShopItem` suma el tipo `license`** (en `KINDS`), que entrega su `grant_key` a `equipment` como `machine`,
  pero la tienda lo muestra en su propio grupo ("Licencias") con el texto `WORLD_SHOP_LICENSE_*`.
- **`ShopItem.requires` también vale para `vehicle`**: `vehicle_boat` pide `license_nautical`, `vehicle_offroad`
  `license_4x4` y `vehicle_plane` `license_flight`. Hoy `CompanyShop.check()` solo mira `requires` en `machine`:
  D-0407 lo aplica también a `vehicle` y `license`. Un solo `requires` alcanza: ningún vehículo pide dos cosas
  para comprarse (el aeródromo lo pide el bloqueo).
- **`CompanyShop.owns()` reconoce `license`** (hoy solo `machine` y `expansion`), así no se compra dos veces.
- **Los bloqueos la piden con `GateRequirement.equipment`**, que ya existe: `gate_puerto` cambia su `milestone`
  `deliveries_50` por `equipment` `license_nautical` (si pidiera los dos, `missing_key` mira el equipo primero y
  antes del hito diría "falta la licencia" cuando todavía no se vende), `gate_nieve_equipo` suma
  `license_high_mountain`, `gate_volcan_equipo` `license_volcanic` y `gate_montana_altura` `aerodrome`.
- El aviso del bloqueo pasa como argumento el nombre traducido del ítem (hoy `missing_key` pasa `str(item)`): lo
  traduce quien lo muestra, con el `display_key` del `ShopItem` cuyo `grant_key` es esa clave.
- Las cinco van en `data/shop/license_*.tres` con `enabled = false` hasta F2, como los vehículos de hoy.

### Por qué estos números

- **Náutica 650**: 4 jugadores ganan el hito el día 5 y cierran ese día con 790 ([economia.md](economia.md) §5),
  después de pagar Suburbio. Con 650 les quedan 140, arriba del piso de 100 de caja de economia.md §3, aun sin
  contar el premio de 600 del hito; con 1 000 no llegan. Así los tres "Abre" (10 / 7 / 5) quedan como estaban.
- **4x4 600**: no abre ninguna zona, solo suma un vehículo de 2 500. Un cuarto del vehículo es lo que se paga
  por algo que no da nada por sí solo.
- **Vuelo, alta montaña y volcánica 1 000**: son los que se usaron para estimar los días de Montaña, Nieve y
  Volcán; ahí manda la avioneta (12 000) y el equipo, y la licencia no mueve el día de apertura más que ~3 días
  de un jugador solo.

## Plata que entra por los hitos

Hoy los hitos no dan plata. Esto agrega 10 líneas que entran **una sola vez**, con el motivo "Hito: <nombre>" en
el resumen del cierre (D-0508.3, D-1905). Regla de tamaño: **un premio no pasa de 3 días de ganancia neta de un
jugador solo en ese momento**, así nunca reemplaza jugar.

| Hito | Premio | Días de ganancia (1 jug.) |
|---|---|---|
| 3 `first_earnings` | 150 | ~0,7 |
| 7 `deliveries_25` | 300 | ~0,8 |
| 10 `clean_week` | 300 | ~0,8 |
| 12 `deliveries_50` | 600 | ~1,5 |
| 17 `clean_fortnight` | 500 | ~1,2 |
| 18 `puerto_12` | 1 200 | ~2,6 |
| 20 `deliveries_100` | 1 200 | ~2,6 |
| 26 `montana_8` | 1 500 | ~3,0 |
| 28 `volcano_permit` | 1 500 | ~2,8 |
| 29 `volcan_6` | 1 500 | ~2,8 |
| **Total** | **8 750** | |

Antes/después de la curva de [economia.md](economia.md): lo único que baja es el comienzo. Con Campo cerrado
hasta el hito 6, el envío medio de los primeros días es 40 y no 50: el margen por pedido cobrado baja ~10 y el
saldo del día 1 de 1 jugador pasa de 206 a ~175 (sigue sobre la reserva de 100). El resto de la curva se mantiene:
el permiso de Suburbio (1 200) está donde ya lo ponía la curva (día 6 de 1 jugador, día 5 de 2 y 4).

## Tipos usados

**Condiciones (D-0402).** Los siete, todos usados. Los hitos 28 y 30 combinan dos condiciones.

| Tipo | Parámetros | Qué cuenta | Cuándo se evalúa | Filas |
|---|---|---|---|---|
| `deliveries_total` | `amount` | entregas (ver arriba), todas las zonas | al instante, en el host | 1, 7, 12, 20, 24, 30 |
| `deliveries_district` | `zone`, `amount` | entregas en esa zona | al instante, en el host | 2, 15, 16, 18, 19, 26, 28, 29 |
| `money_earned_total` | `amount` | suma de cobros de pedidos del libro de caja; **no** premios de hitos, ventas de objetos ni devoluciones | al instante, en el host | 3, 8, 11, 21, 25 |
| `reputation` | `amount` (la global) | reputación de la empresa al cierre ≥ valor | al cierre | 5, 6, 13, 28, 30 |
| `no_breakage_days` | `days`, `min_deliveries` | días de cierre seguidos con 0 productos rotos y al menos `min_deliveries` entregas; un día con rotura o con menos entregas corta la racha | al cierre | 4, 10, 17 |
| `employees` | `amount` | empleados contratados al cierre | al cierre | 9, 14, 23 |
| `machines` | `amount` | **tipos distintos** de máquina colocados y funcionando al cierre | al cierre | 22, 27 |

Cada tipo tiene que poder decir su progreso (actual y objetivo) para el tablero de D-0410.

**Recompensas (D-0403).** Los siete de la tarea, todos usados, **más uno que hace falta**:

| Tipo | Campos | Efecto | Filas |
|---|---|---|---|
| `district` | `zone` | la zona entra al generador de pedidos cuando su bloqueo esté abierto; si el bloqueo nombra el hito, lo abre | 6, 7, 12, 18, 20, 26, 28 |
| `vehicle` | `ids` | el vehículo se ofrece en la tienda (comprarlo pide plata y, si corresponde, licencia) | 5, 7, 12, 15, 16, 18, 20 |
| `machine` | `ids` | se ofrece en la tienda de automatización | 9, 22, 27 |
| `product` | `ids` | entra al catálogo y a los pedidos (D-0434) | 2, 6, 7, 10, 12, 18, 20, 26, 28 |
| `supplier` | `id` | se puede contratar ese proveedor (D-0435) | 13, 18, 20, 21 |
| `money` | `amount`, `reason_key` | entra a la caja con su línea en el cierre | 3, 7, 10, 12, 17, 18, 20, 26, 28, 29 |
| `cosmetic` | `ids` | se desbloquea para la flota o el uniforme (D-0437: son 10) | 4, 13, 17, 21, 23, 24, 25, 27, 29, 30 |
| `shop_item` (**nuevo**) | `ids` | habilita en la tienda algo que no es vehículo ni máquina: licencias, equipo, ampliaciones del galpón, mejoras, agencia de empleo, aeródromo | 1, 7, 8, 9, 11, 12, 14, 16, 19, 20, 25, 26, 28 |

`shop_item` es la única adición a D-0403: sin él, licencias (D-0407), equipo de tripulación (D-0426), tamaños de
galpón (D-0436) y la contratación (D-0413) no tienen dónde colgar.

## Formato sugerido del `.tres` (D-0404)

Un recurso `MilestoneDefinition` por hito en `data/milestones/<id>.tres` (el nombre del archivo es el id).
Campos, sin código:

- `id`, `order` (1 a 30, el `#` de la tabla)
- `name_key`, `description_key`: claves de `tr()`
- `conditions`: lista de condiciones, todas deben cumplirse. Cada una: `kind` (uno de los siete), `amount`,
  `zone` (solo `deliveries_district`), `min_deliveries` (solo `no_breakage_days`)
- `requires`: ids de otros hitos
- `rewards`: lista de recompensas. Cada una: `kind` (uno de los ocho), `ids`, `amount`, `reason_key` (solo `money`)
- `teaches_key`: texto del consejo del bucle (con contenido solo del 1 al 5; D-0130 los afina)
- `expected_day`: tres números (1, 2 y 4 jugadores), solo para D-0441 y el test; no se usan en juego
- `ends_campaign`: verdadero solo en `national_logistics` (dispara D-0438)
- `rank`: rango de la empresa que empieza con el hito (D-0423); vacío si no cambia

`test_milestones_data` debería comprobar: 30 archivos con ids únicos; cada zona cerrada en exactamente un
`district`; cada id de recompensa existe en su catálogo; `requires` sin ciclos; hitos 1 a 5 con `teaches_key`;
los ids que nombran los `data/gates/` existen; ningún premio de plata pasa del tope; cada recompensa que ofrece
algo sale de un hito cumplible por un jugador solo (D-0442).

## Contramedidas (exploits considerados)

Siguiendo [economia-y-contramedidas.md](../../economia-y-contramedidas.md):

| Exploit | Cómo se cierra |
|---|---|
| Farmear la ruta fácil para llegar a los hitos de entregas | El techo de pedidos por día (`min(16, 6 + 2 × jugadores)`) manda: no hay forma de entregar más rápido. Solo cuentan las entregas cobradas. Los hitos de las zonas lejanas piden entregas **en la zona anterior**, y `volcano_permit` pide reputación 80 **y** entregas en Nieve: la reputación sola, juntada en Centro, no alcanza. |
| Suicidar la corrida o quebrar para recomprar | Los hitos son permanentes y la quiebra no los borra (D-0510 no reinicia). Cada premio de plata entra una sola vez. |
| Votar en bloque o comprar solo desde un cliente | Un hito solo **ofrece**; comprar sigue siendo del host (D-0518). El progreso lo cuenta el host y los clientes lo ven replicado (D-0420). |
| Contratar o comprar y vender para cumplir `employees` o `machines` | Cuenta lo que está contratado, colocado y funcionando **al cierre**; el empleado cobra sueldo diario; `machines` cuenta tipos distintos (no tramos de cinta repetidos). Revender devuelve una parte (D-0920), así que el atajo cuesta. |
| No repartir nada para "no romper" (`no_breakage_days`) | Cada día de la racha pide un mínimo de entregas. |
| Inflar `money_earned_total` | Solo cuentan cobros de pedidos: ni premios de hitos ni ventas de objetos. |
| Saltear la reputación de Campo pagando la obra | Cuesta 150 y completa **solo** `reputation_60`: no abre nada más. |
| Cadena de premios de plata | Tope de 3 días de ganancia solitaria por premio y 8 750 en total. |
| Proveedor que se come el margen | Sugerencia para D-0435: ningún proveedor baja el costo de compra más de 10 % (el margen medio de un pedido es ≈ 102). |

## Decisiones

- **Decisión: una entrega es un pedido cobrado (paga > 0)** porque contar los cerrados premia entregar basura:
  una caja equivocada paga 0 y ya costó la mercadería.
- **Decisión: se mantienen "25 entregas" para Suburbio y "reputación 60" para Campo** porque con la curva de
  D-0117 un jugador solo llega a 25 entregas cobradas el día 6, justo donde la curva pone el segundo distrito.
- **Decisión: Suburbio pide además el permiso `permit_suburbio` (1 200)** porque la curva de economia.md §5
  **ya paga** esos 1 200 el día 5 o 6 (el saldo cae a 104, 290 y 790). Sin ese pago, 4 jugadores abrirían el
  distrito el día 3, un día antes de lo previsto, y la plata sobraría antes de tiempo. Hace falta que
  `gate_suburbio` lo pida además del hito, como `gate_puerto` pide la licencia.
- **Decisión: en Empresa F2 Campo arranca cerrado (reputación 60)** y F1 lo deja abierto, porque el corte vertical
  juega con Centro y Campo abiertos para cerrarse sin hitos. Cuesta ~10 de margen por pedido los primeros días.
- **Decisión: Campo abre antes que Suburbio** (día 4 contra 6 de 1 jugador) aunque la tabla los numere al revés,
  porque reputación 60 son unas 15 entregas cobradas y 25 son más.
- **Decisión: las zonas lejanas piden pocas entregas en la zona anterior (12 / 8 / 8 / 6)** porque los pedidos se
  reparten entre las zonas abiertas y cada una recibe una fracción: 10 en Volcán ya serían unos 12 días.
- **Decisión: dos ramas paralelas (agua y aire)** porque el mapa deja entrar a Montaña con la avioneta sin pasar
  por Islas; así hay que elegir en qué ahorrar.
- **Decisión: el hito no va en los bloqueos de Islas, Montaña, Nieve y Volcán** porque ya piden la lancha, la
  avioneta o el equipo, que solo se ofrecen después del hito: menos campos y un solo lugar donde se rompe.
- **Decisión: se suma el tipo de recompensa `shop_item`** porque licencias, equipo, ampliaciones y contratación
  no son ninguno de los siete tipos de D-0403.
- **Decisión: "Primer empleado" (D-0413) se gana por plata (5 000 cobrados) y "Primera máquina" (D-0414) por tener
  un empleado** porque si el hito exigiera tener el empleado, no habría forma de contratarlo.
- **Decisión: D-0416 se reescribe como `campo_25` (25 entregas en Campo) y `license_4x4`** porque con el mapa
  continuo Montaña se abre con la avioneta; la 4x4 es para entregar adentro. Bajé de 50 a 25 entregas porque Campo
  recibe solo una fracción de los pedidos.
- **Decisión: D-0417 pone las conservadoras (D-0721) como `shop_item` `cooler`** porque ningún tipo de condición
  mide "tener un embalaje". Se ofrece con el hito de Nieve, antes de subir.
- **Decisión: el aeródromo y la licencia de vuelo de D-0418 pasan al hito de Montaña** porque ahí se compra la
  avioneta. El de Volcán queda con reputación 80 y entregas en Nieve.
- **Decisión: `machines` cuenta tipos distintos** porque contar piezas deja cumplirlo con tramos de cinta baratos.
- **Decisión: 10 premios de plata, 8 750 en total, ninguno de más de 3 días de ganancia** porque ayudan más al
  solitario (que ahorra más lento) y no cambian la curva de los primeros 20 días.
- **Decisión: los rangos de D-0423 cuelgan de tres hitos** (`deliveries_50` Pyme, `money_30000` Distribuidora,
  `national_logistics` Logística Nacional) y no son una recompensa más. El rango inicial es Garage.
- **Decisión: pagar la obra completa el hito `reputation_60`** porque la zona tiene que entrar al generador de
  pedidos (si no, la valla abierta no sirve de nada). Es el único hito que se puede comprar.
- **Decisión (propuesta a D-1017): límite de empleados por etapa del galpón de 2 / 4 / 6 / 8** porque así
  `employees_3` entra en la etapa 2 y `employees_6` en la 3, que da el hito 14.

## Para revisar al final

- **Campaña larga en solitario.** Con los precios de flota.md (avioneta 12 000) y la curva de D-0117, un jugador
  solo abre Montaña hacia el día 60 y termina hacia el 87 (~26 h de juego); 2 jugadores, 72; 4 jugadores, 53.
  Con la avioneta a 8 000, Montaña abre hacia el 46 / 37 / 27 y el final cae hacia el 72 / 59 / 43. Es la palanca
  más fuerte; conviene pasarla por `critico-diseno` antes de tocar el precio o los premios.
- **Permiso de Suburbio de 1 200.** Es lo que hace cuadrar la curva, pero es una compra más y obliga a tocar
  `gate_suburbio`. La alternativa es abrirlo solo con el hito y aceptar que 4 jugadores lo abren el día 3.
- **Campo cerrado los primeros días.** El juego de hoy (la ruta de Campo) queda detrás de reputación 60; si se
  prefiere Campo desde el día 1, se saca el hito 6 y se reparte su recompensa.
- **Equivalencias de reputación** (para D-0405): 55 ≈ 10 entregas cobradas, 60 ≈ 15, 70 ≈ 50, 80 ≈ 130,
  90 ≈ 300. La curva real de D-0405 manda y estos días se mueven con ella.
- **Precios provisorios** que usé para estimar los días: aeródromo 1 500, equipo de Nieve 1 200, equipo de Volcán
  2 500 (los fija D-0511). Las licencias los fijó D-0124 (sección "Las licencias": 650 / 600 / 1 000 / 1 000 /
  1 000).
- **Ids provisorios** de proveedores (`supplier_*`, D-0621), cosméticos (D-0137), equipo (`work_gloves`, `grip_boots`)
  y máquinas (nombres del grupo 11, no los de economia.md §4).
- **Racha sin roturas de 4 jugadores.** Entregan más por día, así que les cuesta un poco más la racha de 10 días
  (19 contra 17 de un solitario). Si molesta, subir el mínimo de entregas para 1 jugador o dejar la racha por
  persona.
- **Nombres en español** de los 30 hitos: son de trabajo; los afina el texto del juego (D-1920).
- **Pedidos repartidos parejo entre zonas abiertas.** Es el supuesto de los días; D-0807 puede ponderar y eso
  mueve los hitos por zona.

## Fuentes

- [README de la expansión](../README.md), [supuestos.md](../detalle/supuestos.md),
  [F0-01-diseno.md](../detalle/F0-01-diseno.md) (D-0118)
- [vision.md](vision.md), [distritos.md](distritos.md), [mapa.md](mapa.md), [flota.md](flota.md),
  [economia.md](economia.md), [catalogo-productos.md](catalogo-productos.md),
  [corte-vertical.md](corte-vertical.md), [critica-alcance.md](critica-alcance.md)
- Grupos: [04](../04-progresion-e-hitos.md), [10](../10-empleados.md), [11](../11-automatizacion.md),
  [12](../12-flota-bici-carrito.md), [13](../13-lancha-e-islas.md), [14](../14-avioneta-y-aerodromos.md),
  [16](../16-montana-y-nieve.md), [17](../17-volcan.md)
- Decisiones: [mapa continuo](../../decisiones/2026-10-04-mapa-continuo.md),
  [delegadas](../../decisiones/2026-10-04-expansion-decisiones-delegadas.md),
  [recortes](../../decisiones/2026-10-19-recortes-expansion.md);
  [economía y contramedidas](../../economia-y-contramedidas.md)
- Código: [company_state.gd](../../../do-not-drop/scripts/core/company/company_state.gd) (`milestones_done`),
  [gate_requirement.gd](../../../do-not-drop/scripts/gameplay/districts/gate_requirement.gd),
  [data/gates/](../../../do-not-drop/data/gates/); [revisar/D-0306](../revisar/D-0306.md) (hitos placeholder)
