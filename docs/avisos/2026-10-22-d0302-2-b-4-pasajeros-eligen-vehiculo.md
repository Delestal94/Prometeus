# Aviso: pasajeros y cajas sueltas eligen el vehículo que los lleva (D-0302.2.b.4, PR #685, retroactivo 2026-10-22)

Aviso escrito por la rutina de mantenimiento: el PR #685 no lo trajo.

- Archivos de Slatex: `scripts/gameplay/player/player_ride.gd` (+6 líneas) y
  `scripts/gameplay/package/package.gd` (+4 líneas). Pasajeros y cajas sueltas eligen, entre varios
  vehículos, el que los lleva, con el ayudante nuevo `scripts/gameplay/vehicle/vehicle_pick.gd` (Nacho).
- Con un solo vehículo nada cambia. No cambia ninguna firma ni la red.
- Test: `test_company_multi_vehicle`.
