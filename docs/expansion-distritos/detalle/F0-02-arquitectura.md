# F0 · Grupo 02 — Arquitectura, datos y guardado (detalle)

> Carril 1 de la rutina `desarrollador`. Mundo continuo (`docs/decisiones/2026-10-04-mapa-continuo.md`).
> Nada de esto cambia el comportamiento de Entrega ni de Endless: sus tests tienen que seguir verdes en cada PR.
> Aviso en `docs/avisos/` cuando se toque `event_bus.gd`, `network_manager.gd`, `run_manager.gd` o `modules/`.

### D-0201 · Arquitectura de la expansión documentada — A · Opus 5.5 · xhigh · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — sección 10 "Modo Empresa" de `docs/arquitectura.md`: capas, autoridad, señales de `EventBus`, carpetas y flujo de una caja.
**Depende de:** D-0119
**Qué:** sección "Modo Empresa" en `docs/arquitectura.md`:
- **Capas.** `CompanyState` (persistente, autoload) → `DayCycle` (día en curso) → `WorldCells` (qué
  partes del mapa están cargadas) → salidas (vehículo + cajas fuera del galpón).
- **Autoridad.** El host es dueño de todo el estado del negocio; los clientes mandan pedidos de acción
  por RPC con `RpcGuard`.
- **Señales nuevas en `EventBus`.**
- **Carpetas nuevas.**
- **Diagrama** en texto: flujo de una caja desde el palet hasta la puerta.
**Hecho cuando:** la sección existe, y `auditor-red` la leyó sin hallazgos de autoridad.

### D-0202 · Autoload `CompanyState` y `company_tuning.gd` — A · Opus 5.5 · xhigh · Aviso: sí (`project.godot` autoloads) · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `company_state.gd` (autoload tras `UnlockManager`), `company_tuning.gd` (`class_name CompanyTuning`, todos los números de supuestos.md); `Order`, `Pallet` y `ProductDefinition` leen de ahí; `test_company_state` y `test_hud_script_loads` ampliado.
**Depende de:** D-0201
**Qué:**
- `scripts/core/company/company_state.gd`, autoload `CompanyState` registrado después de
  `UnlockManager`. Campos: `money: int`, `day: int`, `clock_minutes: int`, `reputation: float`,
  `district_reputation: Dictionary`, `opened_gates: Array[StringName]`, `fleet: Array[Dictionary]`,
  `employees: Array[Dictionary]`, `milestones_done: Array[StringName]`, `layout: Array[Dictionary]`,
  `inventory: Dictionary` (lo delega a D-0211).
- Métodos: `new_company(name)`, `to_dict()`, `from_dict()`, `is_active()` (falso fuera del modo Empresa,
  para que Entrega y Endless lo ignoren).
- `scripts/core/company/company_tuning.gd` con **todos** los números de [supuestos.md](supuestos.md)
  como `const`.
- No nombrar `Hud` ni clases de UI (lección N-919).
- [x] **D-0202.1** Autoload y tuning.
- [x] **D-0202.2** `test_company_state`: `new_company` → plata 500, día 1, reputación 50. `to_dict` →
  `from_dict` devuelve lo mismo. `is_active()` falso al arrancar Entrega.
- [x] **D-0202.3** Extender `test_hud_script_loads` para que un `--script` que nombra `CompanyState` no pierda autoloads.
**Hecho cuando:** los dos tests pasan y la batería de CI sigue verde.

### D-0203 · `DayCycle`: apertura, operación y cierre — A · Opus 5.5 · high · Aviso: sí (`event_bus.gd`) · F0
**[x] Hecho (2026-10-12, PR pendiente)** — `day_cycle.gd` (`DayCycle`, hijo del mundo): fases como hechos del host (evento `day_phase` de `CompanyNet`, parte `day_cycle` del snapshot, `PROTOCOL_VERSION` 32), señales `company_day_*` emitidas al aplicar en cada peer, galpón congelado como minuto propio (`shed_minute()`, no el reloj pausado), cableado en `company_root.gd` (`GameClock` + `DayCycle` en todos los peers; el host abre el día); `test_day_cycle` (solo + dos peers ENet). Falta: el área del galpón para `crew_in_shed` y `trips_out` (D-0319), guardar al `SUMMARY` (D-0206) y la pantalla de cierre.
**Depende de:** D-0202, D-0219
**Qué:** `scripts/core/company/day_cycle.gd` (nodo hijo del mundo, no autoload).
- **Estados** `OPENING` (08:00, 5 s reales: aparece el proveedor) → `OPERATING` → `CLOSING` (20:00 o
  más tarde si hay salidas afuera, S3) → `SUMMARY` (pantalla de cierre) → día siguiente.
- **Galpón congelado** (S4): sin jugadores dentro del área del galpón y sin empleados, el reloj del
  galpón no avanza. Las salidas siguen.
