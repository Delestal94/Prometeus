# Arquitectura del proyecto — Do Not Drop

> Basado en: `docs/requerimientos-tecnicos.md` y `docs/plan-desarrollo.md`.
> Última actualización: 2026-09-20
> Objetivo: arquitectura modular, reutilizable y con buenas prácticas profesionales,
> pensada para que agregar contenido (trampas, vehículos, tramos) no requiera tocar
> el código central, y para que la IA pueda asistirte trabajando sobre piezas
> aisladas sin romper el resto del sistema.

## Principios de diseño (por qué está armado así)

1. **Composición sobre herencia**: las entidades (vehículo, paquete, jugador) se arman
   combinando componentes chicos e independientes, no con árboles de herencia
   profundos. Godot está pensado para esto de forma nativa (nodos como componentes).
2. **Diseño data-driven**: el contenido (tipos de trampa, vehículos, tramos) se define
   en **Resources** (`.tres`), no hardcodeado en scripts. Agregar una trampa nueva debe
   ser "crear un archivo de datos + un script de comportamiento", no tocar el loop
   central.
3. **Separación simulación / presentación**: la lógica que determina el resultado del
   juego (¿el paquete se rompió?, ¿ganamos?) vive separada de lo que el jugador ve/oye
   (VFX, cámara, sonido). Esto es crítico en multiplayer: la simulación corre con
   autoridad en el host, la presentación corre igual en todos los clientes.
4. **Bajo acoplamiento vía señales (Event Bus)**: los sistemas no se llaman entre sí
   directamente cuando no hace falta — emiten señales a las que otros sistemas se
   suscriben. Así el sistema de puntaje, el de audio y el de red pueden reaccionar al
   mismo evento sin conocerse entre sí.
5. **Interfaces claras para lo que se puede extender**: todo lo que va a crecer con el
   tiempo (trampas, tramos, vehículos) se define contra una interfaz/contrato fijo, no
   contra la implementación de un caso particular.

---

## 1. Estructura de carpetas

> Este es el diseño conceptual original. La estructura real dentro de `do-not-drop/`
> (que es lo que hay que mirar para ubicar un archivo) está en
> `docs/convenciones-godot.md` sección 3 — Godot mezcla `scenes/`/`scripts/` como
> carpetas de primer nivel en vez de esta jerarquía por dominio, y varias carpetas de
> acá (`networking/`, `progression/`, `ui/menus/`) no llegaron a crearse porque su
> contenido todavía no existe (ver sección 2 de más abajo).

```
res://
  core/                 # Sistemas centrales, independientes del contenido específico
    autoloads/          # Singletons globales (ver sección 2)
    state_machine/       # Máquina de estados genérica reutilizable
    event_bus/           # Definición de señales globales
  gameplay/
    vehicle/             # Componentes y lógica del vehículo
    package/             # Entidad Package + sus componentes
    traps/               # Comportamientos de trampa (implementan ITrapBehavior)
    route/                # Sistema de tramos y streaming
  networking/
    sync/                 # Wrappers/helpers de MultiplayerSynchronizer
    authority/            # Lógica de quién tiene autoridad sobre qué
  progression/
    unlocks/              # Sistema de desbloqueos y guardado
  data/                   # Resources (.tres) de contenido: trampas, vehículos, tramos
    traps/
    vehicles/
    route_segments/
  ui/
    hud/
    menus/
  presentation/           # VFX, cámara, audio — nunca lógica de resultado del juego
    vfx/
    camera/
    audio/
  scenes/                 # Escenas compuestas (nivel, lobby, menú principal)
```

**Regla clave**: `gameplay/` nunca depende de `ui/` ni de `presentation/` directamente
— la comunicación va por señales del Event Bus. Esto permite testear/ajustar la lógica
de juego sin arte ni UI final, tal como definimos en el plan de desarrollo (fases 1-3
antes que el pase de arte).

---

## 2. Autoloads (singletons globales)

| Autoload | Responsabilidad | Estado |
|---|---|---|
| `EventBus` | Señales globales desacopladas (ver sección 5). Único punto de "broadcast" del juego. | Registrado |
| `RunManager` | Estado de la partida en curso: ruta actual, paquetes activos, puntaje, tiempo. Se resetea entre partidas. | Registrado |
| `NetworkManager` | Setup de host/cliente (Steam y ENet), conexión de jugadores, mapeo de autoridad. | Registrado |
| `GameManager` | Estado de alto nivel del flujo del juego (menú → lobby → en partida → resultados). Máquina de estados. | **No existe aún** — el flujo de menú/nivel hoy lo maneja `main_menu.gd` + `get_tree().change_scene_to_file()`, sin autoload propio. |
| `UnlockManager` | Progreso meta del jugador (trampas/vehículos/cosméticos desbloqueados) + guardado/carga. | **No existe aún** — no hay progresión persistente todavía (Fase 5). |
| `AudioManager` | Reproducción de música/SFX desacoplada, escucha del `EventBus`. | **No existe aún** — no hay música/sfx dinámicos todavía. |

