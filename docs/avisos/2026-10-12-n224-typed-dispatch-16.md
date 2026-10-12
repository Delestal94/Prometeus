# El rescate del paquete usa tipos para el soporte de la falda y la semilla (N-224.4)

**Fecha:** 2026-10-12 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento:

- `scripts/gameplay/package/package_rescue.gd`: el soporte de la falda como `MountPoint` (`occupied_by`, `store()`) y la semilla de la sesión por `NETWORK_MANAGER` (`world_seed`).
- Siguen por nombre, con la razón anotada en el archivo: el camión (`vehicle.gd` nombra autoloads), RunManager, la radio y el `seat_node_path` de los fakes de los tests.
- `scripts/gameplay/player/player_cargo_care.gd`: sin cambios (todo lo que queda va a RunManager).

`tests/test_dynamic_dispatch_budget.gd` baja el presupuesto de `package_rescue.gd` (call 7 a 6, get 6 a 4) y suma su handle `NETWORK_MANAGER`.
