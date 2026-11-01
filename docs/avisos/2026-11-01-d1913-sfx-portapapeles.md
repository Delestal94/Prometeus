# D-1913: sonidos del portapapeles en SynthAudio

- **Qué cambió:**
  - `modules/synth_audio/` (zona compartida): `SynthAudioHandling.make_clipboard_clip(raise)` y
    `make_clipboard_sheet()`, con sus accesores `SynthAudio.clipboard_clip_up()`, `clipboard_clip_down()` y
    `clipboard_sheet()` (cacheados como los demás). `tests/test_synth_audio.gd` los suma a sus one-shots. Los
    sonidos que ya existían no cambian (el test golden sigue igual).
  - `scripts/presentation/sound_audit.gd`: los tres en `SOUND_NAMES`, para encontrarlos en "Sonidos del juego".
  - `scripts/gameplay/company_clipboard.gd`: un `AudioStreamPlayer` propio en el bus SFX (solo este par). Broche al
    sacar y al guardar, papel al cambiar de hoja (no al abrir en una hoja ni al pedir la que ya se ve).
- **Qué tiene que hacer Nacho:** nada. Si la mezcla del galpón (D-1912) arma un bus propio para la UI de la
  Empresa, el reproductor se llama `ClipboardSfx` y hoy va a `SFX` con `CompanyClipboard.SFX_DB` (-8 dB).
