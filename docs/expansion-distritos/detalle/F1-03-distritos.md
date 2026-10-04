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
**Test del juego** `test_world_cells_company`: manejar del galpón a Centro no deja frames > 50 ms por la
carga (medido con el reloj del motor en headless) ni huérfanos al volver.
**Hecho cuando:** los dos tests pasan y CI corre el módulo en `portability-check.sh`.

### D-0304 · Grafo de calles y tramos sobre aristas — A · Opus 5.5 · xhigh · Aviso: sí (`modules/route_gen/`) · F1
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
**Depende de:** D-0302, D-0311
**Qué:** un `Trip` tiene una lista de paradas (casa + pedidos). Entregar en una casa saca esos pedidos.
La salida no termina hasta volver al galpón. Las cajas que no se entregaron vuelven con estado `FAILED`
y la mercadería vuelve al stock si la caja está sana.
**Test** `test_company_trip_stops`: un `Trip` con 3 casas. Entregar en 2 y volver deja 2 `DELIVERED`, 1
`FAILED` y los productos de esa caja de vuelta en `Inventory`.
**Hecho cuando:** el test pasa.

### D-0306 · Bloqueos (`GateRequirement`) — A · Opus 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `GateRequirement` + `WorldGate` + 7 `.tres` en `data/gates/` (boceto del mapa); `CompanyState.open_gate/is_gate_open/gate_owned` y campo `equipment`; test `test_gate`. La replicación por evento queda en D-2003.
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
**Depende de:** D-0306, D-0207
**Qué:** al despachar (D-0310), un pedido cuya casa está en una zona inalcanzable para ese vehículo (por
bloqueo cerrado o por `gate_key`) se marca y no se puede cargar, con el motivo.
**Test** `test_company_dispatch_rules`: un pedido de Islas no entra en la camioneta (motivo "necesita
lancha"); uno de Suburbio con la barrera cerrada no entra (motivo "barrera: falta el hito X").
**Hecho cuando:** el test pasa.

### D-0310 · Tablero de despacho — A · Opus 5.5 · high · Aviso: sí (`scripts/ui/`) · F1
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
**Depende de:** D-0304
**Qué:** las casas son puntos fijos del mapa: `data/world/houses.tres`, con id, zona, posición, frente y
variante. Usan `DeliveryHouse` tal cual (puerta, timbre, residente, revisión en la puerta). Por día, la
semilla elige cuáles piden. En F1: 30 casas en Centro y 20 en Campo.
**Test** `test_company_houses`: las 50 casas tienen calle a ≤ 12 m (nodo del grafo más cercano), no se
pisan entre sí y cada una se puede instanciar con `DeliveryHouse` sin errores.
**Hecho cuando:** el test pasa.

### D-0312 · Direcciones legibles — B · Opus 5.5 · medium · Aviso: no · F1
**Depende de:** D-0311
**Qué:** cada arista con nombre de calle (lista traducible por zona, D-0345). Cada casa con número par o
impar según el lado. La etiqueta de la caja (D-0707) y el cartel de la casa muestran "Calle N".
**Test** `test_company_addresses`: las direcciones son únicas, y el número de la etiqueta y el de la casa
coinciden para 10 pedidos generados.
**Hecho cuando:** el test pasa.

### D-0313 · Arranque sin congelar y streaming sin tirones — A · Opus 5.5 · high · Aviso: no · F1
**Depende de:** D-0303, D-0214
**Qué:** el modo Empresa usa la pantalla de carga (N-407/N-408) **una sola vez**, al entrar. Después, todo
es streaming de celdas (D-0303). Medir el peor frame al cruzar 10 celdas seguidas.
**Test:** ampliar `test_loading_no_freeze` con el modo Empresa. `test_world_cells_company` mide que el peor
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
**Depende de:** D-0305, D-0501
**Qué:** al cerrar un `Trip` se arma su resumen: pedidos entregados, estado de cada caja (intacta, en
riesgo, rota; como `RunManager` hoy), paga, penalidades y mérito por jugador (`CrewProgression`). Se suma
al resumen del día (D-0508).
**Test** `test_company_trip_result`: una salida con 1 caja intacta y 1 rota da la paga y la penalidad de
la tabla de supuestos, y suma mérito al que llevaba la intacta.
**Hecho cuando:** el test pasa.
