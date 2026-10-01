# Restos del cuidado compartido de anclajes (archivos de Slatex)

N-228.8, después de N-228.4 (`2026-10-01-n228-septimo-anclaje.md`). Sin RPC nuevos; `PROTOCOL_VERSION` igual.

- `scripts/gameplay/interaction/seat_tending.gd`: `SeatTending.on_stored(package, mount)` (solo host). Si
  alguien parado saca una caja del anclaje de un pasajero sentado y la guarda en un anclaje que su asiento
  no mira, ese pasajero deja de cuidarla (se le manda `tend_package` vacío) y la hereda otro sentado frente
  al anclaje nuevo (el dueño primero). Devolverla al mismo anclaje, el regazo (Q) y sentarse con la caja no
  cambian nada.
- `scripts/gameplay/interaction/package_mount_point.gd`: `store()` llama a `SeatTending.on_stored`.
- `scripts/gameplay/interaction/seat_point.gd`:
  - `_reserved` decide si el que lleva la caja en el regazo está sentado con el `occupant` de los asientos
    (host); en un cliente sigue usando `seat_node_path` replicado.
  - Un asiento dueño (`RightSeat3`) con su anclaje vacío pero reservado por el regazo de un vecino
    (`LeftSeat3`/`CenterSeat`) deja sentarse con las manos vacías; el vecino sigue cuidando su caja. Con
    otra caja en la mano no deja (dos cajas irían al mismo anclaje).

Test: `test_seat_tending` (casos nuevos para las tres cosas).
