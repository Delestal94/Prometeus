# Aviso: módulos portables, fase 2 — kit de red (2026-09-30)

Lo hizo Nacho (con Claude), PR `nacho/N-231-net-session` (N-231, `docs/modulos.md`). Zona compartida:
`network_manager.gd`, `event_bus.gd`, `proximity_voice.gd`, `net_stats.gd`, el overlay de red.

## Qué cambió

- Nace `do-not-drop/modules/net_session/`: `NetSession`, `NetEventBus`, `SteamVoice`, `NetStats` (movido
  desde `scripts/core/net_stats.gd`, misma clase) y `NetStatsOverlay` (base).
- `NetworkManager extends NetSession`, `EventBus extends NetEventBus`, `ProximityVoice extends SteamVoice`,
  `scripts/presentation/net_stats_overlay.gd extends NetStatsOverlay`. **La API pública no cambia**:
  `is_online()`, `is_host()`, `local_id()`, `host_session()`, `join_session()`, `leave_session()`,
  `level_ready()`, `begin_restart()`, `world_seed`, `world_house_count`, `world_locked_traps`,
  `world_completed_runs`, `peer_ids`, `Transport`, `MAX_PLAYERS`, `HOST_ID`, `PROTOCOL_VERSION`,
  `EventBus.relay()`, `request_ping`, `request_horn`, `ping_cooldown_seconds`, `reset_ping_cooldowns()`.
- `PROTOCOL_VERSION` pasa a **11** (10 fue N-226, los slots de color): el RPC de reinicio (`_remote_restart`) lleva un diccionario
  `{houses, runs}` y `EventBus` tiene un RPC nuevo `request(event_name, args)`.
- Nuevo en `EventBus` (heredado): `request(event_name, args)` — cualquier peer pide, el host decide y
  relaya `event_name(peer_id, args...)`; `request_cooldowns[&"evento"] = segundos` limita por jugador. Para
  un pedido nuevo de jugador (no host) usá eso en vez de escribir otro par `request_x`/`relay`.
- `NetworkManager`: lo que un joiner recibe en el handshake lo define `_session_state()`; si agregás algo
  que todos los peers tengan que compartir, va ahí (y en `_validate_session_state`/`_apply_session_state`),
  no en un RPC aparte.

## Qué tiene que hacer Slatex

Nada en su código. Si escribís algo que use `NetworkManager` o `EventBus`, es lo mismo de siempre. Si
alguna vez `EventBus.relay` no compila en tu clon: reimportá el proyecto (`tools/run-tests.sh` lo hace la
primera vez), es la caché global de clases.
