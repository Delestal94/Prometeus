# Aviso: timeout de ENet de 20 s en partida, 45 s solo mientras alguien carga (2026-09-30)

Lo hizo Nacho (con Claude), rama `ccr-7ed3ad6f-aszdmn` (N-235). Zona compartida:
`do-not-drop/modules/net_session/net_session.gd` (base de `NetworkManager`) y
`scripts/core/network_manager.gd`. Además `scripts/gameplay/level_common.gd` (`restart_delivery`, sin dueño).

## Qué cambió

- Antes (#111) el timeout de ENet quedaba fijo en 45 s toda la sesión: si un jugador crasheaba, su caja
  seguía "sostenida", el volante ocupado y su voz activa hasta 45 s; si crasheaba el anfitrión, los demás
  veían "anfitrión perdido" a los 45 s. Ahora cada punta de cada enlace ENet usa:
  - **45 s** (`ENET_PEER_TIMEOUT_MIN_MSEC` = `MAX` = 45000, sin cambios) mientras alguien puede estar
    cargando un nivel: el que se une desde que se autentica hasta que el host lo admite, y las dos puntas
    desde que se anuncia el reinicio (`announce_restart()` o `begin_restart()`) hasta que ese cliente avisa
    que volvió (`_report_level_ready`);
  - **20 s** (`ENET_PEER_TIMEOUT_SESSION_MSEC` = 20000, constante nueva del módulo, MIN = MAX) el resto de
    la partida. La bajada no es inmediata: el host espera `settle_delay_seconds` (3 s, variable del
    módulo) después de que el nivel del cliente está arriba, porque los primeros frames todavía pueden
    trabarse (shaders en GL Compatibility), y al vencer vuelve a comprobar que no haya un reinicio
    anunciado o en curso, ni recargas pendientes, y que el peer siga.
- La carga del host al reiniciar bloquea su poll, así que los clientes tienen que enterarse *antes*: RPC
  nuevo en `NetSession`, `_host_load_timeout(loading: bool)`, `@rpc("authority", "call_remote",
  "reliable")`, canal 0, host → clientes. Lo manda con `true` a todos `announce_restart()`, público y
  nuevo: `restart_delivery()` lo llama **antes** del fundido de 0,15 s, así ENet tiene tiempo de
  reenviarlo si se pierde (justo antes de la recarga, un datagrama perdido esperaba toda la carga).
  `begin_restart()` sigue siendo correcto sin anuncio previo (anuncia él; si ya se anunció, no repite nada).
  Hasta `begin_restart()` nadie baja a 20 s. El host manda `false` a un cliente cuando lo admite y cuando
  llega su último `_report_level_ready` pendiente, pasado el margen. `_remote_restart` pasa el cliente a
  45 s antes de su propia recarga.
- Un reporte de un reinicio anterior que llega tarde no baja nada: el host cuenta los reinicios que cada
  cliente le debe (`_reloads_owed`). Tampoco marca al cliente como listo: ya no lo suma a `_ready_peers`
  ni emite `peer_level_ready` si hay un reinicio en curso o una recarga pendiente (antes sí, y el host le
  mandaba jugadores a un nivel a punto de irse). El cliente recarga y avisa de nuevo.
- Un joiner que falla la autenticación (otra versión, sala llena) ya no deja su timeout anotado en el host
  (`_auth_failed` borra `_enet_timeouts` y `_reloads_owed`).
- `NetSession` suma `enet_timeout_msec(peer_id) -> int` (lo que esta punta tolera de ese peer; 0 fuera de
  ENet) y el hook `_reload_level()` (por defecto `reload_current_scene` diferido, lo mismo que antes; el
  test del módulo lo reemplaza). Steam no cambia: sus peers siguen con sus propios timeouts.
- **Protocolo**: `PROTOCOL_VERSION` 12 → **13** (el RPC nuevo corre los ids de RPC del nodo
  `NetworkManager`; el 12 lo tomó N-109, PR #115, que entró antes). Un cliente viejo con un host
  nuevo no se entiende: el handshake lo rechaza con "otra versión del juego".
- `tests/net_pair.gd` y `tests/net_trio.gd` imprimen `NETLOG ... WARNING slow level load` si la carga
  del que se une pasa de 35 s (10 s de margen sobre los 45 s), y `tools/run-net-pair.sh` /
  `tools/run-net-trio.sh` lo repiten como línea `WARNING:` (y `::warning::` en GitHub Actions). Sigue
  siendo PASS. El par además comprueba que, admitido el cliente, las dos puntas llegan a 20 s.

## Qué tiene que hacer Slatex

Nada en su código. Ninguna firma existente cambió. Si algo del juego recarga el nivel online sin pasar
por `NetworkManager.begin_restart()`, tiene que pasar por ahí (y, si hay una espera antes, llamar
`NetworkManager.announce_restart()` al empezarla, como `restart_delivery()`): si no, la otra punta sigue en
20 s y corta a quien tarde más que eso en cargar. Antes de probar con amigos, `git pull` todos: con versiones
distintas no se pueden unir.
