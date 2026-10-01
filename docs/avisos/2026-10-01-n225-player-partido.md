# Aviso: `player.gd` partido por responsabilidad (N-225.5)

Dominio de Slatex: `scripts/gameplay/player/player.gd` (1000 → 695 líneas) y cuatro archivos nuevos en la misma
carpeta. Refactor puro: sin cambio de comportamiento, de RPC ni de `PROTOCOL_VERSION`. No toca cuerpo, apariencia,
ragdoll, clips ni IK (S-311 sigue siendo de Slatex).

Helpers estáticos (`extends RefCounted`, sin `class_name`) que reciben al jugador (`p: Player`), cargados solo por
`player.gd` con `preload`; el estado (`_riding`, `_pitch`, `net_position`…) sigue en `Player`:

- `player_ride.gd` (`Ride`): buscar el camión, máscara a pie, viajar con el camión (cuadro a cuadro y pegado) y el
  estado de red (`apply_net_state`, `publish_net_state`, `drawn_transform`).
- `player_movement.gd` (`Movement`): la parte a pie de `_physics_process`, mirada, balanceo de cabeza, FOV por
  contexto y red de seguridad del piso. Las constantes de FOV, balanceo y pitch se reexportan con el mismo nombre y
  valor.
- `player_input.gd` (`OnFootInput`): el cuerpo de `_unhandled_input` y la entrada del paquete; `MOUSE_SENSITIVITY`
  reexportada.
- `player_net_visibility.gd` (`NetVisibility`): el filtro de visibilidad de spawn/sync para peers listos
  (`_enter_tree`; `_on_peer_level_ready` queda en el nodo).

Los siete `@rpc` quedan en `player.gd`, en el mismo orden, con las mismas anotaciones y su guarda `_from_host()`.
Se quitaron 15 envoltorios privados que solo reenviaban a componentes y nadie usaba de afuera (`_use_card`,
`_is_interact_event`, `_is_drop_event`, `_is_open_event`, `_poll_interact`, `_publish_prompt`, `_publish_lid_hint`,
`_update_highlight`, `_clear_carry_focus`, `_on_probe_entered`, `_on_probe_exited`, `_release_seat_occupant`,
`_pose_seated_body`, `_configure_driver_ik`, `_stop_driver_ik`): se llama directo al componente.

`tests/test_player_split.gd` falla si `player.gd` pasa de 700 líneas, si cambia la tabla de RPC o si se pierde algo de
la API usada desde otros archivos. Margen chico a propósito (695 de 700): si un cambio grande lo pasa, se muda
a un helper o componente, no se sube el tope.

Qué hacer: `git pull` antes de tocar el jugador; lo nuevo va en el helper o componente de su responsabilidad.
