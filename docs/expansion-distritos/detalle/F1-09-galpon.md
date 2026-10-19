# F1 · Grupo 09 — Galpón construible (detalle)

> Carril 2 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [09-galpon-construible.md](../09-galpon-construible.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0901 · Modo construcción: activar, cámara elevada, grilla visible — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-05, PR pendiente)** — `BuildMode` (`scripts/gameplay/business/build_mode.gd`): estado, cámara elevada y líneas de grilla como datos; `test_build_mode`. El adaptador con nodos (dibujar la grilla, mover la cámara, tecla) queda para D-0917/D-0943.
**Depende de:** D-0904 (la celda `WAREHOUSE_GRID_M`); la validación de choque llega con D-0225/D-0902
**Qué:** `class_name BuildMode` (`RefCounted`, sin nodos ni autoloads):
- `enter(size, can_build)`: refusa con `last_refusal` (`already_active`, `empty_floor`, `busy`); si entra, grilla visible, zoom 1, foco al centro, señal `entered`.
- `exit()`, `pan(delta)` (el foco no sale del piso), `zoom_by(amount)` (entre `BUILD_ZOOM_MIN` y `BUILD_ZOOM_MAX`), `set_grid_visible()`.
- `camera_pose()`: posición elevada (`BUILD_CAMERA_HEIGHT_M × zoom`) e inclinación `BUILD_CAMERA_PITCH_DEG`.
- `grid_lines()`: pares de puntos (metros) de cada línea de la grilla, borde incluido.
**Test** `test_build_mode`: entrar/salir con señales, las tres negativas, líneas de grilla (13+9 en 12×8), pan y zoom acotados, cámara más alta al alejar.
**Hecho cuando:** el test pasa.

### D-0902 · Colocar un objeto comprado con previsualización verde/roja — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `BuildPlacement` (`scripts/gameplay/business/build_placement.gd`): previsualización verde/roja y colocación que compra solo si es verde; `test_build_placement`. El adaptador con nodos (dibujar la huella con `preview_color()`, el cursor) queda para D-0917/D-0943.
**Depende de:** D-0901 (grilla), D-0904 (definiciones) y D-0920 (`PlaceableShop`); la grilla portable D-0225 todavía no existe: la lógica de choque vive acá y se mueve cuando exista.
**Qué:** `class_name BuildPlacement` (`RefCounted`, sin nodos ni autoloads):
- `preview(layout, def, x, z, turns, money)` → `{ok, reason, rect}`; motivos `out_of_bounds`, `fixed_area` (rectángulos `fixed_blocked`, para dársena y salida de D-0906), `overlap`, `no_definition`, `no_money`.
- `place(state, def, x, z, turns, free)`: valida con `preview` y recién ahí llama a `PlaceableShop.buy`; si es rojo no cambia nada.
- `preview_color(result)`: verde o rojo translúcido.
**Test** `test_build_placement`: libre, fuera del piso, área fija, choque, bordes que se tocan, giro, sin plata, `free`.
**Hecho cuando:** el test de choque pasa.

### D-0903 · Rotar, mover y vender objetos colocados — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `BuildPlacement.rotate_piece/move_piece/sell_piece` (`build_placement.gd`): las mismas comprobaciones que al colocar, ignorando la pieza misma; `test_build_edit`. El adaptador con nodos (elegir la pieza con el cursor, teclas) queda para D-0917/D-0943.
**Depende de:** D-0902 (`BuildPlacement`) y D-0920 (`PlaceableShop.sell`)
**Qué:** sobre una pieza ya en `layout` (por índice):
- `preview(..., ignore_index)`: el choque no cuenta las celdas de la propia pieza.
- `rotate_piece(state, index, quarter_turns = 1)` y `move_piece(state, index, x, z)`: devuelven el resultado de `preview`; la pieza solo cambia si es verde. No cuestan plata.
- `sell_piece(state, index)`: `PlaceableShop.sell` (devolución parcial); `-1` con índice inválido.
**Decisión:** rotar y mover son gratis (el costo de reubicar es el tiempo del jugador); gira alrededor de la celda esquina, igual que `footprint_rect`.
**Test** `test_build_edit`: giro libre y con vuelta a 0, giro fuera del piso o sobre otra pieza rechazado sin cambios, mover a celda libre (incluidas las propias), mover fuera / sobre área fija / sobre otra pieza rechazado, gratis, vender paga la devolución, índices inválidos.
**Hecho cuando:** el test de las 3 acciones pasa.

