# D-0606.c3: sonido y baliza del autoelevador del galpón

Zona compartida tocada: `modules/synth_audio/synth_audio.gd` (nuevo `forklift_hydraulic_loop()`, sin cambiar
ninguna firma ni generador existente) y `modules/synth_audio/synth_audio_scenes.gd`
(`make_forklift_hydraulic_loop`), más `scripts/presentation/world_mix.gd` (`SHED_FORKLIFT_ENGINE_DB`,
`SHED_FORKLIFT_HYDRAULIC_DB`) y `scripts/presentation/sound_audit.gd` (nombres para "Sonidos del juego").
`ForkliftView` (`scripts/gameplay/forklift_view.gd`) agrega un hijo `ForkliftCues`
(`scripts/gameplay/forklift_cues.gd`) al que `refresh()` y `_process()` le pasan si hay conductor y hacia dónde
van las horquillas. Sin RPC ni cambio de `PROTOCOL_VERSION`.
