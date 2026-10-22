# Los pedidos entran en el mundo de la empresa y `EventBus.order_added` ya sale (D-0813.1)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **Sin cambio de protocolo** (`PROTOCOL_VERSION` no se tocó): ningún RPC, `kind` de `CompanyNet`, forma de datos ni
  sincronizador nuevo o distinto. `network_manager.gd` y `modules/net_session/` no se tocaron.
- **`scripts/core/event_bus.gd`** (zona compartida): solo el comentario de `order_added(order_id: StringName)`, que
  **ahora se emite**: `CompanyRoot` lo emite en cada peer, una vez por pedido y en el orden del host, desde
  `CompanyNet.event_applied` (evento `order_added`); un snapshot no lo emite, un vencimiento tampoco. La firma no
  cambió. Lo escucha `RunTelemetry` (ya contaba `order_added` del día).
- **`CompanyRoot`** (`scripts/gameplay/company_root.gd`): el host planea los pedidos de cada día nuevo en su `OPENING`
  y el `BusinessTick` suma el paso `orders` (después de `day_cycle`); nuevo `order_crew` (0 = la tripulación de la
  sesión) para que el bot del día planee para `--players`. Helper nuevo `CompanyDayOrders`
  (`scripts/core/company/company_day_orders.gd`).
- **Tablero de stock** (`scripts/gameplay/stock_board.gd`, solo el comentario; el cambio está en `CompanyRoot`): las
  marcas "Faltan N" ahora salen del libro que comparten todos (`CompanyNet.orders.book`), así que un cliente ve las
  mismas marcas que el host (antes no veía ninguna).
- Agregados sin cambiar firmas: `OrderBook.prune_closed()` y `CompanyOrdersNet.prune_closed()`; `DayCycle.apply_phase()`
  poda los pedidos cerrados al abrir un día nuevo. `CompanyOrdersNet.MAX_ORDERS` baja de 4096 a 256
  (`docs/decisiones/2026-10-22-pedidos-en-el-mundo.md`).
- Tests: `test_company_orders_world` nuevo; `test_company_bot_day` y `bot_company_day.gd` (el bot toma los pedidos
  del libro compartido); `test_company_stock_board`, solo el comentario.

## Qué tiene que hacer Slatex

Nada obligatorio. Para lo que muestre pedidos (D-0804.b tablero, D-0814.b aviso en el celular): escuchar
`EventBus.order_added` (presentación) o `net.event_applied` con los `kind` de `CompanyOrdersNet.EVENT_KINDS`, y
redibujar también en `company_state_restored`; **no** `OrderBook.order_added` del libro (sale adentro de la
aplicación del evento, donde no se puede pedir ni publicar). `OrderNoticeFeed.watch(book)` hoy escucha esa señal del
libro: al enchufarlo (D-0814.b) conviene pasarlo a `EventBus.order_added`.
