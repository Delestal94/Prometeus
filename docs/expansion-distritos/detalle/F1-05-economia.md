# F1 · Grupo 05 — Economía (detalle)

> Carril 4 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [05-economia.md](../05-economia.md) y se detalla cuando le toque a un
> carril. Números de [supuestos.md](supuestos.md) y de [diseno/economia.md](../diseno/economia.md).

### D-0501 · Billetera de la empresa — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `CompanyState.earn/spend/charge/can_afford/ledger_total` + `ledger` (historial de 200 movimientos, guardado con la empresa); `test_company_wallet`.
**Depende de:** D-0202
**Qué:** la plata sigue en `CompanyState.money` (S8: `CrewProgression.team_money` queda para Entrega/Endless),
ahora con un historial. Cada movimiento es `{day, minute, amount (con signo), reason, balance}`.
- `earn(amount, reason)`: suma; ignora montos ≤ 0.
- `spend(amount, reason)`: resta solo si alcanza (`can_afford`); si no, no cambia nada y devuelve `false`.
- `charge(amount, reason)`: resta aunque quede en rojo (alquiler, penalidades); qué pasa con saldo negativo
  es D-0510.
- `ledger_total(reason)`: suma con signo de los movimientos de un motivo (base del resumen D-0508).
- El historial guarda como máximo `CompanyTuning.LEDGER_MAX` (200); lo más viejo se descarta, la plata no.
  Va en `to_dict()` / `from_dict()` (sin subir `CompanySave.VERSION`: un campo que falta carga vacío).
- Los motivos son `StringName` libres (`order_paid`, `supplier`, `rent`…); cada tarea del grupo define los
  suyos. La señal `money_changed` de `EventBus` es D-0215 y se conecta ahí.
**Test** `test_company_wallet`: ganar y gastar registran día, minuto, monto, motivo y saldo; gastar de más no
cambia nada; `charge` deja en rojo; montos ≤ 0 se ignoran; la suma de movimientos da el saldo; el tope de
200; ida y vuelta por JSON; `new_company` y `reset` limpian.
**Hecho cuando:** el test pasa.

### D-0502 · Precio de un pedido — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `OrderPricing` (`scripts/gameplay/business/order_pricing.gd`): cotiza (productos, envío, requisitos, urgencia) y liquida con el bono por estado; `OrderGenerator` usa la misma cuenta; `test_order_pricing`.
**Depende de:** D-0802, D-0806, D-0117
**Qué:** funciones estáticas sin nodos. `quote(items, zone, requirement_ids, products, catalog)` devuelve
`{goods, shipping, requirements, urgency, total}`: unidades × precio de venta + envío de la zona, y cada
requisito sube la paga en cascada (igual que el generador); lo que suma `urgent` se informa aparte como
urgencia. `with_requirements` es esa cascada sola. `condition_bonus(pay, quality)` da +10 % si la calidad del
armado llega a 90; `settle(order, now_min, quality)` = `Order.payout` (−25 % si tarde) más ese bono.
Números nuevos en `CompanyTuning`: `CONDITION_BONUS_MIN_QUALITY = 90`, `CONDITION_BONUS = 0.10`.
**Test** `test_order_pricing`: 10 pedidos promedio (2 unidades a 80 + envío 40/60) suman 2100 = 10 × 210 de
`diseno/economia.md`; la cotización coincide con el `pay` de `Order.make`; desglose con `urgent` y `fragile`;
ids desconocidos no suman; bono por estado con y sin tardanza.
**Hecho cuando:** el test pasa.

### D-0503 · Costo de compra de mercadería — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `SupplierPurchase` (`scripts/gameplay/business/supplier_purchase.gd`): `cost`, `pallet_cost`, `can_order` y `receive` (recibe el palet y cobra con motivo `supplier`); `test_supplier_purchase`.
**Depende de:** D-0501, D-0604
**Qué:** funciones estáticas sin nodos. El precio unitario es `ProductDefinition.buy_price` (20 a 80).
- `cost(product, qty, products)` = unidades × `buy_price`; producto desconocido o cantidad ≤ 0 cuesta 0.
- `pallet_cost(pallet, products)` y `can_order(wallet, pallets, products)`: al hacer el pedido solo se
  comprueba que la plata alcanza para todo; no se cobra nada.
- `receive(wallet, inventory, pallet, products)`: `Pallet.receive` y, si entró, `charge(costo, &"supplier")`.
  Palet inválido, repetido o de producto desconocido: `false` y no se cobra.
