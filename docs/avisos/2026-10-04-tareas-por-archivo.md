# Las tareas de Nacho pasan a un archivo por tarea

**Qué cambió:** cada `N-xxx` y cada `S-xxx` heredada dejó de ser un bloque de `docs/tareas-nacho.md` y ahora es
`docs/tareas/<ID>.md` (formato en `docs/tareas/README.md`). `tareas-nacho.md` queda como portada: cómo leer
la lista, "Orden de ataque" y la intro de cada sección. `python tools/tareas.py lista --abiertas` las muestra
y CI corre `tools/tareas.py revisar`, que rechaza una tarea escrita de vuelta en `tareas-nacho.md`.

**Por qué:** casi todos los PRs editaban `tareas-nacho.md` (181 de 233 commits en 5 días) y las rutinas en
paralelo chocaban ahí. Ahora un PR que cierra una tarea solo toca su archivo.

**Archivos compartidos tocados:** `README.md` y `docs/colaboracion-equipo.md` (solo el puntero a dónde están
las tareas). **`docs/tareas-slatex.md` no cambia**: S-311 sigue donde está.

**Qué hacer:** nada si no trabajás la lista de Nacho. Si tenías una rama que editaba un bloque de
`tareas-nacho.md`, pasá ese cambio al archivo `docs/tareas/<ID>.md` de la tarea (el check de CI dice cuál).
