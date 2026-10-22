# 2026-10-22 · Dársena de proveedores (D-0621.c.a)

Decidido por `constructor-mundo` (subtarea D-0621.c.a, lógica pura). Detalle en
[detalle/F2-06-stock.md](../expansion-distritos/detalle/F2-06-stock.md), D-0621.c.

- **Decisión: cuando dos camiones de proveedores se pisan en la dársena, hacen cola.** Primera llegada, primera
  atendida (empate: el proveedor por defecto, después por id). El que llega con la dársena ocupada espera afuera y entra
  cuando se libra una bahía; **siempre se va a su hora de salida**, así que la espera se descuenta de su estadía.
- **Decisión: si al liberarse la bahía ya le toca irse, o su estadía recortada al día visible
  (`DAY_START_MIN..DAY_END_MIN`) queda vacía, el camión "no cabe"** (`no_room` / `outside_day`) y no ocupa bahía.
- **Decisión: una sola bahía hoy** (`CompanyTuning.SUPPLIER_DOCK_BAYS` = 1); `DockQueue.plan` ya recibe la cantidad, así
  D-0640 solo sube la constante.
- **Decisión: se resuelve con los horarios, sin red.** Es una función pura de las horas de llegada y salida del
  catálogo (igual en todos los peers); no hay sorteo ni RPC ni cambio de `PROTOCOL_VERSION`.
- **Decisión: los horarios de los `.tres` casi no se tocan.** El central (08:30 + 180) no se puede mover; solo la
  panadería pasa de 06:30 a 07:00 (sigue esperando 90 min) para que se vea: antes se iba a las 08:00, al abrir el día.
  Con eso los cinco proveedores pedidos el mismo día caben en una bahía, pegados uno a otro.
- Alternativas descartadas: segunda dársena ya (es D-0640); correr los horarios hasta que no se pisen (el central
  ancla el día y cualquier cambio de catálogo volvería a pisarlos).

Revisar al final: [revisar/D-0621.c.md](../expansion-distritos/revisar/D-0621.c.md).
