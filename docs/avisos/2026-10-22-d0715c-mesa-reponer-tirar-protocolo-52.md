# Aviso 2026-10-22 · reponer la mesa y tirar la caja abierta por red (D-0715.c)

**Cambia el protocolo:** `PROTOCOL_VERSION` 50 -> 52 (`scripts/core/network_manager.gd`, zona compartida; solo la
constante y su línea del historial). Ningún RPC nuevo ni firma distinta, pero `CompanyNet._request` acepta dos tipos
nuevos y `_apply_event` dos más: un cliente con 50 y un host con 52 no se conectan (error de versión en el menú); con
el mismo número viejo el cliente descartaría esos eventos y quedaría desfasado. Al elegirlo no había PR abierto ni
rama de `origin` por encima de 50 (`docs/convenciones-godot.md` §6).

Qué cambió en la red de la empresa (Nacho, `scripts/core/company/`):
- `CompanyTableNet`: pedidos `box_restock` {station, supply, rid} y `box_discard` {station, rid}; eventos
  `box_restocked` {table, supply, count} y `box_discarded` {table, box, contents, to, pos (solo con `floor:<n>`)},
  todos por el canal confiable de siempre (`reliable`, con `seq`). Motivo de rechazo nuevo `supply_full`. Variables
  nuevas `short_of: Callable` (host, el gancho de `box_shortage`) y `bundles: FloorBundles`.
- `CompanyNet` (`company_net.gd`, queda en 997 de 1000 líneas): los cuatro `kind` en `REQUEST_KINDS` /
  `EVENT_KINDS`, una rama nueva de `_apply_state()` y `table.bundles = floor_bundles` en `_init()`. Nada más.
- Ninguna parte nueva del snapshot: insumos en `packing`, unidades en `inventory`, el bulto en `floor`.
- Contrato: `docs/expansion-distritos/diseno/red-autoridad.md`, filas 15a y 15b y §14.
- Test nuevo: `test_company_table_restock_discard` (puerto 24695).

Para Slatex: nada que hacer; no se tocó nada de su dominio. La mesa visible o su interfaz pide con
`net.request(CompanyTableNet.RESTOCK, {"station": id, "supply": &"tape"})` y
`net.request(CompanyTableNet.DISCARD, {"station": id})`, redibuja en `net.event_applied` (los `kind` de
`CompanyTableNet.EVENT_KINDS`) y muestra el motivo de `net.request_rejected` (`supply_full` necesita texto). Si una
rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 52.