**Decisión:** se cobra al **recibir** (cuando el camión descarga), con `charge` y no `spend`: la mercadería ya
está en el galpón, así que el saldo puede quedar en rojo; qué pasa entonces es D-0510. Un palet que nunca
llega no cuesta.
**Test** `test_supplier_purchase`: 10 lámparas a 50 cuestan 500; recibir baja el saldo 500 y `ledger_total(&"supplier")`
da -500; las unidades quedan en `pallet:<id>`; recibir dos veces o un palet inválido no cobra; `can_order`
mira el pedido entero; recibir sin saldo lo deja en rojo.
**Hecho cuando:** el test pasa.

### D-0504 · Costo de materiales de embalaje — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-05, PR pendiente)** — `PackagingSupplies` (`scripts/gameplay/business/packaging_supplies.gd`): relleno, cinta, etiqueta y sellos se cobran al hacerse, con motivo `packaging`; `test_packaging_supplies`.
**Depende de:** D-0501, D-0212
**Qué:** funciones estáticas sin nodos sobre un `PackedBox` y la billetera (`CompanyState`). La caja vacía ya la cobra `BoxDispenser` (motivo `boxes`); esto es el resto. Precios en `CompanyTuning`: relleno 1 por celda, cinta 1, etiqueta 0, sello 0.
- `pad(box, cells, wallet)`: rellena hasta `cells` celdas libres y cobra solo las que rellenó; todo o nada si no alcanza la plata. Devuelve cuántas rellenó.
- `tape`, `label`, `stamp`: cobran su precio y marcan la caja; repetir cinta o sello, o una etiqueta/sello vacío, devuelve `false` sin cobrar.
- `used_cost(box)`: lo que ya gastaron los insumos de esa caja (para el resumen D-0508).
**Decisión:** se cobra cada paso al hacerlo (no al cerrar la caja), con `spend` y no `charge`: sin plata no se puede seguir embalando, a diferencia de la mercadería ya descargada (D-0503). Una caja abandonada solo cuesta lo usado. Los pasos de la mesa (relleno D-0705, cinta D-0706, etiqueta D-0707) llaman a esta clase.
**Test** `test_packaging_supplies`: rellenar 3 celdas cobra 3; pedir de más se limita a las libres; cinta se cobra una vez; etiqueta y sello rechazan repetidos y vacíos; con 2 de saldo, 3 celdas no entran (la caja y el saldo no cambian) y 2 sí; el libro suma `packaging` y `used_cost` coincide.
**Hecho cuando:** el test pasa.

### D-0506 · Penalidades — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `OrderPenalties` (equivocado, roto, tarde, mal etiquetado) + `CompanyState.add_reputation`; `test_order_penalties`.
**Depende de:** D-0501, D-0502, D-0212
**Qué:** `OrderPenalties` (`scripts/gameplay/business/order_penalties.gd`), funciones estáticas sin nodos.
`assess(order, box, now_min, broken, products)` devuelve `{pay, base, lost, kinds, reputation}`:
- **Producto equivocado, faltante o de más** (`matches_order` compara `PackedBox.contents()` con los ítems del
  pedido): la caja paga `WRONG_BOX_PAY_FACTOR` (0) y cuesta `WRONG_BOX_REPUTATION` (-3).
- **Rotura** (`broken` = un id por unidad rota): se pierde el precio de venta de cada una (tope: la paga) y
  cuesta `BROKEN_PRODUCT_REPUTATION` (-5) por unidad. El envío no se pierde.
- **Tarde:** `LATE_PENALTY` (-25 %), igual que `Order.payout`; no cuesta reputación.
- **Caja mal etiquetada o sin etiqueta:** `MISLABEL_PAY_LOSS` (-15 %) y `MISLABEL_REPUTATION` (-1).
- Las penalidades se apilan en ese orden; la reputación de una entrega nunca baja de `PENALTY_REPUTATION_CAP` (-10).
- `apply_reputation(company, verdict)` pasa el cambio a `CompanyState.add_reputation` (nuevo, con tope del rango).
**Decisión:** las penalidades son **rebajas de la paga** y de reputación, no cobros aparte: lo que el cliente
no paga nunca es plata que la empresa tuvo. (Los cobros a mano, como alquiler, son `charge`.) Los números
nuevos (`MISLABEL_*`, tope) van en `CompanyTuning`. Qué entrega "llega rota" lo decide el tramo de puerta (D-0340);
acá solo se recibe la lista.
**Test** `test_order_penalties`: entrega perfecta; 1 y 3 unidades en vez de 2; una y dos rotas; tarde (y justo en
el minuto límite); etiqueta ajena y caja sin etiqueta; todo apilado (200 → 77); tope de reputación; reputación en
`CompanyState` dentro de su rango.
**Hecho cuando:** el test pasa.

