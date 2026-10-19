# D-2002.3: en el mundo de la empresa el jugador manda su pose 15 veces por segundo

**Fecha:** 2026-10-19 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`scripts/gameplay/player/player.gd`** (tuyo): función nueva `set_on_foot_pose_rate(rate_hz: float)` y dos
  variables privadas (`_on_foot_pose_rate`, `_scene_pose_interval`). Nada de lo que ya existía cambió de firma.
  Con 0 (lo de siempre) el jugador manda al ritmo de `player.tscn`, 30 por segundo; la escena no se tocó.
- **`scripts/gameplay/player/player_ride.gd`** (tuyo): `publish_net_state()` termina llamando a
  `apply_pose_rate(p)` (nueva, estática), que elige el `replication_interval` del `MultiplayerSynchronizer` del
  jugador: a pie, el ritmo pedido; subido a un vehículo (`net_in_vehicle`) o sentado, el de la escena otra vez.
  Si nadie pidió otro ritmo vuelve enseguida sin tocar nada (Reparto e Infinito no cambian). `pose_interval()`
  (nueva) pasa el ritmo a segundos redondeando hacia abajo a 0,1 ms, como el 0,0333 de la escena.
- **`scripts/gameplay/company_root.gd`** (zona compartida): `join_crew(player)` (estática, nueva) agrupa lo que
  `_spawn_player` hacía con `CREW_GROUP` y pide `CompanyTuning.SHED_POSE_RATE_HZ` (15, constante nueva en
  `company_tuning.gd`).
- **`modules/net_pose_smoother/tests/test_net_pose_smoother.gd`** (zona compartida): un caso más, un emisor
  que baja de 30 a 15 Hz. El módulo no cambió.
- Tests: `test_company_bandwidth_budget` ahora falla si el galpón pasa 24 KB/s también con 8 jugadores;
  `test_company_root` comprueba 15/s a pie, 30/s en un vehículo y 30/s fuera de la empresa.

**El protocolo no cambia** (`PROTOCOL_VERSION` sigue en 34): ni RPC ni propiedades ni modos de replicación,
solo cada cuánto manda el dueño. Un cliente viejo con un host nuevo se entiende; el viejo solo manda a 30.

## Qué tiene que hacer Slatex

Nada obligatorio. Si tocás el `MultiplayerSynchronizer` del jugador:
- no le cambies el `replication_interval` desde otro lado mientras el jugador está a pie en la empresa: lo
  elige `apply_pose_rate()` en cada tick (si hace falta otro ritmo, pasalo por `set_on_foot_pose_rate()`);
- si algún día le ponés un `NetRestThrottle`, ese nodo guarda el intervalo de la escena al arrancar y lo
  devolvería a 30 al despertarse: hay que hacer que tome el ritmo de `apply_pose_rate()` como el activo.

Los números están en `docs/rendimiento-pc.md` (sección D-2002).
