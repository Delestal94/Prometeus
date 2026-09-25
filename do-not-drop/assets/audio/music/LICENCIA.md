# Música — origen y licencia

| Archivo | Origen | Licencia |
|---|---|---|
| `mus_menu_loop.ogg` | Compuesta por código en `tools/audio/compose_music.py` (N-403): síntesis nota por nota con semillas fijas, sin samples, sin música de terceros y sin generadores de IA. | Propia del proyecto (Take My Package). |
| `mus_depot_radio_loop.ogg` | Ídem, "radio del depósito". | Propia del proyecto. |

Para regenerarlas: `pip install numpy soundfile` y `python3 tools/audio/compose_music.py`. El
script también reescribe `loudness.json` (RMS y pico de cada `.ogg`), que usa
`tests/test_world_audio_levels.gd` para verificar la mezcla.
