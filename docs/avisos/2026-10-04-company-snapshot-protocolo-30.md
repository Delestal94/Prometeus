# Protocolo 30: snapshot del modo Empresa en `CompanyNet` (D-2004)

**Fecha:** 2026-10-04 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 30** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su
  línea del historial. **Cambió el protocolo**: un cliente con 29 y un host con 30 no se conectan (error de
  versión en el menú).
- **`scripts/core/company/company_net.gd`**: RPC nuevo
  `_snapshot(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray)`,
  `@rpc("authority", "call_remote", "reliable")`, host → un peer, canal 0 (el mismo que `_apply_event`, así
  llega en orden con los eventos). Guardas: `RpcGuard.from_host`, índices y tamaños acotados, `id` para
  descartar trozos viejos, `bytes_to_var` sin objetos. Funciones nuevas: `snapshot()`, `send_snapshot(peer)`,
  `apply_snapshot(data)`, `add_snapshot_part(key, take, put)`, `pack_snapshot()`, `unpack_snapshot()`,
  `stock_ok()`; señal nueva `company_state_restored(snapshot_seq)`; variable `company` (el nodo
  `CompanyState`). `grant_snapshot()` ahora además manda el snapshot. `CompanyNet` se conecta por camino a
  `NetworkManager.peer_level_ready` (no nombra el autoload). Nada cambió en la firma de lo que ya existía.
- **`scripts/gameplay/company_root.gd`**: le pasa `CompanyState` a `CompanyNet` (`net.company`).
- Tests: `test_company_late_join` (nuevo), `test_company_net` (la parte del hueco usa el snapshot real),
  `test_company_root` (el `company` pasado).

## Qué tiene que hacer Slatex

Nada. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 31, con su entrada en el historial.
