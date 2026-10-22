# Protocolo 41: los pedidos del día por red (D-0813)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 41** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea del
  historial. `main` ya tenía el 39 (D-0610.b) y el PR abierto #606 (D-0302.2) usa el 40, así que el 40 queda en el
  historial como salteado acá; el que de los dos se mezcle segundo conserva la línea del otro (`docs/convenciones-godot.md` §6). Ninguna firma ni RPC de `NetworkManager` / `NetSession` cambió y `modules/net_session/` no se tocó.
  **Cambió el protocolo** aunque no hay RPC nuevo: `CompanyNet._apply_event` acepta dos tipos nuevos,
  `order_added` y `order_expired` (canal confiable de siempre, con `seq`), y el snapshot (`_snapshot`, confiable)
  suma la parte `orders` con el libro de pedidos. Un cliente con 39 o 40 y un host con 41 no se conectan (error de
  versión en el menú); con el mismo número viejo el cliente descartaría los eventos de pedidos y se quedaría sin
  libro.
- **`scripts/core/company/company_orders_net.gd`** (nuevo, `class_name CompanyOrdersNet`, `RefCounted`): el
  `OrderBook` que comparten todos los peers (`CompanyNet.orders.book`), el plan del día del host (`plan_day()`,
  con `OrderGenerator` y la semilla) y `poll(net, minuto)`, que publica los pedidos que llegaron y los vencidos;
  cada peer los aplica en `apply()` validando los datos. `CompanyNet` suma `orders` y los dos `kind` a
  `EVENT_KINDS` y `HOST_EVENT_KINDS` (ninguno de petición: un cliente no puede escribir el libro).
- Agregados sin cambiar firmas: `OrderBook.overdue(now_min)` y `OrderBook.expire_one(id, now_min)` (`expire()`
  hace lo mismo que antes), `CompanyNet.is_applying()` y `CompanyAsk.station_of()` (el cuerpo de
  `CompanyNet._lookup_station`, que salió para que `company_net.gd` entre en las 1000 líneas de gdlint).
- Contrato actualizado: `docs/expansion-distritos/diseno/red-autoridad.md`, fila "Fuera de las 20" y §10. El
  vencimiento lleva `{order, minute}` y no `penalty` (D-0807).
- Test nuevo: `test_company_orders_net`; `test_order_book` ampliado.

## Qué tiene que hacer Slatex

Nada obligatorio: el mundo todavía no publica pedidos (D-0813.1). Para el tablero o la hoja cuando se cuelguen
(D-0804.b, D-0805.b): leer `net.orders.book` (`to_dict()["orders"]` es lo que toma `OrderBoard.rows`) y redibujar
en `net.event_applied` con los `kind` de `CompanyOrdersNet.EVENT_KINDS` y en `company_state_restored`; nunca
escribir el libro a mano. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 42.