### D-0507 · Propinas — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `OrderTips` (`scripts/gameplay/business/order_tips.gd`): 15 % de la paga base por entrega perfecta en la primera mitad de la ventana, +1 de reputación; `test_order_tips`.
**Depende de:** D-0501, D-0506
**Qué:** `OrderTips.assess(order, verdict, now_min)` devuelve `{tip, reputation}`; `apply(company, result)` cobra con motivo `tip` y suma la reputación.
- Propina solo si `OrderPenalties.assess` no encontró fallas (`kinds` vacío) y se entregó dentro de `TIP_FAST_WINDOW_SHARE` (0,5) de la ventana del pedido.
- El monto es `TIP_RATE` (0,15) de la paga base. Los tres números van en `CompanyTuning`.
**Decisión:** la propina es plata aparte de la paga (entra como `earn`, no se suma al precio del pedido), así el ledger la muestra por separado en el resumen de D-0508.
**Test** `test_order_tips`: rápida, justo a la mitad, lenta, antes de existir el pedido, cada penalidad la cancela, billetera y reputación.
**Hecho cuando:** el test pasa.

### D-0508 · Resumen financiero del cierre del día — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-18, PR pendiente)** — `DaySummary` (`scripts/gameplay/business/day_summary.gd`): ingresos, costos, ganancia y saldo de apertura/cierre del día, por motivo, desde el libro; `test_day_summary`. El panel (D-0508.2) es `DaySummaryPanel` (`scripts/ui/day_summary_panel.gd`, claves `finance_*`; `test_day_summary_panel`). Mostrarlo al cerrar el día queda en D-0508.3.
**Depende de:** D-0501
**Qué:**
- **D-0508.1 (hecha)** `DaySummary.build(company, day)` devuelve `{day, income, costs, profit, opening, closing, income_by_reason, cost_by_reason, truncated}`. Parte los movimientos del libro de ese día por signo; `costs` y los montos por motivo son positivos. `sorted_reasons(dict)` ordena los motivos de mayor a menor para listarlos. `truncated` avisa que el libro está lleno y puede faltar parte del día (`LEDGER_MAX` = 200).
- **D-0508.2 (hecha, `constructor-ui`)** Panel del cierre del día: lista de ingresos y de costos por motivo (nombres traducibles por clave `finance_reason_<motivo>`), ganancia con color, saldo de apertura y cierre. Se arma por código como el resto de la UI, navegable con mando; la lee `CompanyRoot` al cerrar el día (D-0320). Test de UI: los números del panel coinciden con `DaySummary.build`. Captura de `revisor-visual` a 1080p y Steam Deck.
  Hecho: `DaySummaryPanel.open(summary)` dibuja el diccionario (el mismo que publica `DayCycle` en SUMMARY), `continued` avisa al cerrar y los motivos sin clave se muestran con su id. Más de 8 motivos por lista se pliegan en una fila "Otros" sin perder plata.
- **D-0508.3 (hecha, 2026-10-21)** `CompanyRoot.summary_panel` (`DaySummaryPanel` en su `CanvasLayer`): se abre con `company_day_summary` en todos los pares, "continuar" llama a `DayCycle.next_day()` solo en el host y `company_day_started` esconde la copia de los clientes; `test_company_root`. Falta la captura de `revisor-visual` (ver `revisar/D-0508.md`). Original: `CompanyRoot` instancia el panel y lo abre con `EventBus.company_day_summary` (todos los pares muestran lo que cerró el host); `continued` pasa al día siguiente en el host (`DayCycle.next_day`). Captura de `revisor-visual` a 1080p y Steam Deck. Va junto con D-0320 (resultado de la salida al cierre).
**Decisión:** el resumen se calcula del libro y no se guarda: es una vista, así no hay otro estado que replicar ni migrar. Los motivos no se enumeran acá; el que escriba un cobro nuevo ya aparece solo.
**Test** `test_day_summary`: ingresos/costos por motivo de un día con otros días alrededor, ganancia, apertura + ganancia = cierre, día sin movimientos, empresa nula, `truncated` y orden.
**Hecho cuando:** el test pasa y el panel muestra los mismos números (D-0508.2, hecho); aparece solo al cerrar el día (D-0508.3).

