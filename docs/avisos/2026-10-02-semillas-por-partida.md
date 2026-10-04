# Semilla nueva por partida (N-963)

Primer paso pedido por el equipo el 2026-10-02: variar la semilla entre partidas y
mantener un mismo mundo para todos los jugadores de una partida.

Se cambia `do-not-drop/scripts/core/network_manager.gd`, zona compartida:

- `_on_hosting()` elige una semilla no nula, distinta de la anterior.
- `_before_restart()` elige la semilla de la siguiente entrega antes de reconstruir
  el nivel del host. Se mantiene durante esa entrega, incluso si entra otro jugador.
- `_restart_state()` agrega `seed` al diccionario existente; `_apply_restart_state()`
  la aplica antes de que el cliente recargue el nivel. El handshake de entrada tardía
  sigue enviando la misma `world_seed` actual.
- `PROTOCOL_VERSION` pasa de 27 a 28: los clientes anteriores no entenderían la
  nueva semilla de reinicio. Las firmas de los métodos y RPC siguen iguales.

En Reparto y Endless, una partida nueva es la carga de un nivel nuevo (incluido
el botón de otra entrega). Iniciar la entrega desde el depósito o entrar a una sala
ya iniciada no cambia la semilla. Solo sigue usando `world_seed == 0` y el azar
local existente; al dejar una sala se vuelve a ese estado.

Este paso no implementa el generador de pueblo ni el guardado de su campaña. Cuando
se conecte el mundo persistente del pueblo, continuar una campaña deberá recuperar
su semilla guardada; no deberá usar el reinicio de entrega de los modos actuales.

Cobertura: `test_world_seed.gd` comprueba semillas nuevas, rechazo de una repetición
forzada, payload de reinicio, entrada tardía, limpieza al salir, igualdad del mundo
con semilla fija y variedad en solo. Actualizar el clon antes de continuar cambios
de red; todos los participantes deben usar la misma versión del protocolo.
