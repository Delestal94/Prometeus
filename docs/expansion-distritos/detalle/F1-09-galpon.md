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
