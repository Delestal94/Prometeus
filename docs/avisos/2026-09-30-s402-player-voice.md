# Aviso: S-402, voces sin palabras (2026-09-30)

Rama `nacho/S-402-babble-voices`. Toca `player.gd` (de Slatex) con **una sola línea** en `_ready()` y agrega un
archivo nuevo. **No cambia ninguna firma pública ni la simulación**: es presentación local, cada cliente la arma
desde señales que ya llegan a todos (`package_ruined`, `house_delivery_recorded`) y observando el estado del jugador.

## Qué cambió

- Nuevo `scripts/gameplay/player/player_voice.gd` (`PlayerVoice`, hijo `Node3D` del jugador a 1,7 m): un
  `AudioStreamPlayer3D` por el bus `Voice` que reproduce `SynthAudio.callout_voice()` (formantes por vocal, tono por
  color de jugador). Líneas: hurt (golpe, sube `_flinch_time`), ragdoll (sube `_ragdolled`), cheer (entrega intacta de
  la caja que tenía o atendía), ruined (caja propia arruinada). Un solo hilo de voz por jugador, cooldown de 0,6 s.
- `player.gd::_ready`: `add_child(preload(".../player_voice.gd").new())`. El archivo queda en 994 líneas (tope 1000).
  El componente lee `_flinch_time`, `_ragdolled`, `carried_package` y `tended_package` del jugador: si se renombran,
  hay que ajustar `player_voice.gd`.
- `hud_notices.gd::_speak`: el balbuceo del ping pasa del bus `SFX` al bus `Voice` (el slider "Voces" lo controla).
- Test nuevo `tests/test_player_voice.gd`; `test_quick_callouts.gd` verifica el bus `Voice`.

## Qué tiene que hacer Slatex

Nada. Un golpe nuevo que active el flinch o el ragdoll suena solo mientras siga subiendo `_flinch_time` / `_ragdolled`.
