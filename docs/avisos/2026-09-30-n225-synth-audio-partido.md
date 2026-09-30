# Aviso: `synth_audio.gd` partido por responsabilidad (N-225)

Zona compartida (`modules/synth_audio/`). **La API pública no cambia**: `SynthAudio.xxx()` sigue devolviendo
el mismo stream cacheado, con las mismas claves de caché (`SynthAudio._cache`, que lee `sound_audit.gd`), y
los 43 sonidos salen byte por byte iguales.

- `synth_audio.gd` (999 → 249 líneas) queda como puerta: `_cached`, `_cache`, `_scene_builder` y un
  accesor por sonido que delega en el script de su tema. Las firmas no cambian.
- Scripts nuevos con los generadores (`make_*`): `synth_audio_vehicle.gd` (motor, impacto, chirrido, bocina),
  `synth_audio_world.gd` (viento, lluvia, pájaros, grillos, ruta, campana, portón, alarma de retroceso),
  `synth_audio_handling.gd` (obturador, cinta, cartón, pulso de tensión), `synth_audio_animals.gd` (perro,
  oveja) y `synth_audio_dsp.gd` (costura de bucles, normalizado, `Resonator`).
- `synth_audio_traps.gd` suma los generadores de las seis trampas (`make_glass_chime`, `make_creature_groan`,
  `make_wood_creak`, `make_liquid_slosh`, `make_explosive_tick`, `make_hostile_hiss`); `cushion_pad()` sigue igual.
- Lo que era privado de `SynthAudio` y usaba `synth_audio_scenes.gd` (`_normalized`, `_loop`, `_seamless_loop`,
  `_Resonator`) pasó a `SynthAudioDsp` (`normalized`, `loop`, `seamless_loop`, `Resonator`). Nadie más lo usaba.
- Sonido nuevo: va al script de su tema con un `make_<nombre>` y su accesor en `synth_audio.gd`.
- Test: `modules/synth_audio/tests/test_synth_audio_golden.gd` compara los 43 streams con lo que producía el
  archivo único. La clase nueva necesita que Godot regenere su caché de clases (abrir el editor o
  `godot --headless --import`) antes de correr tests en un checkout viejo.
