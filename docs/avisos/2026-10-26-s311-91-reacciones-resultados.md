# S-311.91 — celebración y derrota en resultados

Hecho el 2026-10-26.

## Coordinación

Se tocó `scripts/ui/hud/hud_results.gd`, parte de la pantalla completada por S-508. El cambio es
aditivo: no modifica filas, premios, progreso, textos, botones, sonido ni el diccionario de
resultados. `_on_ended()` sólo pide una reacción al jugador dueño antes de presentar el diario o la
tarjeta existente.

## Comportamiento

- Una entrega exitosa usa el `VictoryDance` ya creado en S-311.88.
- Un resultado fallido usa el clip nuevo `Defeat`: pecho y cabeza caídos, brazos pesados y un balanceo
  suave que cierra en loop.
- La reacción queda estable mientras resultados está abierto, incluso si el personaje terminó sentado
  o el movimiento sigue actualizándose detrás de la tarjeta.
- Endless no dispara ninguna de las dos poses porque no tiene un resultado de entrega.

## Red y assets

Cada peer recibe los resultados existentes y sólo anima a su jugador local. El dueño publica
`anim_state` / `anim_clip`; los demás reproducen el clip exacto. No hay RPC, señal ni versión de
protocolo nueva.

`animation_library.py` sigue siendo la fuente reproducible. La biblioteca pasa de 48 a 49 clips y se
regeneran el GLB redondeado, los tres LOD gel y sus archivos de autoría/reporte.

## Validación

- `test_player_result_reactions`: clips, pose, duración, loop, selección éxito/derrota, prioridad sobre
  movimiento/asiento y propiedades replicadas.
- `net_pair_animation`: host y cliente ven el mismo `Defeat` del dueño.
- Regresiones de rig, retarget, resultados y jugador se ejecutan antes de publicar.
