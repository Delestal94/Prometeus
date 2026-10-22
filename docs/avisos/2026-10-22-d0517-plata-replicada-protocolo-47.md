# Protocolo 47: la plata de la empresa por red (D-0517)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 47** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea del
  historial. Ninguna firma ni RPC de `NetworkManager` / `NetSession` cambió y `modules/net_session/` no se tocó.
  **Cambió el protocolo** aunque no hay RPC nuevo: `CompanyNet._apply_event` (canal confiable de siempre, con `seq`)
  acepta un tipo nuevo de evento del host, `wallet_moved {amount, reason, money, minute}`. Un cliente con 46 y un host
  con 47 no se conectan (error de versión en el menú); con el mismo número viejo el cliente descartaría el evento y se
  quedaría con otro saldo. El PR #630 (D-0618.b) se mezcló antes con 46: este pasó a 47 y dejó
  la línea del otro (`docs/convenciones-godot.md` §6.3).
- **`scripts/core/company/company_wallet_net.gd`** (nuevo, `class_name CompanyWalletNet`, `RefCounted`): arma
  (`moved()`, host) y aplica (`apply()`, cada peer) `wallet_moved` con el mismo patrón que construir/vender y la mesa
  de empaque: cada peer parte del saldo del host antes del movimiento (`money - amount`), hace un `earn()` o un
  `charge()` (puede quedar en rojo) y la entrada del libro toma el minuto del host. Un peer con otro saldo se corrige y
  pide snapshot (`take_drift()`). Valida todo como dato de red: ints en rango (nada de float), `reason` id corto en
  minúsculas.
- **`CompanyNet`** (agregados, sin cambiar firmas): `WALLET`, `wallet`, `publish_wallet(amount, reason) -> bool`
  (host; falso en un cliente) y el tipo en `EVENT_KINDS` y `HOST_EVENT_KINDS` (no es pedido: un cliente no puede
  mover la plata). Para que `company_net.gd` entre en las 1000 líneas de gdlint, el chequeo de `units_take` y
  `units_store` pasado la estación salió tal cual a `CompanyAsk.take()` / `CompanyAsk.store()`.
- `CompanyLayoutNet._set_balance` / `CompanyTableNet._set_balance` y sus `_entry_minute` usan ahora
  `CompanyWalletNet.set_balance()` / `entry_minute()` (mismo comportamiento y mismo aviso en el log);
  `CompanyLayoutNet.MAX_MONEY` vale lo mismo, tomado de `CompanyWalletNet.MAX_MONEY`.
- Test nuevo: `test_company_money_net` (solo, espejo y host + 2 clientes ENet).

## Qué tiene que hacer Slatex

Nada obligatorio: ningún cobro del juego pasa todavía por el evento. Cuando un cobro sin pedido se conecte al mundo
compartido (cobro en la puerta, propina, alquiler, proveedor, tienda, ampliación, deshacer), en el host va
`net.publish_wallet(monto_con_signo, motivo)` en lugar de `CompanyState.earn()` / `spend()` / `charge()`; lo que se
chequea antes (si alcanza la plata: `can_afford()`) lo sigue haciendo quien cobra. El HUD sigue escuchando
`EventBus.money_changed`, que ahora salta también en cada cliente.
