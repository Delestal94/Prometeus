# Aviso 2026-10-22 · pantalla de la tienda de la empresa en el cierre del día (D-0511.2)

Toca archivos de Slatex (`scripts/ui/`), sin cambio de protocolo:
- `scripts/ui/company_shop_panel.gd` (nuevo): la tienda, UI por código con datos inyectados.
- `scripts/ui/day_summary_panel.gd`: API nueva (`shop_requested`, `set_shop_available()`, `focus_default()`) y un
  botón "Tienda" junto a "Seguir" (que ahora está dentro de un `HBoxContainer`; sigue siendo el primer `Button`).
- `strings_ui.csv`: 14 claves nuevas (`UI_FINANCE_SHOP`, `UI_SHOP_*`).
- `scripts/gameplay/company_shop_screen.gd` (nuevo, adaptador) y 3 líneas en `company_root.gd`.
- `company_shed.gd`: redibuja el galpón con `shop_bought` si cambió `warehouse_stage`.