### D-0509 · Gastos fijos diarios — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `FixedCosts` (`scripts/gameplay/business/fixed_costs.gd`): alquiler diario (`CompanyTuning.RENT_PER_DAY` = 100) con `due`, `total_due`, `shortfall` y `settle`; `test_fixed_costs`.
**Depende de:** D-0501
**Qué:** funciones estáticas sin nodos sobre la billetera (`CompanyState`). `due()` devuelve los costos del día por motivo (hoy solo `rent`; la luz no es un gasto fijo, la maneja D-0912). `settle(company)` los cobra con `charge` (pasan aunque el saldo quede negativo) y devuelve lo cobrado. `shortfall(company)` dice cuánto no cubre la billetera, para que D-0510 decida la quiebra.
**Decisión:** la clase no guarda estado (no hay "último día cobrado" que replicar ni migrar): el cierre del día (D-0203) la llama una vez por día. Se cobra al cierre, antes del resumen D-0508, así el alquiler aparece como costo `rent`.
**Test** `test_fixed_costs`: el día cuesta 100; `settle` cobra con motivo `rent`; con 30 de saldo queda en -70 y `shortfall` da 70; saldo negativo debe el alquiler entero; sin empresa no cobra.
**Hecho cuando:** el test pasa.

### D-0510 · Quiebra — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `Bankruptcy` (`scripts/gameplay/business/bankruptcy.gd`): `is_bankrupt`, `order_share` y `orders_for_day`; `CompanyTuning.BANKRUPT_ORDER_SHARE` = 0,6; `test_bankruptcy`. D-0510.2 hecha (2026-10-21, PR pendiente): el generador de pedidos y el aviso de apertura usan la quiebra.
**Depende de:** D-0501, D-0509
**Qué:** funciones estáticas sin nodos ni estado. Con la billetera por debajo de cero al cerrar (después de `FixedCosts.settle`), el día siguiente abre con el 60 % de los pedidos y un aviso; no hay reinicio ni préstamo forzado (`diseno/economia.md` §3). `orders_for_day(usual, company)` redondea y nunca baja de 1 si el día tiene pedidos.
- **D-0510.2 (hecha, `constructor-progresion` + `constructor-ui`)** La apertura del día (`DayCycle`/`OrderBook`, D-0203/D-0210) llama a `orders_for_day` al generar los pedidos y el panel de apertura muestra el aviso (clave `bankrupt_warning`).
  Hecho: `OrderGenerator.generate_day(..., company)` (y `OrderRhythm.arrival_minutes(..., count)`) usa `Bankruptcy.orders_for_day`; `CompanyRoot` le pasa a `DayCycle.opening_notice` `Bankruptcy.opening_text`, que sale como `depot_notice` justo después de `company_day_started` en cada par (clave `UI_COMPANY_BANKRUPT_WARNING`, con el 60 % sacado de la constante). Aún no hay panel de apertura: el aviso sale como toast del HUD.
**Decisión:** sin contador de "N días en rojo": cada cierre se evalúa solo por el saldo, así no hay otro estado que guardar ni replicar. Se cumple la decisión de diseño ya tomada (sin reinicio, 60 %); el préstamo forzado queda para D-0521 si se quiere.
**Test** `test_bankruptcy`: 0 no es quiebra, -1 sí; 10 pedidos pasan a 6 y 7 a 4; mínimo 1; 0 queda en 0; el alquiler cobrado hasta el rojo la provoca; con plata vuelve el 100 %; sin empresa nada; `generate_day` con la empresa en rojo da el 60 % de los pedidos y sin empresa o con plata, los de siempre; `opening_notice` vacío en 0 y con la clave en -1 (y `test_company_root` comprueba el toast al abrir el día).
**Hecho cuando:** el test pasa y la apertura usa `orders_for_day` (D-0510.2).

