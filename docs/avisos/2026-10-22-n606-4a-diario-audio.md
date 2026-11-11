# Aviso: audio del diario del día siguiente (N-606.4a)

Zona compartida (`modules/synth_audio/`, `world_mix.gd`) y un toque a `loading_screen.gd`. **Ninguna firma
existente cambia**: solo se agregan cosas.

- `modules/synth_audio/synth_audio_newspaper.gd` (nuevo, `SynthAudioNewspaper`) con seis generadores y sus
  accesores nuevos en `synth_audio.gd`: `rooster_crow()`, `morning_chirps()`, `extra_stinger()`,
  `paper_rustle()`, `page_turn()`, `mate_spit()`. Con semilla fija; los demás sonidos no cambian (el test
  dorado `test_synth_audio_golden` sigue igual). La clase nueva necesita que Godot regenere su caché de
  clases (`godot --headless --import`) en un checkout viejo.
- `world_mix.gd`: seis constantes `NEWSPAPER_*_DB` y una clase de mezcla nueva, `foley` (100 ms más fuertes,
  −24 dBFS: papel y manipulación cercana y seca). `test_world_audio_levels` las mide.
- `loading_screen.gd`: los seis accesores se suman a `LEVEL_SOUNDS` (se arman en el hilo de carga, así el
  diario no sintetiza nada al final de la partida).
- `sound_audit.gd`: nombres de los sonidos nuevos y de su fuente (`newspaper_director`).
- Los reproduce `newspaper_director.gd` (Nacho) desde `data/newspaper/shots.json` (`sounds` por plano).
