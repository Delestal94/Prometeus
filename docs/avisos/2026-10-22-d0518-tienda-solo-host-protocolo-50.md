# Aviso 2026-10-22 · la tienda de la empresa por red, solo compra el host (D-0518)

**Cambia el protocolo:** `PROTOCOL_VERSION` 49 -> 50 (`scripts/core/network_manager.gd`, zona compartida; solo la
línea del historial y la constante). Un cliente viejo con un host nuevo no se conecta (error claro de versión).
El PR #630 (D-0618.b) también usa el 46 sobre el 45: al mezclar `main` sube al siguiente libre
(`docs/convenciones-godot.md` §6.3).

Qué cambió en la red de la empresa (Nacho, `scripts/core/company/`):
- `CompanyNet`: pedido nuevo `shop_buy` {item, rid} y evento nuevo `shop_bought` {item, money, minute}. Ningún RPC
  nuevo (viajan por `_request` / `_apply_event`) y ninguna parte nueva del snapshot (lo que cambia una compra ya va
  en `company`). `var shop: CompanyShopNet` nuevo; `_receive` pide snapshot también con `shop.take_drift()`.
- `CompanyShopNet` (nuevo): el host comprueba con `CompanyShop.check()` y solo deja pasar su propia compra; cualquier
  otro peer oye `host_only`. Cada peer aplica el evento con `CompanyShop.buy()` desde el saldo del host.
- `CompanySnapshot`: `chunk_ok()` y `join()` nuevos, sacados tal cual de `CompanyNet._take_chunk()` para que
  `company_net.gd` no pase las 1000 líneas. Mismo comportamiento.
- `company_shop.gd`: solo el comentario de arriba (quién puede gastar).
- Contrato: `docs/expansion-distritos/diseno/red-autoridad.md`, fila 25 y §13.

**Para el PR #630 (D-0618.b)**, que también toca `company_net.gd`: al mezclar, `EVENT_KINDS` y la rama de
`_apply_state()` chocan en las líneas de `CompanySupplierNet.ORDERED` (quedan las dos: `CompanyPallets.DEPARTED` y
`CompanyShopNet.BOUGHT`). El archivo queda en 996 líneas; con las de #630 entra en 1000.

Para Slatex: nada que hacer. Ninguna firma cambió y no se tocó nada de su dominio. La futura pantalla de la tienda
(D-0511.2, `scripts/ui/`) pide con `CompanyNet.request(CompanyShopNet.BUY, {"item": id})` y muestra el motivo de
`request_rejected`: las claves `WORLD_SHOP_*` con `tr()` y `host_only` con un texto propio.
