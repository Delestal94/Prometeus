# N-990: levantarse de un asiento que se va, y `vacate()` en los asientos

- **Qué cambió** (archivos de Slatex, `scripts/gameplay/player/`, y zona compartida, `modules/interaction/`):
  - `Player.leave_seat(tell_host = true)` y `PlayerSeatPose.leave_seat(tell_host = true)`: con `false` no manda
    `release_occupant` al host. Solo lo usa `CompanyFleet.prune()` en el cliente: el host ya sacó ese asiento.
    Las llamadas de siempre, sin argumento, hacen lo mismo que antes.
  - `SeatPoint.vacate()` nuevo: el host suelta al ocupante por su cuenta (la butaca se va con el vehículo), con el
    hook `_on_released` y el volante. `release_occupant()` no cambió de firma ni de reglas. Sin cambio de RPC.
  - `DashboardGps.refresh()` (`scripts/presentation/`) no hace nada fuera del árbol: su `refresh.call_deferred()` de
    `_ready` podía caer sobre una camioneta retirada en el mismo frame en que se armó.
- **Qué tiene que hacer Slatex:** nada.