### D-0904 · Objetos colocables iniciales — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `PlaceableDefinition` (`scripts/gameplay/business/placeable_definition.gd`) + 4 `.tres` en `data/placeables/` (mesa de armado, estante, heladera, zona de despacho); `test_placeable_definitions`.
**Depende de:** nada que falte (solo datos; la grilla de colocación D-0225 y el layout D-0620 los usan, no al revés)
**Qué:** `class_name PlaceableDefinition`, `Resource` solo de datos como `ProductDefinition`:
`id`, `display_key` (`WORLD_PLACEABLE_<ID>`), `footprint` (celdas X×Z), `height_m`, `price`, `role`
(`assembly` / `storage` / `dispatch`), `slots`, `cold`, `blocks_walking`, `owned_at_start`.
- `footprint_for(quarter_turns)`: huella girada (cuartos de vuelta impares cambian X por Z).
- `refund()`: `floor(price × CompanyTuning.PLACEABLE_REFUND_RATIO)` (base de D-0920).
- Celda del galpón: `CompanyTuning.WAREHOUSE_GRID_M = 1.0` (no es la celda de 0,2 m del armado).

| Objeto | Huella | Alto | Precio | Rol | Huecos | Propio al inicio |
|---|---|---|---|---|---|---|
| `assembly_table` | 2×1 | 0,9 m | 120 | armado | 0 | sí |
| `shelf` | 2×1 | 2,0 m | 80 | estante | 8 | sí |
| `fridge` | 1×1 | 1,9 m | 200 | estante frío | 4 | no (D-0616/D-0617) |
| `dispatch_zone` | 3×2 | 0,05 m | 60 | despacho | 0 | sí, y no bloquea el paso |

**Test** `test_placeable_definitions`: los 4 archivos cargan con id y clave correctos, huella/alto/precio
positivos, rol conocido, solo los estantes tienen huecos, solo la heladera es fría, solo el despacho se
puede pisar, la rotación y el reembolso.
**Hecho cuando:** 4 objetos `.tres` y el test pasa.

### D-0912 · Electricidad como restricción de máquinas — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — decidido **no**: sin enchufes ni tablero; `docs/decisiones/2026-10-04-sin-electricidad-en-galpon.md`.
**Depende de:** nada
**Qué:** decidir si las máquinas necesitan enchufe. Decisión: no, coherente con D-0505 (sin energía).
**Test:** ninguno (decisión). **Hecho cuando:** decisión escrita y el detalle de D-0904 y D-0922 coherente.

### D-0920 · Precio y venta con devolución parcial — B · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `PlaceableShop` (`scripts/gameplay/business/placeable_shop.gd`): `buy` cobra el precio y suma la pieza al `layout`, `sell` la saca y paga `PlaceableDefinition.refund()` (50 %); `test_placeable_shop`.
**Depende de:** D-0904 (`PlaceableDefinition`), D-0501 (billetera)
**Qué:** helpers estáticos sobre el `CompanyState` que recibe el llamador (sin nombrar autoloads). Una pieza
colocada es una entrada de `layout`: `{id, x, z, turns}`. Si la celda está libre lo decide la grilla
(D-0225 / D-0902); acá solo se mueve plata y entradas. Movimientos en el libro: `placeable_buy`,
`placeable_sell`. Las piezas `owned_at_start` se agregan con `free = true` (D-0911).
**Test** `test_placeable_shop`: comprar cobra y registra; sin plata no cambia nada; `free` no cobra; vender
devuelve `floor(precio × ratio)` y quita la pieza; índice o id inválido devuelve -1 sin cambios.
**Hecho cuando:** el test pasa.

