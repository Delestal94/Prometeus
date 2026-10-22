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
- **D-0302.2** Cuando exista el vehículo de la empresa (D-0207+): meterlo en el grupo `company_vehicle` con su id como nombre, llamar `stage_cargo()` desde la zona de despacho (D-0703/D-0716), pasar el `OrderBook` de la empresa a `CompanyTrips.book` (D-0801) y replicar `trip_started`/`trip_closed` por evento de `CompanyNet` (D-2003). El `depot_roller_door.gd` no hace falta: el cruce se mide contra el plano de la salida.
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
- **D-0304.4** Capturas de `revisor-visual` de 3 aristas (asfalto, ripio, barro) cuando exista D-0304.1.
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
**Depende de:** D-0302, D-0304
**Qué:** no hay salto: se vuelve manejando. El GPS (D-0308) apunta al galpón cuando no quedan paradas.
Opción "volver con grúa" (pagando 50, valor en tuning): si el vehículo quedó `STUCK` o roto, aparece en
el playón en 3 s de pantalla negra, con los pedidos que quedaban en `FAILED`.
**Test** `test_company_tow_home`: un vehículo `STUCK` con grúa aparece en el playón, la plata baja 50 y
el `Trip` se cierra.
**Hecho cuando:** el test pasa.

### D-0308 · GPS y navegación por el grafo — A · Opus 5.5 · high · Aviso: no · F1
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
**[~] Panel hecho (2026-10-21, PR pendiente)** — `DispatchBoardPanel` (`scripts/ui/dispatch_board_panel.gd`): UI por código sobre datos inyectados (`zone`, `book`, `trips`, `vehicle`, `box_kg`, reglas); filas con marca ✓/○/✗, motivo de `DispatchRules` en las bloqueadas, casilleros y kg del vehículo, "Cargar" por `DispatchZone.load_boxes` -> `stage_cargo`; mando y teclado; cliente con "Cargar" deshabilitado y motivo. `test_company_dispatch_panel`. **Falta D-0310.b** (`constructor-mundo`): la estación `DepotStation` `dispatch` en el galpón (hoy `DispatchZone` no tiene nodo en el mundo, D-0716.b/D-0717.b), el contexto real del panel y la captura de `revisor-visual`. Ver `revisar/D-0310.md`.
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
- **D-0312.1** Cuando `OrderGenerator` nombre casas del `HouseMap` (D-0801+), `house_id` pasa a ser su id y desaparece el camino viejo `<zona>_house_<n>` de `OrderLabel`.
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
**Depende de:** D-0304, D-0311
**Qué:** la parte mínima de D-1501 que necesita el corte vertical:
- cuadras con veredas, 30 casas y 4 esquinas con semáforo apagado (sin tránsito en F1);
- decorado gris con props existentes (`route_props.gd`).
El tránsito y los peatones (D-1504, D-1505) quedan para F2.
**Hecho cuando:** `bot_company_day` entrega en Centro, y `revisor-visual` manda 3 capturas sin agujeros en
el piso ni casas flotando.