Ninguno de estos conoce los detalles internos de los otros — se comunican por señales
o por métodos públicos mínimos y bien definidos.

---

## 3. Entidades como composición de componentes

> **Estado real (2026-09-21)**: esta sección describe el diseño planeado antes de
> programar. En la implementación actual, cada entidad concentra su estado, input y
> sincronización de red en **un solo script** (`vehicle.gd`, `package.gd`,
> `player.gd`) en vez de partirse en los componentes/nodos separados de abajo — fue
> la decisión pragmática mientras el proyecto es un prototipo de 1-2 personas en
> Fases 1-2, evita el overhead de coordinar señales entre varios nodos por una
> ganancia de modularidad que todavía no hace falta. Los árboles de componentes de
> esta sección quedan como **diseño de referencia**, útil si la complejidad futura lo
> justifica (ver `docs/convenciones-godot.md` sección 3), no como lo que hay que leer
> en el código hoy.

### Vehículo
```
Vehicle (VehicleBody3D)
├── VehicleInputComponent      # traduce input del conductor a fuerzas
├── VehicleAudioComponent      # motor, frenos (presentación)
├── VehicleDamageComponent     # opcional: estado del vehículo si se agrega más adelante
└── CargoBay (Node3D)          # punto de anclaje donde "viven" los Package
```

### Package (paquete)
```
Package (RigidBody3D)
├── TrapBehaviorComponent      # referencia a un ITrapBehavior (ver sección 4)
├── PackageStateComponent      # estado: OK / EnRiesgo / Arruinado (máquina de estados)
├── PackageFeedbackComponent   # presentación: partículas, sonido según estado
└── PackageNetSyncComponent    # qué campos se sincronizan en red
```

**Por qué así**: si mañana un paquete necesita una capacidad nueva (ej. que también
pueda "explotar" y dañar a otros paquetes cercanos), se agrega un componente nuevo sin
tocar los existentes — cumple el principio abierto/cerrado.

### Player
```
Player (CharacterBody3D)
├── PlayerInputComponent
├── PlayerRagdollComponent     # activa físicas de ragdoll en impactos fuertes
└── PlayerNetSyncComponent
```

---

## 4. Sistema de trampas — interfaz + datos (el núcleo de la reutilización)

### Contrato (interfaz)
Todo tipo de trampa implementa el mismo contrato, por ejemplo como una clase base
abstracta en GDScript (`class_name ITrapBehavior extends Resource`):

- `on_setup(package, config)` — inicializa el estado con los datos de configuración.
- `on_physics_process(package, delta, vehicle_state)` — reacciona a la física del
  vehículo (sacudida, frenada, ángulo) cada frame de física.
- `on_player_input(package, input_event)` — reacciona a la interacción del jugador
  (resolver el puzzle, sostener el equilibrio, etc.).
- `get_state() -> TrapState` — devuelve OK / EnRiesgo / Arruinado para que
  `PackageStateComponent` lo use.

### Implementaciones concretas (una por tipo de trampa del catálogo)
- `FragileTrapBehavior`
- `GrowingWeightTrapBehavior`
- `BalanceTrapBehavior`
- `NoisyTrapBehavior`

Cada una es un script chico e independiente. **Agregar una trampa nueva post-launch =
crear un script que implemente `ITrapBehavior` + un Resource `.tres` con sus
parámetros (umbral de falla, velocidad de crecimiento, etc.) — cero cambios en
`Package`, `RunManager` ni en el networking.**

### Configuración como datos (Resources)
```
TrapDefinition (Resource)
  - id: String
  - display_name: String
  - behavior_script: Script       # cuál ITrapBehavior usar
  - difficulty: int
  - params: Dictionary            # umbral de falla, velocidades, etc.
```
Esto permite además que el `UnlockManager` y el sistema de asignación aleatoria de
trampas (sección 3.3 del doc técnico) trabajen sobre una lista de `TrapDefinition`
sin conocer los detalles de cada comportamiento.

---

## 5. Event Bus (señales globales)

Señales reales declaradas en `event_bus.gd` (16, actualizado 2026-09-21):

- `cargo_registered(package_id, display_name)`
- `package_hint_changed(package_id, hint)`
- `package_state_changed(package_id, new_state)`
- `package_integrity_changed(package_id, integrity, maximum)`
- `package_ruined(package_id, cause)`
- `package_damaged(package_id, damage)`
- `vehicle_telemetry(speed_kmh)`
- `vehicle_impact(strength, impact_position)`
- `run_started(route_id, players)`
- `run_ended(score, results)`
- `route_progress_changed(progress, remaining_meters, section)`
- `delivery_status_changed(in_zone, stopped_seconds)`
- `start_requested`
- `restart_requested`
- `pause_requested`
- `interaction_prompt_changed(prompt)`

