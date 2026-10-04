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

### D-0702 · Dispensador de cajas — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — lógica: `BoxDispenser` (`scripts/gameplay/business/box_dispenser.gd`); `test_box_dispenser`. El objeto del dispensador y su menú de tamaños quedan para D-0702.b (ver `revisar/D-0702.md`).
**Depende de:** D-0701 (`PackingStation`), D-0501 (billetera de `CompanyState`)
**Qué:** `class_name BoxDispenser`, `RefCounted` con funciones estáticas. `dispense(station, size, wallet)`
abre una caja vacía del tamaño elegido (S, M, L, XL) en el hueco de la mesa y cobra `CompanyTuning.BOX_COST`
con el motivo `&"boxes"`. Rechaza sin cambiar nada: tamaño desconocido, mesa que ya tiene caja, billetera
que no alcanza, mesa o billetera nulas. `can_dispense` es la misma comprobación sin efectos (para el menú).
**Test** `test_box_dispenser`: caja abierta del tamaño pedido en la mesa, cobro y libro mayor, y las cuatro
negativas sin cambios.
**Hecho cuando:** el test pasa (caja aparece abierta en la mesa).
