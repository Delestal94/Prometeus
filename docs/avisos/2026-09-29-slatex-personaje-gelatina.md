# Aviso: tus tareas pasaron a Nacho; te queda S-311, el personaje de gelatina (2026-09-29)

Lo hizo Nacho (con Claude), por pedido del usuario. No cambia código del juego.

- **`docs/tareas-slatex.md`** quedó con **una sola tarea: S-311, "Personaje 2.0"**, partida en 100 ítems
  (bloques A-O): un personaje de gelatina translúcida con **proporciones editables** (un cuerpo base con
  morphs y largos de hueso, sliders en la personalización, presets Delgada, Flaca y cuatro más), material
  de gelatina para GL Compatibility, física de gelatina, ragdoll sobre el rig real, caras, pelos, skins,
  disfraces que siguen las proporciones, animaciones base y de estudio, emotes graciosos, bailes,
  muertes, VFX y sonidos. Tiene que quedar **igual que la imagen de referencia** con el preset Delgada: el
  bloque E define cómo se compara (render de Godot contra
  la foto, IoU de silueta ≥ 0,92, ΔE ≤ 8 por zona, 12 criterios visuales) y pide iterar hasta pasar, con
  un mínimo de 5 rondas.
- **Referencia**: `art/gel_character/referencia/referencia_frente.jpg`. El candidato que ya estaba
  (`art/gel_character/build_gel_character.py`) sirve de punto de partida para el esqueleto.
- **Todas tus tareas anteriores** (S-101 a S-907, el modelado pendiente 101-106 y "para cuando haya
  playtesting") están en `docs/tareas-nacho.md`, sección **"Heredadas de Slatex"**, con los mismos IDs.
  Los modelos de ChatGPT se tradujeron a esfuerzos de Opus 5.5. Nacho y las rutinas las van a trabajar.
- **Tus archivos siguen siendo tuyos** (`docs/colaboracion-equipo.md` no cambió): cada PR que toque
  jugador, paquetes, UI o progresión va a traer su aviso en `docs/avisos/`.
- **En pausa mientras S-311 esté abierta**: S-305 (accesorios), S-308 (emotes), #101 (ragdoll), #102
  (maniquí) y #103, porque S-311 los rehace para la gelatina.
- `planificador-tareas` y la rutina de QA ya no agregan tareas a tu lista: todo lo nuevo va a la de
  Nacho.

Slatex: `git pull`. Si tenías una tarea S- a medias, avisá (o dejá la marca 🔧 en la lista de Nacho) para
que la rutina no la tome.