### D-0511 · Tienda de la empresa — B · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `ShopItem` (`scripts/gameplay/business/shop_item.gd`, `.tres` en `data/shop/`) y `CompanyShop` (`company_shop.gd`): `items()` lee el catálogo, `check()` / `buy()` devuelven `{ok, key, args}` (`WORLD_SHOP_*`) y `buy()` cobra con motivo `shop` y entrega lo comprado. Tres ítems de arranque (mejora 1 = 450, lectora de etiquetas = 600, ampliación 1 = 800); `test_company_shop`. Falta la pantalla (D-0511.2), quién puede gastar (D-0518) y los precios del resto (D-0512 a D-0514).
**Depende de:** D-0501, D-0202
**Qué:** catálogo de `.tres` con tres tipos: `vehicle` (suma una entrada `{vehicle: fleet_key}` a `CompanyState.fleet`; se puede comprar otra vez), `machine` (suma su clave a `equipment`; una sola vez; `requires` opcional) y `expansion` (sube `warehouse_stage`, de a una etapa). Funciones estáticas sin nodos ni red.
- **D-0511.2** Pantalla de la tienda en el cierre del día (`constructor-ui`, con D-0508.3 mostrando el resumen).
**Decisión:** el catálogo vive en `data/shop/` y no en `CompanyCatalog` (sus tipos de ítem no son del registro de la empresa y no hay que tocar `KINDS`); los vehículos y las licencias de distrito se agregan como `.tres` en D-0512 y con las barreras (D-0306).
**Test** `test_company_shop`: catálogo en orden, compra cobra y entrega, motivo `shop` en el libro, rechazos sin cambiar nada.
**Hecho cuando:** comprar un ítem en test descuenta la plata y lo otorga (cumplido).

### D-0512 · Precios de vehículos — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — seis `ShopItem` de `kind = vehicle` en `data/shop/vehicle_<fleet_key>.tres`: camioneta extra 1 500, bici 250, carrito 900, 4x4 (`offroad`) 2 500, lancha 5 000, avioneta 12 000 (`diseno/economia.md` §4 y `diseno/flota.md`). Nombres en `strings_world.csv` (`WORLD_SHOP_VEHICLE_*`) y `CompanyShop.NAME_KEYS`; `test_company_vehicle_prices`.
**Depende de:** D-0511, D-0115
**Qué:** la tabla de precios de la flota como `.tres` del catálogo de la tienda. Cada precio es el de `flota.md`; la escalera bici < carrito < 4x4 < lancha < avioneta sube entre 2× y 3,6× por escalón (la regla de escala del §4).
**Decisión:** todos van con `enabled = false`: `CompanyShop.items()` no los lista hasta que existe el vehículo (bici D-1207, carrito D-1221, 4x4 D-1231, lancha D-1302, avioneta D-1401); esa tarea solo cambia la línea a `true` y suma la pantalla/venta. Comprarlos por código ya funciona (suma `{vehicle: fleet_key}` a la flota). La camioneta extra (1 500) queda apagada hasta que D-1201 compre por unidad. Las camionetas ágil y vieja (1 800 y 2 000) tienen hito, no entran acá: llevan su `.tres` cuando se desbloqueen (D-0401+).
**Test** `test_company_vehicle_prices`: precio y `grant_key` de cada uno, escalera, fuera del catálogo mientras estén apagados, y la compra de la bici cobra 250 con motivo `shop`.
**Hecho cuando:** tabla en `.tres` (cumplido).


### D-0513 · Precios de máquinas de automatización — B · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `data/shop/conveyor.tres` (1 500) y `packer.tres` (4 000) junto a `label_reader.tres` (600, ya en la tienda); nombres `WORLD_SHOP_CONVEYOR` / `WORLD_SHOP_PACKER` en `strings_world.csv` y `CompanyShop.NAME_KEYS`; `test_company_machine_prices`.
**Depende de:** D-0511
**Qué:** la tabla de precios de las máquinas como `.tres` del catálogo de la tienda (`diseno/economia.md` §4: lectora de etiquetas 600 · cinta transportadora 1 500 · embaladora 4 000). Cada escalón cuesta entre 2× y 3× el anterior.
**Decisión:** la cinta y la embaladora van con `enabled = false`, como los vehículos de D-0512: no se listan hasta que existe la máquina (cinta D-1101, embaladora D-1109); esa tarea solo cambia la línea a `true`. La clave de equipo es el id del `.tres` (`conveyor`, `packer`). Las otras máquinas del grupo 11 (encintadora, etiquetadora, balanza…) no tienen precio en el diseño: lo ponen sus tareas.
**Test** `test_company_machine_prices`: precio y `grant_key` de cada una, escalera 2-3×, cuáles están a la venta, y la compra de la cinta cobra 1 500 con motivo `shop` y suma la clave al equipo.
**Hecho cuando:** tabla en `.tres` (cumplido).

