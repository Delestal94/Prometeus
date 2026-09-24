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
| `package_action_primary` | Clic izquierdo | Gatillo derecho (a pie, con paquete en mano) |
| `ui_ping` | Clic de la rueda del mouse | Botón D-pad arriba |
| `drive_horn` | H | Botón Este (B/Círculo) |
| `ui_pause` | Esc | Start |
| `run_restart` | R | Botón Oeste (X/Cuadrado) |

Caminar y conducir comparten `W`/`S`: nunca están activos a la vez, porque un jugador
es conductor o pasajero a pie, no ambos en la misma escena. La mirada en primera
persona con mouse no pasa por el Input Map para el delta continuo (se lee directo de
`InputEventMouseMotion`); `look_left/right/up/down` cubre el equivalente en gamepad, y
`look_center` es la única parte de "mirar" que sí necesita una Input Action mapeable
(una tecla/botón discreto).

Pendiente de implementar (documentado en `docs/controles-y-ui.md` como diseño, todavía
no en `project.godot`): un control de trampa secundario por tipo.

`ui_ping` es deliberadamente un solo mensaje fijo ("¡Cuidado!"), no una rueda de
opciones — cubre la necesidad real (avisar a los compañeros) sin sumar UI de
selección todavía. Ver `Player._send_ping()` en `player.gd`.

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
      event_bus.gd             # autoload
      run_manager.gd           # autoload
      network_manager.gd       # autoload
    ui/
      main_menu.gd
      prototype_hud.gd          # HUD + resultados, sin escena propia
    presentation/
      first_person_camera.gd
      synth_audio.gd            # waveforms generadas en código (bocina), sin assets
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
      interaction/
        interactable.gd         # clase base para puntos interactuables
        package_mount_point.gd
        package_pickup_point.gd
        seat_point.gd
      traps/
        i_trap_behavior.gd      # clase base abstracta
        trap_definition.gd
        fragile_trap_behavior.gd
        growing_weight_trap_behavior.gd
        balance_trap_behavior.gd
        noisy_trap_behavior.gd
      route/
        route.gd                 # ruta curada a mano, la que se juega hoy
        route_smoke_check.gd
        route_segment.gd         # base chainable para streaming (Fase 3)
        route_streamer.gd        # spawn/cull de tramos, no integrado al juego todavía
        segments/
          straight_segment.gd
          speed_bump_segment.gd
          chicane_segment.gd
          narrow_bridge_segment.gd
  data/
    traps/
      fragile.tres
      growing_weight.tres
      balance.tres
      noisy.tres
  tests/
    test_*.gd, check_*.gd       # scripts SceneTree, corren headless (ver README)
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

## Próximo paso
Con esto, la Fase 1 del plan de desarrollo tiene todo lo necesario para arrancar sin
ambigüedad: Input Map, capas de física y estructura de carpetas ya definidas. El
siguiente paso lógico es la Definition of Done de la Fase 1 (ver actualización en
`docs/plan-desarrollo.md`).