El HUD, `RunManager` y el `NetworkManager` escuchan estas señales cada uno por su
cuenta. Ninguno le pide nada directamente a `Package` ni a `Vehicle` — esto es lo que
permite tocar/reemplazar cualquiera de esos sistemas sin romper a los demás (clave
para trabajar de a partes con asistencia de IA). `AudioManager` no existe todavía
(ver sección 3 de `docs/convenciones-godot.md`).

**Patrón de relay para multijugador**: una señal emitida localmente en el host no
llega sola a los clientes — `EventBus` expone un método `relay()` que envuelve la
emisión en una RPC (`@rpc("authority", "call_local", ...)`), así que el host la
retransmite explícitamente a todos los peers y cada cliente la recibe como si la
hubiera emitido localmente. `package_hint_changed`, por ejemplo, se relayea con un
throttle de 0.25s (`HINT_RELAY_INTERVAL` en `package.gd`) para que el texto de ayuda
de una trampa no quede desactualizado en clientes que no son el host.

---

## 6. Máquinas de estado

### Flujo general del juego (`GameManager`)
`MainMenu → Lobby → Loading → InRun → Results → Lobby`

### Estado de cada paquete (`PackageStateComponent`)
`OK → EnRiesgo → Arruinado` (con posibilidad de volver de `EnRiesgo` a `OK` si el
jugador corrige a tiempo, según el tipo de trampa).

Usar una máquina de estados genérica y reutilizable en `core/state_machine/` (no una
implementación distinta para cada caso) — un solo componente `StateMachine` que
recibe estados como Resources/objetos y dispara señales `state_entered`/`state_exited`.

---

## 7. Arquitectura de red (autoridad y sincronización)

- **Modelo de autoridad**: el host es autoritativo sobre la física del vehículo y el
  resultado de cada trampa (evita desincronización/trampas de clientes). Los clientes
  **envían inputs**, no resultados.
- `PackageNetSyncComponent` y el vehículo usan `MultiplayerSynchronizer` para replicar
  únicamente lo necesario (transform del vehículo, estado de cada paquete — no la
  física completa de cada rigidbody si se puede evitar, para ahorrar ancho de banda).
- La resolución del puzzle individual de cada trampa puede simularse localmente en el
  cliente del jugador que la sostiene (para que se sienta responsiva, sin lag) y
  sincronizar solo el resultado final al host, que valida y hace autoritativo el
  estado.
- Esta separación (input del cliente → simulación en host → estado replicado) es
  exactamente lo que permite que `NetworkManager` sea un módulo aparte que no necesita
  saber nada de cómo funciona una trampa específica.

---

## 8. Progresión y guardado

- `UnlockManager` guarda una lista de IDs desbloqueados (trampas, vehículos,
  cosméticos) en un archivo de guardado simple (`.tres` o JSON local).
- El sistema de asignación de contenido en cada partida (qué trampas/vehículos están
  disponibles) consulta a `UnlockManager`, no al revés — mantiene la dependencia en un
  solo sentido.

---

## 9. Convenciones de código sugeridas

- **Carpetas por feature**, no por tipo de archivo (evitar `scripts/`, `scenes/` como
  únicas divisiones — ya reflejado en la estructura de la sección 1).
- **Señales para comunicación entre sistemas**, llamadas directas solo dentro del
  mismo componente/entidad.
- **Un `class_name` claro por script reutilizable** (`ITrapBehavior`, `StateMachine`,
  etc.) para que sean referenciables desde el editor y desde otros scripts sin rutas
  largas.
- **Nombres de señales en pasado** (`package_ruined`, no `ruin_package`) — convención
  estándar de Godot para distinguir señales (hechos) de métodos (órdenes).

---

## Por qué esta arquitectura da resultado "a nivel profesional"

- **Reutilizable**: los componentes (`TrapBehaviorComponent`, `StateMachine`,
  `NetSyncComponent`) no son específicos de este juego — se podrían llevar a un
  proyecto futuro.
- **Modular**: cada sistema se puede tocar, testear o reemplazar sin tocar los demás,
  gracias al Event Bus y la separación simulación/presentación.
- **Barata de extender**: el catálogo de trampas, vehículos y tramos crece agregando
  archivos de datos + scripts chicos, no modificando el núcleo — exactamente lo que
  necesitás para el contenido post-launch que planeamos en `plan-desarrollo.md`.
- **Compatible con desarrollo asistido por IA**: al estar todo desacoplado, podés
  pedirle a la IA que implemente "la trampa X" o "el componente Y" de forma aislada,
  con contratos claros, sin que necesite entender todo el proyecto de una vez.

## Próximo paso
Con esta arquitectura definida, la Fase 1 del plan de desarrollo (`VehicleBody3D` +
trampa "Frágil" de punta a punta) ya tiene un molde concreto para implementarse:
`Vehicle` + `Package` + `FragileTrapBehavior` + `EventBus`, sin sistemas de red ni UI
todavía.
