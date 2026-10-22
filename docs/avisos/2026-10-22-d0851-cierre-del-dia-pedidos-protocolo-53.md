# Protocolo 53: el cierre del día para los pedidos (D-0851)

**Fecha:** 2026-10-22 · **De:** Nacho (red, pedidos) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 53** (`scripts/core/network_manager.gd`, zona compartida): la constante y su línea del historial.
  El PR abierto #694 (D-0616.b) usa el 51, así que el 51 falta en esta rama hasta que entre: `test_protocol_version` falla
  acá por eso y pasa al mezclar `main` (`docs/convenciones-godot.md` §6). **Cambió el protocolo** sin RPC nuevo:
  `CompanyNet._apply_event` acepta un tipo nuevo, `order_closed {order, state}` (`failed` o `cancelled`), host-only como
  `order_added` y `order_expired`. Un cliente con 50 y un host con 53 no se conectan.
- **Qué hace**: un pedido que termina sin entrega (el cliente se cansó una ventana después de vencer, la camioneta volvió
  con él, o el día terminó) se cierra en el libro de cada peer. La reputación (−3 por `failed`) la escribe solo el host.
- Archivos de zona compartida o ajena tocados: `scripts/core/network_manager.gd` (historial), `scripts/core/company/`
  (`company_net.gd`: el kind en `EVENT_KINDS` / `HOST_EVENT_KINDS`; `company_orders_net.gd`, `company_day_orders.gd`,
  `day_cycle.gd`: `is_day_closed()`, el cierre en `CLOSING` y el aviso de las 20:00 como `depot_notice`),
  `scripts/gameplay/districts/company_trips.gd` (`day_open`, `DAY_CLOSED`, `carries()`),
  `scripts/gameplay/company_root.gd` (engancha `day_open`, `trip_closed` → `fail_returned()` y el abandono), archivo
  nuevo `scripts/gameplay/business/order_day_close.gd`. Textos nuevos en `strings_ui.csv` (de Slatex):
  `UI_COMPANY_GATE_DAY_CLOSED` (lo muestra el tablero de despacho con `reason_text()` cuando la salida se niega de noche) y
  `UI_COMPANY_DAY_CLOSING_ROAD` (toast a las 20:00 por `depot_notice`).
- **Para quien muestre la reputación en un cliente**: la reputación nueva solo llega con el próximo snapshot (no hay evento
  de reputación). Si el HUD del cliente la muestra, hay que replicarla (tarea aparte).
- **Para quien enganche la puerta (D-0815.b)**: el libro compartido no sabe aún de entregas; cuando entregue tiene que
  publicar la entrega como evento, o el cierre del día la da por no entregada (`docs/expansion-distritos/diseno/red-autoridad.md` §14).
- Contrato: `red-autoridad.md`, fila "Un pedido termina sin entrega" y §14. Tests: `test_company_day_close_orders` (nuevo),
  `test_company_orders_world` ajustado (ya no quedan pedidos al abrir el día siguiente).
