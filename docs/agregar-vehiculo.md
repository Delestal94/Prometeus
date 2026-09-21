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
