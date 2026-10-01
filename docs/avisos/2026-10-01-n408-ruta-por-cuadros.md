# N-408: la ruta de entregas se arma en varios cuadros (2026-10-01)

Lo hizo Nacho (con Claude), rama `nacho/N-408-loading-no-freeze`. La pantalla de carga no tiene que
congelarse: antes `route.gd` construía todo en un solo `_ready()` (5-6 s con el hilo principal tomado).

- **Qué cambia para quien lee la ruta**: `Route` tiene `is_built`, `signal built` y `loading_progress()`
  (0..1, sube siempre), y mientras arma está en el grupo `SceneLoader.BUSY_GROUP`. Al volver `add_child()` ya
  no está lista: `houses` se va llenando, `terrain`/`dresser`/`goal_lot` aparecen en el camino. Un test que
  la lee enseguida hace `if not route.is_built: await route.built`.
- **Los tests y las herramientas no cambian**: sin una pantalla de carga (un `SceneLoader` bajo la raíz) arma de
  una vez, como siempre (tests, `render_*`, `bench_*`). Arma por cuadros cuando hay un loader que espera (menú →
  nivel, y también el reinicio de la entrega, que ahora pasa por la pantalla de carga), o con
  `Route.always_slice = true` (lo usan `test_route_async_build.gd`, `test_route_golden.gd` -- `-- --sync` en
  este último arma de una vez y firma el mismo mundo --, `net_pair.gd` y `net_trio.gd`).
- **Nivel** (`level_common.gd`, `level_base.gd`): `NetworkManager.level_ready()` y el spawn de jugadores esperan
  a que la ruta esté armada (`_wait_for_world()`, `_is_world_built()`); lo que necesita las casas
  (`assign_packages`, `wrong_package_offered`) corre en `_on_route_built()`. Endless no cambia.
- **Zona compartida** (`modules/`): `render_budget/frame_slicer.gd` (nuevo, `FrameSlicer`: `await slicer.tick()`);
  `DressingBatcher.bake()` y `merge_segment_geometry()` aceptan un `slicer` opcional y ahora son corrutinas
  (llamarlas estáticas pide `await`); `TerrainField` suma `build_async()` y `conform_all()` (números en
  `WorkerThreadPool`, escena en rebanadas), `conform_geometry()` acepta un `slicer`, y `_sample()` calcula
  `nearest()` una vez. El mundo generado es **idéntico** bit a bit (mismo `test_route_golden`).
- **Para Slatex**: nada de `vehicle.gd` ni de la red cambia; `PROTOCOL_VERSION` sigue igual.
