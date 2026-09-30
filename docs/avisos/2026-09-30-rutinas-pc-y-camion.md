# 2026-09-30 · Rutinas de la PC, camión libre para las rutinas y freno de tareas

**De:** Nacho · **Para:** Slatex

Tres cambios en cómo trabajan las rutinas (nada cambia en tu lista ni en S-311):

- **Camión**: la rutina de construcción ya no se saltea las tareas que editan `vehicle.gd` /
  `vehicle.tscn` (se liberaron en el #57). Cuando los toque, pasa por los tests del camión y por
  `auditor-red`.
- **Rutinas de la PC** (`.claude/rutinas/sesion-arte.md` y `pc-build.md`, con `tools/pc/rutina-pc.ps1`):
  una crea y refina assets con Blender y ComfyUI (ramas `arte/*`), la otra exporta la build de Windows y
  mide FPS con GPU todos los días (`docs/rendimiento-pc.md`). La de arte no toca personajes ni nada que
  choque con S-311. Pueden tocar assets de tu dominio heredado (UI 2D, paquetes); cada PR que lo haga
  deja su aviso acá.
- **Freno de tareas** (regla 11 del README de rutinas): cada rutina que planifica deja de crear tareas
  si ya tiene más de 10 abiertas con su `Origen`.

Cambios: `.claude/rutinas/{README,construccion,sesion-arte,pc-build,qa,revision,mantenimiento,lanzamiento,auditoria}.md`,
`tools/pc/`, `CLAUDE.md`.
