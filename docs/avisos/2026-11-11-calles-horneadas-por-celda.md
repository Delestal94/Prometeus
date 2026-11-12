# Calles horneadas por celda: segunda pasada del streamer, StaticMerger y rango de piezas chicas (D-2012.2)

- **`modules/world_cells/cell_streamer.gd` (zona compartida):** `finish_for` nuevo y opcional, `Callable(cell, node)`:
  una segunda pasada sobre la celda ya en el árbol, desde el paso siguiente al que la instanció (un paso nunca hace
  las dos cosas). Si devuelve `false` se la vuelve a llamar el paso siguiente, antes que a otra. Mientras no termina,
  la celda no se dibuja; al terminar se emite `cell_finished(cell, node)`. `is_busy()` cuenta las pasadas pendientes y
  `is_finished(cell)` es nuevo. Sin `finish_for` todo queda como antes.
- **`modules/render_budget/static_merger.gd` (nuevo):** `StaticMerger.merge(holder, roots, drop_hidden, claim)` funde
  la geometría estática de muchas piezas chicas en `MergedStatic`/`MergedModels` y libera los nodos que solo la
  portaban; `begin`/`fold`/`fold_branch`/`finish` hacen lo mismo por pasos.
- **`modules/render_budget/world_quality.gd`:** `WorldQuality.set_view_range(node, base)` da rango de dibujo (escalado
  por el preset, como los lotes de decorado) a un nodo y a todo lo que dibuja debajo.
- **Las casas (`delivery_house.gd`, `house_waiting_marker.gd`), también en la entrega:** el portero eléctrico se
  dibuja hasta 40 m; el buzón, el texto del cartel y la lamparita hasta 120 m; las patas del cartel, el hilo y el
  nudo del globo hasta 250 m (por el preset). El globo, el brillo y los tableros, sin rango.
- **`test_route_golden`:** no firma el rango de dibujo de un nodo bajo `WaitingMarker` (como ya no firmaba el de los
  lotes de decorado). El golden no cambió.
- **Ojo:** algo que lea las mallas de una pieza de calle del modo Empresa después de que su celda se horneó ya no las
  encuentra (quedan en `Streets`, `MergedStatic` y `Verge` de la celda). Las piezas, su `Road` y los `GripArea`
  siguen donde estaban.
