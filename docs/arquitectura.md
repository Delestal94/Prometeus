# Arquitectura del proyecto — Take My Package

> Basado en: `docs/requerimientos-tecnicos.md` y `docs/plan-desarrollo.md`.
> Última actualización: 2026-10-04
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

> **Estado real (2026-10-01)**: desde N-225 los scripts grandes se partieron por responsabilidad
> sin cambiar su interfaz pública: `route.gd` (`route_path`, `route_ground`, `route_houses`,
> `route_props`, `route_signage`, `route_sky`...), `package.gd` y `package_feedback.gd` (`package_*.gd`
> en `scripts/gameplay/package/`), `reference_truck.gd` (`reference_truck_cab/_cargo/_props/_panel_lines.gd`
> en `scripts/presentation/`) y `synth_audio` (`synth_audio_*.gd` en `modules/synth_audio/`). Los HUD
> viven en `scripts/ui/hud/` (`hud.gd` + `hud_*.gd`; ya no existe `prototype_hud.gd`). Nuevos desde
> 2026-09-24: depósito (`scripts/gameplay/depot/`), tramo de barro (`segments/mud_segment.gd`, `mud_crane.gd`),
> animales de carga (`cargo_animals.gd`...), caja manual (`vehicle_gearbox.gd`), `late_join_seating.gd`,
> `seat_tending.gd`, `color_slots.gd`/`player_color_slot.gd`, `nickname.gd`, `face_catalog.gd`. Ubicación
> exacta: `docs/convenciones-godot.md` §3.

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

## 1.1 Módulos portables (`do-not-drop/modules/`)

> Desde 2026-09-30 (N-230). Detalle, catálogo y reglas: `docs/modulos.md`.

Lo genérico del juego vive en carpetas que se pueden copiar a otro proyecto Godot y funcionan:
`modules/<nombre>/` con `module.cfg`, scripts con `class_name` y `tests/`. Adentro de un módulo no
existe el juego (ni autoloads, ni `res://scripts/`, ni clases del juego): lo que necesita lo recibe
por parámetro o por `static var` de configuración, y el juego lo conecta desde un adaptador chico
en `scripts/` (`LowpolyMaterials` → `DetailMaterials`, `LegacyUserData` → `UserDataMigration`).
Dos chequeos lo garantizan en CI: `tools/check_modules.py` (reglas estáticas) y
`tools/portability-check.sh` (cada módulo solo, en un proyecto vacío, corriendo sus tests).

Hoy (17): `persistence`, `loc_text`, `synth_audio`, `net_pose_smoother`, `render_budget`, `acoustics`,
`ragdoll`, `net_session`, `interaction`, `seat_camera`, `settings_store`, `route_gen`, `world_mood`,
`hazards`, `coop_vote`, `unlock_profile`, `run_log`. Los autoloads `NetworkManager`, `EventBus`,
`ProximityVoice`, `GameSettings`, `ShopVoteManager`, `UnlockManager` y `RunTelemetry` extienden la
clase de su módulo y solo conservan lo del juego. Queda en el juego a propósito lo que es contenido o
marca: `UiTheme`, `RoutePlanner`, los tramos con modelos, `RouteDresser`, `RouteSky`, `CrewProgression`,
`RouteEventManager`, `RunManager`, el depósito, las casas, el HUD.

---

## 2. Autoloads (singletons globales)

| Autoload | Responsabilidad | Estado |
|---|---|---|
| `EventBus` | Señales globales desacopladas (ver sección 5). Único punto de "broadcast" del juego. Extiende `NetEventBus` (módulo `net_session`): `relay()` y `request()` viven ahí. | Registrado |
| `RunManager` | Estado de la partida en curso (ruta actual, paquetes activos, puntaje, tiempo — se resetea entre partidas) **y** el leaderboard local persistente (top 10, `user://leaderboard.json`, sobrevive entre partidas y reinicios de la app). | Registrado |
| `NetworkManager` | Setup de host/cliente (Steam y ENet), conexión de jugadores, mapeo de autoridad. Extiende `NetSession` (módulo `net_session`) y solo aporta el estado del mundo que viaja en el handshake y los textos de falla. | Registrado |
| `CrewProgression` | Economía y cartas del equipo durante la campaña. | Registrado |
| `ShopVoteManager` | Votaciones cooperativas de tienda. | Registrado |
| `RouteEventManager` | Eventos de ruta. | Registrado |
| `GameSettings` | Preferencias locales persistentes de controles, audio y cámara. Extiende `SettingsStore` (módulo `settings_store`): el archivo, el idioma, las teclas y los buses viven ahí. | Registrado |
| `GameManager` | Estado de alto nivel del flujo del juego (menú → lobby → en partida → resultados). Máquina de estados. | **No existe aún** — el flujo de menú/nivel hoy lo maneja `main_menu.gd` + `get_tree().change_scene_to_file()`, sin autoload propio. |
| `UnlockManager` | Progreso meta local, desbloqueos y elecciones de uniforme/vehículo/pintura; guarda JSON versionado en `user://unlock_progress.json`. | Registrado |
| `AudioManager` | Reproducción centralizada de música/SFX. | **No existe aún** — la música y los efectos dinámicos actuales viven en scripts de presentación. |

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
- `LiquidTrapBehavior`
- `ExplosiveTrapBehavior`
- `HostileTrapBehavior`

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

