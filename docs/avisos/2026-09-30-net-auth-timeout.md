# Aviso: el cliente ya no crashea cuando vence el handshake (2026-09-30)

Rama `nacho/fix-net-auth-timeout`. Toca la zona compartida `scripts/core/network_manager.gd`, en cuatro lugares.
Ninguna firma pública cambia, no hay RPC nuevo y `PROTOCOL_VERSION` sigue igual.

## Qué cambió

- `_auth_failed` y los rechazos que llegan por `_receive_auth` (el `auth_callback`) ya no llaman a `_fail` en el
  momento: pasan por `_fail_if_current.call_deferred(motivo, peer)`, que solo termina la sesión si el peer sigue
  siendo el mismo (sin doble aviso cuando `server_disconnected` llega en el mismo poll y sin matar una sesión
  nueva). `SceneMultiplayer` emite
  `peer_authentication_failed` desde adentro de su `poll()`, y cerrar y reemplazar el peer en ese momento lo
  liberaba mientras todavía se estaba recorriendo. Eso daba un SIGSEGV en el check "Network pair" de CI (PR #85):
  3 de 3 con el timeout forzado a 6 s, 0 de 3 con el arreglo. El menú muestra el mismo motivo ("timeout"), un
  frame más tarde.
- `JOIN_HANDSHAKE_TIMEOUT` sube de 20 s a 30 s. Con el nivel más grande, cargarlo tarda entre 18 y 34 s en el net
  pair, y el cliente se caía justo al terminar de cargar. `ENET_PEER_TIMEOUT_MAX_MSEC` ya es 30 s y el net pair
  espera hasta 40 s.
- `tests/test_connection_errors.gd`: casos nuevos. Un vencimiento de auth o un rechazo de versión no tocan el peer
  en el mismo frame y al siguiente fallan la sesión una sola vez; un fallo viejo no mata una sesión nueva.

## Qué tiene que hacer Slatex

Nada.
