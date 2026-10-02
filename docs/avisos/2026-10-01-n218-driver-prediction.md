# El conductor cliente predice el camión; módulo nuevo `net_prediction` y protocolo 25 (N-218)

**Fecha:** 2026-10-01 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **Módulo nuevo `modules/net_prediction/`** (zona compartida): `NetInputBuffer` (el host reproduce los inputs
  numerados de un peer remoto, uno por tick de física, con un colchón de 2 contra el jitter) y
  `NetPredictionReconciler` (el cliente guarda su estado después de cada input, lo compara con el del host para el
  mismo input y corrige la diferencia de a poco, sin re-simular). No sabe nada del camión; test propio
  `modules/net_prediction/tests/test_net_prediction.gd`.
- **`PROTOCOL_VERSION` 25** (`network_manager.gd`, zona compartida): `submit_driver_input` lleva el número de input,
  y el camión replica `net_input_seq`, `net_simulating` y sus velocidades, `steering` y `engine_force` a través de
  proxies `net_*` (antes eran las propiedades del cuerpo directas). Mismo tamaño por paquete salvo el entero del
  input.
- El cliente que maneja descongela su copia del camión y la simula (`scripts/gameplay/vehicle/vehicle_prediction.gd`).
  Mientras predice, su camión **no está congelado y se dibuja interpolado**, como el del host: el código que decide
  por `vehicle.is_physics_interpolated_and_enabled()` (`player_ride.gd`, `PackageNetPose._drawn`) toma solo el
  camino del host. No hizo falta tocar nada tuyo; las cajas siguen en el host y se dibujan en el espacio del camión
  del cliente (`net_in_vehicle`), así que viajan con la predicción.

## Qué tiene que hacer Slatex

Nada. Si escribís código del lado cliente que asume "el camión del cliente está congelado" (`vehicle.freeze`, o que
no es la autoridad y entonces no se simula), usá `vehicle.is_physics_interpolated_and_enabled()` o
`vehicle.is_predicted()`: en la máquina del conductor cliente ya no está congelado.