### D-0905 · Etapas del galpón que amplían la grilla — A · Sonnet 5.5 · xhigh · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `WarehouseStages` (`scripts/gameplay/business/warehouse_stages.gd`) + `CompanyState.warehouse_stage` (en el save) + constantes en `CompanyTuning`; `test_warehouse_stages`. El adaptador con nodos (rehacer paredes y piso desde `wall_rects()` sin recargar el nivel) queda para D-0917/D-0943.
**Depende de:** D-0901 (`BuildMode.grid_size`), D-0902 (`BuildPlacement.grid_size`), D-0920 (billetera). El tope por progresión es D-0436 (llega como `unlocked_stage`).
**Qué:** cuatro etapas, grilla en celdas y precio de la mejora **hacia** esa etapa (`CompanyTuning.WAREHOUSE_STAGE_*`):

| Etapa | Id | Grilla | Precio |
|---|---|---|---|
| 0 | `small` | 12×8 | 0 (inicial) |
| 1 | `medium` | 18×12 | 1500 |
| 2 | `large` | 24×16 | 6000 |
| 3 | `logistics_center` | 32×20 | 20000 |

- `expand(state, unlocked_stage = -1)`: cobra (`warehouse_expand` en el libro) y sube `state.warehouse_stage`; rechaza con `no_money`, `max_stage` o `locked` sin tocar nada.
- Todas las etapas crecen desde la esquina (0, 0): las piezas ya colocadas no se mueven ni se pierden.
- `wall_rects(stage)`: 4 segmentos de pared pegados por fuera del piso. `apply_to(stage, placement, mode)`: cambia `grid_size` de `BuildPlacement` y `BuildMode`.
**Decisión:** crece desde la esquina y no desde el centro para no migrar el layout guardado; precios ×4 por etapa como supuesto de balance (se ajustan solo en `CompanyTuning`, junto con D-0117).
**Test** `test_warehouse_stages`: etapas crecientes y con precio creciente, cobro y libro, layout intacto, grilla nueva acepta un lugar antes fuera del piso, tres rechazos, paredes fuera del piso, ida y vuelta por JSON y tope del valor guardado.
**Hecho cuando:** ampliar cambia grilla y paredes sin recargar el nivel (la parte de datos pasa el test; el adaptador de nodos va con D-0917).

### D-0906 · Paredes y portones fijos que no se pueden tapar (dársena, salida) — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `WarehouseStages.dock_rect/exit_rect/fixed_rects/gate_rects` (`warehouse_stages.gd`) + `CompanyTuning.WAREHOUSE_DOCK_CELLS/EXIT_CELLS`; `apply_to` deja las zonas en `BuildPlacement.fixed_blocked`; test ampliado en `test_warehouse_stages`. El adaptador con nodos (abrir el hueco de los portones en las paredes con `gate_rects()`) queda para D-0917/D-0943.
**Depende de:** D-0902 (`fixed_blocked`), D-0905 (etapas)
**Qué:**
- La dársena (portón de carga) es el centro del muro sur y la salida de clientes el centro del muro norte, en todas las etapas. Delante de cada una queda un rectángulo de piso libre: 4×2 celdas la dársena y 2×2 la salida (`CompanyTuning`).
- `fixed_rects(stage)` los devuelve; `apply_to` los pasa a `BuildPlacement.fixed_blocked`, así colocar, mover o girar encima da `fixed_area` (rojo). Las paredes no se tapan por construcción: están fuera del piso (`out_of_bounds`).
- `gate_rects(stage)`: las celdas del muro que quedan abiertas (mismo ancho que cada zona), para que el adaptador no ponga pared ahí.
**Decisión:** dársena al sur y salida al norte, centradas, para que el recorrido camión → estantes → mesas → salida cruce el galpón a lo largo y no dependa de la etapa; los tamaños salen de lo que pasa un autoelevador (4 m) y una persona con carro (2 m).
**Test** `test_warehouse_stages`: en las cuatro etapas las zonas están dentro del piso, no se pisan entre sí, tocan su muro, los huecos alinean con ellas; colocar encima es rojo con `fixed_area`; al lado es verde.
**Hecho cuando:** el test pasa.

