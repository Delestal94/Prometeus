# Protocolo 33: soltar unidades al piso y lo que suelta un cliente que se cae (D-2006)

**Fecha:** 2026-10-12 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 33** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su
  línea del historial. **Cambió el protocolo** aunque no hay RPC nuevo ni firma distinta: `CompanyNet._request`
  acepta un tipo nuevo (`units_drop`), los `units_moved` hacia `floor:<n>` llevan `pos` y el snapshot una
  clave nueva (`floor`). Un cliente con 32 y un host con 33 no se conectan (error de versión en el menú).
- **`scripts/core/company/company_net.gd`**: petición `units_drop` `{product, qty, pos: Vector3, rid}`,
  **crítica** (usa la reserva de `RpcGuard.allow_critical_request`), por el `_request` de siempre
  (`any_peer`, `reliable`, canal 0, valida remitente y presupuesto). Lo nuevo y público: `UNITS_DROP`,
  `FLOOR_PREFIX`, `DROP_REACH`, `floor_bundles` y `drop(product, qty, pos)`; `SNAPSHOT_KEYS` suma `"floor"`
  (una parte de `add_snapshot_part()` ya no puede usar esa clave). Al irse un peer (`NetworkManager.peer_removed`,
  conectado por camino, o `multiplayer.peer_disconnected`) el host suelta lo que tenía en `hands:<peer>`
  en el piso, donde estaba su jugador. `units_take` acepta un bulto `floor:<n>` como estación; `units_store`
  en un bulto se rechaza con `no_station`. Nada de lo que ya existía cambió de firma.
- **`scripts/core/company/floor_bundles.gd`** (nuevo, `class_name FloorBundles`, datos puros): dónde está
  cada bulto del piso, igual en todos los peers.
- Contrato actualizado: `docs/expansion-distritos/diseno/red-autoridad.md` §7.
- Tests: `test_company_rejoin` (nuevo); `test_company_late_join` cambia la clave de su parte de prueba
  (`floor` → `tables`).

## Qué tiene que hacer Slatex

Nada obligatorio. Para el jugador que suelta unidades en el modo Empresa: llamar `net.drop(product, qty,
pos)` (no tocar el `Inventory`) y dibujar los bultos con `net.floor_bundles` al recibir `event_applied` y
`company_state_restored`. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 34.
