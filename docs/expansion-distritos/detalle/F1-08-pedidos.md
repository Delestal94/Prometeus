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
