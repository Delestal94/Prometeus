# Aviso 2026-10-21 · tablero de despacho (D-0310)

Dominio de Slatex tocado (`scripts/ui/`), solo archivos nuevos y filas de traduccion; no cambia ninguna firma existente.

- `do-not-drop/scripts/ui/dispatch_board_panel.gd` (nuevo): `DispatchBoardPanel`, panel por codigo con `open(ctx)`,
  `refresh(ctx)`, `toggle(box_id)`, `confirm()` y las senales `loaded` y `closed`. Datos inyectados, sin autoloads.
- `do-not-drop/translations/strings_ui.csv`: 13 filas `UI_DISPATCH_*` al final.
- `do-not-drop/tests/test_company_dispatch_panel.gd` (nuevo).

Para Slatex: nada que hacer. Cuando D-0310.b enganche la estacion, el panel va debajo del HUD como `DaySummaryPanel`
(pantalla completa, con foco propio y `ui_cancel` para cerrar).
