# D-2012.1: las celdas fijas lejanas no se dibujan

- **Qué cambió (`modules/world_cells`, zona compartida):** `WorldCellGrid.update()` devuelve además `park` y `wake`, y
  hay `is_parked(cell)`. Una celda fijada queda estacionada pasado `load_radius` de toda ancla y se despierta dentro de
  ese radio; una vez despierta aguanta hasta `unload_radius`, igual que la carga de una celda común. `impostor_cells()`
  ahora incluye las estacionadas. `WorldCellStreamer` las deja en el árbol con `visible = false`, con su colisión, y les
  pone el impostor. Sin anclas no cambia nada. Ninguna firma cambió: `update()` solo suma dos claves.
- **Ojo si escribís algo que vive en una celda fija:** `is_visible_in_tree()` puede dar `false` aunque el nodo exista y
  su física corra. Colisión, áreas, `_process` y audio siguen; lo que deja de verse o de emitir son mallas, luces y
  partículas.
- **Tests:** `test_world_cells_freeze` lleva su propio reloj pero dejaba correr el `_process` del streamer con el reloj
  real, y fallaba si Godot tardaba más de 5 s en arrancar (también en `main`). Ahora lo apaga después de `add_child`.
  Es solo el test.
- **Qué tiene que hacer Slatex:** nada.
