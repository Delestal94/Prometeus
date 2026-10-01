# La voz por proximidad ya se oye (N-212.2)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

- **Módulo `net_session` (zona compartida), clase nueva `VoicePlayback`** (`modules/net_session/voice_playback.gd`,
  `extends AudioStreamPlayer3D`): reproduce el PCM que entrega `SteamVoice.voice_received` con un
  `AudioStreamGenerator`. Búfer de jitter de 60 ms al empezar cada frase, tope de 0,3 s (descarta lo más viejo,
  nunca acumula atraso; un paquete más largo que el tope se recorta **antes** de convertirlo), se calla sola a los
  0,5 s sin paquetes. API: `push_pcm(pcm, rate)`, `gain` (0..1, multiplica las muestras: bajar `volume_db` en un
  `AudioStreamPlayer3D` también sube el filtro de distancia, medido en Godot 4.7), `follow` (Node3D del que copia
  la posición), `carry_in_room()`, `carry_in_open(muffled)`, `silence()`, `is_speaking()`, `queued_frames()`.
  Test propio: `modules/net_session/tests/test_voice_playback.gd`.
- **Módulo `net_session` (zona compartida), `SteamVoice`** (`steam_voice.gd`), solo agregados: cupo propio por peer
  de paquetes decodificados antes de `decompressVoice` (`VOICE_PACKETS_PER_SECOND` 120, ráfaga `VOICE_PACKET_BURST`
  30; no usa el de `RpcGuard`), función nueva `take_voice_packet(peer_id, now_msec)`, y `clear_peers()` /
  `_forget_peer()` también borran el cupo. El RPC `_receive_voice` no cambia. Test: `test_net_session.gd`.
- **`scripts/core/proximity_voice.gd`** (sin dueño en la tabla de dominios; es el adaptador de voz): funciones
  nuevas `speaker(peer_id)` y `release_speaker(peer_id)`; sobrescribe `_process`, `clear_peers` y `_forget_peer`
  (llaman a `super`). Escucha `NetworkManager.peer_removed`, `roster_changed` y `session_failed` solo para soltar
  reproductores: si la sesión termina (se dejó, o falló porque se fue el host) suelta todo y olvida silencios y
  volúmenes (`clear_peers()`). No cambia nada de la sesión.
- **`scripts/presentation/sound_audit.gd`** (sin dueño en la tabla): dos nombres más, `"voice_playback": "Voz de
  compañero"` y `&"AudioStreamGenerator": "Voz"`. La lista "Sonidos del juego" muestra "Voz de compañero · Voz";
  silenciarla ahí baja `volume_db` y `proximity_voice.gd` lo sostiene hasta que se vuelve a activar.
- **Tu dominio, sin tocar archivos**: el nodo del jugador que habla recibe en tiempo de ejecución un hijo
  `VoiceChat` (`VoicePlayback`). Sigue su `Head` a pie o el nodo de `seat_node_path` sentado (el cuerpo queda donde
  se sentó). Lo lee, no lo escribe: si `Head`, `seat_node_path` o `net_in_vehicle` cambian de nombre o de
  significado, avisá.
- Buses: los dos en el camión (cámara de asiento del camión + el que habla sentado en él) → `Interior` sin
  atenuación; si no → `Exterior` con atenuación 3D (deja de oírse a 28 m) y apagada si uno está a bordo (sentado,
  o parado en la caja: `net_in_vehicle`) y el otro no. Ninguno de los dos es el bus `Voice`, así que la ganancia
  ya incluye `GameSettings.voice_volume` (el control "Voces" sigue mandando).

**No hay RPC nuevo ni replicación nueva: `PROTOCOL_VERSION` no sube.** La reproducción es local en cada peer; un
cliente viejo y un host nuevo se entienden igual que antes (el viejo simplemente no reproduce).

## Supuestos y riesgos

- `seat_node_path` lo escribe el dueño del jugador y viaja sin validar: un cliente modificado podría decir que
  está sentado en el camión y sonar sin atenuación (bus `Interior`) para los que están sentados. Solo cambia cómo
  se oye su voz en los demás, no el juego; no se arregla ahora.
- El cupo de 120 paquetes por segundo supone que Steam entrega como mucho un paquete cada ~20 ms de voz (unos 50
  por segundo, sin importar los FPS del que habla). Si la prueba con Steam real muestra cortes, subirlo.
- Falta la prueba con Steam real y gente (N-212.1 y N-212.2).

## Qué tiene que hacer Slatex

Nada para que funcione. Para N-212.3 (Opciones y lista de jugadores, `options_panel.gd`): el interruptor sigue
siendo `GameSettings.voice_chat_enabled` (apagado por defecto); silenciar y volumen por compañero son
`ProximityVoice.set_peer_muted()` / `set_peer_volume()` y se aplican al vuelo (un volumen nuevo, desde el próximo
paquete; silenciar, en el acto). Duran lo que dura la sesión. Para un ícono de "está hablando" sobre la cabeza:
`ProximityVoice.speaker(peer_id)` devuelve su `VoicePlayback` (o `null`) y `is_speaking()` dice si suena ahora.
