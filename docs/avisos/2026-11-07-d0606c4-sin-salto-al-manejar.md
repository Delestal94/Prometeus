# D-0606.c4: el conductor del autoelevador no salta

- **Qué cambió** (archivos de Slatex, `scripts/gameplay/player/`):
  - `PlayerSprint.can_jump()` nuevo en `player_sprint.gd`: falso mientras el jugador lleva la meta `PACE_CAP_META`, la que le
    pone el autoelevador a su conductor.
  - `player_movement.gd` lo mira antes de saltar; a pie nada cambia.
- **Por qué:** con el salto, las horquillas quedaban apoyadas arriba de un estante y el conductor colgando en el aire.
- **Qué tiene que hacer Slatex:** nada.
