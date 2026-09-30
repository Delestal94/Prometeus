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

## 2. Dos pasadas en paralelo

Lanzá las dos a la vez (dos llamadas a `auditor-integral` en el mismo mensaje), cada una con la lista
de lo ya conocido:

1. `auditor-integral` con `Pilar: <n>`.
2. `auditor-integral` con `Diff: <primer-hash>^..<commit>` — solo si la ventana tiene commits que no
   sean de rutinas de documentación (`docs:` de revisión/QA/auditoría); si no, se saltea.

## 3. Registrar

- Sin hallazgos nuevos en ninguna pasada: terminá sin PR (regla 7 del README).
- Con hallazgos: rama `rutina/auditoria-AAAA-MM-DD` desde `origin/main`.
  1. `docs/auditorias/AAAA-MM-DD-integral.md`: commit auditado, pilar del día, los hallazgos de las dos
     pasadas sin duplicados (formato del agente, recortado a lo esencial), la matriz impacto/esfuerzo,
     el top 3, las preguntas para el usuario y la línea "Sin cambios".
  2. **`planificador-tareas`** con los hallazgos, bajo estas reglas:
     - **Máximo 3 tareas nuevas por corrida**, en orden P0 → P1 → P2. P3 queda solo en el informe (si
       un P3 aparece en 3 informes seguidos, sube a P2).
     - P0 → al principio de `tareas-nacho.md`, en la sección **"QA — bugs abiertos"** si es un bug,
       o **"Auditoría — urgente"** si no (creala si no existe).
     - Cambios de comportamiento de agentes, rutinas, hooks, `CLAUDE.md` o CI → tarea ⏸ "decide el
       usuario": las rutinas no se reescriben solas. Excepción: referencias muertas (una ruta o un
       agente que ya no existe) se arreglan directo en este PR.
     - Nada contra decisiones del usuario (ver reglas del agente): van a "Preguntas para el usuario".
     - Cada tarea lleva "Origen: auditoría integral AAAA-MM-DD, A-<id>".
  3. Todo va a `tareas-nacho.md` (lo del dominio de Slatex como `S-xxx` en "Heredadas de Slatex", nunca a
     `tareas-slatex.md`); aviso en `docs/avisos/` si se agregaron tareas de su dominio.
  4. PR `docs: daily audit AAAA-MM-DD — pillar <n>` con auto-merge. Cuerpo: top 3, tareas creadas
     (IDs) y **"Para el usuario"** con las preguntas y las tareas ⏸, una por línea.

## 4. Límites

- No arregla código ni assets (salvo referencias muertas en `.claude/`): encuentra y planifica.
- Sin Godot: el agente lee código, docs, logs de CI y capturas existentes. Si hace falta medir, la tarea
  es medir, con `perfilador-rendimiento` o `revisor-visual`.
- Si la rutina de construcción no alcanza a consumir lo que esta genera (más de 10 tareas con "Origen:
  auditoría integral" abiertas), no crees tareas nuevas ese día: solo el informe.
