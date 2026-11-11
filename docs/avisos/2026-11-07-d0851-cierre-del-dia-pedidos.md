# Protocolo 67: el cierre del día para los pedidos (D-0851)

**Fecha:** 2026-11-07 · **De:** Nacho (red, pedidos) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 67** (`scripts/core/network_manager.gd`, zona compartida): la constante y su línea del historial.
  **Cambió el protocolo** sin RPC nuevo: `CompanyNet._apply_event` acepta un tipo nuevo, `order_closed {order, state}`
  (`failed` o `cancelled`), solo del host como `order_added` y `order_expired`. Y `_held_here` acepta `cap` −1
  (`CompanyTripsView.DAY_CLOSED_CAP`): el vehículo se frenó porque el día cerró.
- **Qué hace:** un pedido que termina sin entrega (el cliente se cansó una ventana después de vencer, la camioneta volvió
  con él, o el día terminó) se cierra en el libro de cada peer. La reputación (−3 por `failed`) la escribe solo el host.
  Desde las 20:00 no sale nadie (`DAY_CLOSED`) y el libro no pasa pedidos al día siguiente.
- **Archivos de zona compartida o ajena:** `scripts/core/network_manager.gd`, `scripts/core/company/` (`company_net.gd`,
  `company_orders_net.gd`, `company_day_orders.gd`, `day_cycle.gd`), `scripts/gameplay/districts/company_trips.gd` y
  `company_trips_view.gd`, `scripts/gameplay/company_root.gd`, `scripts/gameplay/company_dispatch.gd`,
  `scripts/ui/dispatch_board_panel.gd`, archivo nuevo `scripts/gameplay/business/order_day_close.gd`. Textos nuevos en
  `strings_ui.csv` (de Slatex): `UI_COMPANY_GATE_DAY_CLOSED` (tablero de despacho y aviso del portón) y
  `UI_COMPANY_DAY_CLOSING_ROAD` (aviso de las 20:00 por `depot_notice`).

## Para tener en cuenta

- **Hasta que la puerta entregue (D-0340) cada pedido que sale cuesta −3 al volver:** no hay forma de entregar en el juego
  real y `trip_closed` lo da por no entregado (regla 7 de `clientes.md`).
- **La puerta (D-0340 / D-0815.b)** tiene que pasarle a `OrderSettlement.settle` `CompanyTrips.delivery_minute()`, no
  `minute()`, y publicar la entrega en el libro compartido, o el cierre del día la cobra como no entregada.
- **Reputación en un cliente:** llega con el próximo snapshot (no hay evento de reputación). Si el HUD del cliente la
  muestra, hay que replicarla (tarea aparte).
- `DayCycle` tarda un `poll` más de `CLOSING` a `SUMMARY` si cerró algún pedido.
- Lo cargado en un vehículo que no salió baja con `SUMMARY` (`CompanyTrips.drop_staged()`, señal `cargo_dropped`): solo host, sin
  evento. La caja sigue en el estante hasta que alguien la baje.
- `OrderDayClose.wire()` va antes de `CompanyTripsView.follow()` en `CompanyRoot`: si se invierten, el `trip_closed` falla el
  pedido sin reputación y `fail_returned()` ya no lo cobra.
- Contrato: `docs/expansion-distritos/diseno/red-autoridad.md`, fila "Un pedido termina sin entrega" y §17. Tests:
  `test_company_day_close_orders` y `test_company_day_close_world` (nuevos), `test_company_orders_world`, `test_company_solo_assists`, `test_company_bot_day` y
  `test_company_dispatch_panel` ajustados.