Señales reales declaradas en `event_bus.gd` (18, actualizado 2026-09-21):

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
- `ping_sent(peer_id, position, label)`
- `horn_honked(peer_id)`
- `depot_orders_posted(orders)` — la pizarra del depósito; cada peer la calcula igual desde la semilla.
- `depot_station_opened(station)` — local: abrir la pantalla de una estación del depósito.
- `depot_supplies_changed(supplies, team_money)` — el host decide la compra, `depot.gd` la reparte.
- `depot_notice(text)` — aviso para todo el equipo (relayed): compra, pedido olvidado, portón.

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

`relay()` asume que el hecho se originó en el host (la simulación es host-autoritativa).
`ping_sent` y `horn_honked` son la excepción: cualquier jugador puede pingear o tocar
bocina, no solo el host, así que necesitan un salto extra antes de poder usar `relay()`
— `EventBus.request_ping()`/`request_horn()` son `@rpc("any_peer", ...)` a los que
cualquier cliente llama con `rpc_id(1, ...)` (el host los llama directo); recién ahí el
host decide que el hecho "pasó de verdad" y lo relayea a todos, incluido quien lo
mandó.

---

## 5.1 El depósito de salida (`scripts/gameplay/depot/`)

Toda partida empieza en `Depot` (nodo de `level_base.tscn` y `level_endless.tscn`): el
camión en su bahía, los paquetes en las estanterías de despacho (cada uno con su código de
estante en la meta `dispatch_code`), la pizarra con un pedido por casa y las estaciones
(`DepotStation`, un `Interactable` que abre la pantalla en el peer de quien la usó). Los
pedidos y el orden de las estanterías salen de `NetworkManager.world_seed`, así que todos
los peers los calculan igual sin mensajes (la cantidad de casas también viene del host:
`NetworkManager.world_house_count`, en el mismo handshake que la semilla); el host decide las compras
(`CrewProgression.buy_supply`) y el cierre del portón, y los reparte por RPC. La geometría
estática se hornea en una malla por material (`DepotKit`); operarios y autoelevador son
presentación local.

En Endless el depósito es el mismo, pero sin casas no hay pedidos (`post_orders(0)`): la
pizarra pasa a "RUTA SIN FIN" con el récord de distancia de `RunManager`, y el portón,
que arranca abierto en los dos modos, no espera nada para dejar salir al camión.

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

## 10. Modo Empresa (la expansión)

> D-0201. Es el contrato de arquitectura del modo nuevo; lo detallan `docs/expansion-distritos/`
> (qué reutiliza el juego actual: `diseno/reutilizacion.md`; el corte vertical: `diseno/corte-vertical.md`).
> **Regla de oro (S1):** Entrega y Endless no cambian de comportamiento. Todo lo de esta sección se
> **agrega** (clases nuevas, señales al final, campos con valor por defecto); ningún test actual se toca
> salvo para sumarle un caso.

### 10.1 Capas

```
CompanyState   (autoload, persistente)   plata, día, reloj, reputación, bloqueos abiertos, flota, layout
   └─ DayCycle  (nodo del mundo)          OPENING → OPERATING → CLOSING → SUMMARY → día siguiente
        └─ WorldCells (módulo)            qué celdas de 256 m están cargadas alrededor de jugadores y vehículos
             └─ salidas                   un vehículo + las cajas que lleva, fuera del galpón
```

| Capa | Vive en | Dura | Quién la escribe |
|---|---|---|---|
| `CompanyState` | `scripts/core/company/company_state.gd` (autoload, se registra después de `UnlockManager`) | toda la empresa; se guarda en `user://saves/company/<slot>.json` | solo el host |
| `DayCycle` | `scripts/core/company/day_cycle.gd` (hijo de `CompanyWorld`, no autoload) | un día (08:00-20:00 de juego, 1 h = 90 s) | solo el host |
| `WorldCells` | `modules/world_cells/` (genérico, sin nombrar nada del juego) | mientras el mundo está abierto | el **host** carga la colisión de las celdas alrededor de todo jugador, vehículo y caja suelta; cada cliente carga la presentación alrededor de lo suyo. El trazado del mapa es fijo y el mismo para todos |
| Salida | vehículo y cajas del mundo | desde el portón hasta volver al galpón | host (vehículo y cajas); el que carga una caja solo propone su pose |

