# Las rutinas de Nacho se quedan sin cupo 6 días de cada 7 — 2026-10-13

**Impacto:**
- Del 2026-10-13 al 10-18 ninguna rutina de Nacho dejó un PR. Lo mismo pasó del 10-05 al 10-11.
- QA, mantenimiento y auditoría no producen desde el 10-01 o 10-02, unos 17 a 18 días.
- El build de la PC no deja un PR desde el 10-12.
- Solo Slatex (Codex) siguió subiendo PRs en esos huecos.

**Detectado por:** el latido de la auditoría integral del 2026-10-19, la primera que corrió desde el 10-02.

## Línea de tiempo (UTC, sacada de los PRs)

- **10-03:** se agota el cupo semanal (`README.md`, sección de modelos).
- **10-04, 09:29 → 10-05, 00:43:** ráfaga de unos 90 PRs. Se crea `PRESUPUESTO`, pero no se commitea.
- **10-05 → 10-11:** ninguna rutina de Nacho deja PR.
- **10-12, 06:21 → 22:26:** ráfaga de unos 63 commits. Entran la revisión semanal (#392) y el build de la PC (#370).
- **10-13 → 10-18, 21:00:** nada de Nacho.
- **10-18, 21:12 → ahora:** ráfaga de desarrolladores, construcción y arte.
- **10-19, 03:15:** falla el build de la PC (issue #483). A las 06:54 el issue se cierra solo, por un éxito de la rutina de arte.

## Causa raíz

1. ¿Por qué no corren QA, auditoría ni mantenimiento? Porque cuando les toca su horario fijo, el cupo ya se agotó.
2. ¿Por qué se agota? Porque el programa pide unas 650 corridas por semana, sobre todo los carriles de la expansión, construcción cada hora y arte en Opus cada 2 h. El cupo alcanza para unas 15 h.
3. ¿Por qué nadie lo frenó? Porque `PRESUPUESTO` solo lo puede poner el usuario (`README.md`, regla 1 bis), y la recomendación de ponerlo va en el cuerpo de un PR de auditoría que nadie lee.
4. ¿Por qué nadie se enteró? Porque el único latido es la auditoría, que también se queda sin cupo. Además el issue `rutina-caida` de la PC lo cierra el éxito de otra rutina, y su texto no distingue el límite de uso.
5. ¿Qué permitió el error? Un sistema de vigilancia que depende del mismo recurso que vigila.

## Qué funcionó y qué no

- **Funcionó:** el CI siguió siendo la compuerta. No entró nada rojo a `main` en las ráfagas.
- **Funcionó:** las ráfagas sí producen, con PRs chicos y verdes.
- **No funcionó:** el freno `PRESUPUESTO` existe, pero nunca se usó.
- **No funcionó:** no hay ningún aviso sin modelo.
- **No funcionó:** el issue de la PC tapó la caída del build.

## Acciones

| Acción | Tipo | Tarea o PR |
|---|---|---|
| Poner `PRESUPUESTO` en `ahorro` y bajar el programa a lo que entra en el cupo | usuario | "Para el usuario" del PR de auditoría 2026-10-19 (A-3.1) |
| Latido sin modelo (`routine-heartbeat.yml`) que abre `rutina-caida` | proceso ⏸ | tarea de A-3.2 |
| Issue `rutina-caida` por rutina de la PC, con detección de límite de uso | proceso ⏸ | tarea de A-3.3 |
| Que la auditoría pueda poner `PRESUPUESTO` sola (regla 3) | usuario | A-3.4, pregunta 2 del informe |
