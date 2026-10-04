# Rutina: auditoría integral diaria

Un director técnico y creativo que mira el proyecto entero todos los días: un pilar a fondo (rota) y lo
que entró en las últimas 24 h en todos los pilares. Sale un informe con prioridades P0-P3 y pocas
tareas. Reglas comunes y sesión: `.claude/rutinas/README.md` (leelo primero).

## 1. Juntar el contexto

1. `git switch --detach origin/main` y anotá el commit (`git rev-parse --short HEAD`).
2. **Pilar del día**: `$(( 10#$(date -u +%j) % 5 + 1 ))` → 1 código y arquitectura, 2 arte técnico/3D/VFX,
   3 agentes y rutinas, 4 documentación vs. realidad, 5 pipeline y automatización. Cada pilar vuelve
   cada 5 días.
3. **Ventana**: commits de `origin/main` de las últimas 24 h
   (`git log --since="24 hours ago" --first-parent origin/main --format="%h %s"`).
4. **Ya conocido** (para no repetir): las 3 auditorías más recientes de `docs/auditorias/` (integrales y
   semanales), la tabla "Hallazgos" de `docs/qa-recorrido.md` y los títulos de las tareas abiertas de las
   dos listas.
5. **Latido de las rutinas** (vos, antes de los agentes; es barato y es lo único que ve una rutina que
   dejó de andar): el último PR de cada una con
   `gh pr list --state all --limit 100 --json headRefName,createdAt,state`, más los issues abiertos
   `rutina-caida` y `decide-usuario` (`gh issue list --label <etiqueta> --state open`).

   | Rutina | Rama | Alarma si |
   |---|---|---|
   | Construcción | `nacho/*` | hay tareas tomables y ningún PR nuevo en 24 h |
   | Build de la PC | `rutina/pc-*` | ningún PR en 36 h (sube una fila todos los días, haya o no hallazgos) |
   | Sesión de arte | `arte/*` | ningún PR en 48 h y hay tareas "necesita PC" de arte abiertas |
   | Revisión / mantenimiento | `rutina/revision-*`, `rutina/mant-*` | ningún PR en 8 días |
   | Lanzamiento | `rutina/lanzamiento-*` | ningún PR en 32 días |
   | Cualquiera | — | PRs de rutina rojos o cerrados sin mezclar, o un issue `rutina-caida` abierto |

   Cada alarma es un hallazgo **P1** del pilar 3 que va directo al informe y a **"Para el usuario"**
   (una rutina caída casi siempre se arregla fuera del repo: la PC, un trigger, el cupo). No genera
   tarea salvo que la causa esté en el repo. QA no tiene alarma: sin hallazgos no abre PR. Sumá también
   los `decide-usuario` abiertos hace más de 7 días, en una línea cada uno. Con
   `.claude/rutinas/PRESUPUESTO` puesto, las rutinas que su nivel deja afuera (regla 1 bis del README) no
   dan alarma. Si en la ventana hubo corridas cortadas por cupo (regla 13: PRs `(partial)` por límite, reservas
   abandonadas en serie, huecos de varias horas en todas las rutinas a la vez) y no hay `PRESUPUESTO`,
   recomendá en "Para el usuario" ponerlo en `ahorro`.

## 2. Dos pasadas en paralelo

Lanzá las dos a la vez (dos llamadas a `auditor-integral` en el mismo mensaje), cada una con la lista
de lo ya conocido:

1. `auditor-integral` con `Pilar: <n>`.
2. `auditor-integral` con `Diff: <primer-hash>^..<commit>` — solo si la ventana tiene commits que no
   sean de rutinas de documentación (`docs:` de revisión/QA/auditoría); si no, se saltea.

## 3. Registrar

- Sin hallazgos nuevos en ninguna pasada ni alarmas del latido: terminá sin PR (regla 7 del README).
  Una alarma del latido sola ya alcanza para abrir el PR con el informe.
- Con hallazgos: rama `rutina/auditoria-AAAA-MM-DD` desde `origin/main`.
  1. `docs/auditorias/AAAA-MM-DD-integral.md`: commit auditado, pilar del día, los hallazgos de las dos
     pasadas sin duplicados (formato del agente, recortado a lo esencial), la matriz impacto/esfuerzo,
     el top 3, las preguntas para el usuario y la línea "Sin cambios".
  2. **Postmortem** por cada incidente de la ventana que cumpla lo de `docs/postmortems/README.md`
     (`main` rojo más de 1 h, rutina caída, regresión que llegó a `main`, revert, corrida trabada):
     `docs/postmortems/AAAA-MM-DD-<tema>.md` con su plantilla, y el link en el informe. Sus acciones
     entran al paso siguiente como hallazgos P1. Si ya existe uno para ese incidente, se completa.
  3. **`planificador-tareas`** con los hallazgos, bajo estas reglas:
     - **Máximo 3 tareas nuevas por corrida**, en orden P0 → P1 → P2. P3 queda solo en el informe (si
       un P3 aparece en 3 informes seguidos, sube a P2).
     - P0 → al principio de `tareas-nacho.md`, en la sección **"QA — bugs abiertos"** si es un bug,
       o **"Auditoría — urgente"** si no (creala si no existe).
     - Cambios de comportamiento de agentes, rutinas, hooks, `CLAUDE.md` o CI → tarea ⏸ "decide el
       usuario": las rutinas no se reescriben solas. Excepción: referencias muertas (una ruta o un
       agente que ya no existe) se arreglan directo en este PR.
     - Nada contra decisiones del usuario (ver reglas del agente): van a "Preguntas para el usuario".
     - Cada tarea lleva "Origen: auditoría integral AAAA-MM-DD, A-<id>".
  4. Todo va a `tareas-nacho.md` (lo del dominio de Slatex como `S-xxx` en "Heredadas de Slatex", nunca a
     `tareas-slatex.md`); aviso en `docs/avisos/` si se agregaron tareas de su dominio.
  5. PR `docs: daily audit AAAA-MM-DD — pillar <n>` con auto-merge. Cuerpo: top 3, tareas creadas
     (IDs) y **"Para el usuario"** con las preguntas y las tareas ⏸, una por línea.

## 4. Límites

- No arregla código ni assets (salvo referencias muertas en `.claude/`): encuentra y planifica.
- Sin Godot: el agente lee código, docs, logs de CI y capturas existentes. Si hace falta medir, la tarea
  es medir, con `perfilador-rendimiento` o `revisor-visual`.
- Freno de tareas (regla 11 del README): con más de 10 tareas abiertas con "Origen: auditoría
  integral", no crees tareas nuevas ese día salvo los P0: solo el informe.
