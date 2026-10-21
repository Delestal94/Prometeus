# F1 · Grupo 06 — Mercadería entrante, descarga y stock (detalle)

> Carril 2 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [06-mercaderia-y-stock.md](../06-mercaderia-y-stock.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0601 · Camión de proveedor NPC que entra al patio, se estaciona en la dársena y espera — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `SupplierTruck` (`scripts/gameplay/business/supplier_truck.gd`: trayectoria por minuto) y `SupplierTruckView` (`scripts/gameplay/supplier_truck_view.gd`: caja gris que la dibuja), cableado en `CompanyRoot`; `test_supplier_truck` (10 corridas). Arte real en [arte-pendiente/D-0601.md](../arte-pendiente/D-0601.md).
**Depende de:** D-0602 (`SupplierSchedule`: 08:30 llega, espera 3 h), D-0905 (`WarehouseStages.dock_rect` / `gate_rects`), D-0219 (`GameClock`)
**Qué:** el camión que trae lo pedido, visible en el patio. Es una función del reloj, no un actor con estado:
- `SupplierTruck.pose(schedule, day, minute, stage)` (`RefCounted`, solo estáticos, sin nodos ni azar) da
  `{present, phase, position, heading, yaw}` en metros del galpón (X este, Z sur, origen al centro del piso).
  Fases (`enum Phase`): `ABSENT`, `DRIVING_IN`, `REVERSING`, `PARKED`, `DRIVING_OUT`.
- **Recorrido:** entra desde el este por un carril al sur de la dársena rumbo al oeste, gira a la izquierda
  (radio 6 m) hasta apuntar al sur sobre el eje de la dársena, retrocede 10 m hacia el norte y queda con la
  trasera a 0,6 m del borde del piso (la pared mide 0,3), fuera del galpón. Espera. Sale hacia delante (sur),
  gira otra vez a la izquierda y se va al este por otro carril 12 m más al sur. No entra a la dársena (las
  celdas de piso `dock_rect` quedan libres para los palets que bajan de la caja, D-0605) ni toca paredes.
- **Horario:** estacionado exactamente de `arrival_minute()` a `departure_minute()` (los estados `at_dock` del
  calendario); entra en los 6 min de juego anteriores y sale en los 4 posteriores (`SUPPLIER_DRIVE_IN_MIN`,
  `SUPPLIER_DRIVE_OUT_MIN`; un minuto de juego son 1,5 s reales). Frena al llegar y arranca suave al irse.
  Sin entrega ese día (`none`) no hay camión. Todos los números (tamaño 2,4 × 3,2 × 6,4 m, radio, retroceso,
  tramo recto, holgura) en `CompanyTuning`.
- `SupplierTruckView` (`Node3D`, hermano del galpón porque `CompanyShed.rebuild()` libera a sus hijos): camión de
  cajas primitivas con la paleta del depósito; cada cuadro llama a `pose()` con `GameClock.minute_now()` y
  `CompanyState.day` y se oculta si no hay camión. **Cero RPC:** los clientes derivan la pose del mismo reloj
  (ancla del host) y del mismo calendario; no hay nada que decida el host.
- Hasta que D-0603 meta pedidos reales, `CompanyRoot._seed_stand_in_calendar()` pone el primer pedido del
  galpón por defecto en los 120 días siguientes al inicial, en todos los peers, para que se vea llegar. No trae
  stock nuevo (los palets de arranque ya están en recepción).
- Bajar los palets de la caja es D-0605; que se lleve lo que quede es D-0618; varios camiones a la vez, D-0640.
**Test** `test_supplier_truck`: 10 corridas (días 1 a 89, las 4 etapas del galpón, pedidos de 1 a 100 unidades):
sin camión antes de entrar, un día sin entrega ni después de salir; estacionado justo en `arrival_minute()`;
fases siempre hacia delante; quieto y sin moverse hasta `departure_minute()`; dentro del carril de la
dársena, de reversa hacia ella, cerca de la pared sin tocarla; en todo el recorrido ninguna esquina toca el
piso, las paredes ni las celdas de la dársena; sin saltos de posición ni de giro; determinista (dos calendarios
iguales, el tamaño del pedido no mueve nada); la vista sigue la pose y se oculta.
**Hecho cuando:** bot: el camión llega y se estaciona sin chocar en 10 corridas (`test_supplier_truck`).

### D-0604 · Palet con N cajas de producto — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Pallet` (`scripts/gameplay/business/pallet.gd`): arma, parte un pedido en palets, los recibe en el `Inventory` y los serializa; `test_pallet`.
**Depende de:** D-0204 (producto), D-0211 (`Inventory`)
**Qué:** `class_name Pallet`, `RefCounted` con solo funciones estáticas. Un palet es un `Dictionary`
(`id`, `product`, `qty`, `state`: `sealed` / `open`) para que viaje por red y entre en el save.
- `make(id, product, qty)`: palet cerrado de 1 a `MAX_UNITS = 24` unidades de un solo producto (supuestos);
  `{}` si no cumple.
- `plan(prefix, product, qty)`: parte un pedido a proveedor en los palets mínimos (24 + 24 + 2…).
- `location(id)` = `&"pallet:<id>"`: dónde cuenta el `Inventory` las unidades del palet.
- `receive(inventory, pallet)`: el camión lo descarga; suma las unidades en `pallet:<id>` una sola vez.
- `units_left`, `validate`, `to_json` / `from_json`.
Abrir el palet (pasar sus unidades a cajas tomables) es D-0607; el objeto físico y verlo en la caja del
camión es D-0601 / D-0605, que usan esta clase.
**Test** `test_pallet`: límites de `make`, `plan` de 50 unidades, `receive` una sola vez sin duplicar,
`validate` con 4 problemas, JSON de ida y vuelta.
**Hecho cuando:** el test pasa. (La parte "aparece en la caja del camión" queda para D-0601.)

### D-0605 · Descargar palet con la zorra — A · Sonnet 5.5 · high · Aviso: no · F1
**[~] Parcial (2026-10-21, PR pendiente)** — la lógica de la zorra (`PalletJack`, `scripts/gameplay/business/pallet_jack.gd`) y `test_pallet_jack`. Falta D-0605.b (el objeto en el mundo y la interacción).
**Depende de:** D-0604 (`Pallet`), D-0601 (`SupplierTruck`, la caja del camión), D-0211 (`Inventory`)
**Qué:**
- **D-0605.a (hecha) — la lógica.** `PalletJack` (`RefCounted`, estado puro): dónde está cada palet (`bed` = caja del camión, `jack` = en la zorra, `floor` = piso del galpón con su punto en metros). `load_bed` sube los palets del día, `pick_up(id, holder)` toma uno (de a uno; del piso hay que estar a `PALLET_JACK_REACH_M` = 1,6 m; la caja del camión se alcanza desde el portón y eso lo chequea quien llama), `put_down(pos, floor_rect, inventory)` lo apoya dentro del piso y sin pisar a otro palet (`PALLET_FOOTPRINT_M` = 1,2 × 0,8 m). Las unidades entran al `Inventory` (`Pallet.receive`) **una sola vez**, al apoyar por primera vez un palet que vino de la caja; lo que no se baja queda en `left_on_bed()` y se va con el camión sin contarse. `remove` lo saca del patio cuando está vacío (D-0607). `to_dict`/`from_dict` para el save y la red.
- **D-0605.b (pendiente) — el mundo.** Zorra como objeto (malla gris placeholder, `arte-pendiente/D-0605.md`), interacción del jugador (agarrar la zorra, subir/bajar el palet, empujarla) y el palet dibujado en la caja del camión (`SupplierTruckView`); el host aplica y replica (D-0619).
**Test** `test_pallet_jack`: palets válidos y repetidos en la caja; uno por vez y alcance; recepción única en el `Inventory`; soltar fuera del piso o encima de otro palet no cambia nada; lo que queda en la caja no se cuenta; 50 movimientos sin perder ni duplicar unidades; ida y vuelta de JSON.
**Hecho cuando:** jugador mueve un palet del camión al piso (test de interacción, D-0605.b).

### D-0607 · Abrir palet — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Pallet.open/take/is_depleted` en `pallet.gd`; ampliado `test_pallet`.
**Depende de:** D-0604 (`Pallet`), D-0211 (`Inventory`)
**Qué:** abrir es solo un cambio de estado: `open(inventory, pallet)` pasa `sealed` → `open` (en el mismo
`Dictionary`) si el palet está recibido y tiene unidades; no las mueve. `take(inventory, pallet, qty, to)`
pasa unidades de `pallet:<id>` a una mano, carrito o hueco, solo con el palet abierto. `is_depleted` avisa
cuando queda vacío para sacarlo del patio. El objeto físico "caja tomable" lo arman D-0605 / D-0609 sobre esto.
**Test** `test_pallet`: no se abre sin recibir; `take` falla cerrado; abre una vez; saca 3 de 5; no saca de más;
vacío = agotado; no se pierde ni duplica ninguna unidad.
**Hecho cuando:** el test pasa.

### D-0608 · Estanterías con huecos etiquetados por producto — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Shelf` (`scripts/gameplay/business/shelf.gd`): huecos con etiqueta de producto sobre el `Inventory`; `test_shelf_slots`.
**Depende de:** D-0904 (`PlaceableDefinition.slots`), D-0211 (`Inventory`)
**Qué:** `class_name Shelf`, `RefCounted`. `make(id, slot_count)` (usa `slots` del `.tres`), `set_label` / `clear_label`
(un producto por hueco y un hueco por producto en cada estante; no se re-etiqueta con unidades adentro),
`deposit(inventory, slot, product, qty, from)` y `withdraw(inventory, slot, qty, to)` (todo o nada, solo con
`Inventory.move`: no se crea ni se pierde nada), `count`, `free_space`, `find_slot`, `to_dict` / `from_dict`.
Las unidades viven en `shelf:<estante>_<hueco>`. Capacidad por hueco: `CompanyTuning.SHELF_SLOT_CAPACITY = 24` (un palet).
El nodo que dibuja el estante y la interacción son D-0609 / D-0611; el frío es D-0616.
**Test** `test_shelf_slots`: 8 huecos, etiquetas, depósito solo del producto etiquetado, tope, retiro, 50 movimientos conservan el total, JSON.
**Hecho cuando:** dejar producto en un hueco lo suma al `Inventory` (test pasa).

### D-0609 · Tomar productos de la estantería (picking) a mano — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `ShelfPicking` (`scripts/gameplay/business/shelf_picking.gd`), `CompanyShed.station_for`, `CompanyNet.request_for` y `CompanyRoot._on_piece_used`; `test_shelf_picking`.
**Depende de:** D-0608 (`Shelf`), D-0914 (`ShedPiecePoint`), D-2003 (`units_take`, `HAND_MAX_UNITS`)
**Qué:** usar un estante (la E de siempre sobre su punto de uso) pasa unidades de un hueco a la mano de quien lo usa:
- `ShelfPicking.plan(uid, shelf, inventory, hands, after)` arma la petición `units_take` `{station, product, qty}`: con las manos vacías toma el siguiente hueco con stock después del último usado (rota y da la vuelta); con producto en la mano sigue en el hueco de ese producto; `qty` = lo que entra hasta `HAND_MAX_UNITS` (4) sin pasar de lo que hay. Sin plan: `empty`, `hands_full` o `hands_busy`.
- `CompanyShed.station_for(id)` es el `stations` de `CompanyNet`: un hueco etiquetado = `{location, spot (el punto de uso), accepts, capacity}`. Nombre de la estación: `<uid>_slot<n>`.
- `Interactable.interact()` corre en el host para todos los pares, así que `CompanyNet.request_for(peer, kind, data)` (nuevo, solo host, sin RPC) hace la petición en nombre del par que usó el estante, con las mismas comprobaciones de siempre (alcance, manos, stock). Un rechazo le llega al par con `rid` 0.
- Guardar de vuelta en el hueco (`units_store`) y elegir un hueco apuntando quedan fuera: ver `revisar/D-0609.md`.
**Test** `test_shelf_picking`: nombres de estación; el plan topa en 4, completa lo que ya hay en la mano y rechaza manos llenas, ocupadas o estante vacío; rotación de huecos; el galpón resuelve solo huecos etiquetados; de punta a punta, tomar 3 baja el hueco en 3 y sube la mano en 3 sin crear unidades; lejos del estante lo rechaza.
**Hecho cuando:** tomar 3 unidades baja el stock en 3 (test pasa).

### D-0602 · Calendario de entregas de proveedores — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `SupplierSchedule` (`scripts/gameplay/business/supplier_schedule.gd`): lo pedido el día N llega el N + 1; `test_supplier_schedule`.
**Depende de:** D-0604 (`Pallet.plan`), supuestos (1 camión por día a las 08:30, espera 3 h)
**Qué:** `class_name SupplierSchedule` (`RefCounted`, sin nodos ni autoloads), día → `{producto: unidades}`:
- `place(order_day, lines)`: suma un pedido (`[{product, qty}]`) al camión del día siguiente; todo o nada.
- `ordered_for(day)`, `pallets_for(day)` (palets sellados con `Pallet.plan`, ids `d<día>_<producto>_<n>`), `upcoming_days(from)`, `has_delivery`, `clear_day`.
- `truck_state(day, minute)`: `none` / `pending` / `at_dock` / `left` (08:30 a 11:30).
- `to_dict` / `from_dict` tolerante. El camión que entra a la dársena es D-0601; la pantalla de pedido, D-0603.
**Test** `test_supplier_schedule`: calendario de 3 días, fusión de pedidos y palets, estados del camión, pedidos inválidos, ida y vuelta JSON.
**Hecho cuando:** el test pasa con un calendario de 3 días.

### D-0620 · Layout inicial del depósito actual adaptado: dársena, recepción, racks, armado, despacho — A · Opus 5.5 · xhigh · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — es D-0911 visto desde el stock: `data/shed/default_shed.tres` (`DefaultShed`) y `CompanyShed`; `test_company_default_layout`. Detalle completo en [F1-09-galpon.md](F1-09-galpon.md).
**Depende de:** D-0608 (estantes con huecos), D-0604 (palet), D-0602 (calendario), D-0904, D-0214
**Qué:** las zonas del depósito actual (dársena, recepción, racks, armado, despacho) como objetos colocables de D-0904 sobre la grilla de la etapa chica, con modelos del depósito (`sm_env_depot_packing_table`, `sm_env_depot_pallet_wrapped`) o cajas grises:
- **Dársena y recepción** junto al portón sur: el primer pedido del calendario de proveedores (`SupplierSchedule`, llega el día 1) aparece como dos palets sellados (`pallet:d1_milk_canister_1`, `pallet:d1_wedding_cake_1`) en la zona de recepción.
- **Racks**: tres estantes al muro oeste con los 8 productos de ambiente en sus huecos etiquetados (6 unidades cada uno; la etiqueta del hueco muestra la cantidad, la parte de dibujo de D-0611) y dos huecos vacíos etiquetados para lo frío.
- **Armado**: dos mesas (`PackingStation` por mesa) con dispensador de cajas; **despacho**: la zona pintada junto a la salida.
- Cada zona lleva su nombre pintado en el piso (`WORLD_SHED_ZONE_*`); la captura aérea con zonas rotuladas es la de `revisor-visual` sobre `company_root.tscn`.
**Test** `test_company_default_layout` (y los `test_company_*` de la expansión verdes); los `test_depot_*` no se tocan: el depósito de Entrega no cambia.
**Hecho cuando:** captura aérea con zonas rotuladas y los tests verdes.

### D-0603 · Pedido a proveedor desde el portapapeles o el tablero — B · Sonnet 5.5 · high · Aviso: no · F1
**[~] Parcial (2026-10-21, PR pendiente)** — la lógica del pedido (`SupplierOrderCart`, `scripts/gameplay/business/supplier_order_cart.gd`) y `test_supplier_order_cart`; la pantalla `SupplierOrderPanel` y `test_company_supplier_panel` (D-0603.b.1). Falta D-0603.b.2 (abrirla en el mundo y replicar el pedido).
**Depende de:** D-0602 (`SupplierSchedule`), D-0503 (`SupplierPurchase`), D-0218 (`SupplierDefinition`), D-0204 (producto)
**Qué:**
- **D-0603.a (hecha) — el carrito.** `SupplierOrderCart` (`RefCounted`): líneas producto → unidades con `add`, `set_qty` y `remove`; solo se piden productos del catálogo que el proveedor vende, de 1 a `MAX_LINE_QTY` (240) unidades por línea. `lines()` (id, unidades, precio unitario y costo), `total()`, `pallet_count()` (24 unidades por palet) y `submit(wallet, schedule, día)`: con el saldo que cubre el total pone el pedido en el calendario para el día siguiente (`SupplierSchedule.arrival_day`) y vacía el carrito. No cobra nada: el cobro sigue siendo al recibir cada palet (D-0503), así que un camión que no se descarga no cuesta.
- **D-0603.b (partida) — la pantalla.** Hecha la pantalla (b.1): `SupplierOrderPanel` (`scripts/ui/supplier_order_panel.gd`) con una fila por producto del proveedor, + / − con teclado, mouse y mando, total, palets, día de llegada y "Pedir" (`SupplierOrderCart.submit`); `test_company_supplier_panel`. Pendiente b.2: abrirla desde el tablero/portapapeles del galpón, pedir por `CompanyNet` y que el host aplique y replique (D-0619). Pedido original:  lista de productos del proveedor, +/- por línea con teclado, mouse y mando, total, palets y "Pedir"; el cliente pide por `CompanyNet` y el host aplica `submit` y replica el calendario (D-0619). Con eso `CompanyRoot._seed_stand_in_calendar()` deja de hacer falta.
**Test** `test_supplier_order_cart`: edición y rechazos, orden y costo de las líneas, palets (30 + 2 unidades = 3), `submit` con saldo corto (no cambia nada) y con saldo suficiente (calendario del día siguiente, camión con 3 palets, nada cobrado).
**Hecho cuando:** test de UI: pedir un palet y que llegue al día siguiente (D-0603.b).

### D-0613 · Aviso de stock bajo para productos con pedidos pendientes — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `StockAlert` (`scripts/gameplay/business/stock_alert.gd`): qué productos faltan para los pedidos pendientes; `test_stock_alert`. El aviso en pantalla (portapapeles, tablero) lo dibuja la UI de stock, D-0612.
**Depende de:** D-0211 (`Inventory`), D-0210 (`OrderBook`), D-0602 (lo que viene en camino)
**Qué:** `class_name StockAlert`, `RefCounted`, solo funciones estáticas sobre datos:
- `shortages(inventory, orders, incoming = {})`: `orders` es lo que devuelve `OrderBook.open_orders()`. Cuenta los pedidos pendientes (abiertos o atrasados que todavía no tienen caja, `is_pending`) y suma lo que piden por producto. Lo compara con el stock libre (`free_units`: todo salvo `box:<id>`, que ya es de un pedido armado). Devuelve una entrada por producto que no alcanza: `product`, `needed`, `have`, `incoming`, `missing`, `due_min` (el vencimiento más cercano) y `covered`, ordenadas por urgencia (vencimiento y después id).
- `incoming` (producto → unidades ya pedidas al proveedor, opcional) baja `missing`; si cierra la brecha entera, `covered` es verdadero ("el camión viene", no "nadie pidió").
- `fresh(previous, current)`: los productos que antes no faltaban y ahora sí (y no están cubiertos), para avisar una vez y no en cada cambio de stock.
- `Inventory.locations_of(product)` (nuevo): ubicación → unidades de un producto.
**Test** `test_stock_alert`: falta y no falta, suma de varios pedidos con el vencimiento más cercano, pedidos armados/entregados/en caja y unidades selladas que no cuentan, `incoming` parcial y total, orden por urgencia, `fresh`.
**Hecho cuando:** test: un pedido que pide más de lo que hay marca el producto con lo que falta (test pasa).

### D-0614 · Recepción: control de remito (lo que llegó vs. lo pedido) — B · Sonnet 5.5 · medium · Aviso: no · F1
**[~] Parcial (2026-10-21, PR pendiente)** — la lógica del remito (`DeliveryNote`, `scripts/gameplay/business/delivery_note.gd`) y `test_delivery_note`. Falta D-0614.b (llamarlo al irse el camión y mostrarlo).
**Depende de:** D-0602 (`SupplierSchedule.ordered_for`), D-0604 (`Pallet`), D-0605 (`PalletJack.left_on_bed`)
**Qué:**
- **D-0614.a (hecha) — la lógica.** `DeliveryNote` (`RefCounted`, sin nodos): `received_units(pallets, received_ids)` suma las unidades de los palets que sí se bajaron; `compare(pedido, recibido)` devuelve una línea por producto (`ordered`, `received`, `missing`, `extra`) en orden de id; `check(día, pedido, recibido)` guarda en el remito solo las líneas que no cierran (un día exacto no deja registro; volver a controlar el mismo día lo reemplaza). `days_with_shortfall()`, `discrepancies(día)`, `missing_totals()`, `is_exact` y `total_missing`. `to_dict`/`from_dict` toleran datos rotos y recalculan `missing`/`extra`.
- **D-0614.b (pendiente) — el cableado.** Cuando el camión se va (`SupplierSchedule.truck_state` pasa a `left`, D-0618), `CompanyRoot` llama a `check(día, ordered_for(día), received_units(pallets_for(día), ids bajados))`, guarda el `DeliveryNote` en el save de empresa y lo replica con el resto del stock (D-0619). Lo que se muestra (lista de faltantes en el resumen del día o el tablero) es UI; el cobro solo de lo recibido ya lo hace D-0503 por palet.
**Test** `test_delivery_note`: solo cuentan los palets bajados; faltante de 6 gallinas registrado en su día; entrega exacta sin registro y volver a controlar reemplaza; sobrante como `extra` y no como faltante; totales por producto y días inválidos; ida y vuelta de JSON y save roto.
**Hecho cuando:** test: un faltante se registra (hecho en la lógica); en el juego, al irse el camión (D-0614.b).
