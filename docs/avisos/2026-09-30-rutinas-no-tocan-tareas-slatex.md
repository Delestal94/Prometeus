# 2026-09-30 · Las rutinas no tocan `tareas-slatex.md`

**De:** Nacho · **Para:** Slatex

Aclara el aviso `2026-09-29-slatex-personaje-gelatina.md`: desde hoy las rutinas en la nube trabajan
**solo** `docs/tareas-nacho.md` (las `N-xxx` y las `S-xxx` heredadas). Tu lista, `docs/tareas-slatex.md`
con S-311, es tuya:

- Ninguna rutina toma ítems de S-311 ni te agrega tareas. Lo que QA, auditoría o revisión encuentren en
  tu dominio va como `S-xxx` a "Heredadas de Slatex" en `tareas-nacho.md`, con aviso acá.
- Lo heredado que choque con el personaje (cuerpo, ragdoll, accesorios, emotes) queda en pausa mientras
  S-311 siga abierta.
- Sigue igual: cada PR de rutina que toque archivos de tu dominio deja su aviso en `docs/avisos/`.

Cambios: `.claude/rutinas/{README,construccion,qa,auditoria,revision,mantenimiento}.md`,
`.claude/agents/planificador-tareas.md`, `CLAUDE.md`.
