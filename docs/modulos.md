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
| `net_session` (`NetSession`) | `scripts/core/network_manager.gd` (`NetworkManager extends NetSession`) | `PROTOCOL_VERSION`, tope de jugadores, escenas de nivel y menú en `_init`; los hooks `_on_hosting`, `_session_state`, `_validate_session_state`, `_apply_session_state`, `_reset_session_state`, `_before_restart`, `_restart_state`, `_apply_restart_state`, `_failure_text` son el mundo de este juego (semilla, casas, trampas bloqueadas, corridas) y sus textos |
| `net_session` (`NetEventBus`) | `scripts/core/event_bus.gd` (`EventBus extends NetEventBus`) | las 50+ señales del juego; `request_ping`/`request_horn` usan `request()` con `request_cooldowns[&"ping_sent"]` |
| `net_session` (`SteamVoice`) | `scripts/core/proximity_voice.gd` (`ProximityVoice extends SteamVoice`) | `_voice_enabled`/`_push_to_talk` leen `GameSettings`; `session = NetworkManager` |
| `net_session` (`NetStatsOverlay`) | `scripts/presentation/net_stats_overlay.gd` | `_theme()` con las fuentes y colores de `UiTheme`, `_severity_color()` con la paleta para daltonismo |
| `interaction` (`SeatPoint`) | `scripts/gameplay/interaction/seat_point.gd` (extiende `SeatPoint`) | `required_mount_path`, `tend_mount_paths` y los hooks `_free_prompt`, `_can_board`, `_accept_boarding`, `_on_boarded`, `_on_released`: la caja del pasajero, la columna de bahías, `carried_package`/`tend_package`/`set_tender` |
| `interaction` (`Interactable`) | los 10 puntos de interacción del juego (`extends Interactable`) | `interaction_layer` (16) y `player_group` (`player`) son `static var` con los valores del juego como default |
| `seat_camera` | `scripts/presentation/first_person_camera.gd` (extiende `SeatCamera`; la escena sigue apuntando ahí) | `_preferred_fov`/`_look_sensitivity`/`_look_y_sign`/`_shake_scale` leen `GameSettings`; `RenderLayers` oculta el cuerpo propio; `EventBus.vehicle_impact` → `add_shake` + `kick_fov`, `package_ruined` → `add_shake` |
| `settings_store` | `scripts/core/game_settings.gd` (`GameSettings extends SettingsStore`) | `SAVED_KEYS`, idiomas, teclas y todas las propiedades del juego con su setter; `_before_load` (migración de "Do Not Drop"), `_after_load`/`_needs_rewrite`/`_before_save` (marca del HUD) |

Regla para escribir un adaptador: si el módulo necesita datos del juego, el adaptador se los da
**antes del primer uso** (`LowpolyMaterials.configure()`), y los lectores del juego siguen usando el
adaptador, nunca el módulo directo, así el orden de inicialización no importa.

## Catálogo (fases 1 a 3, hechas)

