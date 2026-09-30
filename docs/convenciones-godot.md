# Convenciones técnicas del proyecto Godot — Take My Package

> Última actualización: 2026-09-23
> Complementa `docs/arquitectura.md` con las decisiones concretas de configuración de
> Godot necesarias antes de programar (Input Map, capas de física, convenciones de
> nombres y organización real de escenas dentro de `do-not-drop/`).

## 0. Gotchas encontrados (para no repetirlos)

- **Nunca usar `#`/`##` dentro de un archivo `.tscn`.** El formato de escena de Godot
  no es GDScript — sus comentarios (si hacen falta) van con `;`, como en
  `project.godot`. Un comentario `##` estilo GDScript pegado antes de un bloque
  `[node ...]` corrompe el parseo silenciosamente: el nodo siguiente puede
  directamente no cargarse (sin error claro) o generar errores de física
  aparentemente no relacionados (nos pasó: un `##` corrompió la carga de `Package` y
  produjo un error de escala de Jolt en un nodo completamente distinto). Si hace
  falta explicar una decisión de una escena, el lugar correcto es el script `.gd`
  asociado, no el `.tscn`.
- **Las propiedades custom (`@export var`) de un nodo deben ir *después* de la línea
  `script = ExtResource(...)` en el bloque `[node ...]`.** Godot parece aplicar las
  propiedades en el orden en que aparecen en el archivo; si una propiedad custom
  aparece antes de que el script esté asignado, el nodo todavía no la reconoce como
  válida y el valor se pierde silenciosamente (nos pasó con `controls_enabled` en
  `vehicle.tscn`: quedaba en su default `true` pese a tener `controls_enabled = false`
  escrito, porque estaba antes de `script =`).

## 0.1 Rendimiento (2026-09-23, medido con `tests/bench_drive.gd`)

- **La interpolación de física está activada** (`physics/common/physics_interpolation`,
  con `physics_jitter_fix = 0`). La física corre a 60 Hz pero lo que se ve se dibuja
  interpolado entre ticks; sin esto la cámara del conductor quedaba quieta en el 64%
  de los frames y saltaba en el resto (el "tirón" al ir rápido). Consecuencias:
  - Todo lo que **se teletransporta** (soltar o montar una caja, bajarse de un asiento,
    rescatar a alguien que cayó, un nodo recién creado al que después se le pone
    posición) lleva `reset_physics_interpolation()` justo después, o se dibuja un
    frame "barriendo" desde donde estaba.
  - Lo que tiene que viajar **pegado a algo físico** (el cuerpo de un jugador sentado
    en el camión) se posa en `_physics_process`, no en `_process`: así se interpola
    igual que el camión. Posado cada frame quedaría en la pose cruda del tick y
    temblaría contra la cabina.
  - Mirar con mouse/stick en `_input`/`_process` sigue siendo inmediato; no hace falta
    tocar las cámaras.
- **El decorado de la ruta se hornea para dibujarlo** (`dressing_batcher.gd`): después
  de que `RouteDresser` coloca cada pieza, todo lo estático (sin script, sin animación,
  sin colisión, no espejado) se funde en `MultiMeshInstance3D` por modelo y por parche
  de 48 m, las casas en una malla cada una y los bordes/líneas de cada tramo en una
  malla por material. Si agregás un prop que **se mueve o reacciona**, dale un script
  (o un nodo que no sea `Node3D`/`MeshInstance3D`) y queda como nodo; si no, se hornea.
  Los tests que inspeccionan piezas sueltas construyen la ruta con
  `batch_dressing = false`.
- En GL Compatibility **cada `MeshInstance3D` visible es un draw call** (y otra vez por
  cada cascada de sombra). Un modelo armado con muchas partes cuesta una llamada por
  parte: para cosas que se repiten, preferí fusionarlas o hornearlas.
