# Jugadores y cajas remotas suavizados, a 30 Hz (protocolo 22; archivos de Slatex y zona compartida)

N-217 (fase 2 de `docs/investigacion-red.md`). Antes, los jugadores de otros peers y las cajas del cliente se
ponían en la última pose que llegaba, y con el jitter de internet saltaban. Ahora cada pose lleva el reloj de
quien la manda y se dibuja un poco en el pasado, interpolada.

- **Protocolo: cambió.** `PROTOCOL_VERSION` pasa a **22** (`network_manager.gd`).
  - `player.tscn` (`Repl_player`): `.:rotation` pasa a ser `PlayerNetPose:net_yaw` (float; en el espacio
    del camión mientras viaja en la caja de carga) y se suma `PlayerNetPose:net_time` (ALWAYS).
  - `package.tscn` (`Repl_package`): se suma `.:net_time` (ALWAYS).
  - Los dos sincronizadores pasan de `replication_interval` 0,0167 a **0,0333** (30 Hz).
  - Ningún RPC cambió.
- **Módulo `net_pose_smoother` (zona compartida):** clase nueva `NetSnapshotBuffer`, con colchón adaptativo
  (2 intervalos + 2 × jitter, entre 50 y 200 ms), el reloj de quien envía, poses en el espacio del camión, el
  arranque después de una caja quieta y `take()` para leer propiedades replicadas. `NetPoseSmoother` (el
  camión) no cambia.
- **Módulo `net_session`:** `NetStats.round_trip_ms(peer, id)`, el ping de un peer sin tocar los contadores
  de tráfico. **Módulo `interaction`:** `Interactable._within_reach` suma `reach_slack()` si el jugador lo
  tiene.
- **`player.gd` (de Slatex):** nodo hijo nuevo `PlayerNetPose` (`player_net_pose.gd`) y método
  `reach_slack()`. `player_ride.gd` publica el reloj y el giro, y dibuja a los remotos desde el buffer (en
  el host también: la copia de un cliente va unos 50-200 ms atrás).
- **`package.gd` (de Slatex):** `net_time`, un `NetSnapshotBuffer` por caja en el cliente y
  `_reach_slack()`. La caja que lleva el propio cliente en las manos sigue predicha, sin buffer.
- **Alcance en el host:** al pedido de un jugador remoto se le suma 6 m/s × (ping + colchón), con tope de
  1,5 m. Vale para la interacción genérica, abrir la caja, ayudar, pasarla de mano en mano y agarrarla
  para ayudar. El jugador del host no cambia.
- **Si escribís una pose a mano en un test:** con `net_time` en 0 se coloca en el acto, como antes. Con un
  `net_time` puesto, se dibuja con el colchón.

Ancho de banda (`test_net_bandwidth_budget`, 8 jugadores): de host a cada cliente, 117,7 → **67,7 KB/s**
estable (85,8 con todas las cajas moviéndose). Subida del host: 6,8 → **3,9 Mbit/s**.

Tests: `test_net_snapshot_buffer` (módulo, nuevo), `test_remote_smoothing` (nuevo), `test_net_stats`
(`round_trip_ms`), `test_player_split` (`reach_slack`).
