# Cómo agregar un vehículo nuevo

> Ver `docs/tareas-nacho.md` #85-92. Escrito para no tener que
> redescubrir esto la próxima vez que se sume un segundo vehículo
> (manejo más lento/estable o más rápido/nervioso, como desbloqueo).

## Qué necesita `VehiclePresentation` para funcionar sin tocarlo

`scripts/presentation/vehicle_presentation.gd` (#87) ya no depende de rutas
fijas como `"CabinInterior/SteeringWheel"` o `"CargoBay/LeftTailLight"`.
Busca todo por nombre/patrón en cualquier parte del árbol del vehículo, así
que un vehículo nuevo sólo necesita, en algún lugar bajo su nodo raíz
`VehicleBody3D`:

- Exactamente un nodo `MeshInstance3D` llamado **`SteeringWheel`**.
- Exactamente un nodo `Node3D` llamado **`BodyVisuals`** — la carrocería
  exterior visible, la que se inclina en curvas/frenadas (#21) y se hunde
  con el peso de la carga (#96). No debe incluir asientos ni cámaras: eso
  apilaría el balanceo sobre el head bob/shake de cada `FirstPersonCamera`.
- Cualquier cantidad de `MeshInstance3D` cuyo nombre **termine en
  `Headlight`** (los faros delanteros) — cada uno recibe automáticamente su
  propio `SpotLight3D` como haz de luz.
- Cualquier cantidad de `MeshInstance3D` cuyo nombre **termine en
  `TailLight`** (las luces traseras) — se iluminan según freno/motor.
- Cualquier cantidad de nodos `VehicleWheel3D` hijos directos del
  `VehicleBody3D` (ya lo esperaba así desde antes; no hace falta ni un
  nombre ni una cantidad fija — el polvo, el chirrido y el spoke visual se
  generan por cada uno que encuentre).
- Cualquier cantidad de `Camera3D` en cualquier parte del árbol (un asiento
  por cámara) — el ruteo de audio Interior/Exterior (#80/#81) ya las
  recolecta recursivamente, sin lista fija.

Nada de esto necesita coordinarse con Slatex: `vehicle.tscn` y
`vehicle_presentation.gd` no están en la zona compartida de
`docs/colaboracion-equipo.md`.

## Qué sí hay que definir por vehículo

- Parámetros de física propios en el script del vehículo (`maximum_engine_force`,
  `maximum_speed_kmh`, `maximum_steering`, etc. — ver #86) sin tocar los ya
  afinados del vehículo actual (`scripts/gameplay/vehicle/vehicle.gd` sigue
  siendo el vehículo por defecto).
- Si el nuevo vehículo tiene menos o más asientos, `PlayerColors`/el sistema
  de asientos (`seat_point.gd`, dominio de Slatex) no necesita cambios: ya
  deriva ocupación de `Player.seat_node_path`, no de una lista fija de
  asientos.
- Selección de vehículo en el menú (#88) es de Slatex — coordinar antes de
  tocar `main_menu.gd`.

## Qué falta antes de dar esto por terminado

- Un segundo vehículo real todavía no existe, así que #91 (probar que
  respete todo lo ya construido) sigue abierto por falta de contenido, no
  por falta de diseño: no hay nada que playtestear todavía. Construir el
  vehículo en sí es contenido de arte/diseño (#85, prioridad B).

## Asientos y carga compartidos de la flota (D-0208)

La furgoneta (`vehicle.gd`) no hereda de una base común: usa por composición dos
componentes de `do-not-drop/scripts/gameplay/fleet/`, para que una lancha, un avión
o una bici los reutilicen sin ser un `VehicleBody3D`. Son `RefCounted`, reciben
como dueño cualquier `Node3D` y se cargan con `preload` (sin `class_name`, para no
depender de la caché de clases). `vehicle.gd` los crea en `_init()` y los expone como
`fleet_cargo` y `fleet_seats`; su API pública no cambió (`carries()`,
`point_velocity()`, `needs_sweep()`, `get_cargo_spawn_transform()`, `CARGO_BAY`,
`SHELL_LAYER`, `CARGO_WALL_*`) y son envoltorios finos hacia ellos.

| Componente | Qué hace | Qué lee del dueño |
|---|---|---|
| `fleet_cargo.gd` | `carries()`, `point_velocity()`, `needs_sweep()`, el cascarón de carga `CargoShell` (capa 7, `SHELL_LAYER`), `follow()`, `on_package_placed()`, `get_cargo_spawn_transform()` | `linear_velocity`, `angular_velocity`, `center_of_mass`, `freeze` (RigidBody3D; `velocity` si es CharacterBody3D; propiedades con esos nombres en otro caso) |
| `fleet_seats.gd` | Consultas: `seat_points()`, `seat_count()`, `driver_seat()`, `occupied_count()`, `free_seats()`, `has_driver()`, `is_driver(peer)` | `driver_peer_id` del dueño; asientos = nodos hijos con `is_occupied()` y `role` (`SeatPoint`) |

El inventario de qué partes de `vehicle.gd` eran asientos y carga, con sus líneas
de antes de la extracción, está en el encabezado de cada archivo. Los asientos ya
estaban separados (`seat_point.gd`, nodos en `vehicle.tscn`): `fleet_seats.gd` solo
consulta, y `driver_peer_id` / `controls_enabled` siguen siendo propiedades
replicadas del vehículo (no se tocó ninguna ruta del `MultiplayerSynchronizer`).

### Cómo lo usa un vehículo sin ruedas

1. En su `_init()`: `fleet_cargo = FleetCargo.new(self)` y `fleet_seats = FleetSeats.new(self)`
   (con `const FleetCargo = preload("res://scripts/gameplay/fleet/fleet_cargo.gd")`).
2. En `_ready()`: `fleet_cargo.bay = AABB(...)` con la bodega propia (el valor por
   defecto es el de la furgoneta), `fleet_cargo.spawn_point = $Marcador`, y
   `fleet_cargo.build_shell()` cuando las colisiones del casco ya existen.
3. En `_physics_process()` del host, antes del paso: `fleet_cargo.follow(delta)`; en
   `_notification()`, ante `NOTIFICATION_TRANSFORM_CHANGED`,
   `fleet_cargo.on_body_transform_changed()`.
4. Conectar `EventBus.package_placed` a un método propio que llame a
   `fleet_cargo.on_package_placed(id)` (un método del nodo, no del `RefCounted`: se
   desconecta solo al liberar el vehículo).
5. Exponer `carries()` / `point_velocity()` / `needs_sweep()` con esos nombres: el
   paquete, el jugador y los animales los buscan por el grupo `vehicle`.
6. Los asientos son `SeatPoint` hijos del vehículo y un `driver_peer_id` exportado.

Prueba: `tests/test_fleet_components.gd`.
