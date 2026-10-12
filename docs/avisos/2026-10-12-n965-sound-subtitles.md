# Subtítulos de sonidos en cola: bocina, timbre, cliente, fauna y lluvia (N-965)

**Fecha:** 2026-10-12 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Solo suma; ninguna señal ni firma pública cambia, salvo un parámetro con valor por defecto:

- `scripts/ui/hud/sound_subtitle_queue.gd` (nuevo): cola de subtítulos con prioridad y vencimiento, hasta 3 a la vez; `arrow()` da la flecha de dirección respecto de la cámara.
- `scripts/ui/hud/hud_prompts.gd`: se suscribe a `horn_honked`, `house_delivery_recorded`, `house_refused_package`, `cargo_animal_alert` y `run_started` y empuja líneas a la cola. `refresh_sound_subtitle(delta: float = 0.0)` ahora también hace vencer la cola; el subtítulo fijo de la trampa en riesgo se comporta igual y queda arriba. Todo respeta `GameSettings.sound_subtitles`.
- `scripts/ui/hud/hud.gd`: `_process` le pasa `delta` a `refresh_sound_subtitle`.
- `translations/strings_ui.csv`: claves nuevas `HUD_SUB_BEES`, `HUD_SUB_CLIENT_CHEER`, `HUD_SUB_CLIENT_GROAN`, `HUD_SUB_CLIENT_REFUSE`, `HUD_SUB_DOG`, `HUD_SUB_DOORBELL`, `HUD_SUB_GULL`, `HUD_SUB_HORN`, `HUD_SUB_RAIN`.
- `docs/controles-y-ui.md`: la fila "Contexto" menciona la cola. `tests/test_sound_subtitles.gd` (nuevo) dispara cada evento.

## Qué tiene que hacer Slatex

Nada. Si agregás un sonido con significado de juego, sumá su fila al inventario de `docs/tareas/N-965.md` y su línea en `hud_prompts.gd` (clave `HUD_SUB_*`, prioridad y segundos). La lluvia se lee por el nodo `RainSound` de `route_sky.gd`: si lo renombrás, el subtítulo se apaga. Pendiente: captura de `revisor-visual` y revisión de `director-arte` (N-965.3).
