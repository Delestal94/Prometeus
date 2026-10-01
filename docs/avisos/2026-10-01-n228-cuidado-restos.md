# Restos del cuidado compartido de anclajes (archivos de Slatex)

N-228.8, después de N-228.4 (`2026-10-01-n228-septimo-anclaje.md`). Sin RPC nuevos, pero se replica una propiedad nueva del paquete: `PROTOCOL_VERSION` 17 -> 18.

- `scripts/gameplay/interaction/seat_tending.gd`: `SeatTending.on_stored(package, mount)` (solo host). Si
  alguien parado saca una caja del anclaje de un pasajero sentado y la guarda en un anclaje que su asiento
  no mira, ese pasajero deja de cuidarla (se le manda `tend_package` vacío) y la hereda otro sentado frente
  al anclaje nuevo (el dueño primero). Devolverla al mismo anclaje, el regazo (Q) y sentarse con la caja no
  cambian nada.
- `scripts/gameplay/interaction/package_mount_point.gd`: `store()` llama a `SeatTending.on_stored`.
- `scripts/gameplay/interaction/seat_point.gd`:
  - `_reserved` delega en `SeatTending.lap_reserves` (ver abajo); `_on_boarded` fija el anclaje del regazo
    con `DeliveryPackage.set_lap_mount`.
  - Un asiento dueño (`RightSeat3`) con su anclaje vacío pero reservado por el regazo de un vecino
    (`LeftSeat3`/`CenterSeat`) deja sentarse con las manos vacías; el vecino sigue cuidando su caja. Con
    otra caja en la mano no deja (dos cajas irían al mismo anclaje).

Correcciones de auditor-red:
- `scripts/gameplay/package/package.gd`: propiedad replicada `lap_mount_path` (ON_CHANGE + spawn en
  `package.tscn`, como `current_mount_path`) que reemplaza a `_lap_mount` (se resuelve con
  `SeatTending.lap_mount_of`, se fija con `SeatTending.bind_lap`). Se limpia en `take_by` y
  `_release_carrier` (suelta, guardar, traspaso, consumir); antes `_lap_mount` quedaba viejo. El archivo
  queda justo en 1000 líneas (límite de gdlint). Así un cliente ve qué anclaje reservó un regazo y ofrece bien el
  asiento dueño.
- `scripts/gameplay/package/package_rescue.gd`: `request_lap_toggle` fija el anclaje con `set_lap_mount` y
  decide "sentado" con `SeatTending.is_seated` (el `occupant` en el host), no con `seat_node_path`, que
  llega tarde justo al sentarse.
- `seat_tending.gd`: `is_seated(tree, player, is_server)` y `lap_reserves(tree, mount, except, is_server)`
  (host: `carrier` y `occupant`; cliente: el jugador con `carried_package == caja` y su `seat_node_path`).
  `on_stored` ahora también entrega una caja guardada sin cuidador (p. ej. quien se levanta con ella en la
  mano y la guarda frente al dueño sentado) y solo corre en el host.
- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` 18 (propiedad replicada nueva).

Test: `test_seat_tending` (casos nuevos para las tres cosas).
