# F1 · Grupo 08 — Pedidos de clientes (detalle)

> Carril 3 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [08-pedidos-de-clientes.md](../08-pedidos-de-clientes.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0802 · Estructura del pedido — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Order` (`scripts/gameplay/business/order.gd`): arma, valida, normaliza y serializa pedidos; `test_order`.
**Depende de:** D-0204 (el precio sale de `ProductDefinition`)
**Qué:** `scripts/gameplay/business/order.gd` (`class_name Order`, `RefCounted` con solo funciones
estáticas). Un pedido sigue siendo un `Dictionary` (así lo guarda `OrderBook`, D-0210, y viaja por red):
`id`, `customer`, `zone`, `house_id`, `items: [{product, qty}]`, `requirements: [StringName]`,
`created_min`, `due_min`, `pay`, `state`.
- `make(...)`: junta productos repetidos, `due_min = created_min + 240` (ventana de 4 h de juego) si no se
  da, `pay` = unidades × precio de venta + envío de la zona (Barrio Centro 40, Campo 60), `state = open`.
- `validate(order)`: lista de problemas (campos vacíos, 1 a 3 productos distintos con `qty > 0`,
  `due_min > created_min`, `pay ≥ 0`, estado conocido).
- `normalize` / `to_json` / `from_json`: la ida y vuelta por JSON devuelve un pedido igual.
- `payout(order, now_min)`: la paga entera, o −25 % si `now_min > due_min`.
- Los 7 estados son `STATE_*` (los de D-0210). Las transiciones válidas las pone `OrderBook`, no esta clase.
**Test** `test_order`: junta repetidos y calcula `due_min` y `pay`; `validate` acepta uno bueno y nombra
cada problema de uno roto; JSON de ida y vuelta igual al original; `payout` a tiempo y tarde.
**Hecho cuando:** el test pasa.

### D-0806 · Requisitos de pedido — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `OrderRequirement` (`scripts/gameplay/business/order_requirement.gd`) + 6 `.tres` en `data/order_requirements/`; `test_order_requirements`.
**Depende de:** D-0802
**Qué:** recurso de datos (sin autoloads ni UI) con `id`, `display_key` (`WORLD_REQ_<ID>`), `required_seals`,
`min_quality` (0-100), `window_factor` (multiplica la ventana de 4 h) y `pay_bonus` (suma a la paga).
Los ids son los que `Order.requirements` ya admite. `window_min(base)` y `paid(pay)` aplican los dos números.

| id | sellos | calidad mín. | ventana | bonus |
|---|---|---|---|---|
| `fragile` | `fragile` | 70 | ×1 | +15 % |
| `cold` | `cold` | 0 | ×1 | +20 % |
| `gift` | `gift` | 0 | ×1 | +25 % |
| `urgent` | — | 0 | ×0,5 | +30 % |
| `heavy` | `heavy` | 60 | ×1 | +20 % |
| `no_bend` | `no_bend` | 0 | ×1 | +10 % |

**Test** `test_order_requirements`: los 6 archivos cargan con su id y clave, cada uno pide algo y paga un
bonus, `urgent` parte la ventana al medio, y `Order.make` acepta los seis ids.
**Hecho cuando:** el test pasa.

### D-0803 · Ritmo de llegada de pedidos — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `OrderRhythm` (`scripts/gameplay/business/order_rhythm.gd`) + `ORDER_HOUR_WEIGHTS` en `CompanyTuning`; `test_order_rhythm`.
**Depende de:** D-0202
**Qué:** funciones estáticas sin nodos. `orders_for_day(players)` = 6 + 2 por jugador, tope 16 (números de
`CompanyTuning`). `arrival_minutes(seed, players)` saca cada minuto de llegada de una curva por hora
(`ORDER_HOUR_WEIGHTS`, 08:00 a 18:59: apertura lenta, hora pico 10-12, bache al almuerzo, repunte a la
tarde, última hora fina) con un generador sembrado: misma semilla y tripulación, mismos minutos en todos los
peers. Ninguno llega después de las 19:00. `hourly_histogram(minutes)` cuenta pedidos por hora para
imprimir la curva; `weight_at(minute)` da el peso relativo de esa hora.
**Test** `test_order_rhythm`: cuenta por jugadores (con tope), determinismo y orden, rango horario, y la
curva sobre 400 días (pico 10-12, bache a las 13, última hora más fina que la apertura; imprime el histograma).
**Hecho cuando:** el test pasa y muestra la curva.

### D-0801 · Generador de pedidos del día — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `OrderGenerator` (`scripts/gameplay/business/order_generator.gd`); `test_order_generator`.
**Depende de:** D-0802, D-0803, D-0806, D-0205
**Qué:** funciones estáticas sin nodos. `generate_day(day_seed, day, players, zones, products, requirements,
max_items)` devuelve los pedidos del día ordenados por llegada. Los minutos de llegada salen de `OrderRhythm`;
con el mismo generador sembrado cada pedido saca zona (entre las zonas abiertas con `shipping_fee > 0`),
casa (`<zona>_house_1..12`), cliente (lista fija de 16 nombres hasta D-0840), 1 a `max_items` productos
distintos (los de la zona, `districts`, pesan ×3; 15 % de pedir 2 unidades) y requisitos: los que implican los
productos (frágil → `fragile`, frío → `cold`) y, con 20 % de chance, uno de capricho (`gift`, `urgent`,
`no_bend`). La ventana se achica al requisito más justo (`urgent` = ×0,5) y la paga suma cada bono. El que
llama pasa los catálogos ya cargados y las zonas abiertas hoy, así la clase no sabe de `CompanyState`.
**Test** `test_order_generator`: determinismo (misma semilla igual, otra distinta, tripulación distinta),
un pedido válido por minuto de llegada con ids únicos, solo zonas abiertas y ninguna sin entregas, requisitos
por producto, ventana y paga con bono, tope `max_items` y casos vacíos.
**Hecho cuando:** misma semilla, mismos pedidos; el test pasa.

### D-0804 · Tablero de pedidos en el galpón — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `OrderBoard` (`scripts/gameplay/business/order_board.gd`) + `OrderBoardPanel` (`scripts/ui/order_board_panel.gd`); `test_company_order_board`. Falta colgarlo en una pared del galpón (D-0804.b, junto con la mesa 3D).
**Depende de:** D-0210 (OrderBook), D-0802
**Qué:** `OrderBoard.rows(orders, now_min, products)` (estático, sin nodos) recibe los pedidos de
`OrderBook.to_dict()["orders"]` y devuelve una fila por pedido: cliente, dirección (la de `OrderLabel`),
productos con nombre, requisitos (claves `WORLD_REQ_*`), minutos que quedan, paga, estado con su clave de
texto y su marca. Orden: atrasados arriba, después por menos tiempo que queda; los cerrados (entregado,
fallido, cancelado) al final, solo los 3 más nuevos. `OrderBoardPanel.refresh(rows)` dibuja una tarjeta por
pedido (hasta 8, después "Y N más"). Cada estado tiene marca además del color (`○ ◐ ● ! ✓ ✗ –`), así se
lee sin color. Solo muestra: sin foco ni input, igual que la hoja de la mesa; el cliente dibuja lo que el
anfitrión le replica.
**Test** `test_company_order_board`: orden y recorte de las filas, datos de cada fila, marca y clave por
estado, entregado nunca atrasado, entrada rota ignorada, panel vacío / lleno / "Y N más" / inglés, claves
en los dos idiomas.
**Hecho cuando:** el test pasa. La captura legible la toma `revisor-visual` cuando el tablero esté en una
pared (D-0804.b).

### D-0805 · Impresora de pedidos — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `OrderPrinter` (`scripts/gameplay/business/order_printer.gd`) + `PRINTER_TRAY_MAX` y `SHEETS_IN_HAND_MAX` en `CompanyTuning`; `test_order_printer`. Falta el objeto en el galpón (D-0805.b: máquina, bandeja y gesto de tomar/dejar la hoja).
**Depende de:** D-0802, D-0714
**Qué:** estado puro (`RefCounted`, sin nodos), así host y clientes aplican las mismas llamadas. Una hoja es solo el
id de su pedido (lo que dice lo arma `OrderSheet`). `feed(orders)` imprime una hoja por pedido abierto o atrasado
que nunca se imprimió, en orden de llegada, mientras la bandeja tenga lugar (4); con la bandeja llena la impresora
"se atasca" y los pedidos esperan (`pending`) hasta que alguien saca una hoja. `take(id, holder)` pasa la hoja de
la bandeja a una persona (hasta 3 a la vez), `put_on_table(id, holder, mesa)` la deja en una mesa de armado (una
por mesa) y `clear_table` la retira al despachar. Cada pedido se imprime una sola vez. `to_dict` / `from_dict`
para guardar y replicar.
**Test** `test_order_printer`: imprime abiertos y atrasados una vez y en orden, atasco y reanudación, límites de mano
y de mesa, solo quien la tiene la deja, ida y vuelta por JSON.
**Hecho cuando:** hoja aparece y se puede llevar a la mesa (la lógica, en este PR; el objeto 3D, en D-0805.b).

### D-0807 · Vencimiento del pedido y penalidad por tardanza — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `OrderBook.abandon()` + `OrderPenalties.abandoned()` + `ORDER_ABANDON_MIN` y `ABANDONED_REPUTATION` en `CompanyTuning`; `test_order_book` y `test_order_penalties` ampliados. Lo que ya existía (D-0210, D-0506): `expire()` pasa a `late` y `Order.payout` cobra −25 %. Falta el reloj que llame a `expire`/`abandon` y la barra de ventana en la hoja (D-0807.b, con el objeto 3D de D-0805.b).
**Depende de:** D-0802, D-0210
**Qué:** un pedido atrasado que **no salió a la ruta** (`late_from != out`) lo abandona el cliente `ORDER_ABANDON_MIN`
(240, una ventana más) después de su `due_min`: pasa a `failed`, paga 0 y cuesta `ABANDONED_REPUTATION` (−3,
tope `PENALTY_REPUTATION_CAP`). Uno que ya va en camino no se abandona: se cobra con la penalidad de siempre.
`expire()` guarda en el pedido de qué estado vino (`late_from`, también en `to_dict`/`from_dict`).
`OrderPenalties.abandoned(order)` devuelve el veredicto `{pay: 0, kinds: [abandoned], reputation}`.
**Test:** `abandon` no actúa en el minuto límite, falla a los atrasados fuera de ruta y no al que está en
camino, no repite, sobrevive a guardar/cargar; veredicto de `abandoned`.
**Hecho cuando:** el test pasa.

### D-0808 · Asignar pedido a una caja — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `OrderBoxLink` (`scripts/gameplay/business/order_box_link.gd`) + `OrderBook.unpack`; `test_order_box_link`. Falta que la mesa 3D lo llame al cerrar la caja (D-0808.b, junto con el objeto de la mesa).
**Depende de:** D-0210, D-0707
**Qué:** funciones estáticas sobre el `OrderBook`; el vínculo vive en el pedido (`box_id`, estado `PACKED`), no en una tabla aparte, así host, clientes y save coinciden. `assign(book, order_id, box_id, box)` exige pedido abierto o atrasado, caja con cinta y con la etiqueta de ese pedido (D-0707), y que la caja no esté ya atada a otro pedido; devuelve `OK` o el motivo (`unknown_order`, `order_not_waiting`, `box_not_taped`, `label_mismatch`, `box_taken`). El contenido no se revisa acá: una caja equivocada se ata igual y paga 0 en la puerta (D-0712). `order_of_box` busca el pedido de una caja y `release` (`OrderBook.unpack`) lo devuelve a abierto, o a atrasado si ya venció, cuando la caja se abre o se desarma (D-0719).
**Test** `test_order_box_link`: ata abierto y atrasado, cada rechazo sin cambiar nada, caja ocupada, búsqueda por caja, liberar y volver a atar.
**Hecho cuando:** test (la lógica, en este PR; el llamado desde la mesa, en D-0808.b).

### D-0812 · Tamaño de pedidos de los primeros días — B · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `OrderGenerator.items_cap_for_day(day)` + `ORDER_EARLY_DAYS` y `ORDER_ITEMS_EARLY_MAX` en `CompanyTuning`; `generate_day` toma ese tope cuando `max_items` es 0 (el valor por defecto); `test_order_generator` ampliado.
**Depende de:** D-0801
**Qué:** los días 1 a 3 los pedidos piden 1 o 2 productos distintos; del día 4 en adelante, hasta 3 (`ORDER_ITEMS_MAX`). Pasar `max_items` explícito sigue mandando.
Decisión: tres días de rampa (coincide con la primera semana de aprendizaje del galpón) y tope 2, no 1, para que armar una caja con dos productos se vea desde el día 1. Cantidad por producto sin cambios (15 % de pedir 2 unidades).
**Test** `test_order_generator`: topes por día, días 1-3 nunca superan 2 productos y llegan a 2, un `max_items` explícito pisa el tope del día.
**Hecho cuando:** el test pasa. La sim de balance con 1-8 jugadores es D-0844.

### D-0809 · Asignar caja a salida/vehículo — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — fusionada en D-0716 (`DispatchZone`) y D-0717 (`DispatchLoading`); sin código nuevo.
**Depende de:** D-0716, D-0717
**Qué:** el vínculo pedido-caja es D-0808 (`OrderBoxLink`); la caja sellada y quieta en la zona de salida queda asociada a esa salida (`DispatchZone.update_box`) y se le asigna vehículo al cargarla (`DispatchLoading.load_vehicle` → `CompanyTrips.stage_cargo`, que pasa el pedido a `OUT` al cruzar el portón). Una tarea aparte repetiría esa lógica.
Decisión: fundirla, como recomendó la revisión del 2026-10-19 (`docs/auditorias/2026-10-19-revision.md`, punto 4 de lo urgente), en vez de crear otro objeto que asigne cajas a salidas.
**Test:** `test_dispatch_zone` y `test_dispatch_loading` (ya existen).
**Hecho cuando:** esos tests pasan.

### D-0811 · Pedidos imposibles hoy quedan en espera — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-21, PR #580)** — `OrderWaiting` (`scripts/gameplay/business/order_waiting.gd`); `test_order_waiting`. Falta mostrar "en espera" en el tablero y la hoja (D-0811.b, con D-0612).
**Depende de:** D-0210, D-0211, D-0613
**Qué:** un pedido que el galpón no puede cubrir **no falla ni se esconde**: sigue `open` en el `OrderBook` (vence y se abandona con su reloj de siempre) y se marca "en espera" con lo que le falta. No hay estado nuevo: es una clasificación derivada del stock, así no cambia el guardado ni la red.
- `OrderWaiting.classify(inventory, orders)` → `{ready: [ids], waiting: {id: {producto: faltan}}}`. Reparte el stock libre (todo menos lo sellado en cajas, como `StockAlert`) entre los pendientes por `due_min` y después por id: dos pedidos por la última gallina no quedan ambos "listos".
- `can_cover` / `missing_for`: un pedido solo, sin repartir.
- `unblocked_by(inventory, orders, incoming)`: los que esperan y el camión en camino desbloquea.
**Test:** listo vs. en espera con lo que falta; el más urgente se queda con la última unidad; lo sellado, lo armado y lo cerrado no cuentan; líneas repetidas suman; `unblocked_by` no toca el inventario real.
**Hecho cuando:** el test pasa.

### D-0813 · Pedidos replicados en red — A · Sonnet 5.5 · high · Aviso: sí (`network_manager.gd`) · F1
**[x] Hecho (2026-10-22, PR pendiente)** — D-0813.0 (la red: `CompanyOrdersNet`, eventos `order_added` / `order_expired`, parte `orders` del snapshot, protocolo 41) y D-0813.1 (el mundo de la empresa los juega: plan en el `OPENING` con la semilla de la empresa, `poll` en el `BusinessTick`, `EventBus.order_added` en cada peer, poda de los cerrados al abrir el día, `MAX_ORDERS` 256). Revisar: [`revisar/D-0813.md`](../revisar/D-0813.md) y [`revisar/D-0813.1.md`](../revisar/D-0813.1.md).
**Depende de:** D-2001 (contrato), D-2003 / D-2004 (`CompanyNet`, snapshot), D-0210 (`OrderBook`), D-0801 / D-0803 (generador y ritmo), D-0807 (vencimiento)
**Qué:** el libro de pedidos es el mismo en todos los peers y solo lo escribe el host (contrato `diseno/red-autoridad.md`, fila "Fuera de las 20" y §10).
- **Eventos sin petición** (el cliente no tiene ningún `kind` que toque el libro), por `CompanyNet.publish()`: `order_added {order}` (el pedido entero de `Order.normalize()`, estado `open`) y `order_expired {order: id, minute}` (pasa a LATE con `late_from`, `OrderBook.expire_one()`). Cada peer, el host también, los aplica en orden con el mismo código.
- **El host decide:** `plan_day(seed, day, players, zones, products, requirements, company)` arma el plan con `OrderGenerator` (minutos de `OrderRhythm`); `poll(net, minuto)` publica los que llegaron, del más viejo al más nuevo, y después un vencimiento por cada pedido que pasó su `due_min` (`OrderBook.overdue()`). El plan no sale del host.
- **Validación (regla 5)** de cada pedido y del libro del snapshot: claves exactas, tipos, textos de hasta 64, productos y requisitos del catálogo sin repetir, 1 a 3 productos, cantidades 1..24, minutos enteros con `created_min < due_min`, paga 0..10⁹, estado conocido, a lo sumo `MAX_ORDERS` = 256 pedidos (4096 hasta D-0813.1). Un pedido repetido o un vencimiento que no corresponde no se aplica: el host no lo publica (sin gastar `seq`) y un cliente que lo recibe pide snapshot.
- **Join tardío y huecos:** parte `orders` del snapshot (`OrderBook.to_dict()`), que `CompanyNet` suma sola.
- Decisión: `order_expired` lleva `minute` y no `penalty` (D-0807: el atrasado se cobra con −25 % al entregarlo; vencer no cobra ni libera nada todavía). El abandono (FAILED y reputación) como evento queda para D-0807.b.
- Decisión: viaja el pedido entero (380 a 550 bytes) y no la semilla, así ningún cliente depende de tener los mismos catálogos, zonas, tripulación y plata que el host.
- Decisión: `company_net.gd` no entraba en las 1000 líneas de gdlint: el cuerpo de `_lookup_station` pasó a `CompanyAsk.station_of()` (queda en 996).
- Decisión: `poll()` saca un pedido del plan recién cuando su evento salió; uno que nunca entraría (`order_ok()` lo rechaza o su id ya está en el libro) se descarta con un aviso, y con el libro lleno, un evento aplicándose, sin inventario o con `publish()` rechazado corta y reintenta en el próximo `poll()`.
- Decisión: la zona tiene que ser del catálogo (`data/zones/`) y la casa una del mapa (`HouseAddresses`) o `<zona>_house_<n>` de esa misma zona, con `n` de 1 a 12.
- Decisión: `expire_one()` deja el minuto del libro en el del evento, como `expire()`: los minutos cuentan desde la medianoche y un día nuevo los baja.
- [x] **D-0813.0** La red: `CompanyOrdersNet` con el libro, el plan y los dos eventos, la parte del snapshot, `PROTOCOL_VERSION` 41 y el test de red.
- [x] **D-0813.1** (2026-10-22) El mundo juega los pedidos: el host planea cada día en su `OPENING` con la semilla de la empresa y los trae en el `BusinessTick` a `shed_minute()` (`CompanyDayOrders`), cada peer emite `EventBus.order_added` desde `event_applied`, el día nuevo poda los cerrados en cada peer (`prune_closed()`), `MAX_ORDERS` 256, sin cambio de protocolo; `CompanyTrips` sigue con su libro (el bot le copia los pedidos).
**Test** `test_company_orders_world` (D-0813.1): el plan del día con la semilla de la empresa (igual al recargar el día interrumpido, otro con otra semilla), el paso `orders` del tick y sus fases, host + cliente por ENet con el día adelantado hora a hora (mismo libro, un `order_added` por pedido en cada peer, ninguno por vencimiento ni por snapshot) y la poda del día siguiente. `test_company_orders_net`: solo, misma semilla mismos pedidos y otra semilla otros, nada antes del primer minuto, un `order_added` por pedido en orden y un `order_expired` por pedido vencido (LATE desde `open`), cada uno una vez y chico; `poll()` no saca del plan lo que no salió (dentro de un evento, sin inventario, libro lleno) y descarta lo que nunca entraría; el host no publica pedidos mal formados (28 casos, zona y casa incluidas), con datos de más ni repetidos, ni vencimientos que no corresponden (6 casos); la parte `orders` del snapshot se aplica y se rechaza mal formada (14 casos) sin cambiar nada; por ENet, host + cliente con el mismo libro después de cada `poll`, el cliente no puede escribir (ni `publish`, ni `poll`, ni petición, ni `_apply_event` falsificado), un evento mal formado, repetido o un vencimiento falso que le llega no se aplica y vuelve al estado del host con el snapshot, y uno que entra tarde guarda lo que le llega antes de su snapshot, recibe el libro y sigue los eventos; los tres terminan con el mismo libro, `seq` y tipos. `test_order_book`: `overdue()` y `expire_one()`, también que el minuto del día 2 no queda en el del día 1.
**Hecho cuando:** test de red (la red, en este PR; que el mundo la llame, en D-0813.1).

### D-0814 · Notificación de pedido nuevo en el celular — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `OrderNotice` (`scripts/gameplay/business/order_notice.gd`) + `OrderNoticeFeed` (`order_notice_feed.gd`); `test_order_notice`. Falta enchufar el feed al `OrderBook` de `CompanyRoot` y a `HudNotices.toast` (D-0814.b, junto con la replicación de D-0813).
**Depende de:** D-0210, D-0802
**Qué:** el aviso que le llega al jugador cuando entra un pedido. `OrderNotice.message(orders)` (estático, sin nodos) devuelve `{text, priority}`: un pedido dice cliente y dirección (`OrderLabel`), varios juntos se funden en "N pedidos nuevos" (el día abre con varios a la vez). Prioridad 30 si alguno es `urgent`, 20 si no. `OrderNoticeFeed.watch(book)` escucha `order_added` y junta lo que llegue en el mismo frame en **un** aviso (`notice(text, priority)`); la HUD lo muestra como toast. Funciona igual en el anfitrión y en el espejo del cliente.
**Test** `test_order_notice`: texto de uno, de varios y sin dirección, prioridad urgente, entrada sin id, inglés, ráfaga en un frame = un aviso, `watch(null)` calla, claves en los dos idiomas.
**Hecho cuando:** el test pasa. El toast en pantalla se ve con `revisor-visual` cuando esté enchufado (D-0814.b).

### D-0815 · Pedido completado → cobro y reputación — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `OrderSettlement` (`scripts/gameplay/business/order_settlement.gd`) + `OrderBook.mark_delivered(..., pay_override)` + `CLEAN_DELIVERY_REPUTATION` en `CompanyTuning`; `test_order_settlement`. Falta llamarlo desde la puerta del cliente (`DeliveryHouse`, D-0340) y publicar `order_delivered` por `CompanyNet` (D-0815.b, con D-0813.1).
**Depende de:** D-0210, D-0502, D-0506, D-0507
**Qué:** el momento de entregar, en una sola función. `OrderSettlement.settle(book, company, order_id, box, now_min, broken, products)` arma el veredicto de `OrderPenalties` (caja equivocada, unidades rotas, tardanza, etiqueta de otro pedido), cierra el pedido en el libro con ese pago (`mark_delivered` con `pay_override`; `quality` = % del pago base cobrado), suma el pago a la plata (motivo `order_paid`), mueve la reputación (la pérdida del veredicto, o `+CLEAN_DELIVERY_REPUTATION` si no pasó nada) y paga la propina de `OrderTips`. Devuelve `{ok, paid, tip, reputation, kinds, lost}`; si el pedido no está en camino (abierto, desconocido, ya cerrado) o falta libro o empresa, `ok` es false y nada cambia.
**Test** `test_order_settlement`: entrega perfecta y rápida (pago + propina + reputación + libro mayor), perfecta y lenta (sin propina), los cuatro fallos (paga menos, nunca propina, reputación según el caso), doble cobro, pedido abierto, desconocido, sin libro ni empresa.
**Hecho cuando:** el test pasa (la lógica, en este PR; el enchufe a la puerta, en D-0815.b).

### D-0816 · Calificación del cliente (1-5 estrellas) en la puerta — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `OrderRating` (`scripts/gameplay/business/order_rating.gd`) + `stars` en el resultado de `OrderSettlement.settle` + constantes `STARS_*` en `CompanyTuning` + claves `UI_ORDER_STARS_1..5`; `test_order_rating` (y `test_order_settlement` ampliado). Falta guardar la calificación en el pedido del libro (to_dict/from_dict y snapshot de D-0813: D-0816.b), llamarla desde la puerta del cliente y publicarla por `CompanyNet` (D-0815.b), y la reacción en la puerta (D-0817).
**Depende de:** D-0815
**Qué:** la nota del cliente al recibir la caja. `OrderRating.stars(result)` (estático, sin nodos) toma el resultado de `settle()` y devuelve 1 a 5: entrega sin fallos y con propina (rápida) = 5, sin fallos y sin propina (lenta) = 4, solo tardanza o solo etiqueta de otro pedido = 3, producto roto = 2, caja equivocada = 1; con varios fallos manda el peor. Si el resultado no es `ok` devuelve 0 (no hay nada que calificar). `label_key(n)` / `label(n)` dan la palabra (Pésima, Mala, Regular, Buena, Excelente) por `tr()`. `settle()` suma `stars` a su resultado. Es solo información: no mueve plata ni reputación (no se puede farmear). Los números salen de `CompanyTuning` (`STARS_*`).
**Test** `test_order_rating`: un caso por estrella 1 a 5, combinaciones de fallos (el peor manda, sin importar el orden), resultado no ok o vacío = 0, `settle()` informa las mismas estrellas en 8 entregas, calificar no toca plata, reputación, libro mayor, libro de pedidos ni el resultado, etiquetas en los dos idiomas. `test_order_settlement`: `stars` en la entrega perfecta, la lenta, los cuatro fallos y los casos no entregables.
**Hecho cuando:** el test pasa (la lógica, en este PR; guardarla en el libro y mostrarla en la puerta, en D-0816.b y D-0817).
- [ ] **D-0816.b** (`constructor-progresion`, low) Guardar `stars` en el pedido cerrado (`OrderBook.mark_delivered` + `to_dict`/`from_dict` + la validación de `CompanyOrdersNet`, que hoy solo copia `quality`, `paid` e `intact`) y publicarla en `order_delivered` junto con D-0815.b. No se hizo acá porque cambia el formato del snapshot de D-0813 (red y guardado).

### D-0817 · Reacción del cliente en la puerta según calificación — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `OrderDoorReaction` (`scripts/gameplay/business/order_door_reaction.gd`) + `REACTION_*` en `CompanyTuning` + claves `WORLD_DOOR_CHEER_1..3` / `WORLD_DOOR_SHRUG_1..2`; `test_order_door_reaction`. Falta que la puerta (`DeliveryHouse`) la llame y reproduzca el gesto (D-0817.b, junto con D-0815.b).
**Depende de:** D-0816
**Qué:** funciones estáticas sin nodos. `react(result, client, seed, house)` toma el resultado de `OrderSettlement.settle` y devuelve `{reaction, stars, gesture, line}`: 4-5 estrellas = `cheer` (gesto `wave`), 3 = `shrug`, 1-2 = `angry` (gesto `fume`). `line` es una **clave** de traducción (el texto no viaja): cheer y shrug sacan de dos pozos genéricos, el enojo reusa la voz del cliente de `ClientComplaints.pick_line` (`wrong` si la caja era equivocada, si no `ruined`). Misma semilla y casa, misma línea en todos los peers. No mueve plata ni reputación. Umbrales en `CompanyTuning`.
**Test** `test_order_door_reaction`: umbrales por estrella y fuera de rango, un gesto distinto por reacción, las líneas de enojo de los 10 clientes (caja equivocada gana sobre roto), pozos genéricos deterministas y sin huecos, `react` de punta a punta sin tocar el resultado, claves en los dos idiomas.
**Hecho cuando:** 3 reacciones con test (la lógica, en este PR; la animación y el enchufe a la puerta, en D-0817.b).
- [ ] **D-0817.b** (`constructor-mundo`, medium) `DeliveryHouse` llama `OrderDoorReaction.react` con el resultado de `settle()` y muestra la línea (globo o `HudNotices`) y el gesto; la animación del cliente es del `animador`. Depende de D-0815.b.

### D-0820 · Datos de 40 pedidos plantilla por distrito — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — `OrderTemplate` / `OrderTemplateSet` / `OrderTemplateCheck` (`scripts/gameplay/business/`) y `data/order_templates/centro.tres` y `campo.tres` con 40 plantillas cada uno; `test_order_templates`. Falta que `OrderGenerator` las use (D-0820.b).
**Depende de:** D-0801, D-0806, D-0116
**Qué:** una plantilla es un pedido sin cliente, casa ni minuto: productos con cantidad (1-3 productos distintos, 1 o 2 unidades) y los requisitos, los que implican los productos (frágil, frío) más, a veces, un capricho (regalo, urgente, no doblar). El cliente, la casa y la hora siguen saliendo de la semilla. Un archivo `.tres` por zona (`OrderTemplateSet`, 40 `OrderTemplate`). `OrderTemplate.to_order()` arma el pedido con las reglas de paga y ventana de `OrderGenerator`. `OrderTemplateCheck.problems()` valida: 40 por zona, una sola colección por zona, ids únicos, productos y requisitos del catálogo, cantidades, al menos un producto de la zona, requisitos implícitos presentes, sin plantillas repetidas.
- Decisión: solo las zonas que hoy reparten (`shipping_fee > 0`: Barrio Centro y Campo). Las demás zonas reciben su archivo cuando tengan productos y tarifa (grupos 13 a 17); el test exige un set por cada zona con tarifa, así que no se pueden olvidar.
- Decisión: mezcla 14 de 1 producto, 16 de 2 y 10 de 3 por zona, para que los primeros días (tope de 2) tengan de dónde elegir.
- Decisión: los `.tres` salieron de un generador con semilla fija, pero son datos a mano de ahí en adelante (se editan directo).
- [x] **D-0820.b** (hecho 2026-10-22, PR pendiente) `OrderGenerator.generate_day` recibe `templates` (zona → `OrderTemplateSet`) y las zonas con set toman productos y requisitos de una plantilla que entre en `items_cap_for_day`; sin set (o sin plantilla que entre) sigue el sorteo anterior. `CompanyOrdersNet.plan_day` carga los sets de `data/order_templates/`. Ampliado `test_order_generator`; el golden de D-0848 aún no existe.
**Test** `test_order_templates`: datos sin problemas, 40 por zona con tarifa, mezcla de tamaños y caprichos, `to_order` válido, y el validador atrapa 9 clases de error.
**Hecho cuando:** `.tres` validados.

### D-0851 · Cierre del día para los pedidos — A · Opus 5.5 · medium · Aviso: sí (protocolo 52) · F1
**[~] Hecho en parte (2026-10-22, PR pendiente)** — .1, .2, .3 y el aviso de las 20:00 de .4: `order_closed` (protocolo 52), `OrderDayClose`, `CompanyTrips.day_open` / `DAY_CLOSED`, el cierre en `DayCycle`, `abandon()` en el reloj de pedidos; `test_company_day_close_orders`. Falta la tardanza con la hora del galpón al entregar (.4, espera a D-0815.b).
**Depende de:** D-0136 (diseño), D-0807, D-0813.1, D-0253, D-0302
**Qué:** las reglas 2, 4, 6, 7, 8 y 10 de [clientes.md](../diseno/clientes.md), en el host y con un evento de pedido nuevo.
- [x] D-0851.1 `CompanyTrips.day_open` (`Callable`, como `minute_now`): en `CLOSING` `departure_verdict` niega con
  `DAY_CLOSED` y el texto `UI_COMPANY_GATE_DAY_CLOSED`; un vehículo que cruza rechazado en `CLOSING` no cuenta
  para que el día pase a `SUMMARY`.
- [x] D-0851.2 `CompanyDayOrders.poll` sigue en `CLOSING` sin sumar pedidos: publica `order_expired` y el abandono
  (D-0807) con `shed_minute()`.
- [x] D-0851.3 `OrderBook.close_day(early: bool)`: lo `late` → `failed` (`OrderPenalties.abandoned`), lo que está en
  ventana → `cancelled` sin costo (con `early`, también `failed`). Evento de cierre en `CompanyOrdersNet`
  (validado como los demás, regla 5); la reputación la aplica solo el host. `DayCycle.poll` lo llama en `CLOSING`
  cuando `trips_out() == 0`, y pasa a `SUMMARY` en el poll siguiente.
- [ ] D-0851.4 (a medias: el aviso `UI_COMPANY_DAY_CLOSING_ROAD` salió, como `depot_notice` en cada peer al pasar a `CLOSING`, porque el aviso "ya existente" no existía; la hora del galpón al entregar sigue abierta, la puerta no está enganchada) Al entregar, `mark_delivered` recibe `floori(shed_minute())` (con D-0815.b, que engancha la puerta);
  el aviso de las 20:00 suma `UI_COMPANY_DAY_CLOSING_ROAD` ("Los clientes reciben solo lo que ya está en camino").
- Decisión: `OrderBook.close_day(early)` de la subtarea es `OrderDayClose.close_day(book, minuto, early)` (y `closing_plan()` / `abandoned()`, que no tocan el libro): `OrderBook` ya está en el máximo de 20 métodos públicos de gdlint. El host publica un `order_closed {order, state}` por id; los peers aplican con `mark_failed()` / `cancel()`.
- Decisión: `order_closed` no lleva `minute` ni reputación; la reputación (`OrderPenalties.abandoned`, −3) la suma el host al publicar y el cliente la ve con el próximo snapshot (el test pide que solo cambie en el host). `PROTOCOL_VERSION` 52 (el 51 es del PR #694, D-0616.b): `test_protocol_version` falla en esta rama hasta que #694 entre.
- Decisión: el abandono (D-0807) queda enganchado en el mundo para todo el día (`OPENING`, `OPERATING` y `CLOSING`), no solo en `CLOSING`, desde `CompanyDayOrders.poll()` y no desde `CompanyOrdersNet.poll()` (así el test de D-0813 no cambia); no abandona lo que `CompanyTrips.carries()` dice que va en una salida, porque el libro compartido todavía no se entera de que un pedido salió.
- Decisión: el pedido que vuelve sin entregarse (`trip_closed`) se falla (−3) al volver (`CompanyOrdersNet.fail_returned()`, enganchado en `CompanyRoot`), no al cierre; el cierre solo ve lo que sigue vivo. Un vehículo que cruza de noche queda en `_night_out`: no se le niega dos veces, `refused_returned` al volver y no cuenta en `trips_out()`.
- Decisión: `DayCycle` cierra con el minuto del galpón (`floori(shed_minute())`), tarda un `poll` más antes de `SUMMARY` solo si cerró algo, e intenta hasta 3 veces (`MAX_CLOSE_TRIES`) antes de seguir con un error, para que un libro trabado no frene el día. `early` es de `close_early()` y se limpia en cada apertura.
- Abierto: entregar en el libro compartido (D-0815.b debe publicar la entrega como evento, si no el cierre la da por no entregada); la hora del galpón en `mark_delivered`; el `HUD` del cliente no ve la reputación nueva hasta el snapshot.
**Test** `test_company_day_close_orders`: un día que cierra a las 20:00 con un pedido vencido, uno en ventana, uno
que vence durante `CLOSING` y uno que volvió sin entregarse da `failed` −3, `cancelled` 0, `failed` −3 y −3; el
mismo día cerrado antes da todo `failed`; un vehículo que sale después de las 20:00 es rechazado y el resumen no
lo espera; el día siguiente abre con el libro vacío; host y cliente por ENet terminan con el mismo libro y la
reputación solo cambia en el host. `auditor-red` antes del PR.
**Hecho cuando:** el test pasa.
