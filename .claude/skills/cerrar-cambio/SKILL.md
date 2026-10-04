---
name: cerrar-cambio
description: Checklist para cerrar un cambio en Take My Package antes de commitear - test con su encabezado, docs de tareas, aviso de colaboración y mensaje de commit. Usala cuando termines una feature o un fix, o cuando pidan "cerrá el cambio", "commiteá" o "dejalo listo para subir".
---

# Cerrar un cambio

Seguí los pasos en orden. Si un paso no aplica, decí por qué en una línea en vez de
saltearlo en silencio.

## 1. Qué cambió y de quién es

- `git status` y `git diff --stat` para ver los archivos tocados.
- Clasificá cada archivo con la misma tabla que usan los hooks (refleja
  `docs/colaboracion-equipo.md`):
  `git diff --name-only | bash -c '. .claude/hooks/lib.sh; while read -r f; do printf "%s\t%s\n" "$(file_domain "$f")" "$f"; done'`
  → `nacho`, `slatex`, `compartida` o vacío (libre).
- Quién está trabajando: `TMP_DUENO` o el mail de `git config user.email`
  (el de Nacho es `delestal.miguelignacio@...`, el de Slatex `skater.devil@...`).
  Si no se puede saber, preguntá.

## 2. Test

- Cada mecánica nueva o bug arreglado lleva un test `do-not-drop/tests/test_<tema>.gd`
  nuevo o ampliado (o `modules/<nombre>/tests/` si el cambio es de un módulo). Para
  escribirlo, seguí la skill `nuevo-test`.
- Si se tocó `do-not-drop/modules/`: `python tools/check_modules.py` tiene que salir sin
  errores (un segundo; también lo corren el `pre-push` y CI).
- Si el cambio es solo visual, el test headless verifica lo verificable
  (nodos, posiciones, parámetros) y la parte visual la revisa el agente
  `revisor-visual`.

## 3. Descripción del test y README

- Test nuevo → que diga qué cubre en su encabezado (`## ...` debajo de la línea
  `## Run:`). No hay lista de tests que mantener a mano: `tools/list-tests.sh` la
  arma, y `tools/list-tests.sh --missing` tiene que salir vacío.
- Si el cambio altera algo que el README explica (controles, cómo correr, etc.),
  actualizá esa parte.

## 4. Tareas

- Las de Nacho (`N-xxx` y heredadas `S-xxx`) son un archivo cada una: `docs/tareas/<ID>.md`
  (`docs/tareas/README.md`). Marcala **ahí**, nunca en `docs/tareas-nacho.md` (CI lo rechaza:
  `python tools/tareas.py revisar`). Las de Slatex siguen en `docs/tareas-slatex.md`.
  Si la tarea está en la lista, tachala con el mismo formato que las hechas
  (`~~texto~~ **[x] Hecho (AAAA-MM-DD)** — qué se hizo, con el archivo/función`).
  Sin línea de "Última actualización" en el encabezado: la fecha la tiene git, y
  esa línea hacía chocar a todos los PRs.
- No toques la lista del otro integrante.

## 5. Aviso de colaboración

Si se tocó la zona compartida o algún archivo del dominio del otro, creá un
archivo nuevo `docs/avisos/AAAA-MM-DD-<tema>.md` (nunca edites uno existente ni
`colaboracion-equipo.md`: un archivo por aviso no choca con otros PRs): qué archivo, qué función o señal cambió, si cambió una firma
y qué tiene que hacer el otro (por ejemplo `git pull` antes de seguir).

## 6. Tests

Pedile al agente `ejecutor-tests` que corra los tests relacionados con el cambio
(filtro por nombre). No hace falta la batería entera: la corre CI (el hook
`pre-push` corre los tests afectados por el push).

## 7. Commit

- Mensaje en inglés con prefijo: `feat:`, `fix:`, `perf:`, `docs:`, `test:`,
  `chore:`. Un tema por commit; la documentación del cambio va en el mismo commit
  que el código.
- Cambios en zona compartida: commit chico y aislado, separado del resto.
- `.godot/` nunca se versiona. Los `.uid` y `.import` que Godot genera para
  archivos nuevos sí (Godot los necesita iguales en todos los clones).
