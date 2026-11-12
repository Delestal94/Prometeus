# Protocolo 68: la puerta del cliente cobra en el mundo Empresa (D-0340, D-0815.b)

**Fecha:** 2026-11-11 · **De:** Nacho (red, pedidos, mundo) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 68** (`scripts/core/network_manager.gd`, zona compartida): la constante y su línea del historial.
  **Cambió el protocolo** sin RPC nuevo: `CompanyNet._apply_event` acepta un tipo nuevo solo del host,
  `order_delivered {order, package_id, paid, tip, stars, quality, intact, penalties, reputation}`. Un cliente viejo con un
  host nuevo no se entiende. Si otro PR toma el 68 antes (el palet, D-0607.c), este pasa al 69: cambian la constante, la línea
  del historial, este aviso y `revisar/D-0340.md`.
- **`DeliveryHouse.door_check`** (`scripts/gameplay/route/delivery_house.gd`): un `Callable` opcional. Sin él la casa del
  reparto se porta exactamente como antes (los tests `house`, `delivery`, `doorbell`, `results` y `package` siguen igual). Con
  él (lo pone `CompanyDoor` en el host del mundo Empresa) la casa no se traba: tocar sin caja solo suena y recibe pedidos
  seguidos. Se agregaron `outcome_for()` (estática) y se movieron a funciones el rechazo y el sonido del vecino, sin cambiar
  qué hacen.
- **`CompanyNet._apply_state`** (`scripts/core/company/company_net.gd`) le pasa ahora al libro de pedidos el inventario y la
  empresa (`orders.apply(kind, data, inventory, company)`), con argumentos por defecto.
- Archivo nuevo `scripts/gameplay/districts/company_door.gd` (`CompanyDoor`, hijo de `CompanyRoot` en cada peer) y
  `CompanyTrips.active_trips()`.
- `EventBus.order_delivered` (ya existía) ahora se emite en cada peer cuando se entrega un pedido de la empresa.

## Para tener en cuenta

- Nada de `scripts/ui/`, `player/` ni `package/` cambió. La caja se entrega con `DeliveryPackage.consume()` como en el reparto.
- La plata de la entrega llega a los clientes como `wallet_moved` justo después de `order_delivered`, y la reputación viaja
  absoluta en `order_delivered`.
