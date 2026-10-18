# Protocolo 34: el layout del galpón por red, solo lo construye el host (D-0910)

**Fecha:** 2026-10-18 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 34** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su
  línea del historial. **Cambió el protocolo** aunque no hay RPC nuevo ni firma distinta: `CompanyNet._request`
  acepta cuatro tipos nuevos (`layout_place`, `layout_move`, `layout_rotate`, `layout_sell`) y
  `_apply_event` tres (`layout_placed {…, minute, money}`, `layout_moved`, `layout_sold {uid, minute, money}`:
  la plata viaja absoluta, el saldo del host), todos por el canal confiable de siempre (`reliable`, con `seq`). Un cliente con 33 y un host con 34 no se conectan (error de versión en
  el menú); con el mismo número viejo un cliente descartaría los eventos de layout y quedaría desfasado.
- **`scripts/core/company/company_layout_net.gd`** (nuevo, `class_name CompanyLayoutNet`, `RefCounted`):
  valida en el host (`check()`) y aplica en cada peer (`apply()`) los cambios del layout. `CompanyNet` suma
  `build: CompanyLayoutNet` y los `kind` a `REQUEST_KINDS` / `EVENT_KINDS`; nada de lo que ya existía cambió
  de firma. **Solo construye el host**: la petición de un cliente se rechaza con `host_only`.
- **`scripts/gameplay/company_shed.gd`**: `follow(net)` nuevo (redibuja con cada evento de layout y con
  `company_state_restored`, y las etiquetas con `units_moved`). **`scripts/gameplay/company_root.gd`** lo usa
  y ya no redibuja el galpón por su cuenta.
- Contrato actualizado: `docs/expansion-distritos/diseno/red-autoridad.md` §2 (filas 21 a 24) y §8.
- Test nuevo: `test_company_layout_net`.

## Qué tiene que hacer Slatex

Nada obligatorio. Para el modo construcción (D-0917): el verde/rojo local con
`net.build.placement_for(CompanyState).preview(...)` y la colocación confirmada con
`net.request(CompanyLayoutNet.PLACE, {id, x, z, turns})` (o `MOVE`, `ROTATE`, `SELL` con `uid`), nunca
tocando `CompanyState.layout`; el motivo de un rechazo llega por `net.request_rejected`. Si una rama tuya
sube `PROTOCOL_VERSION`, la próxima libre es 35.
