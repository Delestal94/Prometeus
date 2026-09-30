# Módulos portables — qué se puede llevar a otro juego

> Última actualización: 2026-09-30 (N-230, fases 0 y 1).
> Objetivo: que las piezas genéricas de Take My Package vivan en carpetas que se copian a otro
> proyecto Godot y **funcionan**, con la garantía dada por CI y no por la memoria de nadie.

## La idea en tres reglas

1. **Un módulo es una carpeta** `do-not-drop/modules/<nombre>/` con un `module.cfg` (`name`,
   `summary`, `depends`), sus scripts y `tests/test_*.gd`. Llevarlo a otro juego es copiar la
   carpeta (y las que liste en `depends`).
2. **Adentro de un módulo no existe el juego.** Nada nombra `res://scripts/`, `res://scenes/`,
   `res://data/`, `res://assets/`, un autoload (`EventBus`, `NetworkManager`…), una clase del juego
   ni un `/root/...`. Lo que el módulo necesita del juego lo recibe: por parámetro, por `static var`
   de configuración o por una señal propia. Lo comprueba `tools/check_modules.py` (job `lint` de CI).
3. **La garantía es un proyecto vacío.** `tools/portability-check.sh` arma, por módulo, un proyecto
   Godot con solo esa carpeta y sus dependencias, lo importa y corre sus tests headless ahí (job
   `modules` de CI). Si pasa, el módulo se puede llevar y funciona.

Los tests de los módulos también corren en la batería normal (`tools/run-tests.sh` los descubre en
`modules/*/tests/`), así que un cambio en el juego que rompa un módulo se ve igual que cualquier otro.

## Cómo se conecta el juego con un módulo

El patrón es **módulo = mecanismo; el juego = tablas y cableado**, en un adaptador chico dentro de
`scripts/` que conserva la API que los callers ya usaban:

| Módulo | Adaptador del juego | Qué le pasa el juego |
|---|---|---|
| `render_budget` (`DetailMaterials`) | `scripts/presentation/lowpoly_materials.gd` (`LowpolyMaterials`) | la paleta → mapa de detalle, colores levantados, otoño, qué brilla de noche, la ruta de las texturas |
| `render_budget` (`DressingBatcher`) | los llamadores (`route.gd`, `route_streamer.gd`, `delivery_house.gd`) | `piece_groups`, `solid_rules`, `knockable_rules`, `animated_parts` son `static var` con los valores del juego como default |
| `persistence` (`UserDataMigration`) | `scripts/core/legacy_user_data.gd` (`LegacyUserData`) | la carpeta vieja ("Do Not Drop") y los archivos que se migran |
| `net_pose_smoother` | `vehicle.gd` | `configure_sim(NetworkManager.pose_net_sim())` en `_ready`; el módulo no busca la sesión |
| `ragdoll` | `player.gd` | `setup(jugador, camión, máscara)`: quién lo lleva y con qué capas chocan las piezas |
| `acoustics` | `route_sky.gd`, `tunnel_segment.gd`, `depot.gd` | `buses` y `spaces` son configuración (defaults del juego); las zonas se anotan en el grupo `AcousticSpace.GROUP` |

Regla para escribir un adaptador: si el módulo necesita datos del juego, el adaptador se los da
**antes del primer uso** (`LowpolyMaterials.configure()`), y los lectores del juego siguen usando el
adaptador, nunca el módulo directo, así el orden de inicialización no importa.

## Catálogo (fase 1, hecho)

| Módulo | Clases | Qué es | Depende de |
|---|---|---|---|
| `persistence` | `SafeJson`, `UserDataMigration` | Guardado JSON a prueba de cortes (`.tmp` → `.bak` → archivo; lo corrupto va a `.bad` y vuelve el default) y migración única de archivos desde la carpeta de un nombre viejo | — |
| `loc_text` | `LocText` | Una línea de texto que arma un peer y dibuja otro: viaja como `[clave, args...]` y cada uno la traduce | — |
| `synth_audio` | `SynthAudio`, `SynthAudioScenes`, `SynthAudioCare`, `SynthAudioSteps`, `SynthAudioTraps`, `SynthAudioRadio` | Unos 110 sonidos sintetizados por código (motor, lluvia, pájaros, animales, bocina, campanas, cues de UI), cacheados y compartidos | — |
| `net_pose_smoother` | `NetPoseSmoother` | El cliente dibuja un cuerpo del host un poco en el pasado, interpolando entre poses con reloj; simula lag, jitter y pérdida | — |
| `render_budget` | `WorldQuality`, `DressingBatcher`, `DetailMaterials`, `ContactShadow` | Frames en hardware modesto con GL Compatibility: presets de calidad, miles de mallas estáticas en MultiMesh con colisiones, detalle triplanar con estaciones y luz de noche, sombras de contacto falsas | — |
| `acoustics` | `AcousticSpace`, `AcousticZone` | Reverb en los buses del mundo mientras la cámara está dentro de un volumen (túnel, galpón) | — |
| `ragdoll` | `PlayerRagdoll` | Ragdoll visual de cápsulas para un personaje sin huesos físicos | — |

`tools/check_modules.py --list` imprime esta tabla desde los `module.cfg`.

## Lo que sigue (fases 2 a 5)

Cada fase es un PR que pasa CI. El orden es por valor (lo más caro de rehacer primero) y por riesgo.
Tareas en `docs/tareas-nacho.md` (N-231 a N-234).

