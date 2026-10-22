# D-0606.b: el autoelevador en red, arreglos de la auditoría de red

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

Arreglos que pidió `auditor-red` sobre el autoelevador del galpón (mismo PR que
[2026-10-22-d0606b-autoelevador.md](2026-10-22-d0606b-autoelevador.md)).

## Qué cambió

- **Protocolo:** sigue en **47** (lo subió este mismo PR, todavía sin mezclar; 45 y 46 son de main: cajas sueltas D-0316.3 y
  `jack_departed` D-0618.b). La petición `fork_act` con
  `act: mast, dir: 0` acepta ahora `at_height` (float, opcional: la altura que dibuja el conductor al soltar la
  tecla) y el host puede rechazar un `mast` que no cambia nada (`no_change`), `board` con las manos ocupadas
  (`hands_busy`) y `leave` fuera de lugar (`no_room`). Ningún RPC ni sincronizador nuevo; solo cambió el texto de la
  línea 47 del historial en `scripts/core/network_manager.gd`.
- **`scripts/core/company/company_net.gd`** (zona compartida, sin firmas cambiadas, queda en 1000 líneas):
  `_on_object` pasa por `CompanyPallets.check_for(net, peer, kind, data, station)`, que pone el `peer` del que pide
  por encima de lo que diga la estación y, para `fork_act`, `hands_free` y `lag` (ida y vuelta, `NetStats`);
  `_let_go(peer)` (en `peer_removed` / `peer_disconnected`) suelta el autoelevador que manejaba ese peer al
  instante, donde está su jugador (`CompanyPallets.let_go`).
- **`scripts/gameplay/player/player_carry.gd`** (Slatex): `transfer_target()` saltea a un compañero con la meta
  `driving`. **`scripts/gameplay/package/package_handling.gd`** (Slatex): `transfer()` no le pasa la caja a quien
  tiene la meta `driving`. La meta la pone `ForkliftView` en el `Player` del conductor, en todos los peers, mientras
  maneja (`ForkliftView.DRIVING_META`), y la saca al bajarse.
- **`scripts/gameplay/interaction/pallet_jack_point.gd`** (Slatex): `can_interact()` nuevo (override), falso con
  el asiento ocupado (`taken`); antes salía igual por `get_prompt()` vacío.
- **`translations/strings_world.csv`**: clave nueva `WORLD_FORKLIFT_NO_PARK` ("No hay lugar para bajarte acá…").

## Qué tiene que hacer Slatex

Nada. Si agregás otro vehículo que se maneja a pie, poné la meta `driving` en el `Player` mientras lo maneja y
nadie le va a pasar una caja.
