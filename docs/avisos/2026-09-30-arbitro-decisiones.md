# Aviso: agente nuevo `arbitro-decisiones` (2026-09-30)

Lo hizo Nacho (con Claude). No cambia código del juego.

- **`arbitro-decisiones`** (Opus, esfuerzo alto): cuando dos agentes (o nosotros dos) no coinciden,
  verifica en el código los hechos en disputa, pesa las opciones con criterios fijos (pilar, roles con
  1/2/4/8 jugadores, legibilidad, clip, costo, reversibilidad, calendario) y decide, con confianza y
  "revisar si". Lo que es identidad del juego, alcance de la 1.0 o reparto de trabajo lo deja como
  pregunta para el usuario. Si se le pide, deja el acta como archivo nuevo en `docs/decisiones/`.
- Está en la tabla "Ciclo completo" de `CLAUDE.md` (etapa "Decidir") y en la cobertura por etapa de
  `.claude/rutinas/README.md`.