### D-0514 · Precios de ampliaciones del galpón — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `data/shop/expansion_1.tres` (800), `expansion_2.tres` (2 000) y `expansion_3.tres` (5 000), una por etapa (`diseno/economia.md` §4); `CompanyTuning.WAREHOUSE_STAGE_PRICE` pasa de `[0, 1500, 6000, 20000]` a `[0, 800, 2000, 5000]`; nombres `WORLD_SHOP_EXPANSION_2/3` en `strings_world.csv` y `CompanyShop.NAME_KEYS`; `test_company_expansion_prices`.
**Depende de:** D-0511, D-0905
**Qué:** la tabla de precios de las ampliaciones como `.tres` del catálogo de la tienda: 800 / 2 000 / 5 000, cada escalón 2,5× el anterior (regla de escala del §4).
**Decisión:** manda `economia.md` §4 (el modelo económico de D-0117) sobre los 1 500 / 6 000 / 20 000 que D-0905 había puesto como supuesto de balance (su propio texto dice que se ajustan junto con D-0117). El precio vive en dos lugares (el `.tres` de la tienda y `WarehouseStages.price_for`) y el test los obliga a coincidir. Las tres van a la venta (`enabled = true`, como la primera): la tienda ya las ofrece en orden y rechaza saltar etapas con `WRONG_STAGE`.
**Test** `test_company_expansion_prices`: precio, etapa y nombre de cada una, igualdad con `WarehouseStages`, escalera 2-3×, orden obligatorio, rechazo sin plata sin cobrar y compra de las tres (7 800, motivo `shop`).
**Hecho cuando:** tabla en `.tres` (cumplido).

### D-0515 · Sueldos de empleados por rol y nivel — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `EmployeeLevel` (`scripts/gameplay/business/employee_level.gd`, recurso) y `EmployeeLevels` (`employee_levels.gd`: `levels()`, `find()`, `wage_for()`, `name_key()`), con `data/employees/novice.tres` (60 por día, rinde 0,5), `regular.tres` (90, 0,7) y `expert.tres` (130, 1,0); nombres `WORLD_EMPLOYEE_*` en `strings_world.csv`; `test_employee_wages`.
**Depende de:** D-0511
**Qué:** la tabla de sueldos diarios como `.tres` (`diseno/economia.md` §4): novato 60 · normal 90 · experto 130, y cuánto rinde cada nivel frente a un jugador (0,5 / 0,7 / 1,0). El cobro al cierre es D-1009 y los roles son D-1002: leen esta tabla.
**Decisión:** el sueldo depende del **nivel**, no del rol: los cinco roles (descargador, repositor, armador, controlador, despachante) cobran igual en cada nivel, porque `economia.md` §4 da una sola tabla. Si D-1002 necesita un plus por rol, se suma ahí. Sin costo de alta (`referencia-schedule-1.md`). El recurso no es un `ShopItem`: contratar no es comprar (D-1001).
**Test** `test_employee_wages`: sueldo y rendimiento de cada nivel, orden de menor a mayor, nombre en los dos idiomas, un nivel mejor cuesta y rinde más, el novato cuesta menos que el margen de un pedido (102) y un nivel desconocido no tiene sueldo.
**Hecho cuando:** tabla en `.tres` (cumplido).

### D-0518 · Solo el host (o un voto) gasta en la tienda — B · Sonnet 5.5 · high · Aviso: sí (`network_manager.gd`) · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `CompanyShopNet` (`scripts/core/company/company_shop_net.gd`, `CompanyNet.shop`): pedido `shop_buy {item}` y evento `shop_bought {item, money, minute}` por `CompanyNet`; compra solo el host (también jugando solo, peer 1) y un cliente oye `host_only`; `PROTOCOL_VERSION` 50; `test_company_shop_net`. El voto de la tripulación queda en la subtarea abierta D-0518.b.
**Depende de:** D-0511, D-2003, D-2004 (modelo: D-0910 y D-0603.b.2)
**Qué:** la tienda de D-0511 por red, con el contrato de `diseno/red-autoridad.md` (fila 25 y §13).
- El host comprueba con `CompanyShop.check()` y publica un evento; cada peer lo aplica con el mismo `CompanyShop.buy()`: máquina → `equipment`, vehículo → `fleet`, ampliación → `warehouse_stage`, libro con motivo `shop`.
- La plata viaja absoluta, como el layout (D-0910): `money` es el saldo del host después y `minute` su `clock_minutes`, solo para la entrada del libro. Un peer con la plata desfasada la corrige, avisa y pide un snapshot (`take_drift()`).
- Motivos: `host_only`; `bad_data` (ítem que no es texto, desconocido o apagado, o sin empresa); y las claves `WORLD_SHOP_*` de `CompanyShop` tal cual, que la pantalla traduce.
- Join tardío: sin parte nueva del snapshot; plata, libro, `equipment`, `fleet` y `warehouse_stage` ya van en `company`.
- **D-0518.b (abierta, `constructor-red` + `constructor-ui`)** Voto de la tripulación para que un cliente compre (era D-0428): el cliente pide, el host abre una votación (`modules/coop_vote`) y compra si pasa. Entra donde `CompanyShopNet.check()` recibe `by_host`, igual que D-0910.1 para construir.
**Decisión:** "el host o un voto" se resuelve como **solo el host** en esta tarea, igual que construir (D-0910): un cliente pide y oye `host_only` sin que cambie la plata, el inventario ni el `seq`; un `peer` en los datos no cuenta (el remitente lo pone `RpcGuard`). El día no frena la compra: la tienda es la pantalla del cierre (D-0511.2) y la regla `day_closed` del proveedor es por su calendario, no aplica. Un ítem desconocido es `bad_data` (regla 5 del contrato) y no `WORLD_SHOP_UNKNOWN_ITEM`. Para no pasar las 1000 líneas de `company_net.gd`, los chequeos de un trozo del snapshot y su unión salieron a `CompanySnapshot.chunk_ok()` / `join()`.
**Test** `test_company_shop_net`: el ayudante solo (`host_only`, datos malos, claves de `CompanyShop`, eventos rotos, deriva), solo con el catálogo real, y host + cliente por ENet: el cliente no compra (`host_only`, también con `peer: 1`, sin escribir nada antes), el host compra máquina, ampliación y vehículo y los dos quedan iguales, sus rechazos no cambian nada, la deriva termina en snapshot y un tercero que entra tarde ve todo.
**Hecho cuando:** test de red: un cliente no puede comprar solo (cumplido).

