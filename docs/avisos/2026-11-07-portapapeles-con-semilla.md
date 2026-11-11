# Sonidos del portapapeles con semilla fija

- **Qué cambió (`modules/synth_audio`, zona compartida):** `make_clipboard_clip` y `make_clipboard_sheet` usan su
  propio `RandomNumberGenerator` con semilla fija en vez del `randf()` global. Ninguna firma cambió. Suenan igual que
  antes: cada sesión ya cacheaba una sola versión; ahora esa versión es siempre la misma.
- **Por qué:** `test_company_mix` mide el nivel del clip contra -31.5 dBFS con 2 dB de tolerancia, y el ruido sin
  semilla lo movía entre -33.82 y -32.72. De 300 síntesis, 63 quedaban fuera (21 %); el test fallaba al azar en `main`
  y en cualquier PR (d739fd59, #844, #847). Con semilla da siempre -33.30 (sacar), -29.88 (guardar) y -32.12 (hoja).
- **Ojo si agregás un sonido que un test mide con tolerancia:** dale semilla propia, como el resto del módulo. Los otros
  generadores sin semilla (`synth_audio_handling.gd`, `_traps`, `_vehicle`, `_scenes`) no se tocaron: el golden siembra
  el RNG global antes de cada uno.
