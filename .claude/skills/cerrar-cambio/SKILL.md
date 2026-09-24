---
name: cerrar-cambio
description: Checklist para cerrar un cambio en Take My Package antes de commitear - test, lista del README, docs de tareas, aviso de colaboración y mensaje de commit. Usala cuando termines una feature o un fix, o cuando pidan "cerrá el cambio", "commiteá" o "dejalo listo para subir".
---

# Cerrar un cambio

Seguí los pasos en orden. Si un paso no aplica, decí por qué en una línea en vez de
saltearlo en silencio.

## 1. Qué cambió y de quién es

- `git status` y `git diff --stat` para ver los archivos tocados.
- Clasificá cada archivo con la tabla de `docs/colaboracion-equipo.md`:
  dominio de Nacho (vehículo, ruta, depósito, ambientación), de Slatex (jugador,
  paquetes, trampas, interacción, UI, progresión) o **zona compartida**
  (`event_bus.gd`, `network_manager.gd`, `run_manager.gd`, `first_person_camera.gd`,
  `render_layers.gd`, `synth_audio.gd`, `level_base.gd`/`.tscn`, `project.godot`,
  `README.md`, `docs/especificaciones-visuales.md`).
- Quién está trabajando: `TMP_DUENO` o el mail de `git config user.email`
  (el de Nacho es `delestal.miguelignacio@...`, el de Slatex `skater.devil@...`).
  Si no se puede saber, preguntá.

## 2. Test

- Cada mecánica nueva o bug arreglado lleva un test `do-not-drop/tests/test_<tema>.gd`
  nuevo o ampliado. Para escribirlo, seguí la skill `nuevo-test`.
- Si el cambio es solo visual, el test headless verifica lo verificable
  (nodos, posiciones, parámetros) y la parte visual la revisa el agente
  `revisor-visual`.

## 3. README

- Test nuevo → agregá su línea a la lista de "Tests" en `README.md`, con el
  mismo formato que las demás:
  `<godot> --headless --path do-not-drop --script res://tests/test_<tema>.gd`
- Si el cambio altera algo que el README explica (controles, cómo correr, etc.),
  actualizá esa parte.

## 4. Tareas

- En `docs/tareas-nacho.md` o `docs/tareas-slatex.md` (el del dueño del trabajo):
  si la tarea está en la lista, tachala con el mismo formato que las hechas
  (`~~texto~~ **[x] Hecho (AAAA-MM-DD)** — qué se hizo, con el archivo/función`).
  Actualizá la fecha de "Última actualización" del encabezado.
- No toques la lista del otro integrante.

## 5. Aviso de colaboración

Si se tocó la zona compartida o algún archivo del dominio del otro, agregá en
`docs/colaboracion-equipo.md` una sección `## Aviso activo: <tema> (AAAA-MM-DD)`
como las que ya hay: qué archivo, qué función o señal cambió, si cambió una firma
y qué tiene que hacer el otro (por ejemplo `git pull` antes de seguir).

## 6. Tests

Pedile al agente `ejecutor-tests` que corra los tests relacionados con el cambio
(filtro por nombre). No hace falta la batería entera: la corre el hook
`pre-push` y CI.

## 7. Commit

- Mensaje en inglés con prefijo: `feat:`, `fix:`, `perf:`, `docs:`, `test:`,
  `chore:`. Un tema por commit; la documentación del cambio va en el mismo commit
  que el código.
- Cambios en zona compartida: commit chico y aislado, separado del resto.
- No agregues archivos generados por Godot que no estén ya versionados
  (`.godot/`, `*.import`).
