# Aviso: docs sin choques entre PRs (N-706, 2026-09-29)

Lo hizo Nacho (con Claude). No cambia código del juego; cambia cómo se documenta un cambio:

- **Avisos:** cada aviso es un archivo nuevo en `docs/avisos/` (`AAAA-MM-DD-tema.md`), como este. Ya no
  se agrega nada a `docs/colaboracion-equipo.md`, que quedó solo con la política (dominios, zona
  compartida, flujo). Los 68 avisos anteriores están en `docs/avisos/archivo-2026-09.md`.
- **Tests:** no hay más lista de tests en el README. Cada test dice qué cubre en su encabezado (las
  líneas `## ...` debajo de `## Run:`); `tools/list-tests.sh` arma el índice y CI falla si un test no
  tiene descripción (`tools/list-tests.sh --missing`). Se completaron los encabezados que faltaban.
- **Listas de tareas:** sin encabezado "Última actualización" (lo editaban todos los PRs).
- `main` ya no exige que la rama esté al día para mezclar: los PRs encolados entran solos.
- Actualizados a esta regla: `CLAUDE.md`, `CONTRIBUTING.md`, la plantilla de PR, las skills
  `cerrar-cambio` y `nuevo-test`, los agentes `escritor-tests`, `documentador` y `guardian-dominios`,
  y los mensajes de los hooks.

Slatex: `git pull` y listo; si tenés un PR abierto que agrega una línea al README o a
`colaboracion-equipo.md`, sacala y poné la descripción en el test / el aviso en `docs/avisos/`.