- **Señales en `EventBus`**: `company_day_started(day)`, `company_day_closing(day)`,
  `company_day_summary(day, summary: Dictionary)`.
- **Test** `test_day_cycle`: con el reloj acelerado ×100 recorre los 4 estados en orden, una salida
  afuera demora el `SUMMARY`, y con todos fuera del galpón `clock_minutes` del galpón queda quieto.
**Hecho cuando:** el test pasa.

### D-0204 · Recurso `ProductDefinition` — A · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-04, PR #279)** — `ProductDefinition` + 10 `.tres` en `data/products/` (uno por contenido); `test_product_definitions`.
**Depende de:** D-0116
**Qué:** `scripts/gameplay/business/product_definition.gd` (`class_name ProductDefinition extends Resource`).
- **Campos:**
  - `id: StringName` y `content: PackageContent` (modelo, textos, notas; S9);
  - `cells: Vector3i`, `weight_kg: float`, `fragile: bool`;
  - `temperature: StringName` (`&"ambient"`, `&"cold"`, `&"heat"`);
  - `buy_price: int` y `sell_price: int` (por defecto `buy × 1,6`, calculado en `get_sell_price()`);
  - `trap_id: StringName` (la del contenido) y `districts: Array[StringName]`.
- Diez `.tres` en `data/products/`, uno por cada `data/contents/*.tres`, con los valores de D-0116.
- **Test** `test_product_definitions`: los 10 cargan, ids únicos, `cells` dentro de la caja XL (4×4×4),
  `buy_price` entre 20 y 80, `trap_id` existe en `data/traps/`.
**Hecho cuando:** el test pasa.

### D-0205 · Recurso `ZoneDefinition` (antes "DistrictDefinition") — A · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `ZoneDefinition` + 9 `.tres` en `data/zones/` (bounds provisorios en grilla de 256 m hasta D-0301; gates `gate_*` que D-0306 crea); `test_zone_definitions`.
**Depende de:** D-0114
**Qué:** `scripts/gameplay/districts/zone_definition.gd`. En el mapa continuo un distrito es una **zona**
del mapa.
- **Campos:** `id`, `display_key` (texto `tr`), `bounds: Rect2` (en metros del mundo, XZ), `vehicles:
  Array[StringName]`, `hazards: Array[StringName]`, `gates: Array[StringName]` (ids de bloqueos que la
  cierran, D-0306), `mood_profiles: Array[StringName]`, `shipping_fee: int`, `houses_per_trip:
  Vector2i`, `base_reputation_gain: float`.
- `.tres` de las 9 zonas en `data/zones/`, con `bounds` del boceto de mapa de D-0301. Para F1 solo
  `parque_industrial`, `centro` y `campo` tienen datos completos; el resto lleva `bounds` y `gates`.
- **Test** `test_zone_definitions`: las 9 cargan; los `bounds` no se pisan entre sí; cada `gate` existe en
  `data/gates/`; las zonas abiertas al inicio son `parque_industrial` y `centro`.
**Hecho cuando:** el test pasa.

### D-0206 · Guardado de empresa versionado — A · Opus 5.5 · xhigh · Aviso: sí (`modules/persistence/`) · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `company_save.gd` (`CompanySave`: `save`/`load_into`/`migrate` sobre `SafeJson`, `user://saves/company/<slot>.json`, versión 1, `MIGRATIONS` vacía); `test_company_save`. Engancharlo al cierre del día y al menú queda para D-0203/D-0214.
**Depende de:** D-0202
**Qué:** `scripts/core/company/company_save.gd`. Usa `SafeJson` (`modules/persistence/safe_json.gd`) como
`CrewProgression`.
- **Ruta:** `user://saves/company/<slot>.json`, con un campo `"version": 1` y una tabla de migraciones
  `MIGRATIONS = {1: Callable}` (se aplica en orden, del save viejo al nuevo).
- **Escritura atómica:** escribir en `.tmp` y renombrar.
- **Cuándo guarda:** al `SUMMARY` del día y al salir al menú. Nunca a mitad de día en F1 (D-0236 lo amplía).
- [x] **D-0206.1** Guardar y cargar con `CompanyState.to_dict/from_dict`.
- [x] **D-0206.2** Migración de prueba v1 → v2 (agrega un campo con valor por defecto) dentro del test,
  sin dejarla en el código de producción.
- [x] **D-0206.3** `test_company_save`:
  - ida y vuelta igual;
  - un archivo corrupto no rompe y devuelve una empresa nueva con aviso;
  - un save v1 migra;
  - el `.tmp` sobrante de un corte se ignora.
**Hecho cuando:** el test pasa.

