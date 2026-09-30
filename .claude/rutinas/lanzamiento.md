# Rutina: lanzamiento (mensual)

Mantiene vivo el plan de Steam para que el juego no llegue "terminado" sin página, sin cápsulas ni
features de plataforma. Reglas comunes y sesión: `.claude/rutinas/README.md` (leelo primero).

## 1. Estado

**`estratega-steam`** con este pedido: actualizá `docs/marketing/estado-steam.md` (crealo si no existe)
con

1. features de Steam que un coop necesita y su estado real en el código (Remote Play Together, lobby e
   invitaciones, logros, nube, mando, Steam Deck, declaración de IA desde `art/ai-registro.md`);
2. calendario hacia atrás desde la fecha objetivo de `docs/plan-desarrollo.md` (si no hay fecha,
   proponé una y marcala como decisión pendiente);
3. qué cápsulas y capturas existen y cuáles faltan;
4. qué cambió desde el mes pasado (lo mezclado en el mes, `git log --since="1 month ago"`).

## 2. Registrar

Rama `rutina/lanzamiento-AAAA-MM`.

- `docs/marketing/estado-steam.md` actualizado (y los archivos de `docs/marketing/` que el agente toque).
- **`planificador-tareas`** con lo que implica trabajo en el juego: **máximo 5 tareas** por mes, con
  `Origen: lanzamiento AAAA-MM` y sujetas al freno de tareas (regla 11 del README). Cápsulas
  e imágenes → "necesita PC" (las hace la sesión de arte). Precio, fecha y alcance de idiomas → ⏸
  "decide el usuario".
- PR `docs: launch status AAAA-MM` con auto-merge; sección "Para el usuario" con las decisiones pendientes.
