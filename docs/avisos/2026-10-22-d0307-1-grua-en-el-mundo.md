# D-0307.1: la grúa en el mundo de la empresa

Tocado en la zona compartida: `scripts/core/network_manager.gd` (`PROTOCOL_VERSION` 58: `CompanyNet` toma el
pedido `trip_tow {vehicle, rid}`; no hay RPC nuevo, pero la lista de pedidos válidos cambia) y
`scripts/core/company/company_net.gd` (`REQUEST_KINDS`, `CompanyNet.tow`, una rama en `_take_request`; el
archivo está en su tope de 1000 líneas: sale de comprimir comentarios). Fila 19a nueva en
`docs/expansion-distritos/diseno/red-autoridad.md`. Archivos de Slatex: `scripts/ui/day_summary_panel.gd`
(`REASON_KEYS["tow"]` = `UI_FINANCE_REASON_TOW`) y `translations/strings_ui.csv` (esa clave: "Grúa" / "Tow truck").

- Clave nueva `WORLD_TOW_NOT_YOURS` (`strings_world.csv`): el pedido lo acepta solo el conductor, quien va adentro o
  cualquiera si nadie maneja.
- Archivos nuevos: `scripts/gameplay/districts/company_tow.gd`, `scripts/core/company/company_tow_net.gd`,
  `tests/test_company_tow.gd`. Textos: `WORLD_TOW_OFFER` en `strings_world.csv`.
- El resumen del día muestra "Grúa" en los costos cuando hay una línea de libro con motivo `tow` (antes
  mostraba el id).
- `company_root.gd` también queda en 1000 líneas: un hijo `Tow` más y un párrafo de documentación comprimido.
