# Aviso: módulos portables, fase 3 — interacción, cámara de asiento y ajustes (2026-09-30)

Lo hizo Nacho (con Claude), PR `nacho/N-232-interaction-camera-settings` (N-232, `docs/modulos.md`).
Toca dominio de Slatex: `scripts/gameplay/interaction/` y `scripts/core/game_settings.gd`. **Ninguna
API pública cambia**; lo que cambia es de dónde viene el mecanismo.

## `scripts/gameplay/interaction/`

- `interactable.gd` se movió a `modules/interaction/interactable.gd` (`class_name Interactable`, misma API:
  `prompt`, `get_prompt()`, `can_interact()`, `interact()`, `request_interact()`, `interacted`). Los diez
  puntos que lo extendían por ruta (`extends "res://scripts/gameplay/interaction/interactable.gd"`) ahora
  dicen **`extends Interactable`**. Si creás uno nuevo, igual. Nuevo en la base: `find_player(peer_id)`
  y `local_player()`; la capa (16) y el grupo (`player`) son `Interactable.interaction_layer` /
  `player_group`.
- `seat_point.gd` sigue en su lugar (la escena del camión lo referencia) pero ahora **extiende
  `SeatPoint`** del módulo. El módulo hace el asiento (indicador, ocupación por `seat_node_path`, puerta
  requerida, `board_seat`, volante y `release_occupant`); el archivo del juego conserva
  `required_mount_path`, `tend_mount_paths` y lo de la carga en cinco hooks: `_free_prompt()`,
  `_can_board(player)`, `_accept_boarding(player)`, `_on_boarded(player, peer_id)`,
  `_on_released(peer_id)`. Antes eso estaba adentro de `get_prompt()`/`can_interact()`/`interact()`;
  si le agregás lógica de carga a un asiento, va en esos hooks. `_is_occupied()` pasó a ser público:
  `is_occupied()`; `_local_player()` es `local_player()` (heredado).

## `scripts/core/game_settings.gd`

- `GameSettings extends SettingsStore` (`modules/settings_store/`). Todas las propiedades, setters,
  señales y constantes siguen iguales (`master_volume`, `hud_scale`, `key_bindings`, `bind_key()`,
  `binding_label()`, `set_language()`, `prompt()`, `reset_to_defaults()`, `DEFAULT_KEY_BINDINGS`...).
- **Para agregar un ajuste nuevo**: la propiedad con su setter que llama `_save()`, y su nombre en
  `SAVED_KEYS`. Ya no hay que tocar `_load()` ni `_save()`: el módulo escribe y lee cada clave de la lista
  por `get()`/`set()`.
- El archivo de los tests sigue siendo `user://test_settings.cfg` (el módulo lo arma como `test_` + el
  nombre del archivo real).

## `scripts/presentation/first_person_camera.gd` (compartida)

Extiende `SeatCamera` (`modules/seat_camera/`). La escena sigue apuntando al mismo script. Lo que
sacude la cámara ahora entra por `add_shake(cantidad)` y `kick_fov(grados)`: si querés que otro evento
la sacuda, conectalo ahí en `first_person_camera.gd`, no en el módulo.

## Qué tiene que hacer Slatex

Nada ahora. Al escribir un `Interactable` nuevo: `extends Interactable`. Al agregar un ajuste: propiedad +
`SAVED_KEYS`. Si tu clon dice "Could not find base class Interactable": reimportá (caché de clases).
