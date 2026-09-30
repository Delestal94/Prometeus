# Rutina: QA diario sobre main

Recorre el juego armado como lo haría un QA técnico y convierte lo que se rompe en tareas que la rutina
de construcción toma primero. Reglas comunes y sesión: `.claude/rutinas/README.md` (leelo primero).

## 1. Recorrido

1. `git switch --detach origin/main` y anotá el commit (`git rev-parse --short HEAD`).
2. **`probador-qa`** con los 5 escenarios de su prompt. Clima del día: rotá según el día del mes
   (`date +%d` módulo la cantidad de climas de `docs/qa-recorrido.md`) para cubrirlos todos en el mes.
   Pasale la tabla "Hallazgos" actual de `docs/qa-recorrido.md` para que no repita los conocidos.
3. Si reporta crecimiento de nodos o memoria en el endless, o avisos cada frame: **`perfilador-rendimiento`**
   con esos números, para ubicar la causa (sin arreglarla acá).
4. Por cada hallazgo "bloquea" (máximo 3 por corrida): **`cazador-bugs`** con el escenario exacto, para
   tener causa raíz y archivo:línea.

## 2. Registrar

- Sin hallazgos nuevos: terminá sin PR (regla 7 del README).
- Con hallazgos: rama `rutina/qa-AAAA-MM-DD` desde `origin/main`.
  1. Filas nuevas en la tabla "Hallazgos" de `docs/qa-recorrido.md` (fecha, commit, escenario, qué pasó,
     causa si la hay). Hallazgos viejos que ya no aparecen: tachalos con la fecha.
  2. **`planificador-tareas`** con los hallazgos "bloquea" y "molesta": una tarea por bug, en la sección
     **"QA — bugs abiertos"** al principio de la lista del dueño (creala si no existe), con el
     diagnóstico de `cazador-bugs` y "Hecho cuando: el escenario de QA pasa sin el error y hay un test
     que lo fija". Los cosméticos van a la sección que corresponda, prioridad C.
  3. Todo va a `tareas-nacho.md` (lo del dominio de Slatex como `S-xxx` en "Heredadas de Slatex"); aviso en
     `docs/avisos/` si se agregaron tareas de su dominio.
  4. PR `docs: QA AAAA-MM-DD — <n> hallazgos` con la tabla en el cuerpo, auto-merge.

## 3. Límites

- Esta rutina no arregla código del juego: diagnostica y deja tareas.
- Si el mismo hallazgo ya tiene tarea abierta, no dupliques: sumá la fecha de hoy a la tarea ("visto
  de nuevo AAAA-MM-DD").
- Borrá las sondas `qa_tmp_*` y sus `.uid` antes de commitear.
