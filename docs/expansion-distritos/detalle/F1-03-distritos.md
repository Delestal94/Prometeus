# F1 · Grupo 03 — Mapa continuo, calles, bloqueos y salidas (detalle)

> Carril 4 de la rutina `desarrollador`. Reescrito para el **mapa continuo** (`docs/decisiones/2026-10-04-mapa-continuo.md`):
> trazado fijo ≤ 6×6 km, celdas de 256 m, calles como grafo, bloqueos como objetos del mundo. Estas 20 tareas
> **reemplazan** el bloque Núcleo de `03-mapa-y-distritos.md`.

### D-0301 · Boceto del mapa del mundo — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/mapa.md`: 9 zonas en celdas de 256 m, 3 calles principales, 7 bloqueos con posición y chequeo de la regla de oro.
**Depende de:** D-0114
**Qué:** `docs/expansion-distritos/diseno/mapa.md` con un boceto en texto o SVG en grilla de 256 m:
- dónde va cada una de las 9 zonas y la costa;
- las montañas que separan Montaña/Nieve/Volcán del llano;
- las 2-3 calles principales que salen del Parque Industrial;
- dónde va cada bloqueo y de qué tipo (barrera, calle cortada, agua, equipo, altura).
Regla: desde el galpón, Barrio Centro queda a ≤ 90 s de manejo y Campo a ≤ 3 min, por la regla de oro
N-102 aplicada a la salida completa. Es la fuente de los `bounds` de D-0205 y del grafo de D-0304.
**Hecho cuando:** el boceto existe con coordenadas de cada zona y cada bloqueo.

### D-0302 · Portón del galpón como inicio de salida — A · Opus 5.5 · high · Aviso: no · F1
**[~] Parcial (2026-10-19, PR pendiente)** — modelo, enganche y test: `Trip` (`scripts/gameplay/districts/trip.gd`: saca los pedidos PACKED a OUT al salir, entrega y cierra marcando FAILED lo no entregado) y `TripGate` (`trip_gate.gd`: plano del portón, detecta cruce de salida y de entrada por la abertura); `test_company_trip`.
**Subtareas abiertas:**
- ~~**D-0302.1**~~ ✅ (2026-10-19, PR pendiente) `CompanyTrips` (`company_trips.gd`, hijo de `CompanyRoot` en el host): `TripGate` en la salida norte del galpón, sigue cada tick los nodos del grupo `company_vehicle`, `stage_cargo()` guarda lo que despacho cargó y al cruzar arranca el `Trip`; al volver lo cierra; `trips_out()` va a `DayCycle.trips_out`. `test_company_trips`.
- ~~**D-0302.2.a**~~ ✅ (2026-10-22, PR pendiente) Las salidas en red: `CompanyTripsView` (`company_trips_view.gd`, hijo de `CompanyRoot` en cada peer) sigue a `CompanyTrips` en el host y publica por `CompanyNet` `trip_started` / `trip_refused` / `trip_closed`; cada peer sabe qué vehículos están afuera (`vehicles_out()`, `trip_of()`, `trips_out()`, señal `changed`), parte de snapshot `trips` para el join tardío; hasta 64 cajas y pedidos por salida (`CompanyTrips.MAX_CARGO`); protocolo 40; `test_company_trips_net`, `test_company_online` (`_check_trips`).
- ~~**D-0302.2.b.1**~~ ✅ (2026-10-22, PR pendiente) La camioneta de la empresa en el mundo: `CompanyFleet` (`scripts/gameplay/districts/company_fleet.gd`, hijo `Fleet` de `CompanyRoot`) arma un vehículo por entrada de la flota (`CompanyState.fleet`; vacía: `CompanyTuning.STARTING_FLEET`) en `World/Vehicles/<id>` en cada peer (el cliente, al llegar el snapshot del host), en el grupo `company_vehicle`, estacionado afuera de la salida norte, congelado y con `NetRestThrottle`; el host le abre el sincronizador de cada vehículo a un peer recién cuando ese peer avisa que lo armó (`_have_fleet`, RPC crítico en `World/Vehicles`, regla 10); al irse un peer el host lo baja del volante (`release_peer`) y la telemetría de `vehicle.gd` sale solo durante una corrida. `CompanyTrips` mira solo los vehículos de su `multiplayer` y `forget()` cierra la salida de un vehículo que deja el mundo (lo no entregado falla). Protocolo 49. `test_company_fleet` (solo y par ENet), `test_company_trips`. **Decisión:** no se pasa `net.orders.book` a `CompanyTrips.book`: el host escribiría el libro compartido fuera de los eventos y los libros de los clientes se separarían (lo dicen los encabezados y `test_company_bot_day`). Ver [`revisar/D-0302.2.b.md`](../revisar/D-0302.2.b.md).
- ~~**D-0302.2.b.2**~~ ✅ (2026-10-22, PR pendiente) La camioneta se maneja en el mundo de la empresa: `vehicle.gd` tiene `drivable_outside_run` / `is_drivable` / `park()` / `park_at()` (la flota de `CompanyFleet` nace manejable y estacionada en el playón; `_update_parking`, `_drive` y `vehicle_input_component.gd` leen esa única condición; telemetría, impactos y `VehicleFaults` siguen atados a la corrida; la bocina suena solo en la camioneta de su conductor), el `TripGate` pasó de la pared al borde del playón (`CompanyFleet.gate_of()`, `PLAYON_DEPTH_M` 12 m, `PLAYON_WIDTH_M` 26 m, 7 lugares) y su "adentro" es el rectángulo del galpón y el playón (`TripGate.set_yard()`: salir por cualquier lado arranca la salida), losa de respaldo bajo todas las zonas y red de seguridad de la flota (`recover_fallen()` → `CompanyTrips.forget`); `test_company_van_drive`, `test_company_fleet` (cliente al volante), sin cambio de protocolo. Ver [`revisar/D-0302.2.b.2.md`](../revisar/D-0302.2.b.2.md).
- **D-0302.2.b.3** `stage_cargo()` desde la zona de despacho (D-0716.b/D-0717.b, D-0310.b): hoy solo los tests cargan una salida.
- **D-0302.2.b.4** ◐ (2026-10-22, PR pendiente) `VehiclePick` (`scripts/gameplay/vehicle/vehicle_pick.gd`): con más de un vehículo en el grupo `vehicle`, el dueño de un jugador (`PlayerRide.find_vehicle`) y de una caja (`DeliveryPackage._find_vehicle`) elige el que lleva su punto (`carries`), conserva el actual mientras lo lleve y, si ninguno, el actual o el primero; con uno solo nada cambia. `test_company_multi_vehicle`. Falta **D-0302.2.b.4.b**: la copia de un jugador o caja en los otros peers sigue usando el primer vehículo, porque `net_in_vehicle` es un bool; hay que replicar cuál (índice de la flota, `PROTOCOL_VERSION` según `convenciones-godot.md` §6). Los otros `get_first_node_in_group(&"vehicle")` (HUD, asiento, cuidado de carga, voz, clima de tramo) siguen igual: ver `revisar/D-0302.2.b.4.md`.
- ~~**D-0302.2.b.4.b**~~ ✅ (2026-10-22, PR pendiente) `player.tscn` y `package.tscn` replican `net_vehicle` con la pose (`VehiclePick.index_of()`: el lugar en el grupo `vehicle` en orden de árbol, igual en todos los peers; -1 ninguno; `ALWAYS` y en el spawn), y la copia de otro peer va en ese (`VehiclePick.told()` en `PlayerRide.find_vehicle` y `DeliveryPackage._find_vehicle`); `submit_carry_transform` y `request_drop` llevan el índice al final (el host pone la caja cargada en el vehículo del que carga, `PackageHandling.space_of()`) y la predicción del que carga usa su propio vehículo. Con uno solo nada cambia. Protocolo 57. `test_company_multi_vehicle`, `test_ride_sync`. HUD, asiento, cuidado de carga, voz y fauna siguen con el primero: ver [`revisar/D-0302.2.b.4.b.md`](../revisar/D-0302.2.b.4.b.md).
- ~~**D-0302.2.b.5**~~ ✅ (2026-10-22, PR pendiente) Un vehículo comprado a mitad de día (`shop_bought` de un ítem `vehicle`) lo arma cada peer al aplicar el evento (`CompanyFleet._on_event` → `build()`, que suma solo el que falta; el cliente avisa al host con `tell_host()` para abrirle el sincronizador); `_make` ya lo deja `drivable_outside_run`. `CompanyShop.check` rechaza el vehículo que pasa de `PLAYON_SLOTS` (`WORLD_SHOP_FLEET_FULL`) y `buy()` conserva la camioneta inicial (flota vacía = `STARTING_FLEET`) escribiéndola como `{"id": ...}` antes del primer vehículo comprado; sin esto la compra la hacía desaparecer. Sin cambio de protocolo. **Queda D-0302.2.b.6:** vender un vehículo (D-0528, pospuesta) y `CompanyTrips.forget()` para el que sale a mitad de día. `test_company_fleet` (`_check_purchase`), `test_company_shop`. Ver [`revisar/D-0302.2.b.5.md`](../revisar/D-0302.2.b.5.md).
**Depende de:** D-0620, D-0214
**Qué:** el portón de persiana del depósito actual (`depot_roller_door.gd`) es el borde del galpón.
- Una salida (`Trip`) empieza cuando un vehículo con cajas despachadas cruza el portón hacia afuera, y
  termina cuando vuelve a entrar al playón.
