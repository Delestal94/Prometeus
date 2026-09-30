# Aviso: módulos portables, fase 4 — ruta y clima (2026-09-30)

Lo hizo Nacho (con Claude), PR `nacho/N-233-route-gen` (N-233, `docs/modulos.md`). Casi todo es dominio de
Nacho (`scripts/gameplay/route/`); lo que toca a Slatex es **una línea en `game_settings.gd`** y dos lectores
de presentación.

## Qué cambió

- `modules/route_gen/`: `RouteSegment` (movido; `_art()` viste con `DetailMaterials`), `SegmentStreamer` (base
  nueva), `TerrainField` (base nueva, de `route_terrain.gd`), y los tramos `straight`, `speed_bump`, `curve`,
  `s_curve`, `gravel`, `hill` (movidos, mismas clases).
- `scripts/gameplay/route/route_streamer.gd`: `RouteStreamer extends SegmentStreamer`. Misma API
  (`start()`, `distance_along()`, `distance_from_path()`, `point_at()`, `segment_scripts`, `hard_segments`,
  `first_segment_script`, `hard_weight_at()`); los cruces de ciervos van en `_on_segment_spawned()`.
- `scripts/gameplay/route/route_terrain.gd`: extiende `TerrainField`; `route.gd` lo sigue precargando por
  ruta y todas las constantes (`HALO`, `RIVER_MAX_DRIFT`...) se heredan. Las cascadas van en
  `_decorate_river()`, el shader en `_terrain_shader()`, las texturas en `_configure_material()`.
- `modules/world_mood/world_mood.gd`: `WorldMood` movido; ahora escribe la estación y la oscuridad en
  **`DetailMaterials.season` / `DetailMaterials.night_level`** (antes `LowpolyMaterials.*`). Los lectores
  (`house_waiting_marker.gd`, `night_flares.gd`, `route_goal_lot_kit.gd`, `test_house_waiting_marker.gd`)
  ya leen de ahí. `LowpolyMaterials.set_season()`/`set_night_level()` siguen funcionando (reenvían).
- `game_settings.gd` (Slatex): `_ready()` llama `LowpolyMaterials.configure()` para que la paleta del juego
  esté en el módulo antes de que se vista el primer modelo.

## Qué tiene que hacer Slatex

Nada. Si leés la noche o la estación en código nuevo: `DetailMaterials.night_level` / `DetailMaterials.season`.
Un tramo nuevo con modelos: `extends RouteSegment` y sumarlo a `segment_scripts` de `RouteStreamer` (y al
pool de `RoutePlanner` si va en el Reparto).
