# F1 · Grupo 05 — Economía (detalle)

> Carril 4 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [05-economia.md](../05-economia.md) y se detalla cuando le toque a un
> carril. Números de [supuestos.md](supuestos.md) y de [diseno/economia.md](../diseno/economia.md).

### D-0501 · Billetera de la empresa — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `CompanyState.earn/spend/charge/can_afford/ledger_total` + `ledger` (historial de 200 movimientos, guardado con la empresa); `test_company_wallet`.
**Depende de:** D-0202
**Qué:** la plata sigue en `CompanyState.money` (S8: `CrewProgression.team_money` queda para Entrega/Endless),
ahora con un historial. Cada movimiento es `{day, minute, amount (con signo), reason, balance}`.
- `earn(amount, reason)`: suma; ignora montos ≤ 0.
- `spend(amount, reason)`: resta solo si alcanza (`can_afford`); si no, no cambia nada y devuelve `false`.
- `charge(amount, reason)`: resta aunque quede en rojo (alquiler, penalidades); qué pasa con saldo negativo
  es D-0510.
- `ledger_total(reason)`: suma con signo de los movimientos de un motivo (base del resumen D-0508).
- El historial guarda como máximo `CompanyTuning.LEDGER_MAX` (200); lo más viejo se descarta, la plata no.
  Va en `to_dict()` / `from_dict()` (sin subir `CompanySave.VERSION`: un campo que falta carga vacío).
- Los motivos son `StringName` libres (`order_paid`, `supplier`, `rent`…); cada tarea del grupo define los
  suyos. La señal `money_changed` de `EventBus` es D-0215 y se conecta ahí.
**Test** `test_company_wallet`: ganar y gastar registran día, minuto, monto, motivo y saldo; gastar de más no
cambia nada; `charge` deja en rojo; montos ≤ 0 se ignoran; la suma de movimientos da el saldo; el tope de
200; ida y vuelta por JSON; `new_company` y `reset` limpian.
**Hecho cuando:** el test pasa.

### D-0502 · Precio de un pedido — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `OrderPricing` (`scripts/gameplay/business/order_pricing.gd`): cotiza (productos, envío, requisitos, urgencia) y liquida con el bono por estado; `OrderGenerator` usa la misma cuenta; `test_order_pricing`.
**Depende de:** D-0802, D-0806, D-0117
**Qué:** funciones estáticas sin nodos. `quote(items, zone, requirement_ids, products, catalog)` devuelve
`{goods, shipping, requirements, urgency, total}`: unidades × precio de venta + envío de la zona, y cada
requisito sube la paga en cascada (igual que el generador); lo que suma `urgent` se informa aparte como
urgencia. `with_requirements` es esa cascada sola. `condition_bonus(pay, quality)` da +10 % si la calidad del
armado llega a 90; `settle(order, now_min, quality)` = `Order.payout` (−25 % si tarde) más ese bono.
Números nuevos en `CompanyTuning`: `CONDITION_BONUS_MIN_QUALITY = 90`, `CONDITION_BONUS = 0.10`.
**Test** `test_order_pricing`: 10 pedidos promedio (2 unidades a 80 + envío 40/60) suman 2100 = 10 × 210 de
`diseno/economia.md`; la cotización coincide con el `pay` de `Order.make`; desglose con `urgent` y `fragile`;
ids desconocidos no suman; bono por estado con y sin tardanza.
**Hecho cuando:** el test pasa.

### D-0503 · Costo de compra de mercadería — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — `SupplierPurchase` (`scripts/gameplay/business/supplier_purchase.gd`): `cost`, `pallet_cost`, `can_order` y `receive` (recibe el palet y cobra con motivo `supplier`); `test_supplier_purchase`.
**Depende de:** D-0501, D-0604
**Qué:** funciones estáticas sin nodos. El precio unitario es `ProductDefinition.buy_price` (20 a 80).
- `cost(product, qty, products)` = unidades × `buy_price`; producto desconocido o cantidad ≤ 0 cuesta 0.
- `pallet_cost(pallet, products)` y `can_order(wallet, pallets, products)`: al hacer el pedido solo se
  comprueba que la plata alcanza para todo; no se cobra nada.
- `receive(wallet, inventory, pallet, products)`: `Pallet.receive` y, si entró, `charge(costo, &"supplier")`.
  Palet inválido, repetido o de producto desconocido: `false` y no se cobra.
**Decisión:** se cobra al **recibir** (cuando el camión descarga), con `charge` y no `spend`: la mercadería ya
está en el galpón, así que el saldo puede quedar en rojo; qué pasa entonces es D-0510. Un palet que nunca
llega no cuesta.
**Test** `test_supplier_purchase`: 10 lámparas a 50 cuestan 500; recibir baja el saldo 500 y `ledger_total(&"supplier")`
da -500; las unidades quedan en `pallet:<id>`; recibir dos veces o un palet inválido no cobra; `can_order`
mira el pedido entero; recibir sin saldo lo deja en rojo.
**Hecho cuando:** el test pasa.

### D-0504 · Costo de materiales de embalaje — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-05, PR pendiente)** — `PackagingSupplies` (`scripts/gameplay/business/packaging_supplies.gd`): relleno, cinta, etiqueta y sellos se cobran al hacerse, con motivo `packaging`; `test_packaging_supplies`.
**Depende de:** D-0501, D-0212
**Qué:** funciones estáticas sin nodos sobre un `PackedBox` y la billetera (`CompanyState`). La caja vacía ya la cobra `BoxDispenser` (motivo `boxes`); esto es el resto. Precios en `CompanyTuning`: relleno 1 por celda, cinta 1, etiqueta 0, sello 0.
- `pad(box, cells, wallet)`: rellena hasta `cells` celdas libres y cobra solo las que rellenó; todo o nada si no alcanza la plata. Devuelve cuántas rellenó.
- `tape`, `label`, `stamp`: cobran su precio y marcan la caja; repetir cinta o sello, o una etiqueta/sello vacío, devuelve `false` sin cobrar.
- `used_cost(box)`: lo que ya gastaron los insumos de esa caja (para el resumen D-0508).
**Decisión:** se cobra cada paso al hacerlo (no al cerrar la caja), con `spend` y no `charge`: sin plata no se puede seguir embalando, a diferencia de la mercadería ya descargada (D-0503). Una caja abandonada solo cuesta lo usado. Los pasos de la mesa (relleno D-0705, cinta D-0706, etiqueta D-0707) llaman a esta clase.
**Test** `test_packaging_supplies`: rellenar 3 celdas cobra 3; pedir de más se limita a las libres; cinta se cobra una vez; etiqueta y sello rechazan repetidos y vacíos; con 2 de saldo, 3 celdas no entran (la caja y el saldo no cambian) y 2 sí; el libro suma `packaging` y `used_cost` coincide.
**Hecho cuando:** el test pasa.
