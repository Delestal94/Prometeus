# 2026-10-22 · Los pedidos en el mundo de la empresa: tope y poda del libro (D-0813.1)

Decidido por `constructor-red` al construir D-0813.1, con lo que pidió la revisión de `auditor-red` de D-0813
([revisar/D-0813.md](../expansion-distritos/revisar/D-0813.md), "Para D-0813.1"). Detalle en
[detalle/F1-08-pedidos.md](../expansion-distritos/detalle/F1-08-pedidos.md), D-0813, y en el contrato
[diseno/red-autoridad.md](../expansion-distritos/diseno/red-autoridad.md) §10.

- **Decisión: `CompanyOrdersNet.MAX_ORDERS` baja de 4096 a 256** (16 días de la tripulación más grande,
  `ORDERS_MAX_PER_DAY`). Con 4096 el libro lleno pesaba 2,4 MB de los 4 MB del snapshot y tardaba 230 ms en
  validarse en un cliente que entra tarde; con 256, en proporción, unos 150 KB y unos 15 ms.
- **Decisión: el libro poda al abrir cada día**, en cada peer, adentro del `day_phase` que abre un día nuevo
  (`DayCycle.apply_phase()` → `CompanyOrdersNet.prune_closed()`): suelta los entregados, fallados y cancelados (todos de
  días anteriores) y se queda con los abiertos, armados, en camino y atrasados de cualquier día. Sin evento nuevo ni
  cambio de protocolo: cada peer hace lo mismo en el mismo `seq`.
- **Decisión: los pedidos entran y vencen solo con el día abierto** (`OPENING` y `OPERATING`), a la hora del galpón
  (`DayCycle.shed_minute()`): ni en el cierre ni en el resumen.
- **Consecuencia aceptada por ahora:** hasta que un evento cierre pedidos del libro compartido (D-0815.b, D-0302,
  D-0807.b) la poda no suelta nada, así que una sesión de más de 16 días seguidos con 8 jugadores llena el libro y deja
  de recibir pedidos. El libro no se guarda (D-0206): salir y volver a entrar lo vacía.

Revisar al final: [revisar/D-0813.1.md](../expansion-distritos/revisar/D-0813.1.md).
