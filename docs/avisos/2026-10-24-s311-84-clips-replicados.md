# Aviso: S-311.84, clip exacto replicado

La animación visible del jugador ya no vuelve a elegir variantes en cada copia.
El dueño resuelve `Stroll`/`Walk`/`CarryWalk`, la variante de levantar una caja,
los clips sentados y las reacciones, y publica el resultado en `Player.anim_clip`.
Los demás pares reproducen únicamente ese valor; `anim_state` sigue siendo el
estado de gameplay y `locomotion_speed`/`jump_anim_time` conservan el ritmo y la
fase.

Archivos compartidos tocados:

- `scripts/gameplay/player/player.gd` y `player_animator.gd`: nuevo contrato
  `anim_state` (lógica) → `anim_clip` (clip visible).
- `scenes/gameplay/player/player.tscn`: `anim_clip` se replica `ON_CHANGE` y al
  aparecer.
- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` 60 → 61.
- `tests/net_pair_animation.gd`: comprueba en dos procesos y en ambos sentidos
  un blend de levantar y la elección `Walk` → `Stroll`.

Una rama que toque RPCs o replicación debe partir de `main` actualizado y usar
el siguiente número libre después de 61.