### D-0207 · Recurso `VehicleDefinition` sin cambiar la camioneta — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-19, PR #499)** — `VehicleDefinition` (+ `fleet_key` y `amplified_trap` de `flota.md`) y `van_classic/agile/vintage.tres` en `data/vehicles/`; `CompanyTuning.STARTING_FLEET`; `test_vehicle_definitions`. Sin tocar `vehicle.gd` ni `UnlockManager.TRUCKS`.
**Depende de:** D-0115
**Qué:** `scripts/gameplay/fleet/vehicle_definition.gd`. Campos: `id`, `scene: PackedScene`, `variant:
StringName` (las de `vehicle.gd` `VARIANTS`), `seats: int`, `cargo_slots: int`, `cargo_kg: float`,
`movement: StringName` (`&"wheels"`, `&"hull"`, `&"wings"`, `&"pedal"`), `gate_key: StringName` (qué
bloqueo abre: `&"water"`, `&"altitude"`…), `price: int`. Tres `.tres` en `data/vehicles/` para
`classic`, `agile` y `vintage`, leyendo los mismos valores que `UnlockManager.TRUCKS` hoy.
**Test** `test_vehicle_definitions`: los 3 cargan y la escena instancia un `VehicleBody3D` con la variante.
`test_reference_truck` sigue verde (sin tocar el manejo).
**Hecho cuando:** los dos tests pasan.

