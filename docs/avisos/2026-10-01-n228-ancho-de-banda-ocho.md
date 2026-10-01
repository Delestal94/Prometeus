# Ancho de banda con 8 jugadores: ruedas del cliente y cajas quietas a 2 Hz (protocolo 19; archivos de Slatex)

N-228.5. Con 8 jugadores y el encuadre real contado, el host le mandaba a cada cliente 165 KB/s (tope del
test: 128, la mitad de los 256 de Steam) y subía 9,5 Mbit/s. Ahora: 117,7 KB/s y 6,8 Mbit/s. Detalle y
números en `docs/investigacion-red.md` §4.2.

- **Protocolo: cambió.** `PROTOCOL_VERSION` pasa a **19** (`network_manager.gd`): la configuración de
  replicación del camión (`vehicle.tscn`, `Repl_vehicle`) ya no tiene `FrontLeftWheel:transform`,
  `FrontRightWheel:transform`, `RearLeftWheel:transform` ni `RearRightWheel:transform`, y suma
  `.:net_wheel_heights` (`Vector4`, ALWAYS). Un cliente viejo con un host nuevo no se entiende; el handshake
  lo rechaza. Ningún RPC cambió.
- `vehicle.gd`: propiedad nueva `net_wheel_heights` (en el host lee la altura de cada rueda; en el cliente la
  guarda) y `_pose_remote_wheels()`, que en un cliente pone cada rueda con esa altura, `steering` en las
  delanteras y el giro según la velocidad, igual que `VehicleBody3D` (base espejada incluida). `_process`
  del cliente ahora corre aunque el suavizador esté vacío (para las ruedas).
- `package.tscn` (de Slatex): nodo nuevo `NetRestThrottle` (script del módulo `net_pose_smoother`). En el
  host, si `net_transform` y `net_in_vehicle` no cambian (5 mm, 0,01 rad) durante 0,5 s, el sincronizador de
  la caja pasa de cada tick a cada 0,5 s; al moverse vuelve a cada tick en el mismo tick. Cuando el juego
  llama `update_visibility(peer)` (la caja ya lo hace al cargar un peer el nivel) también vuelve a cada tick,
  para que el que entra tarde la reciba enseguida. `package.gd` no cambia. Si alguien renombra
  `net_transform` o `net_in_vehicle`, el nodo da error y deja la caja a ritmo completo (no la congela).
- Los clientes ven igual una caja quieta (a lo sumo 1 cm o 1,2° de diferencia, el doble de la tolerancia, y
  cada envío lento lo corrige); su `linear_velocity` y
  `angular_velocity` replicadas se refrescan a 2 Hz mientras está quieta (solo las usa la tensión de las
  correas, que a velocidad de ruta ya está al tope).
- `scripts/presentation/vehicle_presentation.gd`: solo el comentario de dónde salen las ruedas del cliente.

Tests: `test_net_bandwidth_budget` (reescrito: `MAX_PLAYERS`, encuadre, subida del host, el reposo de una
caja real), `test_net_rest_throttle` (módulo, nuevo), `test_vehicle_presentation` (la copia de un cliente
dibuja las ruedas donde las tiene el host) y `net_pair` (etapa nueva: una caja quieta que el host mueve
llega al cliente y vuelve a mandarse a ritmo completo).

Si al mezclar `main` choca el historial de `PROTOCOL_VERSION`: esta rama ya trae la línea 17 de `main`
(N-228.4) y la 18 de `main` (N-228.8) y agrega la 19.
