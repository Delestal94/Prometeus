# D-0612: la lista de stock abre arriba

Tocado en un archivo del dominio de Slatex: `scripts/ui/stock_panel.gd` (pantalla de la expansión).

- `_focus_first` ahora, un frame después de dar el foco a la primera fila, pone `scroll_vertical = 0`:
  con `follow_focus` y las filas recién armadas, una lista de 10 productos abría scrolleada al final
  (se vio en la captura del galpón, `tests/render_company_shed.gd`, vista `stock_list`).
- Nuevo `list_scroll()` para que los tests lean el desplazamiento; `test_company_stock_panel` comprueba
  que una lista larga abre arriba.
- Si otra pantalla con `ScrollContainer` + `follow_focus` arma sus filas al abrir, puede tener lo mismo.
