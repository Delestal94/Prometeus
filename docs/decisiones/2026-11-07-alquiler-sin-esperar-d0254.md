# El alquiler se engancha sin esperar a D-0254 (D-0509.b)

**Decisión:** D-0509.b se hace antes de D-0254, aunque el detalle lo hacía depender de ella. El cobro vive en un nodo
nuevo, `FixedCostsHook`, y `company_root.gd` solo suma dos líneas (el enganche y su comentario).

**Por qué:** D-0254 existe para que enchufar puerta y cobro no empuje `company_net.gd` (999 líneas) ni
`company_root.gd` contra el tope de 1000 del lint ([revisión D-0140](../expansion-distritos/diseno/revision-diseno.md),
R-16). Este enganche no toca `company_net.gd` y deja `company_root.gd` en 945. El riesgo que D-0254 cuida no aparece
acá, y D-0251, la dependencia que sí protege el guardado, ya está hecha. D-0254 sigue abierta para D-0340.

**Cómo queda el cobro:**

- En `CLOSING`, en el host, una vez por día, con el mismo evento para las 20:00 y para `close_early()`. Cerrar antes no
  esquiva el alquiler.
- Va por `CompanyNet.publish_wallet` (`wallet_moved`), no por `CompanyState.charge()`: todos los pares ven la misma plata y
  el mismo libro. No cambia `PROTOCOL_VERSION`: no hay evento ni campo nuevo.
- `FixedCostsHook` se engancha después de `SupplierAutoOrderHook`. El pedido automático lee una billetera que todavía no
  pagó el alquiler y lo aparta él mismo; al revés, lo apartaría dos veces y compraría de menos. `test_company_root` fija
  ese orden.
- Un día cortado no deja nada: el slot es la apertura de ese día (D-0251), así que al volver a jugarlo paga una sola vez.

**Lo que hay que saber:** la puerta todavía no cobra en el juego (D-0340 sigue abierta: fuera de `tests/` no hay
ninguna llamada a `OrderSettlement.settle`). Mientras tanto el día solo resta: una empresa nueva queda en 0 al cerrar el
día 5 y en rojo el 6, y desde ahí abre con el 60 % de los pedidos y el aviso de quiebra. Es lo que dice el plan de
la revisión D-0140 (las cuatro tareas forman un bloque), no un cambio de números.