- En un cliente, `CompanyState` es un **espejo** del host: no guarda ni toca el slot local (solo guarda el
  host) y `DayCycle` es pasivo (cambia de fase solo con el evento del host).
- Los nodos replicados (jugador, vehículo, `DeliveryPackage`) no son hijos de una celda: descargar una celda
  no los libera ni los mueve de padre.
- El decorado por semilla usa un RNG por celda, con semilla `hash([world_seed, cx, cz])`; la semilla de la
  empresa se guarda en el slot y el host la pone en `NetworkManager.world_seed` antes de cargar `CompanyWorld`.
- `CompanyState.is_active()` es falso fuera del modo Empresa: Entrega y Endless lo ignoran. La plata de la
  empresa vive ahí; `CrewProgression.team_money` sigue siendo la de Entrega y Endless (S8).
- `RunManager` **no** arranca en modo Empresa: una salida no es una corrida, el día lo lleva `DayCycle`.
- El mundo es **un solo mapa continuo** (≤ 6 × 6 km, sin origen flotante, sin pantallas de carga después de
  la inicial): `docs/decisiones/2026-10-04-mapa-continuo.md`. `RouteStreamer` se conserva para Endless.
- Entrada: botón "Empresa" del menú o `--autostart-company [--slot=<n>]`
  (`docs/decisiones/2026-10-04-flag-modo-empresa.md`); la escena raíz es `CompanyWorld` y se suma al final de
  `NetworkManager.LEVEL_SCENES`.

### 10.2 Autoridad (quién manda en cada estado)

**El host es dueño de todo el estado del negocio.** Un cliente nunca escribe estado: manda una
**petición** (`_request(kind, data)`, `@rpc("any_peer")` pasando por `RpcGuard`), el host la valida y, si
es válida, la aplica y difunde un **evento** (`_apply_event(seq, kind, data)`, reliable, host → todos) que
cambia `Inventory`, `OrderBook` o `CompanyState` igual en todos los peers. Una petición inválida se rechaza
sin cambiar nada. Nada de estado de negocio viaja en un `MultiplayerSynchronizer` por tick.

- `_request` es `@rpc("any_peer", "call_local", "reliable")` (así el host usa el mismo camino y las mismas
  validaciones que un cliente). Guardas: `allow_request` y `name_ok(kind)` siempre, `dict_ok(data)` solo en
  `_request`; soltar (manos → piso) va con `allow_critical_request`. **El actor es siempre
  `RpcGuard.sender(self)`, nunca un campo de `data`**, y el alcance físico lo valida el host.
- `_apply_event` es `@rpc("authority", "call_local", "reliable")`, enviado con `rpc_id` solo a los peers con
  `NetworkManager.is_peer_ready()`.

| Estado | Dueño | Cómo viaja |
|---|---|---|
| plata, día, reloj | host | evento; el reloj es un ancla (minuto de inicio, tick, velocidad, pausa) que el host manda al cambiar y cada peer calcula la hora local (D-0219), no un evento por minuto |
| stock (`Inventory`), con reservas | host | evento |
| unidades en mano (`hands:<peer>`) y caja en armado (`table:<id>`) | host | evento; si el peer se va, el host libera sus reservas y emite manos → piso (D-2006) |
| pedidos (`OrderBook`) | host | evento |
| layout del galpón | host | evento |
| bloqueos abiertos | host | evento; un bloqueo abierto no se vuelve a cerrar |
| cajas sueltas (posición) | host | el sincronizador de `DeliveryPackage`, como hoy |
| caja en mano | host | el que la lleva propone la pose (`submit_carry_transform`, unreliable) y la dibuja local (predicción N-217); soltar y pasar son peticiones (`request_drop`, crítica) |
| vehículos | host | como hoy (el host simula todos; como máximo 2 lejos del galpón en F1-F3) |

- Cada evento lleva un número de secuencia `seq`. El hueco real no es de pérdida (es reliable) sino el
  evento que llega antes de que el peer tenga `CompanyWorld`: por eso el snapshot (`CompanyState.to_dict()` +
  inventario + pedidos + layout + bloqueos + **cajas vivas con todo lo que hace falta para crearlas** +
  unidades sueltas) sale desde el gancho de peer listo y lleva `seq`; el cliente descarta eventos con `seq`
  menor o igual. Pedir un snapshot tiene tope por peer (1 cada N segundos).
