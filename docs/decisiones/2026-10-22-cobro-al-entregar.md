# Decisión: la paga de un pedido se cobra al entregar (D-0516)

- **Qué:** la paga y la propina entran a la billetera de la empresa en el minuto de la entrega
  (`OrderSettlement.settle()`, motivo `order_paid` y `tip`). El cierre del día no cobra.
- **Por qué:** feedback inmediato en un coop; evita un estado "por cobrar" que habría que replicar,
  guardar y mostrar; `diseno/economia.md` ya asume la paga en el día de la entrega.
- **Lo que queda afuera al cierre:** no cobra (`FAILED`, D-0302.1).
- **Cambio de código:** ninguno, ya era así desde D-0815; se fija con `test_order_settlement`.