### D-0516 · Cobro al entregar — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — el cobro es **al entregar**, no al cierre del día: ya era así desde D-0815 (`OrderSettlement.settle()` suma la paga a la billetera con motivo `order_paid` en el momento de la puerta). Se fija con test y decisión; no hubo cambio de código.
**Depende de:** D-0501, D-0815
**Qué:** decidir cuándo entra la plata de un pedido (D-0105 deja el reloj de 08:00 a 20:00).
- La paga (y la propina) entra a `CompanyState.money` en el minuto de la entrega, con el día y la hora del reloj en el historial.
- El cierre del día no cobra nada: solo suma el alquiler, los sueldos y el resumen (D-0508), que lee el historial del día.
- Lo que sigue afuera al cierre no cobra: vuelve `FAILED` (D-0302.1).
**Decisión:** al entregar, porque da el feedback inmediato que el coop necesita ("tengo 230 más") y permite comprar a media jornada; cobrar al cierre agregaría un estado "por cobrar" para replicar y guardar sin cambiar el balance (`diseno/economia.md` ya cuenta la paga el día en que se entrega). Archivo: `docs/decisiones/2026-10-22-cobro-al-entregar.md`.
**Test** `test_order_settlement` (`_test_cashed_at_the_door`): el movimiento `order_paid` lleva el día y el minuto de la entrega y `DaySummary` de ese día lo cuenta.
**Hecho cuando:** test y decisión (cumplido).