- `SynthAudio` genera cada sonido una sola vez y lo comparte (hasta 12 ms por sonido
  en GDScript); no mutes el `AudioStreamWAV` que devuelve.

## 0.2 Red: RPC y replicación (N-221, 2026-09-30)

- **Subir `NetworkManager.PROTOCOL_VERSION` con cada cambio de RPC o de replicación:** agregar, sacar,
  renombrar o cambiar los argumentos de un `@rpc` (Godot numera los RPC de cada script, así que un
  cliente viejo llamaría a otro método), cambiar qué replica un `MultiplayerSynchronizer` o qué se
  spawnea, o el significado de un dato que viaja (un texto que pasa a ser clave, un diccionario con
  otras claves, lo que lleva el handshake). Se anota el motivo en el comentario de la constante. Así un
  cliente viejo con un host nuevo recibe "otra versión" en el handshake en vez de un juego roto sin
  explicación.
- **Todo `@rpc("any_peer")` pasa por `RpcGuard`** (`modules/net_session/rpc_guard.gd`): el remitente
  (`sender_ok()`, `from_host()` o `get_remote_sender_id()` comparado con quien corresponde), el cupo por
  peer en los pedidos confiables (`allow_request()`: 40 de golpe y 20 por segundo; las llamadas del host
  no gastan), `finite_float/vec2/vec3/transform()` para números, vectores y poses (un `NaN` en una pose
  rompe Jolt para todos), `dict_ok()` para diccionarios, `args_ok()` para arreglos y `text_ok()` para
  textos. `tests/test_rpc_guard.gd` lee cada RPC `any_peer` del proyecto (módulos incluidos) y falla si
  falta alguno; el que no pueda cumplirlo va a su `EXCEPTIONS` con el motivo. `EventBus.request()`
  solo acepta los eventos de `request_cooldowns`.
- **El color de un jugador es `PlayerColorSlot.slot(peer_id, paleta.size())`**, nunca `peer_id % 5`: sale
  de `NetworkManager.color_slot()`, que el host reparte por orden de llegada (el host siempre el 0, también
  jugando solo), es igual en todos los peers y el que se cae y vuelve recupera el suyo (N-221). Los lectores
  que guardan el color escuchan `color_slots_changed` (`PlayerColorSlot.follow()`). La campaña guarda mérito
  y cartas por ese índice.

## 1. Input Map (Project Settings → Input Map)

> Actualizado 2026-09-21 para reflejar lo que realmente está implementado en
> `project.godot` (la tabla original era el plan previo a programar; difiere en
> algunos nombres — p.ej. `drive_left`/`drive_right` en vez de un solo `drive_steer`).

| Acción (nombre interno) | Input por defecto (teclado) | Input por defecto (gamepad) |
|---|---|---|
| `drive_accelerate` | W | Gatillo derecho |
| `drive_brake` | S | Gatillo izquierdo |
| `drive_left` / `drive_right` | A / D | Stick izquierdo (eje X) |
| `drive_handbrake` | Espacio | Botón Sur (A/X) |
| `interact` | E | Botón Sur (A/X) — agarrar, dejar y sentarse, a pie |
| `walk_forward` / `walk_backward` | W / S | Stick izquierdo (eje Y) |
| `look_left` / `look_right` / `look_up` / `look_down` | — (mouse, delta directo) | Stick derecho (ejes X/Y) |
| `look_center` | C | Clic del stick derecho |
| `sprint` | Shift (mantener, reasignable en Opciones) | Clic del stick izquierdo (mantener) |
| `package_action_primary` | Clic izquierdo | Gatillo derecho (a pie, con paquete en mano) |
| `ui_ping` | Clic de la rueda del mouse | Botón D-pad arriba |
| `use_card` | G (reasignable) | Botón D-pad izquierda |
| `drive_horn` | H | Botón Este (B/Círculo) |
| `ui_pause` | Esc | Start |
| `run_restart` | R | Botón Oeste (X/Cuadrado) |
| `crew_panel` | Tab (mantener) | Botón Back/Select (mantener) — panel de tripulación en el depósito (`crew_panel.gd`, S-507) |
| `toggle_net_stats` | F3 | — (panel de red, `net_stats_overlay.gd`; no reasignable) |

