# Rutina: tareas de Nacho → un PR por tarea

Instrucciones para la rutina en la nube que trabaja `docs/tareas-nacho.md` sin nadie mirando.
El prompt del trigger solo dice "leé y seguí `.claude/rutinas/tareas-nacho.md` de `origin/main`":
para cambiar cómo trabaja la rutina, se cambia este archivo con un PR.

Una corrida = **una** tarea (o arreglar un PR rojo). Plan Pro con cuota limitada: un agente a la vez,
nada en paralelo, nunca la batería entera en local.

## 0. Preparar la sesión

```bash
git fetch origin
git config user.name "Nacho"
git config user.email "delestal.miguelignacio@gmail.com"   # los hooks deducen el dueño de acá
```

Con eso `bash -c '. .claude/hooks/lib.sh; current_owner'` tiene que decir `nacho`. En la nube, el
hook de arranque deja Godot en `~/godot` y `GODOT` definido.

## 1. Primero los PRs abiertos

`gh pr list --state open --search "head:nacho/" --json number,headRefName,statusCheckRollup,labels`

- **PR rojo** (un check requerido falló): arreglarlo es la tarea de esta corrida. Leé el log del check
  que falló (`gh run view <id> --log-failed`, solo las líneas de error), reproducí con `ejecutor-tests`
  y el filtro del test, y si la causa no es obvia pasalo por `cazador-bugs`. Máximo 3 intentos por PR
  (contá los commits `fix:` que sumó la rutina).
- **No hay revisión humana, nunca** (decisión del usuario): nada de etiquetas "para revisar", pedidos
  de aprobación ni esperar a que alguien mire. Si el tercer intento tampoco pone el PR en verde:
  cerralo con `gh pr close <n> --comment "<diagnóstico: qué falla, qué se probó, qué dijo cazador-bugs>"`
  (la rama queda en origin), marcá la tarea en `docs/tareas-nacho.md` como
  `⚠ Bloqueada (AAAA-MM-DD): <motivo en una línea>, PR #n cerrado` en un PR chico de docs, y seguí
  con otra tarea. Una corrida futura la retoma desde cero solo si cambió algo que la destrabe (otra
  tarea mergeada, un arreglo en main).
- **3 PRs `nacho/` abiertos**: no abras otro. Terminá la corrida.

## 2. Elegir la tarea

En `docs/tareas-nacho.md`, la primera tarea abierta (`[ ]`) siguiendo el orden de hitos: **M8
primero**, después el orden de la tabla "Orden de ataque". Saltá:

- lo marcado ⏸, N-211, N-702, la meta de FPS de N-204 y todo lo de "Para cuando haya playtesting";
- lo que necesita la PC de Nacho: ComfyUI, Blender, render con GPU real, medir FPS con ventana (dejá
  una línea "necesita PC" en la tarea si no la tiene);
- lo que ya tenga un PR abierto o una rama `origin/nacho/N-xxx-*`;
- lo que exija editar `vehicle.tscn` / `vehicle.gd` (congelados desde M6): si se puede hacer como
  componente aparte, hacelo así; si no, anotalo en la tarea y seguí.
- Personajes: no tocar hasta que el usuario lo pida (decisión del 2026-09-29).

Si la tarea es ambigua, no preguntes (nadie contesta): elegí la opción más conservadora que encaje con
`docs/` y dejala escrita como "Supuesto" en el PR y en la tarea.

Rama: `git switch -c nacho/N-xxx-<tema-corto> origin/main`.

## 3. Hacer la tarea (la rutina orquesta, los agentes ayudan)

Los subagentes no pueden lanzar otros subagentes: todo lo que sigue lo decide la rutina.

1. **Plan corto** (qué archivos, qué test). Si la tarea tiene `Aviso: sí` o toca 3+ carpetas, pasá el
   plan por `guardian-dominios`. Tocar archivos de Slatex o la zona compartida no frena la tarea:
   exige el aviso en el mismo commit. Lo congelado sí frena.
2. **Implementá vos** (Opus 5.5). Los constructores (`constructor-tramos`, `constructor-trampas`,
   `constructor-ui`, `disenador-audio`) corren en Sonnet 5.5 y pierden el contexto de la tarea: usalos
   solo para una pieza aislada y bien definida, y revisá lo que devuelvan.
3. **Test**: nuevo o ampliado, siguiendo la skill `nuevo-test`.
4. **Correr**: `ejecutor-tests` con el filtro del área (`route`, `trap`, `hud`…), nunca sin filtro.
5. **Si falla sin causa clara**: `cazador-bugs` una vez; arreglá con su diagnóstico.
6. **Si la tarea toca red** (RPC, autoridad, `MultiplayerSynchronizer`, joins tardíos, semilla):
   `auditor-red` una vez antes del PR. Arreglá lo que marque como BUG o RIESGO alto; el resto va al
   cuerpo del PR.
7. **Si la tarea pide capturas o es visual**: `revisor-visual` (render por software en la nube:
   composición, colores y UI valen; sombras y rendimiento no).
8. `revisor-gdscript` no corre en cada PR (cuesta cuota y el equipo sacó la revisión por LLM del CI).
   Usalo solo si la tarea es un refactor de la zona compartida.

Nunca: artistas, `modelador-blender`, `critico-diseno`, `empaquetador-release`.

## 4. Cerrar y subir

1. Skill `cerrar-cambio` completa (test documentado, tarea marcada con el hash, aviso si hubo).
2. `SKIP_TESTS=1 git push -u origin HEAD` (el bypass oficial del hook; nunca `--no-verify`). CI corre
   la batería completa.
3. `gh pr create` con título en inglés con prefijo (`feat: N-xxx …`), cuerpo con qué se hizo, cómo se
   verificó, supuestos y avisos. Si la tarea quedó a medias, "(partial)" en el título y las subtareas
   abiertas en el cuerpo.
4. `gh pr merge --auto --squash`: entra solo cuando los checks requeridos pasan. No hay revisión humana.
5. Cerrá todo proceso de Godot que hayas abierto.
