# Rutina: QA diario sobre main

Recorre el juego armado como lo haría un QA técnico y convierte lo que se rompe en tareas que la rutina
de construcción toma primero. Reglas comunes y sesión: `.claude/rutinas/README.md` (leelo primero).

## 1. Recorrido

1. `git switch --detach origin/main` y anotá el commit (`git rev-parse --short HEAD`).
2. **`probador-qa`** con los 5 escenarios de su prompt. Corre dos veces por día (06:00 y 18:00 hora
   Argentina). Clima de la corrida: índice `(2 × día del mes + (1 si es la de la tarde)) módulo` la
   cantidad de climas de `docs/qa-recorrido.md`, así las dos del día prueban climas distintos. La de la
   tarde, además, mira primero lo que se mezcló desde la de la mañana (`git log --since="12 hours ago"
   --first-parent origin/main`) y le pide a `probador-qa` que apunte a esas áreas.
   Pasale la tabla "Hallazgos" actual de `docs/qa-recorrido.md` para que no repita los conocidos.
3. Si reporta crecimiento de nodos o memoria en el endless, o avisos cada frame: **`perfilador-rendimiento`**
   con esos números, para ubicar la causa (sin arreglarla acá).
4. **Domingos** (`date +%u` = 7): además, el paso 6 de `probador-qa` (balance: `sim_trap_balance` y
   `bench_route_duration`). Una trampa que pasó a "REQUIERE AJUSTE" o una entrega fuera de rango es
   hallazgo "molesta" y la tarea va con `pulidor-jugabilidad`.
5. Por cada hallazgo "bloquea" (máximo 3 por corrida): **`cazador-bugs`** con el escenario exacto, para
   tener causa raíz y archivo:línea. Si el escenario pasaba en la corrida anterior de
   `docs/qa-recorrido.md`, pedile también **qué PR lo trajo** (commits entre los dos, `git log -S`): la
   tarea sale como `Regresión de #<PR>` (regla 14 del README).

## 2. Registrar

- Sin hallazgos nuevos: terminá sin PR (regla 7 del README).
- Con hallazgos: rama `rutina/qa-AAAA-MM-DD-HH` (HH = hora de la corrida) desde `origin/main`.
  1. Filas nuevas en la tabla "Hallazgos" de `docs/qa-recorrido.md` (fecha, commit, escenario, qué pasó,
     causa si la hay). Hallazgos viejos que ya no aparecen: tachalos con la fecha.
  2. **`planificador-tareas`** con los hallazgos "bloquea" y "molesta": una tarea por bug, en la sección
     **"QA — bugs abiertos"** al principio de `tareas-nacho.md` (creala si no existe), con el
     diagnóstico de `cazador-bugs` y "Hecho cuando: el escenario de QA pasa sin el error y hay un test
     que lo fija". Los cosméticos van a la sección que corresponda, prioridad C. Cada tarea lleva
     `Origen: QA AAAA-MM-DD`. Freno de tareas (regla 11 del README): con más de 10 abiertas de QA,
     solo entran los "bloquea"; lo demás queda en la tabla de `qa-recorrido.md`.
  3. Todo va a `tareas-nacho.md` (lo del dominio de Slatex como `S-xxx` en "Heredadas de Slatex", nunca a
     `tareas-slatex.md`); aviso en `docs/avisos/` si se agregaron tareas de su dominio.
  4. PR `docs: QA AAAA-MM-DD — <n> hallazgos` con la tabla en el cuerpo, auto-merge.

## 3. Límites

- Esta rutina no arregla código del juego: diagnostica y deja tareas.
- Si el mismo hallazgo ya tiene tarea abierta, no dupliques: sumá la fecha de hoy a la tarea ("visto
  de nuevo AAAA-MM-DD").
- Borrá las sondas `qa_tmp_*` y sus `.uid` antes de commitear.

## 4. Foco: expansión (parámetro `Foco: expansión`)

El trigger "QA expansión" pasa `Foco: expansión`. Esa corrida **no** hace §1-§2 sobre el juego actual,
sino esto:

1. Commit actual de `origin/main`. Mezclado en las últimas 12 h con `exp/` en la rama
   (`git log --since="12 hours ago" --first-parent origin/main --grep "D-"`).
2. `ejecutor-tests` con el filtro `company`. `probador-qa` con `tools/bot_company_day.gd` (D-2016), si ya
   existe, con 1 y 2 jugadores; si no existe todavía, con los tests de la expansión que haya. Le apuntás a
   las áreas de los PRs del paso 1.
3. Por cada falla o `BOT_FAIL` (máximo 3): `cazador-bugs` para la causa raíz y el PR que la trajo.
4. **Registrar:** un archivo nuevo por bug en `docs/expansion-distritos/bugs/AAAA-MM-DD-<tema>.md`, con:
   - título `D-BUG · <qué>`;
   - gravedad (`bloquea` / `molesta`) y escenario exacto;
   - causa con archivo:línea, PR que la trajo y "Hecho cuando".
   Los toman los desarrolladores antes que cualquier tarea (`desarrollador.md` §1). Lo que solo se puede
   ver a mano va a `docs/expansion-distritos/revisar/qa-AAAA-MM-DD.md`.
5. PR `rutina/qa-exp-AAAA-MM-DD-HH` con los archivos. Si no hubo hallazgos, sin PR (regla 7).
