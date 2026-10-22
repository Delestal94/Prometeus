# Aviso 2026-10-22 · la estación de despacho del galpón abre el tablero (D-0310.b)

Toca archivos de Slatex: `scripts/ui/dispatch_board_panel.gd` y `scripts/gameplay/interaction/shed_piece_point.gd`.
**Sin cambio de protocolo** (`PROTOCOL_VERSION` queda como está): no hay RPC nuevo ni cambia lo replicado. El nodo
nuevo del galpón (`Dispatch_<uid>`, un `DispatchStation`) reusa el único RPC de `DepotStation` (`_open_locally`),
así que ningún id de RPC existente se corre; un cliente de una versión anterior simplemente no tendría ese punto.

- **`DispatchStation`** (`scripts/gameplay/dispatch_station.gd`, nuevo): un `DepotStation` con `station_id = &"dispatch"`
  en el medio de cada zona de despacho del galpón (`CompanyShed.dispatch_stations`, por uid de la pieza), con un
  tablero gris de placeholder. Sobrescribe `_run_started()` (siempre `false`): el depósito esconde el cartel si quedó el
  resultado de una corrida, y el modo Empresa no tiene corrida.
- **`ShedPiecePoint`**: la zona de despacho ya no tiene punto de uso (`PROMPT_KEYS` pierde `&"dispatch"` y `make()` el
  caso especial); tiene la estación. `WORLD_SHED_USE_DISPATCH` es ahora el cartel de la estación.
- **`DispatchBoardPanel`**: `refresh()` conserva el foco si la fila que lo tenía sigue en la lista (el mundo lo
  refresca cada 0,5 s mientras está abierto y, sin esto, el mando perdía el foco). Nada más cambia: mismo contexto,
  mismas señales, `test_company_dispatch_panel` sin tocar.
- **`CompanyDispatch`** (`scripts/gameplay/company_dispatch.gd`, nuevo; hijo `Dispatch` de `CompanyRoot` en cada peer,
  una línea en `_ready()`): escucha `EventBus.depot_station_opened(&"dispatch")` y abre el tablero con el contexto real
  (cajas selladas dentro del área de la pieza de despacho, vehículo real de la flota con sus casilleros y kg, reglas de
  `DispatchRules`). Solo el host carga; el cliente ve la lista con "Cargar" apagado y el motivo.
- **`CompanyTrips.has_cargo(vehicle_id)`** (nuevo, solo lectura): un vehículo con carga lista no se ofrece de nuevo
  (`stage_cargo()` reemplaza lo anterior).
- **Textos** (`strings_world.csv`): `WORLD_ZONE_*` (9 zonas) y `WORLD_VEHICLE_*` (3 camionetas).
- Queda abierto, ver `docs/expansion-distritos/revisar/D-0310.md`: D-0310.c (replicar el estado de la zona por red,
  fila 17), D-0717.b (llevar las cajas a los `PackageMountPoint`, fila 18) y D-0715.b `order_packed` (el libro
  compartido todavía no marca `PACKED` al encintar; el tablero lo ve en una copia propia).
