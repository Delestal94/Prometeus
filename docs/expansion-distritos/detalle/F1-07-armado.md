# F1 · Grupo 07 — Armado de paquetes (detalle)

> Carril 3 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [07-armado-de-paquetes.md](../07-armado-de-paquetes.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0701 · Estación de armado — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — lógica de la mesa: `PackingStation` (`scripts/gameplay/business/packing_station.gd`); `test_packing_station`. Quedan abiertas la mesa visible y la captura (ver `revisar/D-0701.md`).
**Depende de:** D-0212 (`PackedBox`), D-0904 (la mesa `assembly_table`)
**Qué:** `class_name PackingStation`, `RefCounted` sin nodos (como `Shelf`). Una mesa tiene un hueco para
**una** caja abierta (`box: PackedBox`) y hasta `STAGING_SLOTS = 4` productos esperando al lado
(`staged`, ids; Decisión: no son stock del `Inventory`, el que arma los saca de la mano o del estante).
- `start_box(size)`: abre una caja vacía si el hueco está libre y el tamaño existe. El costo de la caja y
  el dispensador son D-0702.
- `stage_product(id)` / `unstage_product(id)`: deja o devuelve un producto a la mesa.
- `put_in_box(product, origin)`: pasa un producto de la mesa a la grilla de la caja (`PackedBox.place`);
  si no hay caja, no está en la mesa o no entra, no cambia nada.
- `take_box()`: saca la caja de la mesa (para cerrarla o despacharla).
- `to_dict` / `from_dict`: ida y vuelta por JSON (red y guardado).
**Test** `test_packing_station`: una caja a la vez y tamaños inválidos, tope de productos en la mesa,
`put_in_box` con sus tres negativas sin cambios, `take_box` y JSON.
**Hecho cuando:** el test pasa. La escena de la mesa (placeholder gris sobre la huella 2×1 de
`assembly_table`) y su captura quedan para la subtarea D-0701.b.
