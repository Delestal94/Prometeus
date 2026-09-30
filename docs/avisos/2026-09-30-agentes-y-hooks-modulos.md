# Aviso: agentes, skills y pre-push al día con los módulos portables (2026-09-30)

Después de N-230 a N-234 (17 módulos en `do-not-drop/modules/`), CI ya cubría los módulos, pero algunos
agentes todavía mandaban a buscar archivos a `scripts/` que ya no están ahí. **No cambia código del juego**:
solo instrucciones de agentes, un hook de git y un doc.

## Qué cambió

- `.githooks/pre-push`: corre `tools/check_modules.py` (un segundo, sin Godot) antes del lint, también con
  `SKIP_TESTS=1`. Si un módulo nombra algo del juego, **el push se frena** con una línea por problema; es el
  mismo chequeo que ya hacía el job `lint` de CI. Sin Python instalado lo saltea y avisa.
- `constructor-trampas`: el contrato está en `modules/hazards/` (`ITrapBehavior`, `TrapDefinition`); el hint
  se escribe en `hint_text()` como línea `LocText` y el `.tres` lleva `translation_key`.
- `constructor-tramos`: la base, el streamer, el terreno y los 6 tramos por código están en `modules/route_gen/`;
  en `segments/` quedan los tramos con assets. Dice dónde va un tramo nuevo y dónde se registra
  (`RouteStreamer._init`, `RoutePlanner`).
- `constructor-jugador`, `constructor-mundo`, `constructor-red`, `constructor-progresion`, `constructor-ui`,
  `artista-vfx`, `disenador-audio`: rutas nuevas de lo que se movió y qué adaptador del juego extiende cada módulo.
- `escritor-tests`, skill `nuevo-test`, skill `cerrar-cambio`, `revisor-gdscript`, `guardian-dominios`: el test
  de un módulo va en `modules/<nombre>/tests/` y corre en un proyecto vacío; `check_modules.py` en la checklist.
- `.claude/hooks/lib.sh`: se sacó `scripts/presentation/synth_audio.gd` de la zona compartida (ya no existe;
  `modules/*` lo cubre). Ningún dominio cambió.
- `docs/convenciones-godot.md` §3: el árbol de carpetas lista los 17 módulos y qué adaptador los extiende.

## Qué tenés que hacer

`git pull`. Si un push te frena por `check_modules.py`, el mensaje dice el archivo y la línea: lo que nombra
al juego va en el adaptador de `scripts/`, no en el módulo (`docs/modulos.md`).
