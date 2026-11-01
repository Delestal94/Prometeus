# D-1902: portapapeles del modo Empresa

- **Qué cambió:** en el mundo Empresa la lista de stock y la pantalla del proveedor ya no son pantallas sueltas:
  son las hojas Stock y Proveedor del portapapeles (`CompanyClipboard`, `scripts/gameplay/company_clipboard.gd`;
  marco en `scripts/ui/clipboard_frame.gd`). `I` / cruceta derecha lo levanta, `Q` / `E` (LB / RB) cambian de
  hoja, `Esc` / B lo guardan. Diseño: `docs/expansion-distritos/diseno/portapapeles.md`.
- **Zona compartida:** `scripts/core/network_manager.gd`, `PROTOCOL_VERSION` 63 → 64: `player.tscn` replica
  `PlayerHeldTool:held_tool` (lo que el jugador tiene en la mano; los demás ven la tabla marrón en `hand.R`).
- **Archivos sin dueño que cambian:**
  - `company_root.gd`: sin líneas nuevas; `_add_stock_board()` llama a `CompanyClipboard.attach(self, stock_board)`
    en lugar de `add_child(stock_board)`. El portapapeles envuelve `ShedBuilder.busy` (no se construye con él
    afuera).
  - `stock_board.gd`: `sheet_mode` (deja de escuchar `company_stock`), `show_sheet()` / `hide_sheet()`.
  - `supplier_board.gd`: `open_in` (el tablero del galpón saca el portapapeles en la hoja Proveedor),
    `show_sheet()` / `hide_sheet()`. Fuera del mundo Empresa (tests, otros usos) los dos se comportan igual
    que antes.
- **Qué tiene que hacer Nacho:** nada. La hoja Empleados (D-1038) se suma con `frame.add_sheet()` y
  `set_listed()` cuando exista el hito 8; D-1004 (bajado y asignar apuntando) usa `held_tool = &"clipboard"`.
