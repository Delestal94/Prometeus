# Portapapeles de gestión (D-0131) — 2026-10-22

## Decisión
Diseño en `docs/expansion-distritos/diseno/portapapeles.md`:
- **Desde el día 1**, no con el hito "Primer empleado": las hojas de stock (D-0612) y del proveedor (D-0603) ya
  existen en F1. El hito 8 suma solo la hoja Empleados.
- **Como mucho 3 hojas**: Stock, Proveedor y Empleados. Pedidos queda en el tablero de la pared (lo que la
  tripulación mira en común; la prioridad ⚑ de D-0838 va ahí). Plata es el HUD del día y el cierre. Flota se ve
  en el mundo: D-1240 queda recortada.
- **F1 solo guardado ↔ levantado** (D-1902). La posición bajada y asignar apuntando llegan con D-1004.
- **Ocupa las manos**; usar algo del mundo lo guarda. El host no lo mira.
- **Sin RPC**: `held_tool` en el synchronizer del jugador (dominio de Slatex, aviso en el PR de D-1902) y
  `PROTOCOL_VERSION` nuevo. Nada al save.
- **Se pide al proveedor desde cualquier lado a pie** (ya era así en el código); red-autoridad fila 1 corregida.
- El carrito del proveedor se precarga con el sugerido **menos lo ya pedido para mañana** (D-0151.3b), así dos
  jugadores no piden dos veces lo mismo.

## Por qué
- `critico-diseno` marcó que el borrador prometía "enchufar los paneles tal cual" (tienen fondo, Cerrar y Esc
  propios), un estado de pose que el jugador no manda así, un celular que en el mundo Empresa no existe, choques
  de LB/RB, cruceta derecha y Esc, y dos hojas (Pedidos, Día) que copiaban el tablero y el HUD. Con los recortes
  D-1902 pasa de ~11 a ~5 días.

## Qué cambia
- D-1902 (título y alcance), D-0838 (en el tablero), D-1240 (recortada), D-0151.3b (sugerido menos lo pedido),
  fila 116 de `referencia-schedule-1.md` y fila 1 de `red-autoridad.md`.