| Fase | Módulo nuevo | De dónde sale | Lo que hay que desatar |
|---|---|---|---|
| 2 · Red | `net_session` (`NetSession` + `NetEventBus`), `proximity_voice`, `net_stats` | `network_manager.gd`, `event_bus.gd`, `proximity_voice.gd`, `net_stats.gd` + overlay | El handshake lleva `houses`/`locked`/`runs`: pasa a un `Dictionary` opaco que el juego registra (`session_state_provider`). `relay()` y el salto cliente→host→todos van a una clase base sin señales; `EventBus` del juego la extiende con sus 50+ señales. `NetworkManager` deja de llamar a `UnlockManager`/`RunManager` (señales `session_started`/`restart_requested` que el juego escucha). Siempre con `auditor-red` después. |
| 3 · Interacción y ajustes | `interaction` (`Interactable`, `SeatPoint` genérico), `seat_camera`, `settings_store`, `ui_theme` | `gameplay/interaction/`, `first_person_camera.gd`, `game_settings.gd`, `ui_theme.gd` | `Interactable`: capa de colisión y prompt por `@export`, el grupo del jugador como constante configurable. `SeatPoint`: lo de `carried_package`/`driver`/`tend_package` pasa a métodos virtuales que el asiento del juego sobreescribe. Cámara: `add_shake()`/`kick_fov()` públicos, el juego los conecta a `vehicle_impact`. `SettingsStore`: volumen por bus, teclas, gamepad, pantalla, idioma; los campos del juego (`hud_scale`, ayuda de controles, log) quedan en `GameSettings` que lo extiende. `UiTheme`: paleta y tipografías como `Resource` del juego. Dominio de Slatex: aviso. |
| 4 · Ruta y clima | `route_gen` (`RouteStreamer`, `RouteSegment`, `RoutePlanner`, `RouteTerrain`, `RouteDresser`, tramos), `world_mood` (`WorldMood`, `RouteSky`, `WindshieldRain`) | `gameplay/route/` (parte), `presentation/` (parte) | El planner piensa en "paradas", no "casas". Los tramos reciben la semilla y el `SynthAudio`/materiales por configuración; el cruce de tren saca sus RPC a una señal que el juego relaya. `WorldMood.pick(seed)` en vez de leer `NetworkManager`. Es la fase más grande; se parte en subtareas por tramo. |
| 5 · Sistemas de juego genéricos | `hazards` (`ITrapBehavior` + `TrapDefinition`), `coop_vote` (`ShopVoteManager`), `profile_store` (perfil versionado con migraciones), `event_log` (`RunTelemetry`) | `gameplay/traps/` (contrato), `shop_vote_manager.gd`, `unlock_manager.gd`, `run_telemetry.gd` | `TrapDefinition.NAME_KEYS` pasa a `@export name_key` (hoy hay que editar el archivo por cada trampa nueva). La votación cobra por un `Callable`, no por `CrewProgression`. El perfil separa el motor de versiones/migraciones del esquema del juego. La telemetría escucha un bus que se le pasa. |

Quedan en el juego, a propósito: paquete y trampas concretas, depósito, casas, `CrewProgression`,
`RouteEventManager`, `RunManager`, HUD, menú, jefe y quejas. Son *este* juego.

## Para llevar un módulo a otro proyecto

1. Copiar `do-not-drop/modules/<nombre>/` (y las carpetas de `depends`) a `modules/` del otro
   proyecto. Los scripts usan `class_name`, así que no hace falta registrar nada; Godot los ve al
   importar.
2. Leer el encabezado del script principal: dice qué configura el juego (las `static var`, los
   parámetros de `setup()`), y el `module.cfg` dice qué hace.
3. Copiar también `tests/` del módulo y correrlos ahí (`godot --headless --path . --script
   res://modules/<nombre>/tests/test_<nombre>.gd`): es la misma prueba que corre CI.

## Reglas al tocar un módulo

- Es **zona compartida** (`docs/colaboracion-equipo.md`): commit chico, aviso en `docs/avisos/`.
- Todo cambio de comportamiento lleva su test en `modules/<nombre>/tests/`, que solo puede usar el
  módulo y sus `depends`. Si el test necesita el juego, no va en el módulo: va en `tests/`.
- Un `preload` adentro de un módulo es relativo (`preload("otro.gd")`), nunca `res://modules/...`
  absoluto a sí mismo, para que la carpeta pueda moverse.
- Antes de subir: `python tools/check_modules.py` (medio segundo) y, si tocaste código,
  `tools/portability-check.sh <nombre>` (con el agente `ejecutor-tests`).
- Los defaults de configuración pueden ser los valores del juego (`DressingBatcher.solid_rules`,
  `AcousticSpace.buses`): documentados como configuración, no como constantes. Lo que no puede
  estar adentro es una *referencia* al juego.

## Además del código

Se llevan igual de bien, aunque no son "módulos": el runner de tests headless (`tools/run-tests.sh` y
el patrón `extends SceneTree` + `_expect` + `quit(_failures)`), el lint con baseline
(`tools/lint.sh`), el pipeline low-poly de Blender (`do-not-drop/assets/tools/`,
`tools/generate_lowpoly_assets.py`) y todo `.claude/` (agentes, hooks, rutinas, skills). Es un kit de
estudio: cambian los nombres de las carpetas y los dominios, no el sistema.
