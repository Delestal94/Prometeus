# Aviso: S-311.85, rig gel compartido en el depósito

Los trabajadores del depósito y el operador del montacargas dejaron de usar el
personaje low-poly anterior. Ahora instancian `gel_body_lod0.glb`, aplican uno de
los seis presets con `GelBodyShaper` y reproducen la misma biblioteca de 23 clips
que el jugador. El retarget depende de los nombres estables de los 26 huesos; no
hay clips ni ajustes de pose exclusivos por NPC.

Archivos compartidos tocados:

- `scripts/gameplay/depot/depot_worker.gd`: configuración común de material,
  skin, color de equipo y proporción gel.
- `scripts/gameplay/depot/depot_dressing.gd`: presets distintos para el personal.
- `scripts/gameplay/depot/depot_forklift.gd`: el operador usa el mismo contrato.
- `tests/test_gel_animation_retarget.gd`: comprueba las seis proporciones, los
  23 clips, los tracks por nombre y las instancias reales del depósito.

Las ramas que modifiquen estos NPC deben conservar `CHARACTER_SCENE` como el rig
gel compartido y validar el test de retarget antes de integrar.
