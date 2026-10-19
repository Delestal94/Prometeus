# Protocolo 36: la mesa de armado compartida por red (D-0715)

**Fecha:** 2026-10-19 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 36** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su
  línea del historial. **Cambió el protocolo** aunque no hay RPC nuevo ni firma distinta: `CompanyNet._request`
  acepta siete tipos nuevos (`box_start`, `box_place`, `box_take_out`, `box_fill`, `box_label`, `box_stamp`,
  `box_tape`), `_apply_event` siete (`box_started` … `box_sealed`), todos por el canal confiable de siempre
  (`reliable`, con `seq`), y el snapshot (`_snapshot`, confiable) suma la parte `packing` con las mesas. Un
  cliente con 35 y un host con 36 no se conectan (error de versión en el menú); con el mismo número viejo el
  cliente descartaría los eventos de la mesa y quedaría desfasado.
- **`scripts/core/company/company_table_net.gd`** (nuevo, `class_name CompanyTableNet`, `RefCounted`): valida
  en el host (`check()`) y aplica en cada peer (`apply()`) los pasos de la mesa; `CompanyNet` suma
  `table: CompanyTableNet` y los `kind`. **`scripts/core/company/company_snapshot.gd`** (nuevo,
  `CompanySnapshot`): el empaquetado del snapshot y los chequeos de lo que trae salieron de `company_net.gd`
  (que estaba al borde de las 1000 líneas); `CompanyNet.pack_snapshot`, `unpack_snapshot` y `stock_ok`
  siguen con la misma firma.
- Agregados sin cambiar firmas: `PackedBox.take_out(cell)` e `Inventory.unreserve(product, qty, order)`.
- Contrato actualizado: `docs/expansion-distritos/diseno/red-autoridad.md` §2 (filas 9 a 15) y §9.
- Test nuevo: `test_company_shared_table`; `test_company_layout_net` lee también las ramas `CompanyTableNet.*`.

## Qué tiene que hacer Slatex

Nada obligatorio. Para la mesa visible o su interfaz: pedir con `net.request(CompanyTableNet.PLACE,
{station, product, cx, cy, cz, rot: 0})` (o `START`, `TAKE_OUT`, `FILL`, `LABEL`, `STAMP`, `TAPE`), nunca
tocando el `PackingStation` a mano; leer la caja con `net.table.station_of(uid)` y redibujar en
`net.event_applied` (los `kind` de `CompanyTableNet.EVENT_KINDS`) y en `company_state_restored`; el motivo de
un rechazo llega por `net.request_rejected`. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 37.