### D-0907 · Caminos libres: validación de que se puede llegar a cada estación — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `WalkReachability` (`scripts/gameplay/business/walk_reachability.gd`) + `BuildPlacement.entry_areas` y razón `blocks_path`; `apply_to` deja la dársena y la salida como entradas; `test_walk_reachability`. El adaptador con nodos (mostrar el motivo en rojo) queda para D-0917/D-0943.
**Depende de:** D-0902 (`BuildPlacement`), D-0906 (dársena y salida)
**Qué:**
- Inundación 4-vecinos sobre la grilla desde las celdas de la dársena y la salida. Las celdas cubiertas por piezas con `blocks_walking` no se pisan; la zona de despacho (no bloquea) sí.
- Una pieza que bloquea se alcanza desde una celda libre alcanzada que toque uno de sus lados; una que no bloquea, desde una de sus celdas.
- `BuildPlacement.preview` (y con él colocar, mover y girar) da `blocks_path` en rojo si, con la pieza puesta, alguna pieza queda sin camino o la dársena queda cortada de la salida. Sin `entry_areas` no se comprueba nada.
**Decisión:** el chequeo es sobre la grilla y no sobre el navmesh: es determinista, corre en headless y en red da lo mismo en todos los clientes; D-0908 rehornea el navmesh con la misma grilla. Si el layout ya estaba roto, cualquier colocación da rojo hasta arreglarlo moviendo la pieza (mover ignora la pieza misma).
**Test** `test_walk_reachability`: una fila de mesas de lado a lado cierra el paso y la última es roja; con un hueco es verde; cuatro heladeras encierran la del medio; la zona de despacho no estorba; `place()` rojo no cobra.
**Hecho cuando:** el test pasa.

### D-0908 · Navmesh que se rehornea al colocar objetos (para empleados) — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `WalkNavigation` (`scripts/gameplay/business/walk_navigation.gd`) + `BuildPlacement.navigation` y `rebake_navigation()`; `test_walk_navigation`. El adaptador que lo cree y se lo dé a `BuildPlacement` queda para D-0917; quien lo consume son los empleados (D-1011).
**Depende de:** D-0907 (misma grilla de 4 vecinos)
**Qué:**
- `WalkNavigation.rebake(size, layout)` arma un `AStarGrid2D` sin diagonales con las celdas de `WalkReachability.blocked_cells` como sólidas y sube `version` (quien guardó un camino compara la versión para saber que quedó viejo).
- `find_path(from, to)` devuelve las celdas del camino (vacío si no hay) y `find_path_to_rect(from, rect)` el más corto hasta una celda que toque un lado de una estación.
- `BuildPlacement` rehornea después de colocar, mover, girar y vender (solo si el cambio se aplicó); `rebake_navigation(state)` sirve también tras cargar un guardado.
**Decisión:** grilla A* en vez de `NavigationMesh` del motor: es determinista, corre en headless y da el mismo camino en todos los peers; coincide con D-0907 (si hay camino, es alcanzable). Si F2 necesita evitación entre empleados (D-1011), se apoya en esto y no en el navmesh del motor.
**Test** `test_walk_navigation`: una mesa sobre la línea recta alarga el camino y no lo cruza; girar, mover y vender rehornean (y vender devuelve el camino corto); una colocación rechazada no rehornea; la zona de despacho no cambia nada; el camino a una estación termina a su lado.
**Hecho cuando:** el test pasa.

