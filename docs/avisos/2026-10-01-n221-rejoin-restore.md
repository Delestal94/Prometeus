# Aviso: N-221, el que vuelve recupera lugar, asiento y caja; identidad antes del estado (2026-10-01)

Rama `nacho/N-221-rejoin-restore`. **Cambia el protocolo**: `NetworkManager.PROTOCOL_VERSION` pasa de 24 a 26
(25 queda reservado para N-218, con una entrada provisoria en el historial que reemplaza por la suya al
mezclar). Un cliente viejo con un host nuevo recibe "otra versión": actualicen los dos.
**Ninguna firma pública cambia de forma incompatible**: se agregan una señal, funciones y una clase del juego.

## Qué cambió

**Módulo `net_session` (zona compartida):**
- `NetSession`: señal nueva `peer_returned(id, previous_id)` en el host, justo después del hook
  `_peer_returned`, para todo el que vuelve con la misma identidad (también con el mismo id, cuando
  `peer_rejoined` no llega). Es la que usa el juego para devolver lo que anotó del que se fue.
- **Identidad antes del estado (LAN, sala llena):** el host ya no le manda el estado completo a un joiner que
  no sabe quién es. Le manda solo `{version, session, identify: true}`; el joiner contesta
  `{identify, version, identity}` (`NetAdmission.answer_identify()`, con el próximo eslabón de su cadena) y el host decide
  ahí (`NetAdmission.on_identity()`): si es el de un fantasma (se suelta) o se liberó un lugar, recibe el
  estado y carga el nivel; si no, oye `"full"` (o `"connection"` si repite un eslabón ajeno) **sin haber
  cargado nada**. Su respuesta de listo no lleva identidad y el host no la vuelve a leer
  (`NetAdmission.identified`). En Steam no cambia nada (el Steam ID se sabe al autenticar).
- El manejo de las respuestas en el host (identidad y "listo") y la respuesta del joiner pasan a
  `NetAdmission` (`receive()`, `receive_identity()`, `send_state()`, `ask_identity()`, `answer_identify()`),
  para que `net_session.gd` siga bajo las 1000 líneas. `NetSession._ready_reply_error()` pasa a ser
  `NetAdmission.ready_reply_error(reply, version)` (estática; también `identity_reply_error()`), y
  `NetSession._claim_identity()` es el virtual de quién dice ser el proceso.

**Juego:**
- `scripts/gameplay/rejoin_keepsake.gd` (`RejoinKeepsake`, nuevo, lo crea `level_common.gd`): el host anota en
  `peer_removed` dónde estaba el jugador (en el espacio del camión si iba en él), su asiento y su caja; con
  `peer_returned` la nota pasa al id nuevo y `_sync_players()` lo spawnea desde ahí: su asiento si sigue libre
  (al del chofer le abre la puerta), si no otro como un join tardío; a pie donde estaba si tiene sentido; y la
  caja de vuelta en las manos si nadie la tocó. Al irse se sigue soltando todo en el acto (S-209). Sin RPC
  nuevos: el spawn, el asiento y el `pick_up` son los de cualquier join.
- `network_manager.gd`: solo el número de protocolo y su historial.

## Para Slatex

No se tocó ningún archivo tuyo. Lo que el regreso usa de tu dominio, por su API de siempre:
`DeliveryPackage.take_by()`, `is_held`, `is_loaded`, `_lost`, `_last_holder_peer`, `lap_mount_path`,
`SeatTending.bind_lap()`, `SeatPoint.can_interact()/interact()`, y del jugador `seat_node_path`,
`net_in_vehicle`, `net_position`, `carried_package`. Si cambia alguno, `tests/test_rejoin_keepsake.gd` avisa.
