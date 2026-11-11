# El proveedor cobra al primer apoyo de cada palet (D-0503.b)

**Decisión:** la mercadería del proveedor se cobra en el host en el momento en que un palet del camión se apoya por
primera vez (en el piso con la zorra o en un estante con el autoelevador), que es cuando sus unidades entran al stock. Se
cobra una vez por palet, sus unidades al precio del proveedor cuyo camión lo trajo, como un `wallet_moved` con motivo
`supplier`. No cambia ningún precio de `company_tuning.gd` ni del catálogo.

**Por qué ahí y no en otro lado:**

- D-0503 ya lo decía: "se cobra al **recibir** (cuando el camión descarga)", con `charge` y no `spend`, así que puede
  dejar la caja en rojo (D-0510). D-0614 y D-0618 repiten que "la billetera solo paga lo que llegó" y que el remito solo
  registra el faltante. El primer apoyo es ese "recibir": es el único momento en que `PalletJack` mete las unidades en el
  `Inventory` (su `received`), y ya era una vez por palet.
- **El remito (D-0614)** se arma cuando el camión se va: cobrar ahí haría que un palet descargado a las 08:40 se pague a
  las 11:30 y que un día cortado antes de esa hora tenga la mercadería sin el gasto en el resumen parcial.
- **El cierre** junta el gasto con el alquiler, pero deja un día entero con mercadería gratis y obliga a guardar qué falta
  cobrar (otro dato en el save). El primer apoyo no necesita nada nuevo en el save: el `received` del libro de palets y la
  billetera se guardan juntos (el día cerrado) o no se guardan (un día cortado vuelve a su apertura, D-0251).
- Lo que el camión se lleva (D-0618) nunca se apoyó: no se paga. Un palet que no entró en el libro (D-0607.b) tampoco.

**Cómo queda:**

- `SupplierBillHook` (`scripts/gameplay/supplier_bill_hook.gd`) escucha `jack_placed` en el host, como `FixedCostsHook`
  (alquiler) y `SupplierAutoOrderHook`. Lo engancha `CompanySupplierLink` después de cargar el catálogo; no toca
  `company_root.gd` ni `company_net.gd` (D-0254 los está partiendo en otro carril).
- Qué palet entró lo dice el libro (`PalletJack.take_received()`): mover otra vez un palet ya recibido no cobra.
- El precio sale de `SupplierPurchase.bill`, con el mismo `SupplierOrderCart.unit_cost` que mostró el tablero al pedir:
  el palet de otro proveedor (D-0621) paga el `price_factor` de ese proveedor.
- Sin protocolo nuevo: no hay evento ni campo nuevo, el cobro es un `wallet_moved` más.

**¿Una empresa nueva puede jugar el día 1?** Sí, sin cambiar nada: el día 1 no hay camión. Lo que hay en el galpón al
abrir es el palet regalado de [economia.md](../expansion-distritos/diseno/economia.md) §3 (`DefaultShed`, 10 unidades que
"valen 500 a precio de compra"), que no viene en un camión y no se cobra. El primer camión llega el día 2 con lo pedido el
día 1, y el tablero solo acepta un pedido que la caja cubre al momento de pedirlo; el pedido automático (D-0151.3b) además
aparta el alquiler y 100 de reserva.

**Lo que hay que saber:** la puerta todavía no cobra en el juego (D-0340 abierta), así que el día solo resta. Con el
proveedor cobrando, una empresa que compra quiebra antes que con el alquiler solo (que la dejaba en 0 el día 5): el
pedido automático gasta lo que sobra sobre alquiler más reserva y al día siguiente se paga. Es esperable mientras falte
D-0340, no un problema de los números; la ganancia del corte vertical (ingresos − costos − alquiler) se mide cuando las
dos puntas estén enchufadas.