### D-0911 · Layout por defecto que ya funciona sin tocar nada — A · Opus 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `DefaultShed` (`scripts/gameplay/business/default_shed.gd`) + `data/shed/default_shed.tres` + `CompanyShed` (`scripts/gameplay/company_shed.gd`, el galpón con nodos); `test_company_default_layout`. Gris: lo dibuja con cajas y los GLB del depósito actual; los modelos finales son la subtarea de arte `arte-pendiente/D-0911.md`.
**Depende de:** D-0904 (objetos), D-0902 (`BuildPlacement`), D-0906 (dársena y salida), D-0907 (alcanzable), D-0214 (escena)
**Qué:** el galpón de una empresa nueva sale armado, sin construir nada, y es el mismo en todos los peers:
- El layout es **dato**: un `DefaultShed` (`Resource`) con las piezas (id de `data/placeables/`, celda, giros y `uid`), los huecos de estante con su stock inicial, el primer pedido al proveedor y las zonas pintadas. Entra por `BuildPlacement.place(free)`: las mismas comprobaciones del modo construcción (dentro del piso, fuera de dársena y salida, sin choque, todo alcanzable), así después se mueve, gira o vende igual. `problems()` dice qué está mal en el dato.
- Plano de la etapa chica (12×8 celdas de 1 m; +Z es el sur, donde está la dársena): dársena (4,6) 4×2 y salida (5,0) 2×2 (las fijas de D-0906); **recepción** (2..3, 5..7) con los palets de arranque; **estantes** `shelf_1..3` pegados al muro oeste (giro 1, miran al este); **armado** `table_1/2` pegadas al muro este (giro 3, miran al oeste), con dispensador de cajas; **despacho** (7,0) 3×2 pegado a la salida.
- Stock inicial: 6 unidades de cada uno de los 8 productos de ambiente en los huecos 0..3 de `shelf_1` y `shelf_2`; el primer pedido (`SupplierSchedule.place(0, …)`, llega el día 1 = `STARTING_DAY`) trae 12 bidones de leche y 6 tortas de boda en dos palets (`pallet:d1_<producto>_1`), y los huecos 0 y 1 de `shelf_3` están etiquetados para ellos y vacíos. Sin plata: `free`, el libro queda vacío.
- Lo arma el **host**: `CompanyRoot._add_net` lo vuelca en `CompanyState` (layout + stock) antes de que `CompanyNet` copie el stock, cuando `DefaultShed.needs_default()` (layout vacío, libro vacío, sin unidades, etapa 0: una empresa nueva o un guardado anterior al layout). Los clientes no corren nada: dibujan lo que trae el snapshot (D-2004; `company_state_restored` redibuja). Sin RPC nuevo ni cambio de protocolo.
- `CompanyShed` solo **dibuja**: piso y paredes de la etapa (hueco en la pared sur para la dársena y en la norte para la salida, desde `WarehouseStages.gate_rects`), zonas pintadas con su nombre en el piso (`WORLD_SHED_ZONE_*`), estantes con un cajón y una etiqueta con la cantidad por hueco etiquetado (se reescribe con cada `units_moved`), mesas con su `PackingStation`, y un nodo por palet `pallet:<id>` del `Inventory`. La geometría estática va por `DepotKit` (una malla por material).
- El `uid` de cada pieza (`shelf_1`, `table_2`) es una clave extra del dict del layout (`{id, x, z, turns, uid}`): las unidades del estante están en `shelf:<uid>_<hueco>` y la mesa guarda su estado por `uid`, así mover la pieza no pierde nada; las piezas sin `uid` se llaman `<id>_<n>` en orden de layout.
- El mundo cambia de tamaño: el galpón de 48×32 m de D-0214 (relleno de prueba) pasa a ser el piso de la etapa (12×8 m), y el jugador aparece en la dársena mirando al norte; `bench_company` recorre ahora el pasillo del medio.
- Arreglos vistos en la primera captura del modo Empresa: la tarjeta de práctica de Entrega ("Cómo cuidar la carga… subite a manejar") ya no sale (los jugadores de `CompanyRoot` están en el grupo `company_crew`, que `player_cargo_care.gd` mira), y la franja negra borrosa en diagonal era el nombre de la zona del parque industrial (`Label3D` de 128 m de alto, a 40 m sobre el galpón): ahora 15 m de alto a 30 m.
**Test** `test_company_default_layout`: el dato es sano y se aplica dos veces igual; empresa nueva = mesa de armado, estantes con stock de los 8 productos, palets de recepción y despacho, sin plata movida; dentro del piso, fuera de dársena y salida, sin choque, todo alcanzable y dársena conectada con la salida; el jugador aparece en la dársena y libre; etiquetas siguen al stock; un par con solo el snapshot dibuja lo mismo; el modo construcción mueve una mesa (conserva `uid` y estación) y la salida la rechaza; no sale la tarjeta de práctica de Entrega; una empresa con layout, libro o etapa distinta no se toca. `test_company_root` ampliado (paredes con hueco, nombres de zona chicos).
**Hecho cuando:** el test pasa y el corte vertical arranca con este galpón.

