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