### D-0520 · Puntaje de la corrida actual en la salida — A · Sonnet 5.5 · xhigh · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `TripScoring` (`scripts/gameplay/districts/trip_scoring.gd`): cada pedido de una salida vale lo que la misma puerta en una entrega (`RunScoring`: 150 intacta, 75 abollada, 20 rota, -60 sin llegar); `TripResult.build()` suma `score`, `score_points` y `score_breakdown`, y el mérito del que llevó la caja sale de ese puntaje (intacta 10, abollada 5, rota o sin llegar 0). `run_scoring.gd`, `run_manager.gd` y `CrewProgression` no se tocaron; `test_company_trip_scoring`.
**Depende de:** D-0501, D-0815 (y D-0320, que arma el resumen de la salida)
**Qué:** el resultado de una salida en modo Empresa usa el puntaje de `RunScoring` como componente de su cierre, sin cambiar Entrega ni Endless.
| Entra / sale | Cuánto | Por qué | Dónde se ve |
|---|---|---|---|
| Plata de la salida | **igual que antes**: la paga de cada pedido, al entregar (D-0516) | el puntaje no cobra: pagarlo además duplicaría cada caja | libro de `CompanyState`, resumen D-0508 |
| Puntaje de la salida | 150 / 75 / 20 por caja intacta / abollada / rota; -60 por pedido que no llegó; suma desde 0, sin multiplicador de caos | mismo precio de puerta que la entrega | `TripResult["score"]` y `["score_breakdown"]` (líneas `HUD_SCORE_*`), `trip_score` en el resumen del día |
| Mérito del que llevó la caja | intacta `TRIP_MERIT_INTACT` (10); abollada la mitad (75 de 150); rota o sin llegar 0 | S8: el mérito se sigue ganando en las salidas | `CrewProgression.award_action`, una vez por pedido |
- `line_points(line)` y `merit_for(line)` leen una línea de `TripResult`; `score(lines)` arma el desglose (mismos rótulos que la pantalla de resultados) y cierra con `RunScoring.settle({}, doors, true, false)`, así ambos modos terminan una corrida igual (piso 0, sin carga en la camioneta, sin caos).
- `TripResult.apply()` ahora paga mérito también a la caja abollada; antes solo a la intacta.
**Decisión:** **el puntaje no es plata.** La paga de cada pedido ya la fijan `OrderPricing` / `OrderPenalties` y se cobra en la puerta (`OrderSettlement`); la curva de `diseno/economia.md` §5 cuenta solo eso. Pagar además los puntos (150 por casa contra unos 105 de margen) duplicaría el ingreso y rompería los 20 días de `sim_economy`. Lo que el puntaje alimenta es el mérito (S8) y el resumen. Quedan fuera a propósito: la foto (+25) y los reclamos (-40) porque el cliente de la empresa responde con reputación (D-0506); los plazos (+40/-15) porque la propina rápida ya los paga (D-0507); la carga que vuelve en la camioneta, porque una caja que regresa vuelve al stock (`Trip.RETURN_LOCATION`) y su pedido ya cuenta como no entregado. Sin número nuevo en `company_tuning.gd`: el mérito de la abollada sale de `TRIP_MERIT_INTACT` × puntos / `POINTS_DELIVERED_INTACT`. Archivo: `docs/decisiones/2026-10-22-puntaje-de-la-salida.md`.
**Falta (no es de esta tarea):** que el cierre del día llame a `TripResult.build/apply/add_to_day` con las salidas reales (D-0508.3 / D-0302.2.b) y que el panel del resumen muestre `trip_score` (D-0547).
**Test** `test_company_trip_scoring`: valor de cada línea contra las constantes de `RunScoring`; mérito por tipo de caja; una salida de cuatro pedidos (intacta, abollada, rota, sin llegar) da 185 con desglose que suma lo mismo; cuatro sin llegar dan -240 puntos y puntaje 0; `apply` paga 15 de mérito una sola vez, `team_money` no se mueve y `pay_total` no cambia; `resolve_deliveries` de una corrida da los mismos puntos para las mismas puertas; el día suma `trip_score`. `test_company_trip_result` sigue verde sin cambios.
**Hecho cuando:** el test pasa y los tests de puntaje y corrida actuales siguen verdes (cumplido: `run_manager`, `score`, `progression`, `dynamic_dispatch`).

### D-0517 · Plata replicada — A · Sonnet 5.5 · high · Aviso: sí (`network_manager.gd`, protocolo 46) · F1
**[x] Hecho (2026-10-22, PR pendiente)** — auditoría de `auditor-red` de todos los caminos que mueven la billetera: construir/vender piezas y la mesa de empaque ya replicaban saldo absoluto; el resto (cobro al entregar, propina, alquiler, proveedor, tienda, ampliación, deshacer) aún no se llama en el juego. Evento host `wallet_moved {amount, reason, money, minute}` (`CompanyWalletNet`, `CompanyNet.publish_wallet`); `PROTOCOL_VERSION` 46; `test_company_money_net` (host + 2 clientes). Fila 25 de `diseno/red-autoridad.md`.
**Depende de:** D-0501
**Qué:** que todos los clientes vean el mismo saldo. Todo cobro o pago nuevo en el mundo compartido se publica con `publish_wallet`, nunca con `earn` / `spend` / `charge` directo en el host.
**Test** `test_company_money_net`: saldo y último `balance` del libro iguales en los 3 peers tras cada movimiento (ingreso, gasto, rojo, deriva), una sola entrada en el host, evento malformado ignorado, entrada tardía, cliente que no puede publicar.
**Hecho cuando:** test y auditoría (cumplido).
**Pendiente (subtareas):** conectar a `publish_wallet` cada camino al enchufarlo (`order_settlement`, `order_tips`, `fixed_costs`, `supplier_purchase`, `company_shop` / D-0518, `warehouse_stages`, deshacer de `build_placement` con pedido `layout_undo` solo del host).
