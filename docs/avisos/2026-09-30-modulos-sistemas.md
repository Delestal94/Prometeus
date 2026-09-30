# Aviso: módulos portables, fase 5 — peligros, votación, perfil y registro (2026-09-30)

Lo hizo Nacho (con Claude), PR `nacho/N-234-game-systems` (N-234, `docs/modulos.md`). Toca dominio de Slatex:
`scripts/gameplay/traps/` y `data/traps/*.tres`. **Ninguna API pública cambia.**

## Trampas (Slatex)

- `i_trap_behavior.gd` y `trap_definition.gd` se movieron a `modules/hazards/` (mismas clases `ITrapBehavior`
  y `TrapDefinition`; los siete comportamientos siguen en `scripts/gameplay/traps/` con `extends ITrapBehavior`).
- **`TrapDefinition.NAME_KEYS` ya no existe**: la clave de traducción es un `@export var translation_key` en
  cada `data/traps/*.tres` (`translation_key = "HUD_TRAP_FRAGILE"`...). `name_key()` y `localized_name()`
  siguen iguales para todos los llamadores. **Para una trampa nueva**: su script, su `.tres` con
  `translation_key`, y la clave en `translations/strings_ui.csv`. Sin tocar el módulo.
- Los `.tres` apuntan al script nuevo (`res://modules/hazards/trap_definition.gd`).

## Autoloads de la zona compartida

- `ShopVoteManager extends CoopVote` (`modules/coop_vote/`): `open_shop()`, `vote()`, `resolve_winner()`,
  `finish_vote()`, `resolve()`, `use_priority()`, `use_revote()`, `use_discount()`, `reveal_offers()`,
  `request_open_shop`, `request_vote`, `request_revote`, `request_discount`, `crew_progression`, `event_bus`:
  todo igual. Nuevo, heredado: `open()`, `buy()`, `close_on()`, `restart_votes()`, `reset()`, `connected_peers()`.
- `UnlockManager extends UnlockProfile` (`modules/unlock_profile/`): misma API (`is_unlocked`, `record_run`,
  `locked_traps`, `select_*`, `*_choices`, `mark_tip_seen`, `next_unlock_progress`, `progress_summary`,
  `reset_profile`, `save_profile`, `load_profile`, `UNLOCKS`, `TRAP_UNLOCKS`...). Un desbloqueo nuevo es una
  fila en `UNLOCKS` con `deliveries` y `score`; una estadística nueva es un caso más en `_stat()`.
- `RunTelemetry extends RunLog` (`modules/run_log/`): `directory`, `last_file`, `save_record()`,
  `is_recording()`, `MAX_FILES` iguales; el nombre del archivo lo sigue dando `TelemetryFormat.file_stem()`.

## Qué tiene que hacer Slatex

Nada en el código actual. Al agregar una trampa: script + `.tres` con `translation_key` + clave en el CSV. Si tu
clon dice "Could not find base class ITrapBehavior": reimportá (caché de clases).
