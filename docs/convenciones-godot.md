# Convenciones técnicas del proyecto Godot — Do Not Drop

> Última actualización: 2026-09-20
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

## 1. Input Map (Project Settings → Input Map)

> Actualizado 2026-09-20 para reflejar lo que realmente está implementado en
> `project.godot` (la tabla original era el plan previo a programar; difiere en
> algunos nombres — p.ej. `drive_left`/`drive_right` en vez de un solo `drive_steer`).

| Acción (nombre interno) | Input por defecto (teclado) | Input por defecto (gamepad) |
|---|---|---|
| `drive_accelerate` | W | Gatillo derecho |
| `drive_brake` | S | Gatillo izquierdo |
| `drive_left` / `drive_right` | A / D | Stick izquierdo (eje X) |
| `drive_handbrake` | Espacio | Botón Sur (A/X) |
| `interact` | E | Botón Sur (A/X) — agarrar, dejar y sentarse, a pie |
| `ui_pause` | Esc | Start |
| `run_restart` | R | Botón Oeste (X/Cuadrado) |
| *(mirada en primera persona, a pie)* | Mouse (delta directo, no es una Input Action) | — pendiente para Fase 4 |

Pendiente de implementar (documentado en `docs/controles-y-ui.md` como diseño, todavía
no en `project.godot`): `drive_horn`, controles de trampa específicos por tipo
(`package_action_primary`/`secondary`), y `ui_ping`. Se agregan cuando la Fase 2 sume
las trampas restantes.

**Nota**: `package_direction` y `drive_steer` pueden convivir sin conflicto porque
nunca están activos en el mismo cliente a la vez (un jugador es conductor O pasajero,
no ambos en la misma partida).

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

## 3. Organización de escenas dentro de `do-not-drop/`

```
do-not-drop/
  scenes/
    main_menu/
      main_menu.tscn
    lobby/
      lobby.tscn
    gameplay/
      level_base.tscn          # composición de ruta + spawns + reglas de partida
      vehicle/
        vehicle.tscn
      package/
        package_base.tscn      # Package genérico, la trampa se inyecta como recurso
      player/
        player.tscn
    ui/
      hud.tscn
      results_screen.tscn
  scripts/
    core/
      state_machine.gd
      event_bus.gd            # autoload
      game_manager.gd         # autoload
      run_manager.gd          # autoload
      unlock_manager.gd       # autoload
      network_manager.gd      # autoload
    gameplay/
      vehicle/
        vehicle_input_component.gd
      package/
        package_state_component.gd
        package_net_sync_component.gd
      traps/
        i_trap_behavior.gd     # clase base abstracta
        fragile_trap_behavior.gd
        growing_weight_trap_behavior.gd
        balance_trap_behavior.gd
        noisy_trap_behavior.gd
      route/
        route_segment.gd
        route_streamer.gd
  data/
    traps/
      fragile.tres
      growing_weight.tres
      balance.tres
      noisy.tres
    vehicles/
      van_default.tres
    route_segments/
      straight.tres
      curve_left.tres
      curve_right.tres
      narrow_bridge.tres
      speed_bump.tres
```

Esto es la traducción concreta de la estructura conceptual definida en
`docs/arquitectura.md` sección 1, ya adaptada a cómo se ve dentro de un proyecto Godot
real (Godot mezcla naturalmente `scenes/` y `scripts/` como carpetas de primer nivel,
en vez de una sola jerarquía por feature — se mantiene la separación por dominio
dentro de cada una).

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

## 5. Autoloads a registrar (Project Settings → Autoload)

Orden de registro (importa si hay dependencias en `_ready()`):
1. `EventBus`
2. `UnlockManager` (lee guardado en disco)
3. `GameManager`
4. `RunManager`
5. `NetworkManager`
6. `AudioManager`

## Próximo paso
Con esto, la Fase 1 del plan de desarrollo tiene todo lo necesario para arrancar sin
ambigüedad: Input Map, capas de física y estructura de carpetas ya definidas. El
siguiente paso lógico es la Definition of Done de la Fase 1 (ver actualización en
`docs/plan-desarrollo.md`).