| Módulo | Clases | Qué es | Depende de |
|---|---|---|---|
| `persistence` | `SafeJson`, `UserDataMigration` | Guardado JSON a prueba de cortes (`.tmp` → `.bak` → archivo; lo corrupto va a `.bad` y vuelve el default) y migración única de archivos desde la carpeta de un nombre viejo | — |
| `loc_text` | `LocText` | Una línea de texto que arma un peer y dibuja otro: viaja como `[clave, args...]` y cada uno la traduce | — |
| `synth_audio` | `SynthAudio`, `SynthAudioScenes`, `SynthAudioCare`, `SynthAudioSteps`, `SynthAudioTraps`, `SynthAudioRadio` | Unos 110 sonidos sintetizados por código (motor, lluvia, pájaros, animales, bocina, campanas, cues de UI), cacheados y compartidos | — |
| `net_pose_smoother` | `NetPoseSmoother` | El cliente dibuja un cuerpo del host un poco en el pasado, interpolando entre poses con reloj; simula lag, jitter y pérdida | — |
| `render_budget` | `WorldQuality`, `DressingBatcher`, `DetailMaterials`, `ContactShadow` | Frames en hardware modesto con GL Compatibility: presets de calidad, miles de mallas estáticas en MultiMesh con colisiones, detalle triplanar con estaciones y luz de noche, sombras de contacto falsas | — |
| `acoustics` | `AcousticSpace`, `AcousticZone` | Reverb en los buses del mundo mientras la cámara está dentro de un volumen (túnel, galpón) | — |
| `ragdoll` | `PlayerRagdoll` | Ragdoll visual de cápsulas para un personaje sin huesos físicos | — |
| `interaction` | `Interactable`, `SeatPoint` | Blanco pasivo que la sonda del jugador encuentra y activa (host-autoritativo vía `request_interact`) y asiento que sube al jugador, le da su cámara y al conductor el volante; hooks para lo que el asiento significa en el juego | — |
| `seat_camera` | `SeatCamera` | Cámara en primera persona colgada del ancla del asiento: límites por asiento, despeje de paredes, mirar atrás, `add_shake()`, `kick_fov()`; ajustes por hooks | — |
| `settings_store` | `SettingsStore` | Base de un autoload de ajustes: guarda al cambiar, carga por cada setter, idioma, pantalla completa, volumen por bus, teclas reasignables, detección de gamepad, hooks de migración | — |
| `net_session` | `NetSession`, `NetEventBus`, `SteamVoice`, `NetStats`, `NetStatsOverlay` | Sesión cooperativa host-autoritativa: Steam (lobby, invitaciones) o ENet, handshake con versión que lleva el estado del host como diccionario opaco, roster, reinicio, códigos de falla; bus con `relay()` y pedidos de cualquier peer con límite de frecuencia; voz por Steam; estadísticas, `--net-sim` y overlay | — |

`tools/check_modules.py --list` imprime esta tabla desde los `module.cfg`.

## Lo que sigue (fases 2 a 5)

Cada fase es un PR que pasa CI. El orden es por valor (lo más caro de rehacer primero) y por riesgo.
Tareas en `docs/tareas-nacho.md` (N-231 a N-234). Cuando el juego ya tiene un autoload con la API que
todos usan, la forma de sacarle el mecanismo es **herencia**: el módulo es la clase base con hooks
virtuales (`_session_state()`, `_failure_text()`), el autoload la extiende y solo conserva lo suyo. Los
tests que llaman `network.call(&"_handshake_error", ...)` o `network.set(&"world_seed", ...)` siguen
funcionando porque la subclase hereda todo.

| Fase | Módulo nuevo | De dónde sale | Lo que hay que desatar |
|---|---|---|---|
| 2 · Red — **hecho (N-231)** | `net_session` | `network_manager.gd`, `event_bus.gd`, `proximity_voice.gd`, `net_stats.gd` + overlay | Resuelto por **herencia**: el autoload del juego extiende la clase del módulo y rellena hooks virtuales (ver la tabla de adaptadores). El handshake sigue siendo un diccionario plano (`version`, `scene` + lo que devuelve `_session_state()`), así los tests que lo arman a mano no cambian. `PROTOCOL_VERSION` 11: el RPC de reinicio lleva un diccionario y los pedidos de peers pasan por `request()`. |
| 3 · Interacción y ajustes — **hecho (N-232)** | `interaction`, `seat_camera`, `settings_store` | `gameplay/interaction/`, `first_person_camera.gd`, `game_settings.gd` | Herencia otra vez: `SeatPoint` genérico con hooks para lo de la carga; `SeatCamera` con `add_shake()`/`kick_fov()` que el juego conecta a sus eventos; `SettingsStore` con `saved_keys` y hooks de migración. **`UiTheme` queda en el juego a propósito**: es la marca (paleta, dos fuentes, íconos de trampas y acciones en `assets/ui/`); un juego nuevo se lo lleva copiando `ui_theme.gd` + `ui_sounds.gd` y las fuentes, y cambia las constantes. Convertirlo en `Resource` tocaría 40+ llamadores por una portabilidad que ya tiene. |
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
