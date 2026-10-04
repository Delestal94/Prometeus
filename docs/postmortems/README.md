# Postmortems

Cuando algo del proceso falla en serio, se escribe qué pasó para que no vuelva a pasar, sin buscar
culpables (personas, rutinas ni agentes: se busca qué permitió el error). Hasta ahora las lecciones
quedaban sueltas dentro de las reglas ("pasó el 2026-09-30"); acá quedan enteras y con sus acciones.

## Cuándo

Lo escribe la **auditoría integral** (`.claude/rutinas/auditoria.md`) cuando en su ventana hubo:

- `main` en rojo más de 1 h (run del SHA de HEAD, regla 16), salvo un test inestable que `ci-flaky.yml`
  salvó al reintentar;
- una rutina caída (issue `rutina-caida`) o sin rastro más de un día;
- una regresión que llegó a `main` y se vio después (tarea `Regresión de #PR`);
- un PR mezclado que hubo que revertir;
- una corrida trabada esperando a una persona, o trabajo duplicado entre rutinas.

Un incidente, un archivo: `docs/postmortems/AAAA-MM-DD-<tema>.md` (fecha del incidente).

## Plantilla

```markdown
# <Qué pasó, en una línea> — AAAA-MM-DD

**Impacto:** qué se frenó o rompió y cuánto tiempo (por ejemplo, "main rojo 3 h 10 min; 4 corridas de
construcción gastadas arreglando lo mismo").
**Detectado por:** quién lo vio primero (QA, latido de la auditoría, ci-flaky, el usuario).

## Línea de tiempo (hora Argentina)
- HH:MM — …

## Causa raíz
Cinco porqués, hasta llegar a algo del proceso (una regla, un check, un hook, una herramienta).

## Qué funcionó y qué no
- Funcionó: …
- No funcionó: …

## Acciones
| Acción | Tipo | Tarea o PR |
|---|---|---|
| … | prevenir / detectar antes / recuperar más rápido | N-xxx |
```

Las acciones que cambian rutinas, agentes, hooks o CI siguen la regla de la auditoría: van como tarea
⏸ "decide el usuario", salvo referencias muertas.