### D-0909 · Guardar el layout en el save de empresa — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `BuildLayoutSave.sanitize` (`scripts/gameplay/business/build_layout_save.gd`) y `CompanyState.from_dict` lo usa para el `layout`; `test_build_layout_save`. El layout ya viajaba en el save (`CompanyState.layout`, D-0205/D-0206); faltaba que al cargar fuera siempre uno que el modo construcción pudo armar.
**Depende de:** D-0905 (la etapa define la grilla), D-0902 (`BuildPlacement.preview`)
**Qué:**
- `sanitize(raw, stage)` rearma la lista como `{id: String, x: int, z: int, turns: 0-3}` (JSON devuelve floats) y conserva solo las piezas que `BuildPlacement.preview` aceptaría una tras otra en la grilla de esa etapa: definición conocida, dentro del piso, fuera de dársena y salida, sin superponerse y sin cortar los caminos.
- `from_dict` lee primero `warehouse_stage` y después el layout; lo inválido se descarta, no se "arregla" (no se inventan posiciones).
**Decisión:** descartar en vez de reubicar: reubicar puede tapar un camino y ocultar un guardado roto; y las piezas descartadas no se reembolsan (un guardado válido nunca las tiene). Las piezas con `turns` ausente valen 0.
**Test** `test_build_layout_save`: ida y vuelta por JSON idéntica y con enteros, descarte de cada tipo de pieza inválida, giros plegados a 0-3, la etapa guardada decide la grilla, layout que no es lista.
**Hecho cuando:** el test pasa. Los tests `test_company_state` y `test_company_save` pasaron a usar el formato `{id, x, z, turns}`.