- `box_sealed` lleva todo para que cada peer cree el `DeliveryPackage` idéntico (nombre de nodo estable,
  `package_id`, trampa, contenido, absorción, `order_id`); un `set_meta` no viaja.
- La tabla completa por acción del corte vertical (tomar, colocar, encintar, despachar, comprar…) es D-2001;
  esta sección fija el principio y D-2001 lo baja a las 20 acciones.
- Cualquier cambio de RPC o replicación sube `PROTOCOL_VERSION` como dice `convenciones-godot.md` §6.

### 10.3 Señales nuevas en `EventBus`

Se agregan **al final** de `event_bus.gd`, sin reordenar las existentes (D-0215). Las señales son hechos,
en pasado. `EventBus` es local por proceso: **cada peer emite la señal al aplicar `_apply_event`**. Aplicar un
snapshot no emite señales de hechos (si no, el que entra tarde repite todo el audio y el HUD del día): emite
una sola de estado restaurado para que la UI se redibuje.

| Señal | La emite | Cuándo |
|---|---|---|
| `company_day_started(day)` | `DayCycle` | arranca un día |
| `company_day_closing(day)` | `DayCycle` | llegan las 20:00 (o termina la última salida) |
| `company_day_summary(day, summary)` | `DayCycle` | pantalla de cierre |
| `order_added`, `order_packed`, `order_delivered` | `OrderBook` | entra, se arma o se entrega un pedido |
| `supply_arrived`, `box_sealed` | galpón | llega el camión del proveedor; se encinta una caja |
| `gate_opened(gate_id)`, `milestone_reached(id)` | `CompanyState` | se abre un bloqueo; se cumple un hito |
| `money_changed(amount, reason)` | `CompanyState` | cualquier movimiento de plata |

La UI y el audio escuchan estas señales; la simulación nunca depende de que alguien las escuche
(separación simulación/presentación, `convenciones-godot.md`).

### 10.4 Carpetas nuevas

| Carpeta | Qué tiene |
|---|---|
| `scripts/core/company/` | `CompanyState`, `company_tuning.gd` (todos los números, como `const`), `DayCycle`, `company_net.gd`, guardado |
| `scripts/gameplay/business/` | `ProductDefinition`, `Inventory`, `Order`, `OrderBook`, `Pallet`, armado de cajas |
| `scripts/gameplay/districts/` | `CompanyWorld`, bloqueos, registro de zonas |
| `scripts/gameplay/fleet/` | `VehicleDefinition` y vehículos nuevos |
| `data/products/`, `zones/`, `vehicles/`, `boxes/`, `suppliers/`, `gates/` | recursos `.tres`; agregar uno suma contenido sin tocar código |
| `scenes/company/` | `company_world.tscn` y lo que cuelga de él |
| `modules/` | lo genérico y portable: `world_cells`, `day_clock`, `inventory`, `order_queue`, `build_grid` (D-0220 lo cierra) |

Un script que no sabe de cajas, camión ni HUD va a un módulo con su `module.cfg` y su test, y el juego lo
conecta desde un adaptador chico; `python tools/check_modules.py` lo comprueba.

### 10.5 Flujo de una caja, del palet a la puerta

```
camión del proveedor (08:30) ──► Pallet (hasta 24 unidades de un producto)
   │  descarga con zorra o autoelevador
   ▼
estante con hueco etiquetado ── Inventory (host): unidades por producto y ubicación, con reservas
   │  picking a mano: el jugador toma unidades (petición → host → evento)
   ▼
mesa de armado ── caja en grilla de celdas de 0,2 m: productos, relleno, cinta, etiqueta, sellos
   │  calidad Q (0-100) y trampa calculadas por el host
   ▼
caja armada = DeliveryPackage (con la trampa del producto de mayor dificultad)
   │  se deja en la zona de despacho: queda asociada a la salida y al pedido (OrderBook)
   ▼
vehículo ── sale por el portón, maneja por el mapa continuo hasta la casa
   ▼
DeliveryHouse ── timbre; compara contenido contra el pedido, daño y plazo
   ▼
cobro ── CompanyState.money (+ propinas, − penalidades) y reputación; resumen al cierre del día
```

- **Simulación y presentación van separadas:** `Inventory`, `OrderBook`, `CompanyState` y `DayCycle` son
  datos y reglas sin nodos de escena, testeables en headless; el galpón, las cajas y el HUD solo los leen.
- **Números:** viven en `company_tuning.gd` y en los `.tres` (precios del producto, costo de caja), nunca
  sueltos en el código (`docs/expansion-distritos/detalle/supuestos.md`).

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