### D-0208 · Base común `FleetVehicle` — B · Opus 5.5 · xhigh · Aviso: no · F0
**[x] Hecho (2026-10-19, PR #525)** — componentes `FleetCargo` (bahía, shell, `carries`/`point_velocity`/`needs_sweep`, acomodo y spawn) y `FleetSeats` (consultas) en `scripts/gameplay/fleet/`; `vehicle.gd` 860 → 744 líneas con la misma API.
**Depende de:** D-0207
**Qué:** lo que necesita cualquier vehículo (asientos, carga, red, presentación) a una clase base o
componente, para que lancha, avioneta y bici no hereden de `VehicleBody3D`. Recomendado: **componente**
`scripts/gameplay/fleet/fleet_seats.gd` + `fleet_cargo.gd` que la camioneta usa por composición. No mover
lógica de manejo.
- [ ] **D-0208.1** Inventario de qué partes de `vehicle.gd` son asientos y carga (con líneas). Ojo: otra
  sesión puede estar tocando `vehicle.gd`: rebase antes de empezar y cambios mínimos.
- [ ] **D-0208.2** Extraer a componentes con la misma API pública.
- [ ] **D-0208.3** Actualizar `docs/agregar-vehiculo.md`.
**Hecho cuando:** los tests con filtros `vehicle`, `truck`, `seat` y `cargo` están verdes, `auditor-red`
no tiene hallazgos y `vehicle.gd` bajó de líneas.

### D-0209 · Interfaz de movimiento del vehículo — B · Opus 5.5 · xhigh · Aviso: no · F0
**[x] Hecho (2026-10-21, PR pendiente)** — `fleet_motion.gd` (`speed_kmh`, `forward`, `right`, `to_local`, `ground_contact`, `cargo_acceleration`) expuesto por la furgoneta como `fleet_motion`; `package_rescue.gd` lee espacio local y ejes por la interfaz con respaldo en la transformada; `road_impacts.gd`/`package_impacts.gd` no leían el vehículo, quedan igual; `test_fleet_motion`.
**Depende de:** D-0208
**Qué:** `scripts/gameplay/fleet/fleet_motion.gd`, interfaz con `speed_kmh()`, `forward()`,
`ground_contact() -> float` (0-1; 1 = apoyado), `cargo_acceleration() -> Vector3` (lo que sienten las
cajas). La implementa la camioneta. Los impactos de carga (`road_impacts.gd`, `package_impacts.gd`)
leen esta interfaz en vez del `VehicleBody3D`.
**Test** `test_fleet_motion`: un vehículo falso (Node3D con la interfaz) mueve cajas igual que la
camioneta con la misma aceleración (±5 %).
**Hecho cuando:** el test pasa y los tests de carga actuales siguen verdes.

### D-0210 · `OrderBook` — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `order_book.gd` (Node, autoridad del host) con `add/mark_packed/mark_out/mark_delivered/mark_failed/cancel/expire/open_orders` y `to_dict/from_dict`; `test_order_book`.
**Depende de:** D-0202, D-0204
**Qué:** `scripts/gameplay/business/order_book.gd`, hijo del mundo, autoridad en el host.
- **Pedido** = `Dictionary` con `id`, `customer`, `zone`, `house_id`, `items: Array[{product, qty}]`,
  `requirements: Array[StringName]`, `created_min`, `due_min`, `pay`, `state` (`OPEN`, `PACKED`,
  `OUT`, `DELIVERED`, `LATE`, `FAILED`, `CANCELLED`).
- **API:** `add(order)`, `mark_packed(id, box_id)`, `mark_out(id, trip_id)`,
  `mark_delivered(id, quality, intact)`, `expire(now_min)`, `open_orders(zone := &"")`.
- **Señales:** `order_added`, `order_changed`.
- **Test** `test_order_book`: el ciclo completo de un pedido; vence a las 4 h de juego (la paga baja 25 %
  si llega tarde); `open_orders` filtra por zona; las transiciones inválidas (`DELIVERED` → `OPEN`) se
  rechazan.
**Hecho cuando:** el test pasa.

### D-0211 · `Inventory` — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `inventory.gd` (RefCounted, solo datos) con `receive/consume/move/count/reserve/release`, `to_dict/from_dict`; `test_inventory`.
**Depende de:** D-0204
**Qué:** `scripts/gameplay/business/inventory.gd`.
- **Stock** por `product_id` y ubicación (`&"dock"`, `&"shelf:<slot_id>"`, `&"cart:<id>"`,
  `&"box:<id>"`, `&"hands:<peer>"`).
- **API:** `move(product, qty, from, to) -> bool`, `count(product, location := &"")`, `reserve(product,
  qty, order_id)`, `release(order_id)`. Las unidades nunca se crean ni se destruyen salvo `receive()` (del
  proveedor) y `consume()` (entregado/roto).
- **Test** `test_inventory`: 200 movimientos al azar con semilla fija conservan el total. Mover más de lo
  que hay falla sin cambiar nada. `reserve` evita que otro pedido tome lo reservado.
**Hecho cuando:** el test pasa.

### D-0212 · `PackedBox` — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `packed_box.gd` (`PackedBox`, RefCounted: grilla de la caja, `place`/`fill_free_cells`/`contents`/`free_ratio`/`fill_ratio`, `to_dict`/`from_dict` aptos para JSON); `test_packed_box`.
**Depende de:** D-0204
**Qué:** `scripts/gameplay/business/packed_box.gd` (`RefCounted`).
- **Campos:** `box_size` (`&"S"`…`&"XL"`), `grid: Dictionary` (celda `Vector3i` → product id o
  `&"fill"`), `taped`, `label_order_id`, `stamps: Array[StringName]`.
- **Métodos:** `place(product, origin: Vector3i) -> bool` (falla si pisa celdas o se sale);
  `fill_free_cells(n)`; `contents() -> Dictionary`; `free_ratio()`; `fill_ratio()`;
  `to_dict()`/`from_dict()`.
- **Test** `test_packed_box`: en una M (3×3×3) entra un producto 1×1×2 en 0,0,0, y no en 0,0,2; el
  relleno no pisa productos; la serialización va y vuelve.
**Hecho cuando:** el test pasa.

### D-0213 · De `PackedBox` a `DeliveryPackage` con su trampa — A · Opus 5.5 · xhigh · Aviso: sí (`package.gd`, `package_content.gd`, de Slatex) · F0
**[x] Hecho (2026-10-05, PR pendiente)** — `box_to_package.gd` (`BoxToPackage.build`): trampa y contenido del producto más difícil, absorción por relleno, metadata `packed_box`/`order_id`/`loose_box`; `test_box_to_package`. Sin cambios en `package.gd`.
**Depende de:** D-0212, D-0109
**Qué:** `scripts/gameplay/business/box_to_package.gd`. Instancia `scenes/gameplay/package/package.tscn`
(como `Depot.PACKAGE_SCENE`) y configura:
- `trap_definition` = la del producto de mayor dificultad (`UnlockManager.TRAP_DIFFICULTY_ORDER`);
- `content` = el `PackageContent` de ese producto;
- `impact_absorption` = `lerp(1.0, 0.6, fill_ratio_of_free)`;
- metadata `&"packed_box"` con el `to_dict()` y `&"order_id"`.
Agregar antes que cambiar: ninguna firma existente cambia.
**Test** `test_box_to_package`:
- jarrón solo con relleno total → `fragile` con absorción 0,6;
- sin relleno → absorción 1,0;
- jarrón + pastel → la trampa del más difícil;
- caja XL con un producto 1×1×1 sin relleno → metadata `&"loose_box"` (la usa D-0710 para Equilibrio).
**Hecho cuando:** el test pasa y el aviso está en `docs/avisos/`.

### D-0214 · Escena del mundo de la empresa — A · Opus 5.5 · high · Aviso: sí (`network_manager.gd` `LEVEL_SCENES`, `main_menu.gd`) · F0
**[x] Hecho (2026-10-21, PR pendiente)** — la raíz es `company_root.tscn` (`CompanyRoot`, PR #324); la continuación la pone en línea: en `LEVEL_SCENES` (`PROTOCOL_VERSION` 38), llama a `level_ready()`, el host spawnea un jugador por peer por `World/PlayerSpawner` (`join_crew()`, `crew_spawn()`) y lo saca cuando se va; `--autostart-company [--slot=<n>]` (alias `--mode=company`) y `--host-company` (sin botón: uno más en la página Jugar empuja "Volver" fuera de una pantalla de 720 px; queda para quien reacomode esa página); `test_company_world_boot`, `test_company_online` y `tools/run-net-pair.sh --company`. Aviso `docs/avisos/2026-10-21-d0214-empresa-en-linea.md`.
**Depende de:** D-0202, D-0301
**Qué:** `scenes/company/company_world.tscn` con raíz `CompanyWorld` (`scripts/gameplay/districts/company_world.gd`).
- **Hijos:** `WorldCells` (D-0303), `DayCycle`, `OrderBook`, `Inventory`, el galpón (D-0620), el
  vehículo inicial y los spawns de jugadores.
- **Registro:** se suma a `NetworkManager.LEVEL_SCENES` (sin eso el cliente no la carga).
- **Arranque:** `--autostart-company [--slot=<n>]` (no `--autostart --mode=company`: decisión `docs/decisiones/2026-10-04-flag-modo-empresa.md`).
- **Menú:** el botón "Empresa" arriba de "Partida rápida", según la decisión 1 de
  `2026-10-04-expansion-decisiones-delegadas.md`.
**Test** `test_company_world_boot`: con `--autostart-company` la escena carga, `CompanyState.is_active()` es
verdadero, hay `DayCycle` en `OPENING` y no hay `ERROR` en el log (Logger que cuenta errores, como N-917).
**Hecho cuando:** el test pasa y Entrega/Endless arrancan igual que antes.

### D-0215 · Señales de negocio en `EventBus` — A · Opus 5.5 · medium · Aviso: sí (`event_bus.gd`) · F0
**[x] Hecho (2026-10-12, PR pendiente)** — 11 señales al final de `event_bus.gd` (sin relay: cada peer las emite al aplicar); `CompanyState` ya emite `money_changed` y `gate_opened`; las demás las conecta la tarea de su emisor; `test_event_bus_company`.
**Depende de:** D-0201
**Qué:** agregar al final de `event_bus.gd` (sin reordenar las 58 actuales):
- `company_day_started`, `company_day_closing`, `company_day_summary`;
- `order_added`, `order_packed`, `order_delivered`;
- `supply_arrived`, `box_sealed`;
- `gate_opened(gate_id)`, `milestone_reached(id)`;
- `money_changed(amount, reason)`.
Cada una con su comentario `##` de quién la emite.
**Test:** ampliar el test que hoy verifica las señales de `EventBus` (o crear `test_event_bus_company`)
para que todas existan con su firma.
**Hecho cuando:** el test pasa y el aviso está.

### D-0216 · Registros leídos de `data/` — A · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-19, PR pendiente)** — `CompanyCatalog` (`scripts/core/company/catalog.gd`): lee las seis carpetas de `data/` (y raíces extra) por id, resuelve `.remap`, junta ids repetidos o faltantes en `errors`; `company_root.load_zones()` lo usa; `test_company_catalog`.
**Depende de:** D-0204, D-0205, D-0207
**Qué:** `scripts/core/company/catalog.gd` (`RefCounted` estático o hijo de `CompanyState`). Lee
`data/products/`, `data/zones/`, `data/vehicles/`, `data/gates/`, `data/suppliers/` y `data/boxes/` con
`DirAccess` y los deja por id. Nada de listas a mano.
**Ojo export:** en el `.pck` los `.tres` pueden venir como `.tres.remap`; resolver como hace el resto del
proyecto.
**Test** `test_company_catalog`: un `.tres` de producto agregado en el test (en `user://`, cargado por la
ruta alternativa del catálogo) aparece sin tocar código; los ids repetidos dan error claro.
**Hecho cuando:** el test pasa.

### D-0217 · Cajas como datos — A · Opus 5.5 · low · Aviso: no · F0
**[x] Hecho (2026-10-21, PR pendiente)** — `BoxDefinition` (`scripts/gameplay/business/box_definition.gd`: `id`, `cells`, `cost`, `model`, `volume()`, `size_m()`), `data/boxes/S|M|L|XL.tres` con los números de `CompanyTuning.BOX_CELLS`/`BOX_COST` y `sm_cargo_box_cube.glb`, y `CompanyCatalog.box()`/`boxes()` (de menor a mayor); `test_company_catalog`. Los usuarios de `BOX_CELLS` siguen igual.
**Depende de:** D-0216
**Qué:** `scripts/gameplay/business/box_definition.gd` (`id`, `cells: Vector3i`, `cost`, `model`). Cuatro
`.tres` en `data/boxes/` (S, M, L, XL con los números de supuestos). `model` usa
`assets/models/cargo/sm_cargo_box_cube.glb` escalado hasta que existan las de D-1806.
**Test:** en `test_company_catalog`, las 4 cajas cargan y crecen de tamaño en orden.
**Hecho cuando:** el test pasa.

### D-0218 · Proveedores como datos — A · Opus 5.5 · low · Aviso: no · F0
**[x] Hecho (2026-10-21, PR pendiente)** — `SupplierDefinition` (`scripts/gameplay/business/supplier_definition.gd`: `id`, `products`, `price_factor`, `arrival_min`, `wait_minutes`, `truck_scene`, `sells()`, `unit_price()`), `data/suppliers/distribuidora_central.tres` (10 productos, 08:30, 180 min, factor 1,0, camión `null` hasta D-0601) y `CompanyCatalog.supplier()`; `test_company_catalog`.
**Depende de:** D-0216
**Qué:** `scripts/gameplay/business/supplier_definition.gd` (`id`, `products: Array[StringName]`,
`price_factor`, `arrival_min`, `wait_minutes`, `truck_scene`). Un `.tres` para F1: `distribuidora_central`,
que vende los 10 productos, llega a las 08:30 y espera 180 min.
**Test:** en `test_company_catalog`, carga y sus productos existen.
**Hecho cuando:** el test pasa.

### D-0219 · Reloj del juego desde el host — A · Opus 5.5 · high · Aviso: sí (`network_manager.gd` si hace falta un RPC) · F0
**[x] Hecho (2026-10-12, PR pendiente)** — `modules/day_clock/` (`DayClock`, ancla y `minute_at`) + adaptador `game_clock.gd` (`GameClock`): evento `clock_anchor` de `CompanyNet` solo al cambiar la marcha, ancla en el snapshot (parte `clock`), `PROTOCOL_VERSION` 31; `test_game_clock` con dos peers ENet. Falta cablearlo al mundo (D-0203/D-0214).
**Depende de:** D-0202
**Qué:** `scripts/core/company/game_clock.gd`. Lógica en `modules/day_clock/` (D-0223): sin nombres del
juego, con adaptador.
- **El host** avanza `clock_minutes` con `company_tuning.SECONDS_PER_GAME_HOUR = 90` y, solo cuando cambia
  la marcha (apertura, pausa, reanudación, cierre que espera a la salida), manda un **ancla**
  `clock_anchor` `{minute, speed, paused}` (cada peer toma su propio tick al recibirlo, menos medio RTT) como evento de `CompanyNet` (D-2003).
- **Los clientes** calculan la hora local desde el ancla; no hay envío periódico ni interpolación.
  Decisión de D-2001 ([red-autoridad.md](../diseno/red-autoridad.md) §2,
  `docs/decisiones/2026-10-04-reloj-por-ancla.md`); antes decía "cada 2 s, `unreliable_ordered`".
- **Pausa:** el reloj se para con la pausa del host (si existe en modo coop) y con el galpón congelado (S4).
**Test** `test_game_clock`: dos peers ENet locales (forzar ENet, lección de módulos) ven la misma hora
±1 min después de 60 s simulados, y la pausa los frena a los dos.
**Hecho cuando:** el test pasa y `auditor-red` lo revisó.

### D-0220 · Carpetas y módulos — A · Opus 5.5 · medium · Aviso: sí (`docs/arquitectura.md`, `.claude/hooks/lib.sh`) · F0
**[x] Hecho (2026-10-12, PR pendiente)** — `README.md` en las carpetas que faltaban; tabla "Qué va a `modules/`" en `docs/arquitectura.md` §10.4; las carpetas de la expansión son de Nacho en `file_domain` y en `colaboracion-equipo.md` (cierra D-0144); `tools/test-file-domain.sh` en CI.
**Depende de:** D-0201
**Qué:** crear las carpetas con un `README.md` de 3 líneas cada una:
- `scripts/core/company/`, `scripts/gameplay/business/`, `scripts/gameplay/districts/`,
  `scripts/gameplay/fleet/`;
- `data/products/`, `zones/`, `vehicles/`, `boxes/`, `suppliers/` y `gates/`;
- `scenes/company/`.
Además: decidir y escribir qué va a `modules/` (`day_clock`, `world_cells`, `inventory`, `order_queue`,
`build_grid`) y sumar las carpetas nuevas a `file_domain` de `.claude/hooks/lib.sh` como dominio de Nacho
(D-0144).
**Hecho cuando:** las carpetas existen, `python tools/check_modules.py` pasa y `file_domain` clasifica un
archivo de cada carpeta como Nacho.

### D-0232 · Tick de negocio a 4 Hz — B · Opus 5.5 · medium · Aviso: sí (`modules/`, `docs/modulos.md`) · F0 (Ampliación)
**[x] Hecho (2026-10-21, PR #578)** — módulo `modules/fixed_tick/` (`FixedTick`) + adaptador `scripts/core/company/business_tick.gd` (`BusinessTick`, solo en el host); `DayCycle.poll` es su primer paso y el `_process` propio del ciclo queda apagado en el mundo Empresa.
**Depende de:** D-0203, D-0214
**Qué:** las reglas del host que solo necesitan mirar el mundo unas veces por segundo (fases del día,
y después pedidos, proveedor, empleados, máquinas) corren en un tick fijo, aparte de la física y del
frame dibujado.
- **Módulo `fixed_tick`** (`FixedTick`, puro, sin nodos): pasos con nombre que corren en el orden en que
  se agregaron; `advance(delta)` acumula y corre un tick por período entero; tras un tirón corre a lo
  sumo `max_catch_up` (4) ticks y tira el resto (`dropped_ticks`); un paso cuyo objeto se liberó se cae;
  `last_run_usec` mide lo que costó el último tick, para el perfilador.
- **Adaptador `BusinessTick`** (nodo, hijo de `CompanyRoot`, solo en el host): ritmo
  `CompanyTuning.BUSINESS_TICK_HZ = 4.0`, sin recuperación (`max_catch_up` 1): sus pasos miran el mundo,
  no integran tiempo, y el `DayCycle` no debe cruzar dos fases en un frame. Los pasos son reglas del host que publican por `CompanyNet`;
  un cliente cambia solo por los eventos del host.
- `DayCycle` conserva su `_process` (cada `POLL_SECONDS` = 0,25 s) para cuando nadie lo maneja (tests,
  sin mundo); `CompanyRoot` lo apaga en todos los peers y en el host lo suma como paso `day_cycle`.
**Test** `modules/fixed_tick/tests/test_fixed_tick.gd`: a 4 Hz, 10 s a 60, 144 y 20 fps corren 40 ticks
(±1); orden de los pasos, nombres repetidos y Callables inválidos rechazados, paso de objeto liberado
descartado; un frame de 3 s corre el tope y descarta el resto; deltas negativos, NaN e infinitos no corren
nada; 10 000 frames cuestan menos de 100 µs por frame en promedio. `test_company_world_boot`: el host
tiene `BusinessTick` con el paso `day_cycle` y el `_process` del `DayCycle` apagado.
**Hecho cuando:** los dos tests pasan y `check_modules` / `portability-check` están verdes.

### D-0235 · Varias empresas guardadas (slots) — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-21, PR pendiente)** — `CompanySave.list_slots` (nombre, día, plata, fecha, última jugada primero, sin mover archivos), `delete` (con `.bak`/`.tmp`/`.bad`) y `new_slot_id`; `test_company_slots`. La lista en el menú queda para la UI.
**Depende de:** D-0206
**Qué:** en `scripts/core/company/company_save.gd` (`CompanySave`), solo datos; la pantalla que los muestra
es de la UI del menú (Jugar → Empresa) y no entra acá.
- `list_slots(dir)`: una entrada por slot de `user://saves/company/` con `slot`, `name` (el `company_name`,
  o el slot si está vacío), `day`, `money`, `saved_at`, `interrupted` y `version`, del último jugado al
  primero. Lee sin mover archivos: cuenta un slot que solo tiene `.bak` (escritura cortada) y deja afuera
  `.tmp`, `.bad` y JSON que no son saves. Un save de un build más nuevo aparece con su `version` para que la
  UI lo muestre deshabilitado.
- `delete(slot, dir)`: borra el `.json` del slot y sus `.bak`, `.tmp` y `.bad`.
- `new_slot_id(dir)`: `company` si está libre, si no `company_2`, `company_3`…
**Test** `test_company_slots`: crea 3 slots con nombre, día y plata distintos, los lista en orden de
`saved_at`, borra uno (con su `.bak`) y después los otros; `.bak` solo cuenta, `.tmp`/`.bad`/no-save no;
`new_slot_id` y carpeta inexistente.
**Hecho cuando:** el test pasa.

### D-0236 · Guardado automático al cerrar el día y al salir — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-21, PR pendiente)** — `CompanyRoot.save_closed_day()`: el host guarda el slot en cuanto se aplica el SUMMARY, como la apertura del día siguiente (día + 1 a las 08:00, sin `interrupted`, stock con las manos en el piso); al salir durante el resumen guarda eso mismo en vez del día interrumpido; a mitad de día sigue el guardado interrumpido de D-2005; `test_company_autosave`.
**Depende de:** D-0203, D-0206, D-2005
**Qué:** en `scripts/gameplay/company_root.gd`, solo el host (también solo):
- al aplicarse el `day_phase` SUMMARY (`CompanyNet.event_applied`), guardar el slot como **la apertura del
  día siguiente**: una copia de la empresa con `day + 1` y `clock_minutes = DAY_START_MIN`, sin
  `interrupted`; la empresa en juego conserva su día hasta `next_day()`. Cargarlo abre ese día, igual que
  `next_day()`;
- al cerrarse el mundo (`_exit_tree`, también al cerrar el juego) durante el SUMMARY, ese mismo guardado; en
  cualquier otra fase, el día interrumpido de D-2005.
**Test** `test_company_autosave`: un día completo (OPENING → SUMMARY) guarda el día 2 desde la apertura con
la plata y el stock; matar el proceso a mitad del día 2 (sin el guardado de `_exit_tree`) y cargar da el
último cierre; salir en el resumen no lo pisa con el día 1 interrumpido; salir a mitad de día sigue guardando
interrumpido.
**Hecho cuando:** el test pasa.

### D-0238 · Flags de desarrollo del modo Empresa — B · Opus 5.5 · low · Aviso: no · F0 (Ampliación)
**[x] Hecho (2026-10-22, PR #594)** — `CompanyDevFlags` (`scripts/core/company/company_dev_flags.gd`): `--company-day=N`, `--district=<zona>` y `--money=N`, aplicados por el host de `CompanyRoot` al levantar el mundo; README y `render_company_shed.gd`; `test_company_dev_flags`.
**Depende de:** D-0202, D-0205, D-0214
**Qué:** en `scripts/core/company/company_dev_flags.gd` (puro, sin autoloads) y un llamado en
`CompanyRoot._add_net()` (solo el host, también solo), después de cargar el slot o arrancar una empresa nueva
y antes de que `CompanyNet` copie el stock (así el snapshot de los clientes los lleva):
- `--company-day=N` (N ≥ 1): la empresa juega el día N desde su apertura (`DAY_START_MIN`);
- `--district=<id>`: abre todas las compuertas de la zona `data/zones/<id>.tres` (una zona abierta no abre
  nada; una que no existe se avisa y se ignora). No mueve al jugador: las capturas ponen su cámara;
- `--money=N` (cualquier entero, deuda incluida): la plata de la empresa, sin asiento en el libro.
Un valor que no se lee se avisa (`push_warning`) y se ignora. Lo que cambian queda en la empresa y se guarda
con ella, como cualquier cambio. `CompanyRoot.dev_args` (por defecto `OS.get_cmdline_user_args()`) deja que
un test pase los suyos.
**Test** `test_company_dev_flags`: `parse()` con flags repetidos y valores malos; `apply()` sobre una empresa
(día y reloj, plata negativa, `suburbio` abre `gate_suburbio`, `centro` no abre nada, zona desconocida
afuera, sin flags no cambia nada); un `CompanyRoot` host con `dev_args` abre el día 4 con 12345 y las
compuertas de `campo`, y sin flags arranca en el día 1 con `STARTING_MONEY`.
**Hecho cuando:** el test pasa; documentados en el README; `render_company_shed.gd` los toma de su línea de comandos.

### D-0239 · Registro local del día de la empresa — B · Opus 5.5 · medium · Aviso: no · F0 (Ampliación)
**[x] Hecho (2026-10-22, PR #598)** — `RunTelemetry` guarda un JSON por día (`<fecha_hora>_day<N>.json`, `"kind": "company_day"`) con los eventos de negocio; `run_telemetry_format.describe_day()` lo lee; `tools/telemetry-summary.py` suma una tabla "Dias de empresa"; `test_company_day_telemetry`.
**Depende de:** D-0203, D-0215
**Qué:** en `scripts/core/run_telemetry.gd` (el autoload del registro de partidas, S-805), con la misma opción
"Guardar registro de partidas" y la misma carpeta `user://telemetry/`, solo escuchando `EventBus` (sin RPC ni
estado):
- `company_day_started` abre el día y vacía el buffer; desde ahí anota `order_added`, `order_packed`,
  `order_delivered`, `supply_arrived`, `box_sealed`, `gate_opened`, `milestone_reached`, `money_changed` y
  `company_day_closing` como `{"t": segundos desde la apertura, "event": <señal>, ...}`; la lista corta en
  `MAX_DAY_EVENTS` (2000) pero los conteos siguen (`events_dropped`);
- `company_day_summary` escribe el archivo: día, rol, tripulación, duración, el resumen del día (valores
  planos), los eventos y los conteos por tipo. Un día abandonado antes del resumen no escribe nada;
- los registros de entrega llevan `"kind": "run"` (un archivo sin `kind` es una entrega; `FORMAT_VERSION`
  sigue en 1 porque el campo es aditivo).
En `run_telemetry_format.gd`: `record_kind`, `day_event_counts`, `day_file_stem`, `plain` y
`describe_day(record)`, que da líneas legibles (día, ingresos/costos/ganancia, billetera, pedidos,
proveedores y cajas, plata por motivo).
**Test** `test_company_day_telemetry`: opción apagada no escribe; prendida, un día simulado deja un solo
`*_day2.json` con los eventos en orden y los conteos; `describe_day` sobre el archivo leído da las líneas
esperadas; un día abandonado no escribe ni contamina el siguiente; el tope de eventos se respeta; una
entrega sigue escribiendo, con `kind: "run"`.
**Hecho cuando:** el test pasa y el log del día se lee con `run_telemetry_format`.
