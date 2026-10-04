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
