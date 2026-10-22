# Aviso 2026-10-22 · pedido al proveedor en el galpón y en red (D-0603.b.2)

**Cambia el protocolo:** `PROTOCOL_VERSION` 40 -> 41 (`scripts/core/network_manager.gd`, zona compartida). Un
cliente viejo con un host nuevo no se conecta (error claro de versión). Nada más cambió en `network_manager.gd`.
Los PRs #617 (D-0605.b) y #610 (D-0813) también usan el 41: el que mezcle después sube al siguiente libre
(`docs/convenciones-godot.md` §6.3).

Qué cambió en la red de la empresa (Nacho, `scripts/core/company/`):
- `CompanyNet`: pedido nuevo `supplier_order` {<producto>: unidades} (plano, por `RpcGuard.dict_ok`), evento
  nuevo `supplier_ordered` {order_day, lines: [{product, qty}], peer} y parte nueva `supplier` del snapshot (el
  calendario del proveedor). Ningún RPC nuevo en `CompanyNet` (viajan por `_request` / `_apply_event` /
  `_snapshot`). `var supplier: CompanySupplierNet` nuevo. Se quitaron `CompanyNet.PRODUCTS_DIR` y
  `CompanyNet.product_exists()` (sin usos: `CompanyAsk.product_exists()` es el mismo; igual que en #617) para
  que el archivo no pase las 1000 líneas.
- `CompanySupplierNet` (nuevo): chequeo del host y aplicación en cada peer.
- `CompanyState.supplier_calendar` (nuevo, en `to_dict`/`from_dict`, tolerante): el save de empresa guarda el
  calendario. No sube la versión del save (un save viejo carga con el calendario vacío).

Dominio de Slatex tocado (sin firmas cambiadas, solo agregados):
- `scripts/ui/supplier_order_panel.gd`: el ctx acepta `request: Callable(lines) -> int`; con eso "Pedir" pide al
  host en vez de llamar `submit`, y la pantalla espera `placed(arrival_day)` o `refused(key, args)` (métodos
  nuevos), más `is_waiting()`. Sin `request` todo es como antes (`test_company_supplier_panel` igual).
- `scripts/gameplay/interaction/supplier_board_point.gd` (nuevo): `SupplierBoardPoint extends Interactable`, el
  tablero del proveedor. `interact()` corre en el host y abre la pantalla en el peer de quien lo usó con un RPC
  nuevo, `_open_here` (`@rpc("authority", "call_remote", "reliable")`, chequea `RpcGuard.from_host`), como
  `DepotStation._open_locally`. Señal `opened`.
- Textos: `UI_SUPPLIER_SENT`, `UI_SUPPLIER_DAY_CLOSED`, `UI_SUPPLIER_TOO_MUCH`,
  `UI_SUPPLIER_NAME_DISTRIBUIDORA_CENTRAL` (`strings_ui.csv`) y `WORLD_SHED_USE_SUPPLIER` (`strings_world.csv`).

Mundo (sin dueño): `company_root.gd` (`_add_supplier_orders()`, `_seed_first_truck()`, `_on_supplier_ordered()`;
se quitó `_seed_stand_in_calendar()` y `STAND_IN_DAYS`), `company_shed.gd` (`_build_supplier_board()`,
`supplier_board_spot()`, señal `supplier_board_opened`, `var supplier_point`), `supplier_board.gd` (nuevo).

**Ojo D-0605.b (PR #617):** el camión ya no viene todos los días. Su `test_company_pallet_jack_world`
(`_test_root`, día 2 en la raíz real) contaba con el calendario de relleno: al mezclar, que pida antes el
pedido del día 2 (por ejemplo `level.net.request(CompanySupplierNet.ORDER, {"milk_canister": 12,
"wedding_cake": 6})` con plata suficiente en el día 1, o `level.supplier_schedule.place(1, ...)`).

Para Slatex: nada que hacer. `Interactable`, `Player` y el sondeo de interacción no cambian.
