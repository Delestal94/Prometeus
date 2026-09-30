# Aviso: el cliente ya no crashea cuando vence el handshake (2026-09-30)

Rama `nacho/fix-net-auth-timeout`. Toca la zona compartida `scripts/core/network_manager.gd`, en dos líneas.
Ninguna firma pública cambia, no hay RPC nuevo y `PROTOCOL_VERSION` sigue igual.

## Qué cambió

- `_auth_failed`: `_fail("timeout")` pasa a `_fail.call_deferred("timeout")`. `SceneMultiplayer` emite
  `peer_authentication_failed` desde adentro de su `poll()`, y cerrar y reemplazar el peer en ese momento lo
  liberaba mientras todavía se estaba recorriendo. Eso daba un SIGSEGV en el check "Network pair" de CI (PR #85):
  3 de 3 con el timeout forzado a 6 s, 0 de 3 con el arreglo. El menú muestra el mismo motivo ("timeout"), un
  frame más tarde.
- `JOIN_HANDSHAKE_TIMEOUT` sube de 20 s a 30 s. Con el nivel más grande, cargarlo tarda entre 18 y 34 s en el net
  pair, y el cliente se caía justo al terminar de cargar. `ENET_PEER_TIMEOUT_MAX_MSEC` ya es 30 s y el net pair
  espera hasta 40 s.
- `tests/test_connection_errors.gd`: caso nuevo. Un vencimiento de auth no toca el peer en el mismo frame; al frame
  siguiente falla la sesión con "timeout" y vuelve offline.

## Qué tiene que hacer Slatex

Nada.