`crew_panel` comparte Tab y Back con `spectate_toggle` (vista de espectador, `spectator_camera.gd`) a propósito:
el espectador solo existe con el camión en ruta y el panel solo con el depósito abierto (`CrewPanel.in_depot()`),
así que nunca compiten. No quedan botones de gamepad libres (los cuatro del D-pad, los gatillos, los
bumpers, los sticks, Start y las caras están tomados), y Tab es la tecla de "quién está en la sala".
Si alguna vez se necesita el panel durante la ruta, hay que separar las teclas.

`sprint` comparte botón con `look_back` en el gamepad (clic del stick izquierdo): nunca están activos a
la vez, `sprint` es a pie y `look_back` es sentado (`player_sprint.gd`, `first_person_camera.gd`).

Caminar y conducir comparten `W`/`S`: nunca están activos a la vez, porque un jugador
es conductor o pasajero a pie, no ambos en la misma escena. La mirada en primera
persona con mouse no pasa por el Input Map para el delta continuo (se lee directo de
`InputEventMouseMotion`); `look_left/right/up/down` cubre el equivalente en gamepad, y
`look_center` es la única parte de "mirar" que sí necesita una Input Action mapeable
(una tecla/botón discreto).

Pendiente de implementar (documentado en `docs/controles-y-ui.md` como diseño, todavía
no en `project.godot`): un control de trampa secundario por tipo.

`ui_ping` conserva “¡Cuidado!” con un toque corto. Al mantenerlo abre una rueda de
seis mensajes, seleccionable con mouse o stick derecho. Ver el catálogo compartido
en `scripts/ui/ping_catalog.gd` y el envío en `Player._send_ping()`.

## 2. Capas de física (Project Settings → Layer Names → 3D Physics)

| Capa # | Nombre | Qué la usa |
|---|---|---|
| 1 | `environment` | Terreno, tramos de camino, geometría estática |
| 2 | `vehicle` | El `VehicleBody3D` |
| 3 | `package` | Cada `Package` (RigidBody3D) |
| 4 | `player` | Los `CharacterBody3D` de cada jugador (si se implementan cuerpos visibles, no solo cámara) |
| 5 | `interaction_area` | `Area3D` que detecta qué jugador puede interactuar con qué paquete |
| 6 | `route_trigger` | Zonas invisibles que disparan el streaming de tramos (spawn/despawn) |

**Máscaras recomendadas**:
- `vehicle` colisiona con `environment` (para la física de manejo) y con `package`
  (para que los golpes del vehículo se transmitan a la carga vía el `CargoBay`, si los
  paquetes no están rígidamente anclados).
- `package` colisiona con `vehicle` y consigo mismo (para que se puedan golpear entre
  ellos si se caen), pero **no** con `environment` directamente si están dentro de la
  caja de la camioneta (evita que "se caigan del mundo" por error de física).
- `interaction_area` solo detecta `player`, no genera colisión física real (Area3D en
  modo monitor).
- **Decorado físico local** (la caja de herramientas y el termo de `cargo_clutter.gd`):
  capa `0` y máscara `environment | vehicle`. Nadie los busca, así que nunca tocan
  paquetes ni jugadores, y como no se replican cada peer simula los suyos. No pueden
  desincronizar el camión: en los clientes el camión está congelado y lo posiciona el
  host, y en el host pesan menos del 1 % del camión (`test_cargo_clutter`). Cualquier
  objeto suelto nuevo que sea solo decorado va igual.

## 3. Organización de escenas dentro de `do-not-drop/`

