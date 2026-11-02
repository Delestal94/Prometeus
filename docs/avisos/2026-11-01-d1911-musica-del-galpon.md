# D-1911: música del galpón en SynthAudio

- **Qué cambió:**
  - `modules/synth_audio/` (zona compartida): `SynthAudioWorkMusic` y el accesor
    `SynthAudio.work_music_layer(capa)`. Es un loop genérico en tres capas del mismo largo; no nombra nada del
    juego. Los sonidos que ya existían no cambian.
  - `scripts/gameplay/company_root.gd`: `_ready()` llama a `ShedMusic.add_to(self)` después del panel de cierre.
    Para no sumar líneas (N-985) se reacomodó el comentario de `save_slot` (mismo texto).
  - `ShedMusic` (`scripts/presentation/`) escucha `net.event_applied` en cada par. No usa la red.
- **Qué tiene que hacer Nacho:** nada. Cuando la mezcla del galpón (D-1912) arme sus buses, la música va hoy al
  bus `Music` con `ShedMusic.VOLUME_DB` (-14 dB). La actividad se ajusta con `EVENT_ENERGY` y
  `DECAY_PER_SECOND`.
