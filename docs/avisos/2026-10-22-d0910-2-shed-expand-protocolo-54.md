# Aviso 2026-10-22 · ampliar el galpón por red, protocolo 59 (D-0910.2)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

**Cambia el protocolo:** `PROTOCOL_VERSION` 58 -> 59 (`scripts/core/network_manager.gd`, zona compartida: solo la
constante y su línea `## 59:` del historial). Un cliente con 58 y un host con 59 no se conectan (error claro de
versión); con el mismo número viejo el cliente descartaría `shed_expanded` y se quedaría con la grilla chica hasta
el próximo snapshot. Los PRs en vuelo #706 / #697 declaran 52 / 51: el que se mezcle después de este sube al
siguiente libre y corrige su línea (`docs/convenciones-godot.md` §6.3). Ninguna firma ni RPC de `NetworkManager` /
`NetSession` cambió y `modules/net_session/` no se tocó.

Qué cambió (Nacho, `scripts/core/company/` y `scripts/gameplay/`):
- `CompanyNet`: pedido nuevo `shed_expand` {stage, rid} y evento nuevo `shed_expanded` {stage, minute, money}, en
  las listas `REQUEST_KINDS` / `EVENT_KINDS` y en la rama de layout de `_apply_state()`. Ningún RPC nuevo (viajan por
  `_request` / `_apply_event`, confiables, con `seq`) y ninguna parte nueva del snapshot (`warehouse_stage` ya va en
  `company`). El archivo sigue en 996 líneas.
- `CompanyLayoutNet`: `EXPAND`, `EXPANDED`, `REASON_WRONG_STAGE`; `check()` y `apply()` con sus ramas. Solo el host
  amplía; cualquier otro oye `host_only`.
- `BuildLayoutSave.misfit(raw, stage)` nueva (misma pasada que `sanitize()`, que no cambia de comportamiento).
- `CompanyShed`: `OVERLAY_GROUP` nueva (los nodos de ese grupo sobreviven a `rebuild()`); las zonas, carros y lugares
  de palets del galpón por defecto se dibujan en cualquier etapa igual o más grande (antes solo en la 0).
- `ShedBuilder`: su cámara, grilla y fantasma entran a `CompanyShed.OVERLAY_GROUP` (antes cualquier evento de layout
  los liberaba con el modo abierto) y con `shed_expanded` / `shop_bought` el cursor toma la grilla nueva.
- Contrato: `docs/expansion-distritos/diseno/red-autoridad.md`, fila 26 y §15. Test nuevo:
  `test_company_shed_expand_net`.

Para Slatex: nada obligatorio, no se tocó nada de su dominio. Si una pantalla (tienda, D-0511.2, o un botón del modo
construcción) pide la ampliación: `CompanyNet.request(CompanyLayoutNet.EXPAND, {"stage": etapa_actual + 1})` y
mostrar el motivo de `request_rejected` (`host_only`, `no_money`, `max_stage`, `wrong_stage`, `fixed_area`,
`blocks_path`). Un nodo propio que cuelgue bajo `CompanyShed` y tenga que sobrevivir al redibujo va en
`CompanyShed.OVERLAY_GROUP`. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 60.
