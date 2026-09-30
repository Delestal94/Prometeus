# Rutina: revisión semanal (la contra)

Una vez por semana el equipo se hace la contra: qué de lo último no suma, qué assets desentonan, qué
de lo que viene conviene cambiar antes de construirlo. Sale una auditoría escrita y tareas nuevas.
Reglas comunes y sesión: `.claude/rutinas/README.md` (leelo primero).

## 1. Juntar el material

- PRs mezclados en los últimos 7 días: `gh pr list --state merged --search "merged:>=<fecha>" --json
  number,title,headRefName,files --limit 50`.
- Las 2 auditorías anteriores en `docs/auditorias/` (para no repetir y ver qué quedó sin resolver).
- Las próximas 5 tareas abiertas de cada lista según su "Orden de ataque".

## 2. Cuatro miradas, en este orden

1. **`abogado-del-diablo`**: sobre lo mezclado en la semana y el hito en curso. Pedile los 6 ejes y el
   top 3 por valor/día.
2. **`director-arte`**: sobre los assets que cambiaron en la semana más un área que rota por semana
   del mes (1: modelos 3D, 2: texturas e imágenes, 3: UI y animaciones, 4-5: audio y efectos). En la nube
   no hay Blender: que trabaje con los .glb, las imágenes y las capturas del repo.
3. **Rotación del mes** (una por semana según `date +%d`: días 1-7, 8-14, 15-21, 22-31):
   - semana 1 — **primera partida**: `pulidor-jugabilidad` en modo "pasada de primera partida" (solo
     informe: pedile que no aplique cambios, la rutina de construcción los toma como tareas);
   - semana 2 — **accesibilidad y opciones**: `director-arte` con foco en su punto 7 más las opciones de
     `ui/options_panel.gd` (subtítulos o texto para lo que solo suena, remapeo, color, sacudida);
   - semana 3 — **red sin mirar un diff**: `auditor-red` sobre el flujo completo (crear sala, join tardío,
     desconexiones, host que se va) para encontrar lo que ningún PR tocó;
   - semana 4 — **rendimiento**: `perfilador-rendimiento` en modo medición (sin cambios) sobre endless y
     entrega, contra los números de la auditoría anterior.
4. **`critico-diseno`**: sobre las próximas tareas que agregan una mecánica nueva o tienen esfuerzo
   `xhigh` (máximo 3), **antes** de que la rutina de construcción las tome. Su veredicto se anota en la
   tarea: "Veredicto `critico-diseno` (AAAA-MM-DD): CONSTRUIR CON CAMBIOS — <cambios>".

## 3. Escribir y planificar

Rama `rutina/revision-AAAA-MM-DD` desde `origin/main`.

1. `docs/auditorias/AAAA-MM-DD-revision.md`: resumen de las cuatro miradas (no el texto entero), con el
   top 3, las decisiones pendientes del usuario y qué quedó sin resolver de la auditoría anterior.
2. **`planificador-tareas`** con los hallazgos, bajo estas reglas:
   - **Máximo 8 tareas nuevas** por semana; el resto queda en la auditoría. Cada una lleva
     `Origen: revisión semanal AAAA-MM-DD`, y con el freno de tareas activo (regla 11 del README) no
     se crea ninguna: todo queda en la auditoría.
   - MANTENER no genera tarea. SIMPLIFICAR y REFINAR chicos → tareas normales (agente sugerido:
     `pulidor-jugabilidad` o el artista del caso).
   - **BORRAR, RECORTAR, REHACER algo grande, POSTERGAR o DESCARTAR** una tarea → tarea ⏸ "decide el
     usuario" con el argumento: nunca se ejecuta sola.
   - Nada contra decisiones ya tomadas por el usuario (personajes en pausa,
     sin playtesting, decisiones de M8): si el abogado las ataca, va a la auditoría como pregunta, no
     como tarea.
3. Todo va a `tareas-nacho.md` (lo del dominio de Slatex como `S-xxx` en "Heredadas de Slatex", nunca a
   `tareas-slatex.md`); aviso en `docs/avisos/` si se agregaron o anotaron tareas de su dominio.
4. PR `docs: weekly review AAAA-MM-DD` con auto-merge. Cuerpo: top 3, tareas creadas (IDs), y una
   sección **"Para el usuario"** con las decisiones ⏸ pendientes, cada una en una línea.
