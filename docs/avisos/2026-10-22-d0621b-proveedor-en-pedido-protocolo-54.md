# Protocolo 54: el pedido al proveedor nombra al proveedor (D-0621.b.a)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 54** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea
  del historial. `main` tenía el 53; de los PRs abiertos, #706 (D-0851) también usa el 53 y #697 (D-0715.c) el 52,
  así que los dos tienen que subir al mezclarse (`docs/convenciones-godot.md` §6: el segundo que entre toma el
  siguiente libre y corrige su línea). Ninguna firma ni RPC de `NetworkManager` / `NetSession` cambió y
  `modules/net_session/` no se tocó.
  **Cambió el protocolo** sin RPC nuevo: la petición `supplier_order` de `CompanyNet` lleva `supplier` (el id del
  proveedor), el evento `supplier_ordered` lo lleva siempre (`{order_day, lines, peer, supplier}`) y la parte
  `supplier` del snapshot suma `suppliers` (los camiones de los otros proveedores). Un cliente con 53 y un host con
  54 no se conectan (error de versión en el menú); con el mismo número viejo el cliente rechazaría el evento y el
  snapshot con otros proveedores.
- **Compatibilidad:** una petición sin `supplier` sigue andando y es de `distribuidora_central` (el proveedor por
  defecto, `SupplierIds.DEFAULT`); un guardado viejo (`supplier_calendar` con solo `deliveries`) carga como el
  camión por defecto; un guardado nuevo leído por una versión vieja pierde solo los camiones de otros proveedores.
  Un pedido lleva ahora hasta 14 productos (`CompanySupplierNet.MAX_LINES`, antes 15: una clave es `supplier`).
- **`scripts/gameplay/business/supplier_schedule.gd`** (`SupplierSchedule`): un camión por día y proveedor. Agregado
  sin romper: `place`, `has_delivery`, `ordered_for`, `pallets_for`, `upcoming_days`, `truck_state` y `clear_day`
  tienen un último parámetro opcional `supplier` (sin él, el camión por defecto, igual que antes); nuevos
  `use_suppliers`, `set_times`, `arrival_minute_of`, `departure_minute_of`, `suppliers_on`. `day_count()` cuenta
  camiones (con un solo proveedor, lo mismo que antes). Ids de palet de los otros proveedores:
  `d<día>-<proveedor>-<producto>_<n>` (los del por defecto no cambian).
- **`scripts/gameplay/business/supplier_ids.gd`** (nuevo, `SupplierIds`): `DEFAULT`, `ok(id)`, `pallet_prefix`,
  `pallet_supplier`.
- **`scripts/gameplay/business/supplier_order_cart.gd`**: el precio usa el `price_factor` del proveedor del carrito
  (`unit_price(producto)`, `SupplierOrderCart.unit_cost`); con `distribuidora_central` (×1,0) no cambia nada.
  `submit()` toma un último parámetro opcional `truck`.
- **`scripts/core/company/company_supplier_net.gd`**: `suppliers` (todos los del catálogo), `seller(id)`,
  `sellers()`, `truck_of(def)`, `request_data(líneas, proveedor = "")`. `load_catalog` elige el proveedor por defecto
  por id (antes, el primero por nombre de archivo) y pasa los horarios al calendario.
- **`scripts/gameplay/supplier_board.gd`**: la petición nombra al proveedor del carrito y la respuesta se compara con
  el camión de ese proveedor.
- `ExpansionResourceCheck` marca un proveedor cuyo id no pasa `SupplierIds.ok` (no tendría camión).
- Contrato: fila 1 de `docs/expansion-distritos/diseno/red-autoridad.md`. Test nuevo `test_company_supplier_choice`.

## Qué tiene que hacer Slatex

- **`scripts/ui/supplier_order_panel.gd`** (tuyo, no se tocó): la fila de cada producto muestra
  `SupplierPurchase.cost(producto, 1, cart.products)`, el precio de lista. Con un proveedor que no sea el por defecto
  el total (`cart.total()`) ya sale con su `price_factor` y la fila no; hay que pasarla a `cart.unit_price(producto)`.
  Lo hace la tarea del tablero, D-0621.b.b (rutina de Nacho), salvo que lo toques antes.
- Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 55.