### D-0315 · Campo como zona del mapa — A · Opus 5.5 · high · Aviso: no · F1
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
**[~] Parcial (2026-10-21, PR pendiente)** — `WorldCellInterest` (módulo `world_cells`, `cell_interest.gd`): el host manda el sincronizador de cada vehículo (`company_vehicle`) y caja suelta (`company_loose_box`) solo a los peers con su jugador a ≤ 2 celdas (lo suelta pasado 3; el conductor y un peer sin jugador lo reciben siempre; pulso cada 20 s), y un cliente esconde su copia lejana (y la saca de la física) hasta que una actualización la trae cerca; `CompanyInterest` (hijo `Interest` de `CompanyRoot`); en un cliente las celdas cargan solo alrededor de su jugador; tope `CompanyTuning.VEHICLES_FAR_MAX = 2` en `CompanyTrips.departure_verdict()` (el portón no arranca una tercera salida, `departure_refused`, pero ese vehículo cuenta como afuera en `trips_out()` hasta volver) y el tablero de despacho apaga "Cargar" con el motivo `WORLD_DISPATCH_FAR_LIMIT`. Sin cambio de protocolo. `test_company_split_crew` (3 peers ENet), `test_world_cells_interest`, `test_company_trips`, `test_company_dispatch_panel`, `test_company_root`. Ver `revisar/D-0316.md` y `docs/decisiones/2026-10-21-visibilidad-por-distancia.md`.
**Subtareas abiertas:**
- [x] **D-0316.1** (2026-10-22, PR pendiente) Los nodos de los jugadores ya estaban (D-0214, PR #567: `_add_crew`, `CREW_GROUP`, el host los spawnea, entrada tarde y salida) y `CompanyInterest` los usa de ancla. Ahora `DayCycle.crew_in_shed` = `CompanyRoot._crew_in_shed()`: algún jugador de esta sesión dentro de `CompanyShed.holds()` (piso del stage + espesor de pared, sin altura); sin galpón o sin jugadores todavía, true (no se congela antes del spawn). Sin cambio de protocolo: el congelado ya viaja en `day_phase`. `test_company_root`. Nadie lee `shed_minute()` todavía (el proveedor usa el reloj del mundo): ver [`revisar/D-0316.1.md`](../revisar/D-0316.1.md).
- **D-0316.2** (`constructor-red`, high; con D-0302.2) El vehículo real de la empresa en `company_vehicle` con su `MultiplayerSynchronizer` hijo directo: comprobar que la copia que se esconde/muestra (`hide_far_copies`, sin colisiones mientras está escondida) se ve bien con el `NetPoseSmoother` y la predicción del conductor; frenar en el portón a un tercer vehículo rechazado (`departure_refused`) y mandarle el motivo a su conductor (hoy solo cuenta como afuera). Ningún hecho único ni baja del vehículo por RPC sobre el vehículo mismo (no llega a quien no lo ve: propiedad ON_CHANGE, evento de `CompanyNet` o `untrack()` antes). El contexto real del tablero (D-0310.b) le pasa `trips`. **Sube `PROTOCOL_VERSION`** (un cliente viejo no esconde las copias que el host deja de mandar). Medir en D-2002.2 el costo del pulso (0,1 s cada 20 s por cuerpo y peer oculto).
- **D-0316.3** (con D-0318.1) Las cajas sueltas del galpón y la calle entran al grupo `CompanyInterest.LOOSE_BOX_GROUP`. Antes, sacar de la caja todo RPC de hecho único o baja que se llame sobre ella (`package_handling.gd` `_remote_consume`: con la caja oculta para un peer lejano, ese peer se quedaría con una caja fantasma): propiedad ON_CHANGE, evento de `CompanyNet` o `untrack()` antes del broadcast. **Sube `PROTOCOL_VERSION`** en ese PR.
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
**[~] Parcial (2026-10-19, PR pendiente)** — `WorldCellStreamer.track_body/untrack_body/is_body_frozen` (módulo `world_cells`): un `RigidBody3D` registrado se congela (`FREEZE_MODE_STATIC`, velocidades guardadas) mientras su celda no está instanciada y se descongela al volver; lo que el juego ya tenía congelado se respeta. `modules/world_cells/tests/test_world_cells_freeze.gd`.
**Subtareas abiertas:**
- **D-0318.1** Registrar las cajas sueltas del modo Empresa (`CompanyCells.track_body`) cuando existan las cajas del galpón/calle (D-0703, D-0214): hoy ningún nodo las suelta en el mapa.
**Depende de:** D-0303
**Qué:** las cajas sueltas en celdas sin ancla se congelan (`freeze = true`) con su estado guardado, y se
descongelan al volver a cargar la celda, para que no se pierdan cuerpos que caen por un piso no cargado.
**Test** `test_world_cells_freeze`: una caja dejada en una vereda, lejos, sigue en el mismo lugar ±5 cm
después de que su celda se descarga y se vuelve a cargar.
**Hecho cuando:** el test pasa.

### D-0319 · El viaje gasta horas del día — A · Opus 5.5 · low · Aviso: no · F1
**Depende de:** D-0219, D-0302
**Qué:** no hace falta código especial, porque el reloj corre siempre (S3). Lo que sí: el resumen de la
salida muestra la hora de salida y de vuelta, y el GPS estima la llegada en hora de juego.
**Test:** en `test_company_trip`, la hora de vuelta es mayor que la de salida en (tiempo real × 60 / 90) ±1 min.
**Hecho cuando:** el test pasa.

### D-0320 · Resultado de la salida al cierre del día — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `TripResult` (`scripts/gameplay/districts/trip_result.gd`): `build()` arma el resumen de un `Trip` cerrado (línea por pedido con resultado, estado de la caja intacta/en riesgo/rota/sin entregar, paga, penalidad y reputación, más totales y mérito por jugador), `apply()` da el mérito al que llevó cada caja intacta (`CompanyTuning.TRIP_MERIT_INTACT`, sin repetirse) y `add_to_day()` suma las salidas al resumen del día; `test_company_trip_result`. Falta que el cierre del día lo llame (D-0508.3).
**Depende de:** D-0305, D-0501
**Qué:** al cerrar un `Trip` se arma su resumen: pedidos entregados, estado de cada caja (intacta, en
riesgo, rota; como `RunManager` hoy), paga, penalidades y mérito por jugador (`CrewProgression`). Se suma
al resumen del día (D-0508).
**Test** `test_company_trip_result`: una salida con 1 caja intacta y 1 rota da la paga y la penalidad de
la tabla de supuestos, y suma mérito al que llevaba la intacta.
**Hecho cuando:** el test pasa.
