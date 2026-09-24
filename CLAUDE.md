# Take My Package — notas para Claude

Juego cooperativo en Godot 4.7 (`do-not-drop/`, renderer GL Compatibility). Dos
integrantes con dominios separados: ver `CONTRIBUTING.md` y `docs/colaboracion-equipo.md`.

## Correr Godot: siempre a través del agente que corresponde

Nunca corras Godot (tests, capturas, import) directo desde la conversación principal:
sus logs son largos y gastan contexto.

- **Tests headless** (`tests/test_*.gd`): agente `ejecutor-tests`, que usa
  `tools/run-tests.sh` y devuelve solo el resumen. Pedile un filtro cuando alcance
  (`tools/run-tests.sh depot`), no la batería entera después de cada cambio chico.
- **Capturas y previsualización** (`tests/render_*.gd`, `check_driver_sightline.gd`,
  `check_pivots.gd`, cualquier cosa que necesite pantalla o mirar imágenes): agente
  `revisor-visual`.
- **Diagnóstico de un test que falla**: agente `cazador-bugs`.
- La red de seguridad final es el hook `pre-push` (corre la batería completa) y CI en
  GitHub: no hace falta correr todo antes de cada commit.

## Al terminar un cambio

- Test nuevo o ampliado para lo que se cambió, anotado en la lista del README.
- Actualizar `docs/tareas-nacho.md` / `docs/tareas-slatex.md` y, si se tocó la zona
  compartida o archivos del otro integrante, un aviso en `docs/colaboracion-equipo.md`.
- Commits con prefijo (`feat:`, `fix:`, `docs:`…), en inglés.
