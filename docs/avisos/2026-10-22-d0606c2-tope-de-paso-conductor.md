# Aviso: tope de paso del conductor del autoelevador (D-0606.c2, 2026-10-22)

Lo hizo la rutina `desarrollador` (carril 2), rama `exp/D-0606.c2-forklift-driver-feel`.

- Archivo de Slatex: `scripts/gameplay/player/player_sprint.gd`. Nueva meta `PACE_CAP_META` (`&"pace_cap"`):
  mientras un jugador la lleva, `can_run()` es falso y `ground_speed()` no pasa del valor de la meta. Sin la
  meta, nada cambia. No cambia ninguna firma ni la red (la meta la pone cada peer sobre el jugador, igual que
  `driving`).
- Quién la pone: `ForkliftView` (Nacho), con `CompanyTuning.FORKLIFT_DRIVE_SPEED_MPS` = 2,2 m/s.
- Tests: `test_player_sprint` y `test_company_forklift_world`.
