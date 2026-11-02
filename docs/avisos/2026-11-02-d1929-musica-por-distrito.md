# D-1929: música por distrito en SynthAudio

- **Qué cambió:**
  - `modules/synth_audio/` (zona compartida): `SynthAudioThemeMusic` y el accesor `SynthAudio.theme_music(i)`,
    nueve temas genéricos. Los sonidos que ya existían no cambian.
  - `DistrictMusic` (`scripts/presentation/`), agregado por `CompanyUi`. Elige el tema según la zona
    (`THEME_OF`).
  - `ShedMusic.away` apaga el loop del galpón mientras el jugador anda por un distrito.
- **Qué tiene que hacer Nacho:** nada. Una zona nueva necesita su fila en `DistrictMusic.THEME_OF`. El test
  falla si una zona de `data/zones` no tiene tema.