- `scripts/gameplay/districts/trip.gd` guarda: vehículo, cajas, pedidos, paradas y hora de salida.
**Test** `test_company_trip`: un vehículo con 2 cajas despachadas que cruza el área del portón crea un
`Trip` con esos 2 pedidos en `OUT`; al volver vacío, el `Trip` se cierra y sus pedidos quedan `DELIVERED`
o `FAILED`.
**Hecho cuando:** el test pasa.

### D-0303 · Módulo `world_cells`: cargar el mapa por celdas — A · Opus 5.5 · xhigh · Aviso: sí (`modules/`) · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `modules/world_cells/` (`WorldCellGrid` + `WorldCellStreamer`, con `module.cfg` y test propio) y su adaptador `CompanyCells`; `test_world_cells` y `test_company_cells`.
**Depende de:** D-0220, D-0301
**Qué:** `modules/world_cells/` (portable, sin nombres del juego), con `module.cfg` y `tests/`.
- **Grilla:** celdas de 256 m. Cada celda es una escena `cell_<x>_<z>.tscn` o se arma desde datos. Se
  carga en un radio de 2 celdas alrededor de cada "ancla" (jugador o vehículo) y se descarga a 3 (histéresis).
- **Carga en hilo** con `ResourceLoader.load_threaded_request`. La instanciación se reparte en rebanadas
  de ≤ 4 ms por frame, como `Depot.BUILD_SLICE_MSEC`, para no repetir N-917.
- **Las celdas lejanas** muestran un impostor liviano (malla de una pieza). El galpón y las calles
  principales nunca se descargan.
- **Adaptador** en `scripts/gameplay/districts/company_cells.gd`.
**Test del módulo:** con 3 anclas falsas moviéndose, el set de celdas cargadas es el esperado en cada
paso, y una celda nunca se carga y descarga en el mismo segundo.
**Test del juego** `test_company_cells`: manejar del galpón a Centro no deja frames > 50 ms por la
carga (medido con el reloj del motor en headless) ni huérfanos al volver.
**Hecho cuando:** los dos tests pasan y CI corre el módulo en `portability-check.sh`.

### D-0304 · Grafo de calles y tramos sobre aristas — A · Opus 5.5 · xhigh · Aviso: sí (`modules/route_gen/`) · F1
**[~] Parcial (2026-10-12, PR pendiente)** — grafo, datos y test: `modules/route_gen/` suma `RoadNetwork`/`RoadNode`/`RoadEdge` (grafo con aristas Bézier, muestreo por largo, punto más cercano, celdas cruzadas, caminos mínimos que frenan en un bloqueo cerrado, `validate()`, `crossing_pairs()`; test `modules/route_gen/tests/test_road_network.gd`); `scripts/gameplay/districts/road_graph.gd` (`RoadGraph`) + `data/world/road_graph.tres` (27 nodos, 32 calles, ~12,2 km: galpón → Centro (grilla de 3 x 3 con adoquín) → Campo (ripio y barro), más las puntas hasta los bloqueos de Suburbio y Puerto); `RoadGraph.register_terrain()` pone los `add_span` del terreno sobre cada curva; `CompanyCells.pin_streets()`; `test_road_graph`.
**Subtareas abiertas:**
- ~~**D-0304.1**~~ ✅ (2026-10-21, PR pendiente) Entrega por celda: `EdgeCellContent` (`scripts/gameplay/districts/edge_cell_content.gd`) reparte las piezas de `EdgePieces` a la celda donde empieza cada una y arma el nodo `Cell_<x>_<z>`; `CompanyCells.use_graph(graph)` lo conecta a `content_for` y fija las calles principales. La calzada, banquinas y marcas las dibuja cada `RouteSegment` (no se duplicó su lógica). Queda **D-0304.1b**: la superficie con shader en vez de cajas de color (N-323), `artista-shaders`. `test_company_edge_cells`.
- ~~**D-0304.2**~~ ✅ (2026-10-19, PR pendiente) `EdgePieces` (`scripts/gameplay/districts/edge_pieces.gd`): `plan()` reparte `edge.segments` a lo largo de la curva (cada pieza es una cuerda recta puesta en el punto de la calle y girada hacia donde sigue; la pieza que no entra al final es un `straight` recortado; `curve` toma el giro de la calle en sus 50 m) y `build()` arma los `RouteSegment`; `signature()` es el golden por arista. `test_company_edge_pieces`. Falta entregarlas por celda (D-0304.1).
- **D-0304.3** Piloto automático del bot (D-2016) galpón → Centro con `OFF_ROAD` = 0: la línea ya existe (`test_road_graph` arma la polilínea del camino mínimo sin saltos), falta seguirla con el vehículo; depende de D-2016 y de la malla.
- ~~**D-0304.4**~~ ✅ (2026-10-22, PR pendiente) Capturas: `tests/render_company_edges.gd` arma `avenida_este_1` (asfalto), `camino_campo_3` (ripio con curvas y puente) y `chacra_1` (tierra con barro) con `EdgePieces.build` y la luz del nivel, en 4 vistas (conductor, 3/4, de arriba, primera junta). Asfalto y barro, continuos; las calles con `curve` tienen huecos (D-0304.5). Informe: [`revisar/D-0304.4.md`](../revisar/D-0304.4.md).
- ~~**D-0304.5**~~ ✅ (2026-10-22, PR pendiente) Hueco después de cada `curve`: `EdgePieces._piece` ahora avanza el largo con que se construye la curva (`CurveSegment.length_for_turn`) y calcula el giro sobre ese tramo (unas pasadas hasta que giro y largo coinciden), así la pieza siguiente empieza donde ésta termina. `test_company_edge_pieces` exige que `advance == length` y que la suma de largos cubra la calle (± 12 m). Queda sin mirar el escalón de unos cm en la junta en ángulo entre cuerdas (vista `joint` de `camino_campo_3`): `revisor-visual` con `render_company_edges.gd` en la PC o próxima corrida.
**Depende de:** D-0301, D-0303
**Qué:** `scripts/gameplay/districts/road_graph.gd` + recurso `data/world/road_graph.tres`:
- **nodos:** posición, tipo `junction|dead_end|gate`;
- **aristas:** curva Bézier, ancho, superficie `asphalt|gravel|dirt|cobble`, lista de tipos de tramo.
La malla de calle se arma por arista con la misma lógica de calzada y terreno de `route_gen` (sin
duplicarla: extraer lo común si hace falta). Los tipos de tramo actuales (`route/segments/`) se colocan
sobre aristas del Campo con su largo y dificultad. Para F1 el grafo incluye galpón → Centro → Campo con
~12 km de calle.
**Test** `test_road_graph`: el grafo carga, todas las aristas conectan nodos existentes, y desde el
galpón se llega a todo nodo de una zona abierta. El piloto automático del bot (D-2016) recorre galpón →
Centro sin salirse de la calzada (`OFF_ROAD` = 0).
**Hecho cuando:** el test pasa y `revisor-visual` mandó capturas de 3 aristas (asfalto, ripio, barro).

