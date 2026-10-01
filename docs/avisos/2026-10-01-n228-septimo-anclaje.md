# Séptimo anclaje de caja y cuidado compartido de un anclaje (archivos de Slatex)

N-228.4: con 8 jugadores hay hasta 7 cajas y el camión tenía 6 anclajes.

- `vehicle.tscn`: anclaje nuevo `CargoBay/RightSeat3PackageMount`, en el piso contra la pared derecha
  (entre el banco derecho y los asientos plegables). `RightSeat3` es su dueño (`required_mount_path`) y
  `LeftSeat3` y `CenterSeat` lo cuidan (`tend_mount_paths`): todo asiento de pasajero cuida algún anclaje.
- `PROTOCOL_VERSION` pasa a **17** (nodo interactuable nuevo en una escena compartida).
- `scripts/gameplay/interaction/seat_point.gd` y `scripts/gameplay/package/package_rescue.gd` (de Slatex):
  con varios asientos mirando el mismo anclaje, el último en sentarse ya no le saca el cuidado al que lo
  tenía (el host dejaba de leer su input sin avisarle). Regla nueva, en `seat_tending.gd` (`SeatTending`,
  solo host): quien ya cuida la caja la conserva, salvo que llegue el dueño del anclaje (al desplazado se le
  manda `tend_package` vacío); al levantarse o desconectarse el que cuida, otro sentado frente al anclaje
  la hereda, el dueño primero. Sin RPC nuevos. Los asientos están en el grupo `cargo_seat`.
- `route_event_manager.gd`: el evento parásito elige cajas en anclajes con asiento dueño
  (`SeatTending.is_owned_mount`) en vez de buscar "Seat" en el nombre; mismo conjunto que antes más el nuevo.

Tests: `test_multi_cargo` (anclajes >= `MAX_PLAYERS - 1`, cada asiento cuida uno), `test_reference_truck`,
`test_seat_tending` (nuevo), `test_route_events`.

Después de la revisión de `auditor-red` y `revisor-gdscript` también cambiaron:
- `seat_point.gd`: el conductor no entra al grupo `cargo_seat` ni cuenta como dueño de un anclaje (se borró
  su `required_mount_path`, que nadie leía); quien se sienta con una caja en brazos pasa a cuidarla; un asiento
  que cuida con caja en mano exige un anclaje libre que ningún otro regazo reservó; los asientos de columna
  toman la primera caja sin cuidar.
- `scripts/gameplay/player/player_seat_pose.gd` (de Slatex): `apply_tend_package` ignora una caja si el
  jugador ya no está sentado, y `apply_board_seat` limpia `tended_package`.
Pendiente de bajo riesgo: N-228.8.
