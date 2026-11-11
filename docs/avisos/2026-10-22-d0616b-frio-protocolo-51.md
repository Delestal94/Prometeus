# Protocolo 51: lo frío que se echa a perder, por red (D-0616.b)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 51** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea del
  historial. `main` y las ramas abiertas estaban en el 50 (se miraron los PRs abiertos que tocan el archivo: ninguno).
  Ningún RPC cambió, pero `CompanyNet._apply_event` acepta un tipo nuevo, `units_spoiled` `{product, qty, location}`
  (canal confiable de siempre, con `seq`): un cliente con 50 lo descartaría y su stock quedaría con leche que el host
  ya tiró (`docs/convenciones-godot.md` §6).
- **`scripts/core/company/company_cold_net.gd`** (nuevo, `CompanyColdNet`): arma el evento y lo aplica en cada peer
  con `Inventory.discard`. `CompanyNet` lo suma a `EVENT_KINDS` / `HOST_EVENT_KINDS` (el host lo publica por su
  cuenta, un cliente no puede pedirlo) y saca `cold_clocks` de la parte `company` del snapshot.
- **`scripts/gameplay/business/cold_chain_tick.gd`** (nuevo, solo host): cada minuto de juego del galpón envejece lo frío
  fuera de la heladera. Sin cambios de firmas en `ColdChain` (suma `age`, `note_moved`, `ages_at`, `is_ticking`,
  `forget_empty`); `CompanyState` suma la clave opcional `cold_clocks` (un guardado viejo carga igual).
- Contrato: `docs/expansion-distritos/diseno/red-autoridad.md` §14. Test nuevo: `test_company_cold_chain_world`.

## Qué tiene que hacer Slatex

Nada. Si una rama tuya sube `PROTOCOL_VERSION`, la próxima libre es 52.