### D-0305 · Varias paradas por salida — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `Trip` suma paradas por casa (`stops`, `pending_stops()`, `next_stop()`, `deliver_stop()`) y `close()` con `Inventory`: lo no entregado vuelve `FAILED` y los productos de una caja sana pasan de `box:<id>` a `dock` (`Trip.RETURN_LOCATION`); si la caja está rota se pierden. `test_company_trip_stops`. Falta que el GPS/tablero use `next_stop()` (D-0308, D-0307).
**Depende de:** D-0302, D-0311
**Qué:** un `Trip` tiene una lista de paradas (casa + pedidos). Entregar en una casa saca esos pedidos.
La salida no termina hasta volver al galpón. Las cajas que no se entregaron vuelven con estado `FAILED`
y la mercadería vuelve al stock si la caja está sana.
**Test** `test_company_trip_stops`: un `Trip` con 3 casas. Entregar en 2 y volver deja 2 `DELIVERED`, 1
`FAILED` y los productos de esa caja de vuelta en `Inventory`.
**Hecho cuando:** el test pasa.

### D-0306 · Bloqueos (`GateRequirement`) — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `GateRequirement` + `WorldGate` + 7 `.tres` en `data/gates/` (boceto del mapa); `CompanyState.open_gate/is_gate_open/gate_owned` y campo `equipment`; test `test_gate`. La replicación por evento queda en D-2003.
**[x] Modelos (2026-10-04, sesión de arte)** — tranquera con garita, vallas de obra, puesto de guardaparque y carteles de costa y montaña (`assets/tools/build_world_gates.py`, `models/environment/gates/`); `WorldGate` los instancia por `kind` y al abrirse levanta la barra, corre las vallas o abre la puerta; `test_gate` lo cubre.
**Depende de:** D-0205, D-0202
**Qué:** `scripts/gameplay/districts/world_gate.gd` (`Node3D` con `StaticBody3D`) + recurso `GateRequirement`.
- **Campos del recurso:** `id`, `kind` (`barrier|roadblock|water|equipment|altitude`),
  `milestone: StringName`, `vehicle_key: StringName`, `equipment: Array[StringName]`, `cost: int`.
- **Si está cerrado:** bloquea físicamente y muestra un cartel con el motivo (texto `tr`). Al abrirse
  cambia de modelo (barrera levantada, vallas al costado) y saca la colisión.
- **Los de tipo `water` y `altitude`** no tienen colisión: son el borde del mapa transitable para ese
  vehículo. Una costa no se cruza en camioneta; la avioneta sí cruza.
- **Estado:** en `CompanyState.opened_gates`, replicado por evento (D-2003).
- **Datos:** `data/gates/*.tres` para los bloqueos del boceto. En F1 funcionales `gate_suburbio`
  (barrera por hito) y `gate_campo_obra` (calle cortada por hito).
**Test** `test_gate`: un bloqueo cerrado frena un cuerpo que lo choca; al cumplir el hito se abre, emite
`gate_opened` y queda abierto después de guardar y cargar; uno de tipo `equipment` no deja pasar a un
jugador sin el equipo.
**Hecho cuando:** el test pasa.

