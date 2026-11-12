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
4. **Daño:** una caja rota entrega todas sus unidades rotas; abollada o abierta, ninguna (la paga no baja por eso). "Rota" es
   la regla del cierre de la salida (`TripCargo.is_broken`): arruinada, o con el contenido afuera sin restaurar
   (`care.needs_restore`), aunque la hayan encintado. Esa caja se lee abollada (`AT_RISK`) y antes de la revisión pagaba
   como intacta.
5. **Caja equivocada en la casa correcta:** se entrega con la regla de `OrderPenalties` (paga `WRONG_BOX_PAY_FACTOR` = 0,
   −reputación, 1 estrella). No se agregó un rechazo nuevo.
6. **La reacción del cliente (D-0817.b)** la arma `CompanyDoor` en cada peer al aplicar `order_delivered`, con las estrellas
   del host, la semilla y el número de la casa, y usa la escena que `DoorReaction` ya tiene: festejo = `delivered_ok`,
   encogerse = `delivered_at_risk`, enojo = `delivered_ruined`. El sonido del vecino sale de esa misma escena, en cada peer:
   no del estado de la caja (una caja impecable a la que le falta un producto no festeja).
8. **Antes de cobrar, la puerta comprueba que `order_delivered` va a salir** (`CompanyOrdersNet.delivered_ok` sobre los ids y
   la reputación, y que `CompanyNet` no esté aplicando otro evento). Si saliera rechazado después de cobrar, el libro
   compartido dejaría el pedido afuera y el cierre lo cobraría −3 con la caja ya entregada.
9. **La caja devuelta solo se oye en el host** (gruñido, sin gesto). Retransmitirla a los clientes pide un RPC y frases nuevas
   sin la etiqueta de la caja del reparto clásico: queda para D-0340.5, junto al cartel del porche.
7. **Las unidades del paquete** (`package:<caja>`) salen del inventario con `consume`; si lo prometido a otros pedidos no las
   deja salir, con `discard` (achica esas reservas). Ya son del cliente.

## Por qué

Es lo más chico que cumple la fila 20 de `red-autoridad.md` sin tocar la casa del reparto ni `company_net.gd` más que una
línea, y reusa `OrderSettlement`, `OrderPenalties`, `OrderRating`, `OrderDoorReaction` y `DoorReaction` tal como estaban.

## Lo que queda abierto

`auditor-red` sobre el diff, el bot por la puerta (D-2016.4) y, en D-0340.5, el cartel del porche que sigue a los pedidos y
la negativa de la puerta vista y oída por los clientes.
Detalle en `docs/expansion-distritos/revisar/D-0340.md`.
