# Protocolo 29: `CompanyNet`, eventos de negocio del modo Empresa (D-2003)

**Fecha:** 2026-10-04 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 29** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea
  del historial. **Cambió el protocolo**: un cliente con 28 y un host con 29 no se conectan (error de versión
  en el menú).
- **`scripts/core/company/company_net.gd`** (nuevo, `class_name CompanyNet`): los tres RPC de negocio del modo
  Empresa, según `docs/expansion-distritos/diseno/red-autoridad.md`:
  - `_request(kind: StringName, data: Dictionary)`: `@rpc("any_peer", "call_local", "reliable")`, cliente →
    host. Pasa por `RpcGuard` (`allow_request`, `name_ok`, `dict_ok`), lista blanca de `kind` y `rid` entero;
    el actor es siempre el que lo manda.
  - `_apply_event(seq: int, kind: StringName, data: Dictionary)`: `@rpc("authority", "call_local",
    "reliable")`, host → cada peer listo (`NetworkManager.is_peer_ready()`), con `rpc_id`, nunca `.rpc()`.
  - `_rejected(rid: int, reason: StringName)`: `@rpc("authority", "call_remote", "reliable")`, host → solo el
    que pidió. No cambia estado.
  Todos en el canal 0. `_snapshot` (D-2004) todavía no existe: cuando llegue, sube el protocolo otra vez.
- **`scripts/gameplay/company_root.gd`**: la raíz del modo Empresa suma un hijo `CompanyNet` que arranca con el
  stock de `CompanyState`. Entrega y Endless no cambian.
- **`scripts/core/company/company_tuning.gd`**: `HAND_MAX_UNITS = 4` (unidades de un producto en la mano).
- Tests: `test_company_net` (nuevo, dos peers ENet en un proceso) y `test_company_root` (el hijo nuevo).

## Qué tiene que hacer Slatex

Nada. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 30, con su entrada en el historial.
