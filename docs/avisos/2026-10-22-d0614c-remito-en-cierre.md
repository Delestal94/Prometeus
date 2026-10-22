# D-0614.c: el remito del proveedor en la pantalla de cierre del día

Tocado en un archivo del dominio de Slatex: `scripts/ui/day_summary_panel.gd` (pantalla de la expansión).

- `open(summary, note_lines := [])` y `refresh(summary, note_lines := [])` aceptan las líneas del remito
  del día (`DeliveryNote.discrepancies()`); sin líneas, todo queda como antes (la sección "Remito del
  proveedor" no aparece).
- Nuevos `note_rows()` y `note_text()` (estáticos) y cuatro claves `UI_FINANCE_NOTE*` en
  `translations/strings_ui.csv`.
- Los nombres de producto salen de `PickingCartPoint.product_name()` (el mismo texto que el carrito).