### D-0910 · Layout replicado en red; solo host o voto coloca — A · Opus 5.5 · xhigh · Aviso: sí (`network_manager.gd`) · F1
**[x] Hecho (2026-10-18, PR pendiente)** — `CompanyLayoutNet` (`scripts/core/company/company_layout_net.gd`, `CompanyNet.build`): colocar, mover, girar y vender una pieza como peticiones de `CompanyNet` que valida el host y eventos que aplica cada peer; solo construye el host; `CompanyShed.follow(net)` redibuja; `PROTOCOL_VERSION` 34; `test_company_layout_net`. El voto de la tripulación queda en la subtarea abierta D-0910.1.
**Depende de:** D-0902, D-0903 (`BuildPlacement`), D-0920 (`PlaceableShop`), D-0911 (`uid` de las piezas, `CompanyShed`), D-2003 / D-2004 (`CompanyNet` y snapshot)
**Qué:**
- **Peticiones y eventos** (contrato `diseno/red-autoridad.md` §2 filas 21 a 24 y §8), por el `_request` / `_apply_event` de siempre (ningún RPC nuevo): `layout_place {id, x, z, turns}` → `layout_placed {id, x, z, turns, uid, minute, money}`; `layout_move {uid, x, z}` y `layout_rotate {uid, turns: 1..3}` → `layout_moved {uid, x, z, turns}` (pose final); `layout_sell {uid}` → `layout_sold {uid, minute, money}`. Todo enteros y ids cortos (< 200 bytes por evento).
- **El host valida** con lo mismo que el modo construcción: `BuildPlacement.preview` en la grilla de la etapa (`WarehouseStages.apply_to`: dentro del piso, fuera de dársena y salida, sin choque, todo alcanzable) y la plata. Rechaza con los motivos de `BuildPlacement` más `host_only`, `no_piece`, `not_empty` (vender un estante o una mesa con unidades) y `bad_data` (un id que no es exactamente un archivo de `data/placeables/`, celdas no enteras o fuera de ±256, giros fuera de rango). El rechazo le llega solo al que pidió y no gasta `seq`.
- **Cada peer aplica** con las mismas llamadas (`PlaceableShop.buy` / `sell`, la pose en el dict de la pieza) y solo comprueba los datos (regla 6), todo antes del primer cambio. La plata va absoluta: `money` es el saldo del host después del movimiento y cada peer arranca desde el saldo del host antes, así plata y `balance` del libro quedan iguales; si el espejo estaba desfasado lo corrige y `CompanyNet` pide un snapshot (`take_drift()`). `minute` va solo a la entrada del libro (el `clock_minutes` del cliente no se escribe). `CompanyNet._apply_state` tiene una rama explícita para los tres eventos. Antes de cada evento las piezas sin `uid` guardan el que se les deducía (vender una no renombra a otra) y un nombre repetido le da a la segunda pieza uno nuevo.
- **Join tardío**: el layout ya viaja en el snapshot (`CompanyState.to_dict()`), sin parte nueva. `CompanyShed.follow(net)` redibuja en cada evento de layout y en `company_state_restored` (y las etiquetas en `units_moved`); `CompanyRoot` lo usa en vez de redibujar por su cuenta.
- **D-0910.1 (abierta, `constructor-red` + `constructor-ui`)** Voto de la tripulación para que un cliente construya: el cliente pide, el host abre una votación (`modules/coop_vote`) y aplica si pasa; hoy `CompanyLayoutNet.check()` recibe `by_host` y ahí entraría "o el voto pasó".
- **D-0910.2 (abierta, `constructor-red`)** Ampliar la etapa por red: `WarehouseStages.expand` es local; hace falta un `kind` (`shed_expand`) para que la grilla nueva llegue a todos sin esperar un snapshot.
**Decisión:** solo el host construye (el cliente puede pedir y oye `host_only`, para que el modo construcción le diga por qué); construir no depende de la fase del día ni del galpón congelado, porque ni el contrato ni D-0203 lo piden; las piezas se nombran por `uid` y no por índice (dos pedidos en vuelo no se confunden de pieza); no se vende una pieza con unidades (se perderían). `docs/decisiones/2026-10-18-construccion-solo-host.md`.
**Test** `test_company_layout_net`: solo, colocar paga y nombra `<id>_<n>`, mover y girar gratis, vender devuelve; un espejo con la plata desfasada termina en el saldo del host, con el minuto del host en el libro y su `clock_minutes` (centinela) intacto; cada evento de `EVENT_KINDS` tiene su rama en `_apply_state` (leído del código); nombres repetidos; un evento rechazado no guarda nombres; cada rechazo (choque, dársena, fuera del piso, camino cortado, sin plata, con unidades, pieza que no existe, datos malos) no cambia nada; nombres de piezas sin `uid`; eventos que no encajan no se aplican; con host + cliente ENet, 8 cambios con el galpón descongelado y congelado llegan en orden, iguales (layout, plata, libro, stock, día, dibujo) y sin tocar el día; el cliente que pide oye `host_only` 4 veces y nada cambia; el host gana plata sin evento y compra: el cliente queda en su plata y saldo, pide snapshot y termina igual; un tercero que entra tarde recibe el layout por snapshot, lo dibuja y sigue; `seq` sin huecos en los tres.
**Hecho cuando:** el test de red pasa.

### D-0913 · Iluminación que se adapta al layout (sin rincones oscuros) — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `ShedLighting` (`scripts/gameplay/business/shed_lighting.gd`) + constantes `SHED_LAMP_*` en `CompanyTuning` + `CompanyShed._build_lights`; `test_shed_lighting`. La captura con luz real queda en `revisar/D-0913.md` (la nube renderiza por software).
**Depende de:** D-0905 (etapas), D-0911 (`CompanyShed`)
**Qué:** las luces del galpón salen del dato, no de posiciones a mano:
- Rejilla de lámparas de techo: una por baldosa de hasta 8 m (`SHED_LAMP_SPACING_M`), centrada en su baldosa; crece con la etapa (2 lámparas en la chica, 12 en el centro logístico). Alcance 8,5 m: el punto más lejano de una baldosa está a 5,7 m, dentro del 75 % del alcance (`SHED_LAMP_REACH`), así que ninguna celda queda oscura.
- Una lámpara de tarea sobre cada mesa de armado: sigue a la mesa al moverla o girarla (se redibuja con el layout).
- Tope de luces por punto: el renderer Compatibility ilumina un objeto con 8 omni como mucho; `max_overlap` lo comprueba para todas las etapas.
- `OmniLight3D` sin sombras a 3,6 m (bajo las paredes de 4 m).
**Decisión:** las lámparas dependen de la etapa y de las mesas, no de cada estante: los estantes son bajos y la rejilla ya cubre todo el piso. Sin sombras porque en Compatibility cada sombra cuesta una pasada y no aporta con muebles de menos de 2 m.
**Test** `test_shed_lighting`: cada etapa sin celda oscura y bajo el tope de luces, más lámparas en etapas grandes; la mesa recibe lámpara que la sigue; estantes, zona de despacho y entradas basura no; quitar una lámpara deja celdas oscuras (el chequeo puede fallar); `CompanyShed` cuelga una `OmniLight3D` por lámpara bajo la pared y las redibuja sin apilar.
**Hecho cuando:** el test pasa y la captura del galpón (a mano) no muestra rincones oscuros.

