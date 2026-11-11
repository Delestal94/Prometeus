# 2026-10-22 · El autoelevador en el mundo (D-0606.b)

Decidido por la sesión que hizo D-0606.b. Detalle en [detalle/F1-06-stock.md](../expansion-distritos/detalle/F1-06-stock.md), D-0606, y
[revisar/D-0606.md](../expansion-distritos/revisar/D-0606.md).

- **Decisión: manejar es caminar.** El autoelevador no es un cuerpo físico con red propia: va debajo del `Player` del conductor y todos los
  peers lo dibujan donde está ese jugador (su pose ya se replica). Cero tráfico por frame, ningún `MultiplayerSynchronizer` nuevo y el
  conductor usa el movimiento normal. El host juzga por dónde está el conductor. Costo: sin física de vehículo (velocidad, giro, colisión de las
  horquillas); queda en D-0606.c.
- **Decisión: el estado discreto va por los eventos de `CompanyNet`, sin RPC nuevo.** Una petición (`fork_act {act}`) y un evento
  (`fork_state`); tomar y dejar reusan `jack_picked` / `jack_placed` con `by` y `slot`. `PROTOCOL_VERSION` 48 por las listas de `CompanyNet`
  y la parte `pallets` del snapshot.
- **Decisión: el mástil se integra por tiempo, con ráfagas de 0,5 s.** El host dice "sube / para / baja" y cada peer integra con su reloj; cada
  evento lleva la altura del host. El conductor repite el pedido mientras sostiene la tecla: un "parar" perdido no manda las horquillas al tope.
  El "parar" lleva la altura que dibujó el conductor y el host la toma acotada a lo que suben en su ida y vuelta (con lag, las horquillas
  quedan donde el conductor las vio, no un ping más arriba).
- **Decisión: una sola mano para la zorra y el autoelevador.** Comparten el libro `PalletJack` y su `carrying`; `forklift.holds` dice cuál lo
  lleva y el otro rechaza.
- **Decisión: el hueco de rack es la cubierta del estante** (`<estante>-<nivel>`), para tener racks altos sin una pieza nueva; un rack propio
  queda como alternativa en revisar/D-0606.md.
- **Decisión: el conductor toma la tecla de interactuar con una meta del jugador** (`interact_override`: `use` y `prompt`), en vez de un
  cambio de estado en `Player`; así `player.gd` no crece y otro vehículo a pie puede usarla.

Revisar al final: [revisar/D-0606.md](../expansion-distritos/revisar/D-0606.md).