> Actualizado 2026-09-21 para reflejar la estructura real del proyecto, no el plan
> previo a programar. Dos diferencias de fondo con ese plan original: (1) no hay
> escenas separadas para menú/HUD/resultados — `main_menu.tscn` es un wrapper mínimo
> que arma toda la UI en código (`main_menu.gd`), y el HUD (`prototype_hud.gd`) y la
> pantalla de resultados viven igual, sin `.tscn` propio; (2) los "componentes" de
> paquete/vehículo no se separaron en nodos/scripts independientes por responsabilidad
> como sugería el plan — cada entidad (`package.gd`, `vehicle.gd`, `player.gd`) es un
> único script que concentra su estado, networking e input. Fue la decisión pragmática
> mientras el proyecto es un prototipo de 1-2 fases; si la complejidad lo justifica más
> adelante, se puede partir en componentes reales sin romper la interfaz pública de
> cada entidad.

```
do-not-drop/
  modules/                      # portables: se copian a otro juego y funcionan (docs/modulos.md)
    persistence/                # SafeJson, UserDataMigration
    loc_text/                   # LocText
    synth_audio/                # SynthAudio + vehículo, trampas, mundo, animales, escenas, cuidado, pasos, radio, dsp
    net_pose_smoother/          # NetPoseSmoother
    render_budget/              # WorldQuality, DressingBatcher, DetailMaterials, ContactShadow
    acoustics/                  # AcousticSpace, AcousticZone
    ragdoll/                    # PlayerRagdoll
    net_session/                # NetSession, NetEventBus, RpcGuard, SteamVoice, NetStats, NetStatsOverlay
    interaction/                # Interactable, SeatPoint (genérico, con hooks)
    seat_camera/                # SeatCamera
    settings_store/             # SettingsStore
    route_gen/                  # RouteSegment, SegmentStreamer, TerrainField, 6 tramos por código
    world_mood/                 # WorldMood
    hazards/                    # ITrapBehavior, TrapDefinition
    coop_vote/                  # CoopVote
    unlock_profile/             # UnlockProfile
    run_log/                    # RunLog
    <nombre>/module.cfg         # name, summary, depends; tests/ propios del módulo
  scenes/
    ui/
      main_menu.tscn            # wrapper mínimo, la UI se arma en main_menu.gd
    gameplay/
      level_base.tscn           # composición de ruta + spawns + reglas de partida
      vehicle/
        vehicle.tscn
      package/
        package.tscn
      player/
        player.tscn
      route/
        route.tscn
    presentation/
      first_person_camera.tscn
  scripts/
    core/
      event_bus.gd             # autoload, extiende NetEventBus (modules/net_session)
      run_manager.gd           # autoload
      network_manager.gd       # autoload, extiende NetSession (modules/net_session)
      game_settings.gd         # autoload, extiende SettingsStore (modules/settings_store)
    ui/
      main_menu.gd
      prototype_hud.gd          # HUD + resultados, sin escena propia
    presentation/
      first_person_camera.gd    # extiende SeatCamera (modules/seat_camera)
      lowpoly_materials.gd      # adaptador: las tablas del juego para modules/render_budget
    gameplay/
      level_base.gd
      vehicle/
        vehicle.gd
        vehicle_input_component.gd
      package/
        package.gd
        package_feedback.gd
      player/
        player.gd
      interaction/              # las bases (Interactable, SeatPoint) están en modules/interaction
        package_mount_point.gd
        package_pickup_point.gd
        seat_point.gd           # extiende el SeatPoint del módulo con la carga
      traps/                    # el contrato (ITrapBehavior, TrapDefinition) está en modules/hazards
        fragile_trap_behavior.gd
        growing_weight_trap_behavior.gd
        balance_trap_behavior.gd
        noisy_trap_behavior.gd
      route/
        route.gd                 # ruta curada a mano, la que se juega hoy
        route_smoke_check.gd
        route_planner.gd         # qué tramo va dónde en la ruta de entregas
        route_streamer.gd        # extiende SegmentStreamer (modules/route_gen): pools y semilla del juego
        route_terrain.gd         # extiende TerrainField (modules/route_gen)
        segments/                # solo los tramos con assets; los de puro código están en modules/route_gen
          chicane_segment.gd
          narrow_bridge_segment.gd
          construction_zone_segment.gd
          rail_crossing_segment.gd
          tunnel_segment.gd
  data/
    traps/
      fragile.tres
      growing_weight.tres
      balance.tres
      noisy.tres
  tests/
    test_*.gd, check_*.gd       # scripts SceneTree, corren headless (ver README); los de cada módulo, en modules/<nombre>/tests/
```

