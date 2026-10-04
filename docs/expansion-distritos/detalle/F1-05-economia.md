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
