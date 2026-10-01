# El panel de pedidos del depósito scrollea con 7 pedidos (N-228.6)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

Con 8 jugadores el depósito puede tener 7 pedidos y la hoja de pedidos medía ~799 px en una pantalla de 720.

`scripts/ui/depot_panel.gd` (tu dominio):
- `_build_orders()` pone las filas en un `ScrollContainer` "OrdersScroll" (lista "OrdersList", filas "Order_<i>").
  `_fit_orders_scroll()` le da el alto que necesita hasta lo que deja la pantalla (el resto de la tarjeta se mide
  después del layout, por las notas del Jefe que se parten en líneas); se recalcula en `size_changed`. El botón
  Volver queda siempre visible y conserva el foco inicial.
- Si la lista no entra, el scroll es una parada más del foco (con su anillo: `draw_focus_border`, stylebox `focus` sin márgenes de contenido): con él enfocado, arriba/abajo lo desplazan
  (`ORDERS_SCROLL_STEP`) y en los extremos el foco sigue al vecino (Volver); la rueda del mouse anda sola. Si entra
  entera no toma foco.
- Una cara nueva del panel que tenga una lista larga puede copiar este patrón.

`scripts/ui/ui_theme.gd`: `UiTheme.focus_ring()` (público; envuelve el anillo de foco de siempre).
`tests/test_crew_panel.gd` ahora prueba 8 entradas (el panel de tripulación ya entraba: 511 px). Test nuevo:
`tests/test_depot_panel.gd`.

## Qué tiene que hacer Slatex

Nada. Sin textos nuevos.
