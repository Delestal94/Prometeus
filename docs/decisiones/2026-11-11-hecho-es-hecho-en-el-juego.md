# En la expansión, "hecho" es hecho en el juego (pasada de docs de F1)

**Decisión:** una tarea de la expansión lleva ✅ en su tabla y `[x]` en su detalle solo si lo que promete ocurre en
el juego. Si la lógica y su test están pero nadie la llama fuera de `tests/`, queda ◐ y `[~]`, con lo que falta en una
subtarea con casilla. Con esa regla, nueve filas de F1 volvieron de ✅ a ◐ el 2026-11-11.

**Por qué:** la rutina `desarrollador` elige la primera tarea que no está `[x]`
(`.claude/rutinas/desarrollador.md` §2). Un enganche pendiente escrito en prosa debajo de un `[x]` no lo toma nadie.
Así quedaron sin dueño justo las piezas que cierran el corte de F1: la puerta que cobra, la mesa que se usa, el
resultado de la salida. El bot las tapaba llamando a la lógica por su cuenta, y D-2016.4 ya no lo permite.

**Qué cambió de estado:**

| Tarea | Lo que no pasa en el juego | Subtarea que lo cierra |
|---|---|---|
| D-0306 | ningún `WorldGate` está en el mundo: nada cierra Campo ni Suburbio | D-0306.b (nueva) |
| D-0320 y D-0520 | nadie llama a `TripResult`: una salida no deja resumen, puntaje ni mérito | D-0320.b (nueva) |
| D-0701 | la mesa no tiene estación ni puntos de uso: no se puede armar una caja | D-0701.b (existía en prosa) |
| D-0702 | no se puede abrir una caja ni elegir tamaño | D-0702.b (existía en prosa) |
| D-0715 | faltan `order_packed`, las cajas vivas en el snapshot y el `_serial` guardado | resto de D-0715.b |
| D-0815, D-0816 y D-0817 | nadie llama a `OrderSettlement.settle`: la puerta no cobra, no califica ni reacciona | D-0815.b (con D-0340) y D-0817.b |

D-0340 (la puerta del cliente) recibió su bloque de detalle en `detalle/F1-03-distritos.md`: su fila está en
Ampliación pero es del cierre de F1 ([corte-vertical.md](../expansion-distritos/diseno/corte-vertical.md) §2 #13).

**La excepción:** una subtarea abierta que no está en la lista cerrada del corte (corte-vertical §2) no le saca el
✅ a su tarea. Lleva casilla y dice "fuera de la lista del corte". Es el caso de los votos (D-0518.b, D-0910.1), la
balanza (D-0713.b), desarmar (D-0719.b), la impresora (D-0805.b), los pedidos en espera (D-0811.b) y las dos de
direcciones (D-0312.1, D-0312.2). Ponerlas en ◐ haría que la rutina las construya antes de cerrar el corte.

**Lo que pasó de fase:** D-0315 con D-0315.b (Campo) y D-0616 (frío) dicen F2 en su fila y en su encabezado, como
ya había decidido la [revisión D-0140](../expansion-distritos/diseno/revision-diseno.md). No se toman hasta que
D-2016 cierre F1.

**Los "PR pendiente":** cada línea de estado nombra ahora el PR cuyo commit en `main` la escribió por primera vez
(sacado del historial de git, 215 líneas). Una sola se fijó a mano: D-0302.2.b.4 es el PR #685.

**Lo que no se decidió acá** (queda en [`revisar/docs-f1.md`](../expansion-distritos/revisar/docs-f1.md)): dónde va
el botón de la grúa, qué hacer con el frío que corre en F1, y si F2 espera también a D-2012, D-2013 y D-2017.

**Cómo volver atrás:** las marcas son texto. Revertir el PR devuelve los ✅; las subtareas con casilla se pueden
conservar igual.
