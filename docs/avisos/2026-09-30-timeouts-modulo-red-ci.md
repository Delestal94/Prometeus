# Restaurar los timeouts en el módulo de red

El merge de `main` en el PR #111 conservó el test de la carga lenta, pero el traslado
de `network_manager.gd` a `NetSession` dejó las constantes anteriores en el módulo.
Por eso `test_connection_errors.gd` fallaba en sus tres verificaciones de tiempos.

En `do-not-drop/modules/net_session/net_session.gd`, zona compartida:

- `JOIN_HANDSHAKE_TIMEOUT`: 30 → 45 s.
- `ENET_PEER_TIMEOUT_MIN_MSEC`: 15000 → 45000 ms.
- `ENET_PEER_TIMEOUT_MAX_MSEC`: 30000 → 45000 ms.

El test propio del módulo comprueba también el `auth_timeout` aplicado al alojar
una sesión y la relación entre los tiempos de ENet y autenticación. Así la
corrección queda cubierta incluso al probar el módulo en un proyecto vacío.

No cambia ninguna firma ni el protocolo. Antes de seguir con red, hacer `git pull`.
El costo sigue siendo detectar una caída sin despedida a los 45 s; una salida limpia
se detecta enseguida. N-235 conserva sus tareas de seguimiento pendientes.
