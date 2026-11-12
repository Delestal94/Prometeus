# La puerta del cliente en el mundo Empresa (D-0340, D-0815.b, D-0817.b)

**Fecha:** 2026-11-11 · **Decidió:** la rutina, por recomendación (nadie para preguntar) · **Tarea:** D-0340

## Qué se decidió

1. **La casa le pregunta a la puerta.** En el mundo Empresa `DeliveryHouse` no espera una caja fija (`assigned_package_id`):
   `CompanyDoor.ring()` busca entre las salidas afuera un pedido de esa casa cuya caja (el libro de la salida,
   `CompanyTrips.book.box_of()`) sea la que se tocó. Si no hay, la caja vuelve a las manos (`wrong_package_offered`). El
   gancho es opcional (`door_check`): la casa del reparto clásico no cambia.
2. **La casa no se traba en el mundo Empresa.** Tocar sin caja solo suena; una casa recibe varios pedidos el mismo día o el
   siguiente.
3. **La plata viaja aparte, la reputación dentro.** `order_delivered` cierra el pedido en cada libro con la paga y las
   estrellas del host; la plata sale después como `wallet_moved` (`order_paid`, `tip`), por `CompanyNet.publish_wallet`,
   nunca con `company.earn` del host solo. La reputación que mueve `settle()` es la del host (como en `order_closed`) y viaja
   absoluta en `order_delivered`: cada peer toma la del host. Así un cliente queda al día en cada entrega, también de lo que
   un `order_closed` le dejó desfasado.
4. **Daño:** una caja arruinada entrega todas sus unidades rotas; abollada o abierta, ninguna (la paga no baja por eso).
5. **Caja equivocada en la casa correcta:** se entrega con la regla de `OrderPenalties` (paga `WRONG_BOX_PAY_FACTOR` = 0,
   −reputación, 1 estrella). No se agregó un rechazo nuevo.
6. **La reacción del cliente (D-0817.b)** la arma `CompanyDoor` en cada peer al aplicar `order_delivered`, con las estrellas
   del host, la semilla y el número de la casa, y usa la escena que `DoorReaction` ya tiene: festejo = `delivered_ok`,
   encogerse = `delivered_at_risk`, enojo = `delivered_ruined`.
7. **Las unidades del paquete** (`package:<caja>`) salen del inventario con `consume`; si lo prometido a otros pedidos no las
   deja salir, con `discard` (achica esas reservas). Ya son del cliente.

## Por qué

Es lo más chico que cumple la fila 20 de `red-autoridad.md` sin tocar la casa del reparto ni `company_net.gd` más que una
línea, y reusa `OrderSettlement`, `OrderPenalties`, `OrderRating`, `OrderDoorReaction` y `DoorReaction` tal como estaban.

## Lo que queda abierto

`auditor-red` sobre el diff, el bot por la puerta (D-2016.4) y el cartel del porche que sigue a los pedidos (D-0340.5).
Detalle en `docs/expansion-distritos/revisar/D-0340.md`.
