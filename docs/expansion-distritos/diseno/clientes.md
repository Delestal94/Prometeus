# Clientes: horario y ventanas de entrega

Escrito por D-0136 (grupo 01). Define **cuándo recibe un cliente** en el modo Empresa: hasta qué hora entra un
pedido, contra qué reloj corre su ventana, qué pasa a las 20:00 y qué pasa con lo que no se entregó al cierre.
Lo construye **D-0851** (grupo 08). Entrega y Endless no cambian.

Lo que ya estaba decidido y no se toca:

- Día de 08:00 a 20:00, 1 h de juego = 90 s reales; a las 20:00 no se corta una salida, el cierre espera a que
  vuelva (S3, [supuestos](../detalle/supuestos.md)).
- Los pedidos entran de 08:00 a 19:00 (`ORDER_LAST_ARRIVAL_MIN`), con la curva de `ORDER_HOUR_WEIGHTS`; jugando
  solo, hasta las 15:00 del galpón (`SOLO_ORDER_LAST_ARRIVAL_MIN`, [roles-tripulacion.md](roles-tripulacion.md)
  §6.2).
- Ventana de 4 h desde que entra (`ORDER_WINDOW_MIN`). Pasada la ventana el pedido queda `late` y se cobra
  −25 % (`LATE_PENALTY`); un atrasado que no salió a la ruta lo abandona el cliente una ventana después
  (`ORDER_ABANDON_MIN`, D-0807): paga 0 y cuesta −3 de reputación.
- Los pedidos **entran y vencen con la hora del galpón** (`DayCycle.shed_minute()`, S4): con el galpón congelado
  no entra ninguno y la ventana no corre (D-0813.1).
- El libro de pedidos no se guarda: cada día los sortea de nuevo con la semilla ([guardado.md](guardado.md)).
- **Horarios por cliente** (la tienda que abre a las 9, D-0825) están pospuestos a post-lanzamiento
  ([crítica de alcance](critica-alcance.md), P4). Acá hay **un solo horario para todos**.

## 1. Reglas

1. **Un cliente recibe mientras el día está abierto.** Todos los clientes de todas las zonas reciben desde las
   08:00 hasta que vuelve la última salida del día. No hay clientes que abran más tarde ni que cierren antes, y
   una caja nunca vuelve porque "el cliente ya no estaba".
2. **De noche no sale nadie.** Desde las 20:00 (fase `CLOSING`) ningún vehículo empieza una salida: la salida
   del predio se niega como cualquier `departure_verdict` en contra (clave nueva al lado de `FAR_LIMIT`), con el
   aviso `UI_COMPANY_GATE_DAY_CLOSED` ("El día cerró: ya no se sale a repartir"). Lo mismo después de un cierre
   anticipado (D-0253). `CompanyTrips` no conoce la fase del día: recibe un `Callable` `day_open`, como
   `minute_now`. **Un vehículo que cruza igual la salida rechazado en `CLOSING` no frena el resumen**: hoy queda
   en `_refused_out` y cuenta en `trips_out()`, así que cualquiera trabaría el día saliendo vacío después de
   las 20:00; en `CLOSING` el resumen espera solo a las salidas de verdad. "Los clientes no reciben de noche"
   quiere decir esto: lo que no salió antes de las 20:00 ya no sale.
3. **Lo que ya está en la ruta se entrega igual.** Una salida que partió antes de las 20:00 sigue: el cliente
   abre aunque sean las 20:40 y ya esté oscuro (D-0325 lo muestra de noche). Se cobra con la misma regla de
   tardanza que a cualquier hora (regla 4). Así una salida que se fue a las 19:50 hacia el Campo no se castiga
   por llegar a la noche, solo por el reloj de su pedido.
4. **La tardanza se mide con la hora del galpón**, la misma con la que corrió la ventana: al entregar,
   `OrderBook.mark_delivered(id, ..., when)` recibe `floori(shed_minute())`, no el minuto del mundo de la
   salida (`CompanyTrips.minute()`). Si se midiera con el mundo, el que juega solo y sale con el galpón
   congelado llegaría "tarde" a un pedido cuya ventana no corrió (con 3 salidas de ~3 min reales el mundo va
   ~6 h adelante del galpón: el galpón marca ~14:00 cuando el mundo marca 20:00, [roles-tripulacion.md](roles-tripulacion.md)
   §6.2). Con alguien en el galpón los dos relojes dan lo mismo. Asimetría aceptada: jugando solo casi nada
   llega a vencer, así que el que juega solo casi nunca pierde reputación al cierre (coherente con S4).
5. **La ventana no se recorta al final del día.** Un pedido que entra a las 18:30 vence a las 22:30 del galpón,
   aunque el día cierre a las 20:00: no hay tope. Recortarla haría que los pedidos de la tarde nazcan casi
   vencidos y que el cierre los cobre como atrasados sin que la tripulación haya tenido tiempo.
6. **En `CLOSING` se sigue venciendo.** Desde las 20:00 no entran pedidos, pero el paso de pedidos del host
   sigue publicando vencimientos (`order_expired`) y abandonos (D-0807, que así queda enganchado en el mundo
   Empresa) con la hora del galpón mientras se espera a las salidas. Si no, un pedido que vence durante la
   espera quedaría `open` y la regla 7 lo cancelaría gratis.
