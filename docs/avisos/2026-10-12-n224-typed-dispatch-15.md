# Cinco archivos más usan tipos (N-224.4)

**Fecha:** 2026-10-12 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento:

- `scripts/ui/hud/crew_panel.gd`: el camión como `VehicleScript` (`driver_peer_id`).
- `scripts/gameplay/player/player_ride.gd`: `pose_net_sim()` por `NetSession`.
- `scripts/gameplay/depot/depot_station.gd`: RunManager por `PackageAutoloads.run_manager()`.
- `scripts/core/unlock_manager.gd`: `peer_ids` por `NetSession`.
- `scripts/tools/newspaper_concept/render_newspaper_concept.gd`: la cara como `Face`.

`tests/test_dynamic_dispatch_budget.gd` suma los cinco archivos a `BUDGETS`.
