# Timeouts de red más largos para cargas lentas (zona compartida)

`scripts/core/network_manager.gd` (zona compartida):

- `JOIN_HANDSHAKE_TIMEOUT` 30 → 45 s.
- `ENET_PEER_TIMEOUT_MIN_MSEC` 15000 → 45000 y `ENET_PEER_TIMEOUT_MAX_MSEC` 30000 → 45000.

Por qué: el que se une carga el nivel bloqueando el poll de ENet (18-34 s en CI). Con MIN en 15 s, la
regla de reintentos de ENet cortaba al peer a los ~15 s de silencio en plena carga, y el trío de red
fallaba de forma intermitente en main ("0 players seen"). Costo: un peer que se cae sin despedirse se
nota a los 45 s en vez de a los 15-30 s. No cambia `PROTOCOL_VERSION`. El arreglo de fondo (cargar el
nivel sin bloquear el poll) queda para más adelante.

`tests/net_trio.gd` ya no nombra `PackageRescue`: lo carga al usarlo, así `--script` no intenta
compilar `hud.gd` antes de que existan los autoloads (era un `Compilation failed` inofensivo en el log).