7. **Al cierre de las 20:00, lo que no se entregó se resuelve.** Lo hace el host **en `CLOSING`**, en el `poll`
   donde `trips_out() == 0`, **antes** de pasar a `SUMMARY`; `SUMMARY` llega en el `poll` siguiente, así
   `DaySummary.build()` ya ve todo. Cada pedido que queda sin entregar:
   - `late` (ya vencido) → `failed` como un abandono: paga 0 y cuesta `ABANDONED_REPUTATION` (−3,
     `OrderPenalties.abandoned`). La tripulación tuvo su ventana entera;
   - todavía en ventana (`open` o `packed`) → `cancelled`: paga 0 y **no** cuesta reputación ("el cliente lo
     pidió a otro"). Le llegó tarde en el día; castigarlo sería castigar la curva de llegada, no a la
     tripulación;
   - uno que salió y volvió sin entregarse ya lo cerró la salida (`Trip.close` → `failed`): cuesta lo mismo que
     un vencido (−3), lo cobra D-0851 si la salida no lo hizo;
   - la caja armada para un pedido que no se entregó ya va al bulto de devolución al guardar
     ([guardado.md](guardado.md) §3, D-0252): no hace falta nada más.
   Con esto ningún pedido pasa al día siguiente: hoy `prune_closed()` de la apertura deja en el libro los que no
   están cerrados, con minutos del día anterior que nunca vencen (el minuto del día nuevo es más chico). Es el
   hueco que tapa D-0851. No hay tope de reputación por día en F1 (el de siempre es por pedido, −10): un día con
   8 vencidos cuesta −24, y es un día muy malo de verdad; lo mide D-0844.
8. **Cierre anticipado: todo lo no entregado falla.** Con D-0253 (el host cierra antes), cada pedido sin entregar
   pasa a `failed` con −3, esté o no en ventana. Así lo pide [guardado.md](guardado.md) regla 2 ("se penaliza
   igual que a las 20:00, así que no sirve para esquivar nada"): si se cancelara gratis lo que está en ventana,
   cerrar a las 12:00 borraría sin costo cualquier mañana que salió mal. La cancelación gratis es solo del
   cierre de las 20:00. Para el que se tiene que ir, la salida sigue siendo cerrar: pierde reputación por lo que
   dejó, pero se guarda lo hecho.
9. **Sin avisos nuevos en F1.** El aviso de `company_day_closing` (20:00) ya existe; D-0851 le suma "Los clientes
   reciben solo lo que ya está en camino". Un aviso a las 19:00 y una línea "Sin entregar" en el resumen quedan
   para Pulido (§2): el resumen de F1 ya muestra la reputación del día.
10. **Red:** todo lo decide el host. La negativa de la salida ya viaja como la de cualquier `departure_verdict`
   (D-0302). El cierre de cada pedido viaja como un evento de pedido nuevo de `CompanyOrdersNet` (hoy solo hay
   `order_added` y `order_expired`; se suma uno de cierre, que sirve también para el abandono de la regla 6), no
   dentro de `day_phase`: así cada espejo cambia su libro por el evento y la reputación la escribe solo el host
   (los espejos nunca escriben `CompanyState`, `day_cycle.gd`), sin tocar las claves del resumen. Ver
   [red-autoridad.md](red-autoridad.md) §10.

## 2. Lo que no entra

- **Ventanas que abren más tarde** ("entre las 14 y las 16") y horarios por cliente: D-0825, pospuesta.
- **Clientes que salen a recibir o esperan afuera**: D-0339, pospuesta.
- **Luz del porche o de la casa encendida de noche**: es decorado de D-0325 / D-1542, no regla. Si se hace, que
  sea por la hora del mundo.
- **Penalidad por llegar de noche**: no hay (regla 3). La tardanza ya la cobra el reloj del pedido.
- **Aviso de la última hora (19:00) y línea "Sin entregar" en el resumen**: Pulido, cuando se pula el resumen
  del día; el aviso no puede decir "queda para mañana" (nada pasa al día siguiente, regla 7).

## 3. Quién lo construye

| Qué | Tarea | Dónde |
|---|---|---|
| Negar la salida en `CLOSING` y no esperar a la rechazada (regla 2) | D-0851 | `CompanyTrips.departure_verdict` + `day_open` |
| Tardanza con la hora del galpón al entregar (regla 4) | D-0851 (con D-0815.b, que engancha la puerta) | quien llame a `mark_delivered` |
| Vencer y abandonar en `CLOSING` (regla 6) | D-0851 | `CompanyDayOrders.poll` |
| Resolver lo no entregado al cierre y al cierre anticipado (reglas 7 y 8) | D-0851 | `OrderBook.close_day(early)` + evento de cierre en `CompanyOrdersNet` + `DayCycle.poll` en `CLOSING` |
| Texto del aviso de las 20:00 (regla 9) | D-0851 | aviso de `company_day_closing` |
| Verse de noche (regla 3) | D-0325 | `WorldMood` |

Test de D-0851 (`test_company_day_close_orders`): un día que cierra a las 20:00 con un pedido vencido, uno en
ventana, uno que vence durante `CLOSING` y uno que volvió sin entregarse da `failed` −3, `cancelled` 0, `failed`
−3 y −3; el mismo día cerrado antes da todo `failed`; un vehículo que sale después de las 20:00 es rechazado y el
resumen no lo espera; host y cliente por ENet terminan con el mismo libro y la reputación solo cambia en el host.