### D-0914 · Interacción con objetos colocados igual que con los fijos — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `ShedPiecePoint` (`scripts/gameplay/interaction/shed_piece_point.gd`) + `CompanyShed._add_use_point` / `use_points` / `piece_used`; claves `WORLD_SHED_USE_*`; `test_shed_interaction`. Qué hace cada uso (abrir el estante, trabajar la mesa) es de las tareas de cada estación (D-0703 y el grupo 06); acá solo se dice quién usó qué pieza.
**Depende de:** D-0911 (`CompanyShed`), D-0903 (mover y vender)
**Qué:** cada estante, mesa de armado y zona de despacho del layout recibe, al dibujarse, un punto de uso (`Interactable`, la misma sonda, aviso y alcance que el resto del juego). Se cuelga en el mismo dibujado para las piezas por defecto y las que puso la tripulación, así que no hay dos caminos.
- El punto está **delante de la pieza**, a 0,45 m de su huella (una esfera de 0,8 m): el collider del estante es macizo, un punto adentro no se vería ni se alcanzaría (`Player.within_reach`). Gira con la pieza (sus cuatro giros). La zona de despacho no bloquea el paso: su punto está en el medio.
- Mover, girar o vender una pieza redibuja el galpón y con él sus puntos: ninguno queda de una pieza vendida ni se duplica.
- `ShedPiecePoint.used(uid, role, peer_id)` y `CompanyShed.piece_used` dicen quién usó qué. `interact()` corre en el host como todo `Interactable`; no hay RPC nuevo.
**Decisión:** un punto por pieza en vez de uno por casilla o por estante: es lo que ve la sonda y mantiene el costo en una `Area3D` por mueble. Los bloques sin rol (muebles lisos) no tienen punto.
**Test** `test_shed_interaction`: un punto por pieza trabajable del layout por defecto; cuatro estantes puestos a mano, uno por giro, reciben el mismo punto (clase, capa, forma, texto) y están dentro del piso y fuera de toda huella; mover cambia el punto de lugar, vender lo saca, sin duplicar; usar el punto de un estante por defecto, una mesa y uno puesto informa uid, rol y peer.
**Hecho cuando:** el test pasa.

### D-0916 · Deshacer la última colocación — A · Sonnet 5.5 · low · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `BuildPlacement.undo_last_placement/can_undo` (`scripts/gameplay/business/build_placement.gd`) + `UNDO_DEPTH`; `test_build_undo`. El botón o la tecla (Ctrl+Z) quedan para el adaptador de D-0917/D-0943.
**Depende de:** D-0902 (`BuildPlacement.place`)
**Qué:** `place()` recuerda las últimas 8 piezas compradas (las entradas del layout mismas); `undo_last_placement()` saca la más nueva que siga en el layout y devuelve **el precio entero** (vender devuelve el 50 %).
- Una pieza movida o girada después se encuentra igual; una vendida entremedio se saltea. Las piezas que no pasaron por `place()` (layout cargado o por defecto) no se deshacen.
**Decisión:** solo colocaciones, no mover, girar ni vender: es lo que dice la tarea y evita un historial de acciones con dinero. Reembolso completo porque es un error recién cometido, no una venta.
**Test** `test_build_undo`. **Hecho cuando:** el test pasa.
