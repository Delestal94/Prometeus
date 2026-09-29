# Aviso: agentes revisados y tocar el dominio del otro sin frenar (2026-09-29)

Lo hizo Nacho (con Claude). No cambia código del juego; cambia cómo trabajan los agentes y un hook
que también usás vos:

- **Tocar el dominio del otro ya no pide confirmación** (`.claude/hooks/protect-files.sh`), para los
  dos. Antes el hook frenaba con "ask"; ahora deja pasar y le recuerda a Claude que el mismo commit
  lleve un aviso en `docs/avisos/` con qué cambió. Motivo: las rutinas en la nube corren sin nadie que
  conteste, y Nacho decidió poder tocar tus archivos avisando qué se cambió. Slatex: esperá ver PRs
  `nacho/` que tocan jugador, paquete, trampas o UI, siempre con su aviso acá.
- **Dominios en un solo lugar:** `file_domain` en `.claude/hooks/lib.sh` (lo usan hooks, la skill
  `cerrar-cambio` y `guardian-dominios`). Suma `core/game_settings.gd` como tuyo, y `README.md`,
  `docs/especificaciones-visuales.md` y `docs/colaboracion-equipo.md` como zona compartida.
- **Agentes** (`.claude/agents/`): cada uno fija modelo y esfuerzo (Opus 5.5 o Sonnet 5.5).
  `cazador-bugs` no cargaba (YAML inválido) y ahora sí. Ningún agente "delega" en otro, porque un
  subagente no puede lanzar otro: recomiendan y orquesta la conversación principal. Datos al día: 11
  tipos de tramo, 7 trampas + N-117, textos con `tr("CLAVE")` (catálogo bilingüe), nada de `assert()`
  en tests.
- `vehicle.tscn` / `vehicle.gd` siguen congelados (decisión de M6), ahora con ese motivo escrito en los
  agentes en vez de "Slatex reemplaza el modelo".
- Flujo de la rutina de Nacho, sin revisión humana: `.claude/rutinas/tareas-nacho.md`.

Slatex: `git pull` y listo. Si usás `constructor-ui` o `constructor-trampas`, ahora piden las claves de
`translations/strings_ui.csv` en vez de textos sueltos.
