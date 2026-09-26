# Cómo trabajamos en Take My Package

## Primera vez en un clon

```bash
tools/setup-hooks.sh
```

Activa el hook `pre-push`: antes de cada `git push` se corre la batería de tests headless
(`tools/run-tests.sh`) y, si algo falla, no se sube nada. Si el push solo trae cambios de
documentación, el hook no corre los tests. GitHub Actions corre los tests headless y los
checks de red en cada push a `main` y en cada PR, incluidos los cambios que solo tocan
documentación. En una emergencia: `SKIP_TESTS=1 git push`.

El hook y el script buscan Godot en `GODOT`, en el `PATH` o en
`D:/Descargas/Godot_v4.7.2-stable_win64_console.exe`. Si lo tenés en otro lado:
`export GODOT=/ruta/a/Godot_v4.7.2-stable_win64_console.exe`.

## Claude Code

La configuración compartida está en `.claude/` (agentes, skills, hooks, `settings.json`)
y en `.mcp.json` (MCP de Blender y de Godot). Lo personal va en
`.claude/settings.local.json`, que no se sube. Para que el hook de dominios sepa quién
sos si tu mail de git no es el de siempre:

```json
{ "env": { "TMP_DUENO": "nacho" } }
```

El MCP de Godot (`@coding-solo/godot-mcp`) abre el editor, corre el juego y lee la salida
de depuración. Usa `GODOT` para encontrar el ejecutable; si no está definida, lo busca
solo.

## Tests

```bash
tools/run-tests.sh              # toda la batería, en paralelo, resumen compacto
tools/run-tests.sh depot red    # solo los tests cuyo nombre contiene "depot" o "red"
tools/run-tests.sh -v traps     # con el log de cada falla
```

- Cada test corre con su propio `user://`, así que nunca toca tu progreso ni tu leaderboard.
- `SKIP`: el test necesita pantalla (no corre headless).
- "cierre inestable": el test pasó todas sus verificaciones y después Godot crasheó al
  cerrarse. Es un crash conocido del motor al salir, se reintenta una vez y no bloquea.
- `render_*.gd` y `check_*.gd` generan capturas y necesitan pantalla y alguien que las
  mire: no entran en la batería (ver el agente `revisor-visual`).
- Cada mecánica nueva o bug arreglado lleva su test (`tests/test_<tema>.gd`, patrón
  `extends SceneTree` + `_expect` + `quit(_failures)`), anotado en la lista del README.

## Builds de release

Un tag `v*` en `main` (`git tag v0.2.0 && git push origin v0.2.0`) dispara
`.github/workflows/release.yml`: pone la versión del tag en `config/version` de
`project.godot` (el menú la muestra abajo a la izquierda), exporta Windows y Linux con
`tools/export/export_presets.cfg`, prueba que la build de Linux arranque sin errores de
carga y sube `TakeMyPackage-<versión>-windows.zip` y `-linux.zip` al release del tag.
También adjunta `SHA256SUMS.txt` para verificar la integridad de los ZIP descargados.
El `export_presets.cfg` de `do-not-drop/` sigue siendo local de cada uno (está en
`.gitignore`); si cambiás filtros o rutas en el tuyo, copiá el cambio al de `tools/export/`.
También se puede correr a mano desde Actions ("Run workflow"): deja los zip como artefacto
sin publicar un release.

## Commits

Mensajes en inglés, con prefijo: `feat:`, `fix:`, `perf:`, `docs:`, `test:`, `chore:`.
Un tema por commit. Los cambios de documentación que acompañan a un cambio de código van
en el mismo commit.

## Dominios

Nacho: vehículo, ruta, ambientación, depósito. Slatex: jugador, paquetes, interacción, UI y
progresión. Antes de tocar archivos del otro o la zona compartida, dejá un aviso en
[docs/colaboracion-equipo.md](docs/colaboracion-equipo.md). Las tareas pendientes de cada
uno están en [docs/tareas-nacho.md](docs/tareas-nacho.md) y
[docs/tareas-slatex.md](docs/tareas-slatex.md).
