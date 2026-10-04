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
