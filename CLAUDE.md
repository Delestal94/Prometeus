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

Los agentes están en `.claude/agents/` (versionados).

### Orquestación

- **Un subagente no puede lanzar otro.** La conversación principal (o la rutina) es la
  única que orquesta: cuando un agente "recomienda" pasar algo por otro, lo hace ella.
- Modelos fijados en cada agente (Opus 5.5 / Sonnet 5.5 con su `effort`): los que
  corren y resumen (tests, capturas, dominios, docs) van en Sonnet con esfuerzo bajo;
  diagnóstico, red y revisión en Opus.
- En una rutina en la nube sirven `ejecutor-tests`, `cazador-bugs`, `revisor-visual`,
  `guardian-dominios`, `auditor-red` y `documentador`. Los artistas y
  `modelador-blender` necesitan ComfyUI/Blender en la PC; `critico-diseno` y
  `empaquetador-release` necesitan a alguien que decida. El flujo de la rutina de
  Nacho está en `.claude/rutinas/tareas-nacho.md`.
- `vehicle.tscn` / `vehicle.gd` están congelados desde el hito M6 (2026-09-28): lo nuevo
  del camión va como componente aparte. La fuente es `docs/colaboracion-equipo.md`.
- Los dominios que usan hooks y agentes salen de `file_domain` en
  `.claude/hooks/lib.sh`; si cambia la tabla de `docs/colaboracion-equipo.md`,
  actualizá las dos. En la nube, el hook de arranque
instala Godot 4.7.2 en `~/godot` y deja `GODOT` definido; las capturas corren con
`xvfb-run` (render por software).

## Hooks de este repo (`.claude/settings.json`)

- Al editar un `.gd`, Godot lo carga con los autoloads y, si no compila, el error
  vuelve como feedback: arreglalo antes de correr tests.
- No se editan a mano `*.uid`, `*.import`, `.godot/` ni `addons/godotsteam/` (el hook
  lo bloquea). Tocar un archivo del dominio del otro integrante pide confirmación
  (`TMP_DUENO=nacho|slatex` en `.claude/settings.local.json`, o el mail de git).

## Al terminar un cambio

Seguí la skill `cerrar-cambio` (y `nuevo-test` para escribir el test). En resumen:

- Test nuevo o ampliado para lo que se cambió, con su descripción en el encabezado del test
  (`tools/list-tests.sh` arma el índice; no hay lista a mano que mantener).
- Actualizar `docs/tareas-nacho.md` / `docs/tareas-slatex.md` y, si se tocó la zona
  compartida o archivos del otro integrante, un aviso: un archivo nuevo en `docs/avisos/` (`AAAA-MM-DD-tema.md`).
  Nunca se edita un archivo que todos los PRs tocan (así no chocan entre sí).
- Commits con prefijo (`feat:`, `fix:`, `docs:`…), en inglés.
