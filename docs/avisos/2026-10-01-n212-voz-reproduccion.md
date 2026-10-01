# La voz por proximidad ya se oye (N-212.2)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

- **Módulo `net_session` (zona compartida), clase nueva `VoicePlayback`** (`modules/net_session/voice_playback.gd`,
  `extends AudioStreamPlayer3D`): reproduce el PCM que entrega `SteamVoice.voice_received` con un
  `AudioStreamGenerator`. Búfer de jitter de 60 ms al empezar cada frase, tope de 0,3 s (descarta lo más viejo,
  nunca acumula atraso), se calla sola a los 0,5 s sin paquetes. API: `push_pcm(pcm, rate)`, `gain` (0..1),
  `follow` (Node3D del que copia la posición), `carry_in_room()`, `carry_in_open(muffled)`, `silence()`,
  `is_speaking()`, `queued_frames()`. Test propio: `modules/net_session/tests/test_voice_playback.gd`.
  `SteamVoice` no cambia.
- **`scripts/core/proximity_voice.gd` (zona compartida)**: funciones nuevas `speaker(peer_id)` y
  `release_speaker(peer_id)`; sobrescribe `_process`, `clear_peers` y `_forget_peer` (llaman a `super`). Escucha
  `NetworkManager.peer_removed` y `roster_changed` (solo para soltar reproductores; no cambia nada de la sesión).
- **Tu dominio, sin tocar archivos**: el nodo del jugador que habla recibe en tiempo de ejecución un hijo
  `VoiceChat` (`VoicePlayback`). Sigue su `Head` a pie o el nodo de `seat_node_path` sentado (el cuerpo queda donde
  se sentó). Lo lee, no lo escribe: si `Head`, `seat_node_path` o `net_in_vehicle` cambian de nombre o de
  significado, avisá.
- Buses: los dos en el camión (cámara de asiento del camión + el que habla sentado en él) → `Interior` sin
  atenuación; si no → `Exterior` con atenuación 3D (deja de oírse a 28 m) y apagada si uno está a bordo (sentado,
  o parado en la caja: `net_in_vehicle`) y el otro no. Ninguno de los dos es el bus `Voice`, así que la ganancia
  ya incluye `GameSettings.voice_volume` (el control "Voces" sigue mandando).
- La lista "Sonidos del juego" (`sound_audit.gd`) muestra estas voces como `voice_playback · AudioStreamGenerator`.

**No hay RPC nuevo ni replicación nueva: `PROTOCOL_VERSION` no sube.** La reproducción es local en cada peer; un
cliente viejo y un host nuevo se entienden igual que antes (el viejo simplemente no reproduce).

## Qué tiene que hacer Slatex

Nada para que funcione. Para N-212.3 (Opciones y lista de jugadores, `options_panel.gd`): el interruptor sigue
siendo `GameSettings.voice_chat_enabled` (apagado por defecto); silenciar y volumen por compañero son
`ProximityVoice.set_peer_muted()` / `set_peer_volume()` y se aplican al vuelo. Para un ícono de "está hablando"
sobre la cabeza: `ProximityVoice.speaker(peer_id)` devuelve su `VoicePlayback` (o `null`) y `is_speaking()` dice si
suena ahora.
