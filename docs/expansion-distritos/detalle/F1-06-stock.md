# F1 · Grupo 06 — Mercadería entrante, descarga y stock (detalle)

> Carril 2 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [06-mercaderia-y-stock.md](../06-mercaderia-y-stock.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0604 · Palet con N cajas de producto — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Pallet` (`scripts/gameplay/business/pallet.gd`): arma, parte un pedido en palets, los recibe en el `Inventory` y los serializa; `test_pallet`.
**Depende de:** D-0204 (producto), D-0211 (`Inventory`)
**Qué:** `class_name Pallet`, `RefCounted` con solo funciones estáticas. Un palet es un `Dictionary`
(`id`, `product`, `qty`, `state`: `sealed` / `open`) para que viaje por red y entre en el save.
- `make(id, product, qty)`: palet cerrado de 1 a `MAX_UNITS = 24` unidades de un solo producto (supuestos);
  `{}` si no cumple.
- `plan(prefix, product, qty)`: parte un pedido a proveedor en los palets mínimos (24 + 24 + 2…).
- `location(id)` = `&"pallet:<id>"`: dónde cuenta el `Inventory` las unidades del palet.
- `receive(inventory, pallet)`: el camión lo descarga; suma las unidades en `pallet:<id>` una sola vez.
- `units_left`, `validate`, `to_json` / `from_json`.
Abrir el palet (pasar sus unidades a cajas tomables) es D-0607; el objeto físico y verlo en la caja del
camión es D-0601 / D-0605, que usan esta clase.
**Test** `test_pallet`: límites de `make`, `plan` de 50 unidades, `receive` una sola vez sin duplicar,
`validate` con 4 problemas, JSON de ida y vuelta.
**Hecho cuando:** el test pasa. (La parte "aparece en la caja del camión" queda para D-0601.)

### D-0607 · Abrir palet — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Pallet.open/take/is_depleted` en `pallet.gd`; ampliado `test_pallet`.
**Depende de:** D-0604 (`Pallet`), D-0211 (`Inventory`)
**Qué:** abrir es solo un cambio de estado: `open(inventory, pallet)` pasa `sealed` → `open` (en el mismo
`Dictionary`) si el palet está recibido y tiene unidades; no las mueve. `take(inventory, pallet, qty, to)`
pasa unidades de `pallet:<id>` a una mano, carrito o hueco, solo con el palet abierto. `is_depleted` avisa
cuando queda vacío para sacarlo del patio. El objeto físico "caja tomable" lo arman D-0605 / D-0609 sobre esto.
**Test** `test_pallet`: no se abre sin recibir; `take` falla cerrado; abre una vez; saca 3 de 5; no saca de más;
vacío = agotado; no se pierde ni duplica ninguna unidad.
**Hecho cuando:** el test pasa.

### D-0608 · Estanterías con huecos etiquetados por producto — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `Shelf` (`scripts/gameplay/business/shelf.gd`): huecos con etiqueta de producto sobre el `Inventory`; `test_shelf_slots`.
**Depende de:** D-0904 (`PlaceableDefinition.slots`), D-0211 (`Inventory`)
**Qué:** `class_name Shelf`, `RefCounted`. `make(id, slot_count)` (usa `slots` del `.tres`), `set_label` / `clear_label`
(un producto por hueco y un hueco por producto en cada estante; no se re-etiqueta con unidades adentro),
`deposit(inventory, slot, product, qty, from)` y `withdraw(inventory, slot, qty, to)` (todo o nada, solo con
`Inventory.move`: no se crea ni se pierde nada), `count`, `free_space`, `find_slot`, `to_dict` / `from_dict`.
Las unidades viven en `shelf:<estante>_<hueco>`. Capacidad por hueco: `CompanyTuning.SHELF_SLOT_CAPACITY = 24` (un palet).
El nodo que dibuja el estante y la interacción son D-0609 / D-0611; el frío es D-0616.
**Test** `test_shelf_slots`: 8 huecos, etiquetas, depósito solo del producto etiquetado, tope, retiro, 50 movimientos conservan el total, JSON.
**Hecho cuando:** dejar producto en un hueco lo suma al `Inventory` (test pasa).
