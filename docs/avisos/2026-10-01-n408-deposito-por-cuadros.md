# N-408: el depósito se arma en varios cuadros y se muestra por partes (2026-10-01)

Lo hizo Nacho (con Claude), rama `nacho/N-408b-depot-slices` (sobre `nacho/N-408-loading-no-freeze`). Seguimiento del
aviso `2026-10-01-n408-ruta-por-cuadros.md`: `Depot._ready()` tomaba el hilo principal ~300 ms de una (el cuadro
del cambio de escena) y su primer dibujo (compilar shaders) otros 190-250 ms en un solo cuadro.

- **Qué cambia para quien lee el depósito**: `Depot` tiene `is_built`, `signal built`, `loading_progress()` (0..1,
  sube siempre) y `build_stats`, y mientras arma está en `SceneLoader.BUSY_GROUP`. La misma regla que la ruta: arma
  en rebanadas de 12 ms solo si hay un `SceneLoader` bajo la raíz (o `Depot.always_slice = true`, que usa
  `test_depot_async_build.gd`); sin pantalla de carga (tests, `render_*`, herramientas) arma de una vez dentro de
  `_ready()`, igual que siempre, y el depósito sale **idéntico** (mismos nodos en el mismo orden, mismas mallas,
  mismos estantes y stock; lo comprueba el test). `async_build = false` lo fuerza de una vez.
- **Nivel** (`level_common.gd`, `level_base.gd`, `level_endless.gd`): lo que necesita el depósito completo corre
  cuando está armado: `withhold_locked` + `stock_shelves` (`_stock_depot()`), `post_orders` (`_after_depot()`),
  los jugadores (`_is_world_built()` ahora pide depósito **y** ruta) y `NetworkManager.level_ready()`
  (`_wait_for_world()` espera a los dos). Mientras tanto las cajas del nivel esperan congeladas (todavía no hay
  piso). Las casas reciben sus pedidos cuando están la ruta y el tablero (`_assign_orders()` en `level_base.gd`).
- **Primer dibujo por partes**: `Depot.reveal_steps()` parte lo que ve el jugador en ~13 pasos (lo que hay antes
  del lote grande, ocho tandas del lote, sombras y escudo, puerta/carteles, tablero/estaciones, luces, vida) y el
  cargador los muestra de a uno por cuadro. Zona compartida: `modules/scene_loader/scene_loader.gd` — un nodo de
  `reveal_paths` que tenga `reveal_steps() -> Array[Callable]` se muestra en esos pasos (uno por cuadro); los demás
  siguen igual. `LoadingScreen.REVEALS` no cambia.
- **Builders** (`depot_hall.gd`, `depot_furnishing.gd`, `depot_zones.gd`, `depot_props.gd`, `depot_circulation.gd`,
  `depot_dressing.gd`): sus `build*()` ahora son corrutinas que hacen `await kit.tick()` entre pasos
  (`DepotKit.slicer`, `DepotKit.commit_sliced()`); sin slicer no esperan nada. Nadie más las llama.
- **Flechas del piso que parecían flotar** (reporte del usuario): `paint_arrow()` apuntaba la flecha a la
  estación **en 3D** (a 1,3-2 m de altura), así que se inclinaba: la punta subía hasta 4 cm y la cola se hundía en
  el piso (el "muñón lila"). Ahora se aplana, es una sola pieza plana opaca con el grano del piso (`detailed`,
  antes un `flat` liso, sin textura) y las de las sendas miden 0,6 m (`ARROW_LENGTH`, que estaba definido y sin usar:
  la punta pisaba la franja blanca del borde). Toda la geometría es una malla de `DepotLabels.flat_arrow_mesh()`.
  `render_depot.gd` suma seis tomas `floor_arrow_*`.
- **Texturas del depósito** (reporte del piso blanco, sin reproducir): `DepotKit._texture()` avisa una vez con
  `push_warning` y deja el color liso si un `tx_detail_*` o el atlas de pictogramas no carga (el atlas ausente no
  dibuja cuadrados blancos). `DepotAtmosphere._adopt()` acota lo que recupera del `Environment` (cielo 0..1, energía
  ≤ 4, niebla ≤ 0,2, color 0..1) para que un entorno sin mezclar no deje valores inflados. Test nuevo
  `test_depot_textures.gd`.
- **Para Slatex**: nada de `vehicle.gd`, la red ni la UI cambia; `PROTOCOL_VERSION` sigue igual.