### D-0307 · Volver al galpón manejando — A · Opus 5.5 · medium · Aviso: no · F1
**[~] Parcial (2026-10-22, PR pendiente)** — la regla de "volver con grúa" (`scripts/gameplay/districts/trip_tow.gd`, `TripTow`, lógica pura sin nodos ni RPC): `tow_home(trip, estado_del_vehículo, billetera, book, now_min, inventory, cajas_rotas)` con el vehículo `STUCK` o `BROKEN` cobra `CompanyTuning.TOW_COST` = 50 (motivo `tow` en el libro de la billetera), cierra el `Trip` con `Trip.close` (los pedidos no entregados quedan `FAILED`; con `Inventory`, lo de una caja sana vuelve al `dock`) y devuelve `{ok, key, args, cost, failed_ids, black_screen_s}` con `CompanyTuning.TOW_BLACK_SCREEN_SECONDS` = 3.0. Si no hay viaje abierto, el vehículo anda o no alcanza la plata, devuelve `WORLD_TOW_NO_TRIP` / `WORLD_TOW_NOT_STUCK` / `WORLD_TOW_NO_MONEY` y no cambia nada. `test_company_tow_home`. Revisar: [`revisar/D-0307.md`](../revisar/D-0307.md).
**Subtareas abiertas:**
- **D-0307.1** Conectarlo al mundo. **[~] Parcial (2026-10-22, PR pendiente)** — hecho: `CompanyTow` (`scripts/gameplay/districts/company_tow.gd`, hijo `Tow` de `CompanyRoot`, solo el host) cuenta los segundos de `STUCK` de cada vehículo de la flota con viaje abierto (conductor, pedal y casi sin velocidad, no en barro: `CompanyTuning.TOW_STUCK_SECONDS` = 6 y `TOW_STUCK_SPEED` = 0.3, los números de `level_common`), `tow(vehicle_id)` llama a `TripTow.tow_home` a través de `CompanyTrips.tow()` con una billetera que mueve la plata como evento (`CompanyNet.publish_wallet`, motivo `tow`), cierra el viaje (`trip_closed` por el `TripsView`) y deja el vehículo en su lugar del playón (`CompanyFleet.send_home`). Red: pedido `trip_tow {vehicle, rid}` (`CompanyTowNet`, `CompanyNet.tow`, fila 19a de `red-autoridad.md`, `PROTOCOL_VERSION` 58); lo pide cualquier peer, el efecto sale como `wallet_moved` y `trip_closed`, el rechazo vuelve con la clave `WORLD_TOW_*`. Textos: `WORLD_TOW_OFFER` (`CompanyTow.offer_text()`) y `UI_FINANCE_REASON_TOW` (`REASON_KEYS`; aviso por el archivo de Slatex). Después de la auditoría de red: el atasco se traba (`STUCK` hasta que el vehículo anda `TOW_UNSTUCK_SECONDS` = 1 s seguidos, o se cierra el viaje; soltar el pedal o el volante no lo borra), el pedido lo acepta solo el conductor, quien va adentro o cualquiera si nadie maneja (`WORLD_TOW_NOT_YOURS`) y al remolcar se suelta el volante. `test_company_tow`. Revisar: [`revisar/D-0307.1.md`](../revisar/D-0307.1.md).
  - **D-0307.1.a** Botón "Volver con grúa" en el tablero con el precio (`CompanyTow.offer_text()`), visible solo si el vehículo está varado o roto; pide `trip_tow` y muestra el rechazo. Depende de D-0310.b (la estación de despacho): hoy solo hay pedido por red, sin botón ni tecla.
  - **D-0307.1.b** Pantalla negra de `black_screen_s` (el answer de `tow_home` la trae; hoy el vehículo aparece en el playón al instante, sin fundido). `CanvasLayer` en el HUD, en cada peer, avisada por un evento (hoy `trip_closed` no dice que fue grúa) o por el `wallet_moved` con motivo `tow`.
  - **D-0307.1.c** El estado `BROKEN`: nada rompe todavía una camioneta de la empresa (`VehicleFaults` es de la corrida de entrega y su puerta y su espejo no impiden manejar); `CompanyTow.set_broken()` es el gancho para el día que un choque o una falla lo haga.
  - **D-0307.1.d** Mercadería de las cajas sanas: no se pasa `Inventory` (mover `box:<id>` a `dock` sin evento desincronizaría a los clientes, y la vuelta por el portón tampoco lo hace); queda para cuando el cierre de un viaje publique ese movimiento. Un vehículo que salió negado (`refused_out`, sin viaje) no se puede remolcar (`WORLD_TOW_NO_TRIP`).
  - **D-0307.1.f** Carga y pasajeros en la bahía: al remolcar, las cajas sueltas y los jugadores sentados o parados en la camioneta no se mueven con ella (solo se teletransporta el vehículo; quien estaba sentado sigue sentado, sin volante: `CompanyFleet.release_wheel`, y tiene que bajarse y subir de nuevo para manejar). Moverlos con la camioneta (o bajarlos en el playón).
  - **D-0307.1.g** Replicar el estado "remolcable" (`STUCK`/roto) a los peers: hoy solo el host lo sabe (`CompanyTow.vehicle_state`), así que el botón del tablero (D-0307.1.a) no puede decidir cuándo mostrarse en un cliente sin pedir y ser rechazado.
  - **D-0307.1.e** Captura de `revisor-visual` del botón y del fundido (D-0307.1.a y .b).
**Depende de:** D-0302, D-0304
**Qué:** no hay salto: se vuelve manejando. El GPS (D-0308) apunta al galpón cuando no quedan paradas.
Opción "volver con grúa" (pagando 50, valor en tuning): si el vehículo quedó `STUCK` o roto, aparece en
el playón en 3 s de pantalla negra, con los pedidos que quedaban en `FAILED`.
**Test** `test_company_tow_home`: un vehículo `STUCK` con grúa aparece en el playón, la plata baja 50 y
el `Trip` se cierra.
**Hecho cuando:** el test pasa.

### D-0308 · GPS y navegación por el grafo — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — GPS por el grafo completo: `RoadNavigator` (`scripts/gameplay/districts/road_navigator.gd`, funciones puras sobre un `RoadNetwork`): `route()` da el camino más rápido entre dos puntos del mapa (peso = largo / velocidad de la superficie, `CompanyTuning.SURFACE_SPEED`), sin cruzar un bloqueo cerrado; si el único camino pasa por uno, lo rechaza con `gate_closed` y la lista de candados que lo abrirían; `guidance()` lee la posición del vehículo y devuelve metros y segundos que faltan y el punto adelante (`GPS_LOOKAHEAD`) al que apunta la flecha. `test_road_graph_path`.
**Subtareas abiertas:**
- ~~**D-0308.1a**~~ ✅ (2026-10-22, PR pendiente) `CompanyGps` (`scripts/gameplay/districts/company_gps.gd`): el adaptador que pide `DashboardGps.guidance_provider`. `guidance(position)` apunta a la casa de `Trip.next_stop()` (rótulo con calle y número de `HouseAddresses`) y, sin paradas, al galpón (`WORLD_GPS_SHED`); usa los candados abiertos (`open_locks` = `CompanyState.opened_gates`), conserva la ruta y la recalcula si cambia el destino o los candados o el vehículo se aleja más de `OFF_ROUTE` = 25 m; un destino sin camino abierto da `{}`. Devuelve también `seconds`, `game_minutes` (= D-0308.2, `seconds` × 60 / 90) y `polyline`. `test_company_gps`.
- ~~**D-0308.1b**~~ ✅ (2026-10-22, PR pendiente) `CompanyGpsLink` (`scripts/gameplay/districts/company_gps_link.gd`, hijo `GpsLink` de `World` en cada peer): a cada vehículo de la flota le pone en su `DashboardGps` un `guidance_provider` con su propio `CompanyGps` (`guidance_to(posición, parada)`), con los candados abiertos de la empresa. La parada sale de lo que tiene cada peer, no del `Trip` del host: la entrada de `CompanyTripsView.trip_of()` y el `OrderBook` replicado (`next_stop()`: la primera orden no cerrada, por su casa). La pantalla suma el tiempo en hora de juego (`WORLD_GPS_ETA`, "~N MIN", D-0308.2). `test_company_gps_link`. 
- ~~**D-0308.1c**~~ ✅ (2026-10-22, PR pendiente) `DashboardRouteMap` (`scripts/presentation/dashboard_route_map.gd`): dibuja `polyline` en la pantalla del tablero como una cinta tenue detrás del texto, con el rumbo del vehículo hacia arriba y solo los 120 m de adelante, 100 m a cada lado y 20 m atrás (recorte Liang-Barsky); se apaga con el código de bomba y fuera de este modo. `test_company_gps_link` (matemática de pantalla + malla). La captura de `revisor-visual` queda pendiente (el render de la nube no muestra el tablero 3D legible): ver `revisar/D-0308.1c.md`.
- ~~**D-0308.2**~~ ✅ la estimación en hora de juego sale de `CompanyGps.guidance()` (`game_minutes`); mostrarla es parte de D-0308.1b.
**Depende de:** D-0304
**Qué:** el GPS del tablero (N-501/N-502) calcula el camino más corto por `road_graph`, con A* y peso por
tiempo (largo / velocidad típica de la superficie), hasta la próxima parada, y dibuja la flecha y el
camino. Evita aristas detrás de bloqueos cerrados.
**Test** `test_road_graph_path`: el camino galpón → casa X evita un bloqueo cerrado y lo usa cuando se abre.
**Hecho cuando:** el test pasa y una captura muestra el GPS con la ruta.

