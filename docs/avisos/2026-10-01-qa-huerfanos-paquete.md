# Tarea S-908: nodos huérfanos en `package_salvage.gd`

**Fecha:** 2026-10-01 · **De:** rutina QA (Nacho) · **Para:** Slatex

## Qué cambió

Solo documentación: se agregó la tarea heredada `S-908` en `docs/tareas-nacho.md` ("QA — bugs abiertos"). Toca tu
dominio, `scripts/gameplay/package/package_salvage.gd:25-59`: `tape_mesh` y `toy_mesh` se cuelgan con
`add_child.call_deferred`, y si el paquete se libera antes, quedan sin padre (unos 50 huérfanos por nivel liberado:
`RepairTape`, `ReplacementHen`). Gravedad molesta, prioridad B.

## Qué tiene que hacer Slatex

Nada: la rutina de Nacho toma la tarea. Si tenés cambios en curso en ese archivo, avisá para no pisarnos.
