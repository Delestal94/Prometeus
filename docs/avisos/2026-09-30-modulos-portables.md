# Aviso: módulos portables, fase 1 (2026-09-30)

Lo hizo Nacho (con Claude), PR `nacho/N-230-modulos-portables`. Nace `do-not-drop/modules/`: carpetas
que se pueden copiar a otro proyecto Godot y funcionan (reglas y catálogo en `docs/modulos.md`).
Es zona compartida. **Solo cambian rutas y tres firmas**; ninguna mecánica.

## Archivos de Slatex que se movieron o cambiaron

- `scripts/gameplay/player/player_ragdoll.gd` → `modules/ragdoll/player_ragdoll.gd`. Ya no busca el
  grupo `"vehicle"` por su cuenta: **`setup(jugador, carrier, máscara)`** recibe el camión y las capas
  con las que chocan las piezas. `player.gd:_activate_ragdoll` ya pasa
  `get_first_node_in_group(&"vehicle")` y `1 | 64` (suelo + carcasa de carga). Si agregás otro
  origen de ragdoll, pasale lo mismo.
- `player.gd`: solo el `preload` del ragdoll y esa llamada. Sigue en 1000 líneas justas: si le
  agregás algo, antes hay que sacarle algo (N-225).
- `scripts/gameplay/interaction/` no se tocó (va en la fase 3, con aviso propio).
- Tests de Slatex con rutas nuevas (`preload`): `test_player_sprint.gd`, `test_care_prompt_view.gd`,
  `test_safe_json.gd`, `test_legacy_user_data.gd` (misma API de `LegacyUserData`).

## Rutas nuevas (todos los dominios)

| Antes | Ahora |
|---|---|
| `scripts/core/safe_json.gd` | `modules/persistence/safe_json.gd` (ahora `class_name SafeJson`) |
| `scripts/core/legacy_user_data.gd` | sigue ahí como adaptador; el mecanismo es `modules/persistence/user_data_migration.gd` |
| `scripts/core/loc_text.gd` | `modules/loc_text/loc_text.gd` |
| `scripts/presentation/synth_audio*.gd` (6) | `modules/synth_audio/` (todos con `class_name`: `SynthAudioSteps`, `SynthAudioTraps`, `SynthAudioRadio`, `SynthAudioCare` nuevos) |
| `scripts/gameplay/vehicle/vehicle_net_smoother.gd` (`VehicleNetSmoother`) | `modules/net_pose_smoother/net_pose_smoother.gd` (**`NetPoseSmoother`**); ya no lee `NetworkManager` en `_init`: `vehicle.gd` llama `configure_sim(NetworkManager.pose_net_sim())` |
| `scripts/presentation/world_quality.gd`, `contact_shadow.gd` (ahora `class_name ContactShadow`) | `modules/render_budget/` |
| `scripts/gameplay/route/dressing_batcher.gd` | `modules/render_budget/dressing_batcher.gd`; `GROUPS`/`SOLID_RULES`/`KNOCKABLE_RULES`/`ANIMATED_PARTS` pasan a `static var piece_groups`/`solid_rules`/`knockable_rules`/`animated_parts` (mismos valores) |
| `scripts/presentation/lowpoly_materials.gd` | sigue ahí (`LowpolyMaterials`, misma API y tablas); el mecanismo es `modules/render_budget/detail_materials.gd` (`DetailMaterials`) |
| `scripts/presentation/acoustic_space.gd`, `scripts/gameplay/route/acoustic_zone.gd` | `modules/acoustics/`; `BUSES`/`SPACES` → `static var buses`/`spaces`; el grupo es `AcousticSpace.GROUP` |

## Herramientas nuevas

- `tools/check_modules.py`: nada dentro de `modules/` puede nombrar el juego (corre en el job `lint`).
- `tools/portability-check.sh`: cada módulo solo, en un proyecto vacío, con sus tests (job `modules`).
- `tools/run-tests.sh`, `tools/lint.sh` y `tools/list-tests.sh` ya incluyen `modules/`.
- Hook: `do-not-drop/modules/*` es zona compartida (`.claude/hooks/lib.sh`).

Qué tiene que hacer Slatex: nada ahora. Si escribís un script nuevo que sea genérico (no sabe de
paquetes, camión ni HUD), ponelo en `modules/<nombre>/` con su `module.cfg` y su test; el resto lo
dice `docs/modulos.md`.