### D-0309 · Qué vehículo puede ir adónde — A · Opus 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `DispatchRules` (`scripts/gameplay/districts/dispatch_rules.gd`): `check()` / `check_order()` devuelven `{ok, key, args}` según la zona del pedido, el `VehicleDefinition` y los bloqueos de la zona; claves `DISPATCH_NEEDS_*` en `strings_world.csv`; `test_company_dispatch_rules`. Falta que el tablero (D-0310) lo muestre.
**Depende de:** D-0306, D-0207
**Qué:** al despachar (D-0310), un pedido cuya casa está en una zona inalcanzable para ese vehículo (por
bloqueo cerrado o por `gate_key`) se marca y no se puede cargar, con el motivo.
**Test** `test_company_dispatch_rules`: un pedido de Islas no entra en la camioneta (motivo "necesita
lancha"); uno de Suburbio con la barrera cerrada no entra (motivo "barrera: falta el hito X").
**Hecho cuando:** el test pasa.

### D-0310 · Tablero de despacho — A · Opus 5.5 · high · Aviso: sí (`scripts/ui/`) · F1
**[~] Panel hecho (2026-10-21, PR pendiente)** — `DispatchBoardPanel` (`scripts/ui/dispatch_board_panel.gd`): UI por código sobre datos inyectados (`zone`, `book`, `trips`, `vehicle`, `box_kg`, reglas); filas con marca ✓/○/✗, motivo de `DispatchRules` en las bloqueadas, casilleros y kg del vehículo, "Cargar" por `DispatchZone.load_boxes` -> `stage_cargo`; mando y teclado; cliente con "Cargar" deshabilitado y motivo. `test_company_dispatch_panel`. **D-0310.b parcial (2026-10-22, PR pendiente)** — `DispatchStation` (`scripts/gameplay/dispatch_station.gd`, un `DepotStation` con `station_id = &"dispatch"`, placeholder gris por código) en el medio de cada zona de despacho del galpón (`CompanyShed.dispatch_stations`; la zona ya no tiene `ShedPiecePoint`) y `CompanyDispatch` (`scripts/gameplay/company_dispatch.gd`, hijo `Dispatch` de `CompanyRoot` en cada peer, una línea en `_ready`): al usar la estación abre el panel con el contexto real: las cajas selladas, quietas y dentro del área de la pieza de despacho (`DispatchZone` armada leyendo `World/Packages`, D-0716.b en su versión mínima), el primer vehículo de la flota que está en el playón, no salió y no tiene carga lista (nombre `WORLD_VEHICLE_*`, casilleros y kg de su `VehicleDefinition`), `DispatchRules` con las zonas y bloqueos del catálogo; solo el host carga (`CompanyTrips.stage_cargo`; el libro propio de `CompanyTrips` aprende esos pedidos como `PACKED`), el cliente ve la lista con "Cargar" apagado y el motivo. 12 claves `WORLD_ZONE_*` / `WORLD_VEHICLE_*`. Sin cambio de protocolo. `test_company_dispatch_station`. Ver `revisar/D-0310.md`.
**Subtareas abiertas de D-0310:**
- **D-0310.c** (`constructor-red` + `constructor-mundo`) El estado de la zona por red: `box_dispatched` / `box_undispatched` (fila 17 de `red-autoridad.md`) para que el cliente sepa qué cajas ya cargó el host; hoy cada peer lee su copia de los paquetes y el cliente sigue viendo una caja cargada mientras no se mueva. Sube `PROTOCOL_VERSION`; `auditor-red`.
- **D-0717.b** (`constructor-mundo`) Llevar las cajas cargadas a los `PackageMountPoint` del vehículo (fila 18): hoy "Cargar" solo las deja en `CompanyTrips` y siguen en el piso de la zona (el tablero las esconde).
- **D-0715.b `order_packed`** `box_sealed` marca `PACKED` el pedido en el libro compartido; el tablero usa una copia propia donde lo está. Cuando exista, `CompanyDispatch._read_box()` deja de marcarlo y `_bridge()` (copia de pedidos al libro de `CompanyTrips`) sobra junto con D-0302.2.b.3.
- **D-0310.d** Más de una tanda por vehículo y elegir vehículo: hoy se ofrece el primero libre y uno con carga lista no se vuelve a ofrecer (`stage_cargo()` reemplaza); hace falta que el plan de `DispatchLoading` descuente lo ya cargado.
- **D-0310.e** Captura de `revisor-visual` del tablero a 1080p y de la estación en el galpón (`render_company_shed.gd`); el tablero gris es placeholder: pedido de arte para `modelador-blender` (cartel/mostrador de despacho).
**Depende de:** D-0309, D-0716
**Qué:** estación `dispatch` (un `DepotStation` con `station_id = &"dispatch"`). Al interactuar abre un
panel (UI por código, como el resto):
- lista de cajas listas, con sus pedidos y su zona;
- vehículo disponible con sus casilleros;
- botón "Cargar" que asigna las cajas al vehículo y las pone en la caja de carga (D-0717).
Navegable con mando.
**Test** `test_company_dispatch_panel`: con 3 cajas listas, elegir 2 con mando y confirmar las asigna al
vehículo; la tercera queda.
**Hecho cuando:** el test pasa y una captura de `revisor-visual` es legible a 1080p.

### D-0311 · Casas de entrega del mapa fijo — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `HouseMap` + `HouseSpot` (`scripts/gameplay/districts/`) y `data/world/houses.tres`: 30 casas en Centro y 20 en Campo, a 4-12 m del borde de la calzada de su calle, con la puerta hacia ella; `pick_for_day()` elige por semilla y día, `instance()` arma el `DeliveryHouse` tal cual; `test_company_houses`. Falta que el flujo de pedidos las use (D-0801+) y la dirección legible (D-0312). Ver `revisar/D-0311.md`.
**Depende de:** D-0304
**Qué:** las casas son puntos fijos del mapa: `data/world/houses.tres`, con id, zona, posición, frente y
variante. Usan `DeliveryHouse` tal cual (puerta, timbre, residente, revisión en la puerta). Por día, la
semilla elige cuáles piden. En F1: 30 casas en Centro y 20 en Campo.
**Test** `test_company_houses`: las 50 casas tienen calle a ≤ 12 m (nodo del grafo más cercano), no se
pisan entre sí y cada una se puede instanciar con `DeliveryHouse` sin errores.
**Hecho cuando:** el test pasa.

### D-0312 · Direcciones legibles — B · Opus 5.5 · medium · Aviso: no · F1
**[~] Parcial (2026-10-21, PR pendiente)** — `HouseAddresses` (`scripts/gameplay/districts/house_addresses.gd`): calle = etiqueta `street` de la arista de la casa (nombre `WORLD_STREET_<CALLE>`, 9 calles es/en en `strings_world.csv`), número = cuenta por calle y por lado (derecha par, izquierda impar) según el orden de aristas y la distancia; `OrderLabel.address` lo usa para las casas del mapa (las de `<zona>_house_<n>` quedan como antes) y `HouseMap.instance` lo pone en el cartel y el timbre (`DeliveryHouse.address_number` / `sign_number()`); `test_company_addresses`. Ver `revisar/D-0312.md`.
**Subtareas abiertas:**
- **D-0312.1** Cuando `OrderGenerator` nombre casas del `HouseMap` (D-0801+), `house_id` pasa a ser su id y desaparece el camino viejo `<zona>_house_<n>` de `OrderLabel`. Desde D-2016.2 (2026-10-22) `OrderGenerator` ya nombra casas del `HouseMap` en las zonas que tienen (Centro y Campo); el camino viejo queda solo para zonas sin casas en el mapa.
- **D-0312.2** Cartel de calle en las esquinas del mapa (arte: `arte-pendiente`), con la captura de `revisor-visual`.
**Depende de:** D-0311
**Qué:** cada arista con nombre de calle (lista traducible por zona, D-0345). Cada casa con número par o
impar según el lado. La etiqueta de la caja (D-0707) y el cartel de la casa muestran "Calle N".
**Test** `test_company_addresses`: las direcciones son únicas, y el número de la etiqueta y el de la casa
coinciden para 10 pedidos generados.
**Hecho cuando:** el test pasa.

### D-0313 · Arranque sin congelar y streaming sin tirones — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `CompanyRoot` suma el hijo `WorldCells` (`CompanyCells`) anclado a la tripulación y a los vehículos de empresa; la carga (menú → `LoadingScreen`) ocurre una sola vez. `test_company_cells` mide 10 celdas seguidas (< 50 ms por paso) y `test_company_root` comprueba el hijo y que no queda loader. Ver `revisar/D-0313.md`.
**Depende de:** D-0303, D-0214
**Qué:** el modo Empresa usa la pantalla de carga (N-407/N-408) **una sola vez**, al entrar. Después, todo
es streaming de celdas (D-0303). Medir el peor frame al cruzar 10 celdas seguidas.
**Test:** ampliar `test_loading_no_freeze` con el modo Empresa. `test_company_cells` mide que el peor
frame es < 50 ms.
**Hecho cuando:** los dos pasan.

### D-0314 · Barrio Centro jugable en gris — A · Opus 5.5 · high · Aviso: no · F1
**[~] Parcial (2026-10-22, PR pendiente)** — `CentroDecor` (`scripts/gameplay/districts/centro_decor.gd`) lo da cada celda `Cell_<x>_<z>` en un nodo `Centro` (`EdgeCellContent` + `CompanyCells.use_graph`): veredas de 2 m a los dos lados de las 17 calles de Centro (cortadas donde cruza otra calzada o hay una casa), las 30 casas de `houses.tres` con `HouseMap.instance()` en la celda donde caen (entran al árbol de a una por cuadro), 4 esquinas con semáforo apagado (poste y cabeza grises por esquina), 88 faroles y 47 bancos; una malla por color y un cuerpo de colisión por celda. `test_company_centro`. Ver [`revisar/D-0314.md`](../revisar/D-0314.md) y [`arte-pendiente/D-0314.md`](../arte-pendiente/D-0314.md).
**Subtareas abiertas:**
- ~~**D-0314.a**~~ ✅ (2026-10-22, PR pendiente) Nadie llama a `CompanyCells.use_graph()` en el juego (solo los tests): `CompanyRoot._add_cells()` arma celdas vacías. Conectarlo (con la malla de calles de D-0304.1, que hoy tampoco se ve en el juego) y comprobar que el galpón y las losas de zona (`_add_zone_slab`) conviven con la calzada y las veredas. Quedó: `CompanyRoot._add_cells()` llama `cells.use_graph(RoadGraph.load_default(), semilla de la sesión, false, CompanyCells.shed_ground(shed))`; las calles que arrancan en el centro del galpón empiezan donde salen de su suelo más grande (`EdgePieces.plan(..., keep_clear)`), el bloque lejano de cada celda baja a -0,2 para no pelear con las losas (-0,1) y `CompanyCells` guarda el contenido (un `Callable` no retiene el `RefCounted`). `test_company_root_graph`. Ver [`revisar/D-0314.a.md`](../revisar/D-0314.a.md).
- **D-0314.b** `bot_company_day` entrega en Centro (depende de D-0304.3, D-0801 y D-0314.a) y `revisor-visual` manda las 3 capturas (esquina con semáforo, cuadra con casas, vereda de cerca) sin agujeros en el piso ni casas flotando.
**Depende de:** D-0304, D-0311
**Qué:** la parte mínima de D-1501 que necesita el corte vertical:
- cuadras con veredas, 30 casas y 4 esquinas con semáforo apagado (sin tránsito en F1);
- decorado gris con props existentes (`route_props.gd`).
El tránsito y los peatones (D-1504, D-1505) quedan para F2.
**Hecho cuando:** `bot_company_day` entrega en Centro, y `revisor-visual` manda 3 capturas sin agujeros en
el piso ni casas flotando.

### D-0315 · Campo como zona del mapa — A · Opus 5.5 · high · Aviso: no · F1
**[~] Parcial (2026-10-22, PR pendiente)** — los eventos del Campo ya se planifican por arista y no por segmento generado: `EdgeEvents` (`scripts/gameplay/districts/edge_events.gd`, función pura de grafo + semilla) da, para cada calle del Campo (zona `campo` y superficie `gravel`/`dirt`; 11 de las 32 aristas), la lista determinista de eventos con su distancia a lo largo de la curva: `deer_crossing`, `flock_crossing` y `chasing_dog` (las chances y la semilla por pieza de `RouteWildlife`, sobre piezas `straight` del `EdgePieces`; el perro solo en las chacras, que es lo más parecido a un pueblo que tiene el Campo), `cargo_animal` (`CargoAnimalPlan.for_leg`: las calles del Campo en orden del grafo son los tramos del viaje) y `low_visibility` (`LowVisibilityPlan.draw`, un sorteo cada 75 m, una por calle como mucho). `EdgeCellContent` los reparte por celda (`events_in`, `event_cells`; el que cae en la celda donde está su punto) y, con `spawn_events` (apagado por defecto, y `CompanyCells.use_graph(graph, seed, spawn_events)`), arma en la celda los nodos de ciervo, rebaño y perro en su punto mirando a lo largo de la calle; sin eso la celda queda como antes. Los tipos de tramo de hoy ya estaban en el Campo salvo dos: se sumaron `construction_zone` (obras, `camino_campo_2`, junto a `gate_campo_obra`) y `speed_bump` (badén, `chacra_5`) en `data/world/road_graph.tres`. `test_company_edge_events` (misma semilla = mismos eventos, solo Campo, dentro de la arista, los planes reutilizados, el reparto por celda, los nodos), con `test_company_edge_pieces`, `test_company_edge_cells`, `test_road_graph` y el filtro `segment` en verde. Ver `revisar/D-0315.md`.
**Subtareas abiertas:**
- **D-0315.b** (`constructor-tramos`, high; depende de D-0302.2.b, el vehículo de la empresa) [~] Hecho (2026-10-22, PR pendiente): `EdgeCellContent.event_claims(cell)` / `reserve_events(placement, cell)` dan y marcan en un `RoutePlacement` los círculos de ciervo, rebaño y perro (las celdas de Campo todavía no pasan por un `RouteDresser`, así que falta quien lo llame; ver `revisar/D-0315.b.md`). Resto: Prender `spawn_events` en `CompanyRoot` con la semilla del mundo; que `cargo_animals.gd` y `low_visibility_event.gd` lean los eventos `cargo_animal` / `low_visibility` de la arista en la que va el vehículo (hoy corren por tiempo de viaje y no se enteran del grafo); que los animales ocupen un lugar en `RoutePlacement` para que el decorado de la celda no pise la espera del ciervo. Que `bot_company_day` entregue en Campo después de abrir `gate_campo_obra`, y la captura comparativa de `revisor-visual` (Campo-Empresa contra la ruta actual): ninguna de las dos se hizo, dependen del vehículo.
**Depende de:** D-0304
**Qué:** las aristas del Campo llevan los tipos de tramo de hoy (badén, chicana, puente, ripio, barro,
obras, tren). Los animales y eventos (`cargo_animals`, `flock_crossing`, `chasing_dog`,
`low_visibility_event`) se disparan por arista y no por segmento generado. La calidad visual tiene que ser
igual a la ruta actual.
**Hecho cuando:**
- `bot_company_day` entrega en Campo después de abrir `gate_campo_obra`;
- los tests de tramos (filtro `segment`) siguen verdes;
- `revisor-visual` compara una captura de Campo-Empresa con una de la ruta actual y el informe no marca
  diferencias de calidad.

### D-0316 · Jugadores repartidos entre galpón y calle — A · Opus 5.5 · xhigh · Aviso: sí (`network_manager.gd`) · F1
**[x] Hecho (2026-10-22, PR pendiente)** — las cuatro subtareas cerradas (D-0316.4: el conductor cliente frena su copia en el portón; `auditor-red` sin BUG). Lo que sigue es de D-0310.b (contexto real del tablero). Antes, parcial (2026-10-21): `WorldCellInterest` (módulo `world_cells`, `cell_interest.gd`): el host manda el sincronizador de cada vehículo (`company_vehicle`) y caja suelta (`company_loose_box`) solo a los peers con su jugador a ≤ 2 celdas (lo suelta pasado 3; el conductor y un peer sin jugador lo reciben siempre; pulso cada 20 s), y un cliente esconde su copia lejana (y la saca de la física) hasta que una actualización la trae cerca; `CompanyInterest` (hijo `Interest` de `CompanyRoot`); en un cliente las celdas cargan solo alrededor de su jugador; tope `CompanyTuning.VEHICLES_FAR_MAX = 2` en `CompanyTrips.departure_verdict()` (el portón no arranca una tercera salida, `departure_refused`, pero ese vehículo cuenta como afuera en `trips_out()` hasta volver) y el tablero de despacho apaga "Cargar" con el motivo `WORLD_DISPATCH_FAR_LIMIT`. Sin cambio de protocolo. `test_company_split_crew` (3 peers ENet), `test_world_cells_interest`, `test_company_trips`, `test_company_dispatch_panel`, `test_company_root`. Ver `revisar/D-0316.md` y `docs/decisiones/2026-10-21-visibilidad-por-distancia.md`.
**Subtareas abiertas:**
- [x] **D-0316.1** (2026-10-22, PR pendiente) Los nodos de los jugadores ya estaban (D-0214, PR #567: `_add_crew`, `CREW_GROUP`, el host los spawnea, entrada tarde y salida) y `CompanyInterest` los usa de ancla. Ahora `DayCycle.crew_in_shed` = `CompanyRoot._crew_in_shed()`: algún jugador de esta sesión con su `reach_origin()` (el asiento si está sentado) dentro de `CompanyShed.holds()` (piso del stage + espesor de pared, sin altura); sin galpón o sin jugadores todavía, true (no se congela antes del spawn). Sin cambio de protocolo: el congelado ya viaja en `day_phase`. `test_company_root`. Nadie lee `shed_minute()` todavía (el proveedor usa el reloj del mundo): ver [`revisar/D-0316.1.md`](../revisar/D-0316.1.md).
- [x] **D-0316.2** (2026-10-22, PR pendiente) Hecho:
  - la van real ya estaba en `company_vehicle` con su sincronizador como hijo directo (protocolo 49);
  - `WorldCellInterest.keep_shown` (en `CompanyInterest`: la que conduce este peer) no esconde nunca la copia predicha;
  - al mostrarse, `NetPoseSmoother` arranca de cero con un salto de más de 6 m (medido: menos de 0,5 m en el primer cuadro);
  - un vehículo con carga que cruzaría con `VEHICLES_FAR_MAX` afuera queda frenado: el host lo devuelve a su última pose de adentro, sin velocidad horizontal (`CompanyTrips.hold_at_gate`, `departure_held`, `TripGate.departs()`);
  - el conductor recibe el motivo por `CompanyTripsView._held_here` (`rpc_id` sobre `TripsView`, no sobre el vehículo), como aviso del depósito, como mucho una vez cada 3 s;
  - `copy_hidden` suelta el `occupied_by` del soporte de una caja escondida y `copy_shown` lo retoma si sigue libre;
  - `PROTOCOL_VERSION` 52;
  - tests: `test_company_trips`, `test_company_fleet` (ENet) y `test_world_cells_interest`.
  El conductor ve su vehículo en el portón con un aviso que le llega a él, y lo puede doblar a lo largo de la línea. Queda: el contexto real del tablero con `trips` (D-0310.b), el pulso medido en D-2002.2 y el freno en la copia del cliente (D-0316.4). Ver [`revisar/D-0316.2.md`](../revisar/D-0316.2.md). Texto original: El vehículo real de la empresa en `company_vehicle` con su `MultiplayerSynchronizer` hijo directo: comprobar que la copia que se esconde/muestra (`hide_far_copies`, sin colisiones mientras está escondida) se ve bien con el `NetPoseSmoother` y la predicción del conductor; frenar en el portón a un tercer vehículo rechazado (`departure_refused`) y mandarle el motivo a su conductor (hoy solo cuenta como afuera). Ningún hecho único ni baja del vehículo por RPC sobre el vehículo mismo (no llega a quien no lo ve: propiedad ON_CHANGE, evento de `CompanyNet` o `untrack()` antes). El contexto real del tablero (D-0310.b) le pasa `trips`. **Sube `PROTOCOL_VERSION`** (un cliente viejo no esconde las copias que el host deja de mandar). Medir en D-2002.2 el costo del pulso (0,1 s cada 20 s por cuerpo y peer oculto). Con los racks de la camioneta, resolver el soporte que una copia escondida y vieja deja ocupado (`package_mount_point.gd` `occupied_by`, latente desde D-0316.3: ver `revisar/D-0316.md`).
- [x] **D-0316.4** (2026-10-22, PR pendiente) Hecho: `CompanyGateBrake` (hijo `GateBrake` de `CompanyRoot`, solo en un cliente) escucha la señal nueva `CompanyTripsView.held_at_gate(vehicle_id, cap)` (la emite `_tell_held`, con el aviso de `_held_here`), arma una vez el mismo portón que el host (`CompanyFleet.trip_gate()`, que ahora usa también el host con `CompanyTrips.use_gate()`; lo rearma solo después de un snapshot) y durante `CompanyTuning.GATE_BRAKE_REAL_SECONDS` (3,5 s, más que la pausa de 3 s entre avisos, `GATE_HELD_NOTICE_REAL_SECONDS`) frena la copia que predice: al cruzar desde adentro la devuelve a su última pose de adentro (`CompanyTrips.put_back()`, el mismo código que el host); si ya estaba pasada cuando llegó el aviso, solo le saca la velocidad hacia afuera (`CompanyTrips.stop_outward()`, `TripGate.outward_at()`) y la predicción la trae (devolverla también la corregía dos veces y de un salto). Suelta antes con menos afuera que el tope, la camioneta afuera o la pose del host más de 1 m fuera del predio (propiedad `predicted_host_pose` de `vehicle.gd`: el host la soltó por algo que el cliente no ve; la copia la sigue sin snap). Sin cambio de protocolo. Medido (`test_company_fleet` `_check_held_lagged`, ahora afirma): ningún snap, como mucho 0,23 m por tick y brecha de 1,8-2,1 m (antes 1 snap de 3,04 m y 4,70 m); con el aviso 85 ms tarde, 2,7-3,1 m sin snap (impreso). `package.gd`: el setter de `current_mount_path` vacía el soporte solo si sigue siendo suyo (aviso `docs/avisos/2026-10-22-d0316-4-soporte-de-otra-caja.md`). `test_company_trips`, `test_company_fleet`. Queda: avisar antes de cruzar para bajar la brecha con un enlace real. Ver [`revisar/D-0316.4.md`](../revisar/D-0316.4.md). Texto original: Que el conductor cliente frene su propia copia en el portón. Al recibir `_held_here` guarda la línea del portón (`CompanyFleet.gate_of`, determinista) y durante unos 3 s limita su copia igual que el host. Con 150 ms + 20 ms de jitter a 12 m/s hoy salta una vez: corrección de 3,05–3,17 m (más que `SNAP_DISTANCE`, 3 m) y brecha de 5 m (`test_company_fleet` `_check_held_lagged`, informativo). Hecho cuando ese check afirma ningún snap y una brecha de menos de 2,5 m. De paso, el setter de `current_mount_path` en `package.gd` (de Slatex, con aviso) debería limpiar `occupied_by` solo si sigue siendo él (auditor-red, D-0316.2).
- [x] **D-0316.3** (2026-10-22, PR pendiente) Cada `DeliveryPackage` de `World/Packages` es caja suelta en todos los peers: `CompanyRoot._on_package_added()` llama a `CompanyInterest.add_loose_box()` (entra a `LOOSE_BOX_GROUP`; en el host, la señal nueva `DeliveryPackage.consuming`, que `PackageHandling.consume()` emite antes del broadcast de `_remote_consume`, llama a `WorldCellInterest.release()`: `untrack()` y fuera de los grupos, así la baja llega también al peer lejano). El ancla de un jugador es su `reach_origin()` (`CompanyInterest.anchor_point()`, también en `cell_anchors()`): sentado, el asiento, y no el cuerpo que quedó en el galpón (si no, la caja que va en la camioneta se le escondía a quien viaja con ella). Copia escondida: una capa o máscara que le escribe una actualización (el setter de `is_held`) o el juego se guarda para cuando se muestre y se vuelve a poner en 0; señal `copy_shown` y `CompanyInterest` rehace las capas de la caja con su `is_held`. `PROTOCOL_VERSION` 45. `test_world_cells_interest`, `test_company_sealed_package` (ENet: el `_remote_consume` de una caja oculta no llega; después de `consume()` sí), `test_company_split_crew` (el que viaja sentado), `test_company_root`.
**Depende de:** D-0303, D-2003
**Qué:** cada jugador es un ancla de `world_cells`. Un jugador en el galpón no recibe sincronización de
cuerpos de celdas lejanas: visibilidad por distancia con `MultiplayerSynchronizer.public_visibility` /
`set_visibility_for` en vehículos y cajas. El host sí simula todo. Tope de 2 vehículos lejos a la vez:
el tablero de despacho no deja salir un tercero, con motivo.
**Test** `test_company_split_crew`: 3 peers, 2 en una salida y 1 en el galpón. El del galpón no recibe
actualizaciones del vehículo lejano (contador del sincronizador), nadie se teletransporta y al volver la
salida todos ven lo mismo.
**Hecho cuando:** el test pasa y `auditor-red` aprobó.

### D-0317 · Decisión: vehículos lejos a la vez — B · Opus 5.5 · medium · Aviso: no · F1
**Depende de:** D-2002, D-0316
**Qué:** con las mediciones de D-2002, confirmar o subir el tope de 2 (punto 6 de la decisión del mapa).
Se anota en una decisión nueva del día.
**Hecho cuando:** la decisión está documentada y el número está en `world_tuning.gd`.

### D-0318 · Física lejos del jugador — B · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — con D-0318.1: las cajas del modo Empresa (los paquetes de `box_sealed`, D-0715.b) quedan registradas en `CompanyCells` en el host.
**[~] Parcial (2026-10-19, PR pendiente)** — `WorldCellStreamer.track_body/untrack_body/is_body_frozen` (módulo `world_cells`): un `RigidBody3D` registrado se congela (`FREEZE_MODE_STATIC`, velocidades guardadas) mientras su celda no está instanciada y se descongela al volver; lo que el juego ya tenía congelado se respeta. `modules/world_cells/tests/test_world_cells_freeze.gd`.
**Subtareas abiertas:**
- [x] **D-0318.1** (2026-10-22, PR pendiente, con D-0715.b) Las cajas del modo Empresa son los `DeliveryPackage` que deja `box_sealed` (D-0715.b, `World/Packages`): en el host, `CompanyRoot._on_package_added()` las registra con `cells.track_body()` y las suelta con `untrack_body()` al salir del árbol; la copia de un cliente sigue a la del host y no se registra. El galpón está en celdas fijas, así que adentro nunca se congelan. `test_company_root` (corre en el galpón, se congela lejos, se descongela al salir del árbol). Entran a `company_loose_box` con D-0316.3.
**Depende de:** D-0303
**Qué:** las cajas sueltas en celdas sin ancla se congelan (`freeze = true`) con su estado guardado, y se
descongelan al volver a cargar la celda, para que no se pierdan cuerpos que caen por un piso no cargado.
**Test** `test_world_cells_freeze`: una caja dejada en una vereda, lejos, sigue en el mismo lugar ±5 cm
después de que su celda se descarga y se vuelve a cargar.
**Hecho cuando:** el test pasa.

### D-0319 · El viaje gasta horas del día — A · Opus 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-22, PR pendiente)** — el reloj ya corre durante el viaje; `TripResult.build()` suma `depart_clock` / `return_clock` ("HH:MM", `TripResult.clock_text`) y el GPS ya daba `game_minutes` (D-0308.1a). `test_company_trip` comprueba 270 s reales = 180 min de juego (±1).
**Depende de:** D-0219, D-0302
**Qué:** no hace falta código especial, porque el reloj corre siempre (S3). Lo que sí: el resumen de la
salida muestra la hora de salida y de vuelta, y el GPS estima la llegada en hora de juego.
**Test:** en `test_company_trip`, la hora de vuelta es mayor que la de salida en (tiempo real × 60 / 90) ±1 min.
**Hecho cuando:** el test pasa.

### D-0320 · Resultado de la salida al cierre del día — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `TripResult` (`scripts/gameplay/districts/trip_result.gd`): `build()` arma el resumen de un `Trip` cerrado (línea por pedido con resultado, estado de la caja intacta/en riesgo/rota/sin entregar, paga, penalidad y reputación, más totales y mérito por jugador), `apply()` da el mérito al que llevó cada caja intacta (`CompanyTuning.TRIP_MERIT_INTACT`, sin repetirse) y `add_to_day()` suma las salidas al resumen del día; `test_company_trip_result`. Falta que el cierre del día lo llame (D-0508.3). D-0520 (2026-10-22): el mérito sale del puntaje de la salida (`TripScoring`: intacta 10, abollada 5) y `build()` suma `score`; ver `detalle/F1-05-economia.md`.
**Depende de:** D-0305, D-0501
**Qué:** al cerrar un `Trip` se arma su resumen: pedidos entregados, estado de cada caja (intacta, en
riesgo, rota; como `RunManager` hoy), paga, penalidades y mérito por jugador (`CrewProgression`). Se suma
al resumen del día (D-0508).
**Test** `test_company_trip_result`: una salida con 1 caja intacta y 1 rota da la paga y la penalidad de
la tabla de supuestos, y suma mérito al que llevaba la intacta.
**Hecho cuando:** el test pasa.