`UnlockManager` sí existe desde la Fase 5: centraliza el perfil local, los desbloqueos
y las elecciones persistentes. `GameManager`, `AudioManager` y un `StateMachine`
genérico siguen siendo diseño futuro; la música y los efectos actuales viven en los
componentes de presentación.

## 4. Convenciones de nombres

- **Archivos y carpetas**: `snake_case` (estándar de Godot/GDScript).
- **Nodos dentro de una escena**: `PascalCase` (estándar del editor de Godot).
- **Clases reutilizables** (`class_name`): `PascalCase`, con prefijo `I` para
  interfaces/clases base abstractas (`ITrapBehavior`).
- **Señales**: verbo en pasado, `snake_case` (`package_ruined`, `run_started`).
- **Autoloads**: nombre del singleton en `PascalCase` tal como se accede desde código
  (`EventBus.package_ruined.emit(...)`), archivo en `snake_case`
  (`event_bus.gd`).
- **Resources de datos** (`.tres`): nombre descriptivo en `snake_case`
  (`fragile.tres`, `van_default.tres`), ubicados en `data/<categoría>/`.

## 5. Autoloads registrados (Project Settings → Autoload)

Orden real en `project.godot` (importa por dependencias en `_ready()`):
1. `EventBus`
2. `NetworkManager`
3. `RunManager`
4. `CrewProgression`
5. `ShopVoteManager`
6. `RouteEventManager`
7. `GameSettings`
8. `UnlockManager`

`GameManager` y `AudioManager` siguen en el plan original pero no están registrados.
`UnlockManager` y `GameSettings` sí lo están (ver nota de la sección 3).

## 6. `PROTOCOL_VERSION` (red)

`NetworkManager.PROTOCOL_VERSION` (`scripts/core/network_manager.gd`) sube en **cada** cambio de RPC
(uno nuevo, uno renombrado, argumentos distintos: los ids de RPC se ordenan por nombre y se corren
todos) o de replicación (propiedades de un `MultiplayerSynchronizer`, spawners). Host y cliente con
números distintos no se conectan, con un error claro; con el mismo número y distinto protocolo se
desincronizan en silencio.

Cómo elegir el número sin chocar con otro PR en vuelo:
1. Antes de subirlo, mirá los PRs abiertos que tocan `network_manager.gd` (en la nube, con
   `mcp__github__list_pull_requests` y su diff) y tomá **el siguiente al más alto** entre `main` y
   esos PRs, no el siguiente al de `main`.
2. Sumá la línea `## N: qué cambió, <ID>` al historial del comentario de arriba de la constante.
   Así dos ramas con el mismo número chocan en git (líneas distintas en el mismo lugar) en vez de
   mezclarse solas, y `test_protocol_version` (PR #122) exige el historial único y consecutivo.
3. Si al mezclar `main` el número ya lo usó otro PR, subí al siguiente libre y corregí tu línea del
   historial; nada más.

## Próximo paso
Con esto, la Fase 1 del plan de desarrollo tiene todo lo necesario para arrancar sin
ambigüedad: Input Map, capas de física y estructura de carpetas ya definidas. El
siguiente paso lógico es la Definition of Done de la Fase 1 (ver actualización en
`docs/plan-desarrollo.md`).
