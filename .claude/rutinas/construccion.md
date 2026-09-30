# Rutina: construcción → una tarea, un PR

Trabaja **solo** `docs/tareas-nacho.md` sin nadie mirando: las `N-xxx` y las `S-xxx` de su sección
"Heredadas de Slatex" (desde el 2026-09-29 son de Nacho). `docs/tareas-slatex.md` (S-311, el personaje
de gelatina) es de Slatex y no se toca nunca: ni se toman sus ítems ni se le agregan tareas. Corren dos
triggers con este mismo archivo: **Prioridad: nacho** (`N-xxx` primero) y **Prioridad: slatex**
(heredadas `S-xxx` primero). Así las dos corridas avanzan en frentes distintos y casi nunca compiten.
Reglas comunes, freno de mano y sesión: `.claude/rutinas/README.md` (leelo primero).

Una corrida = **una** tarea, o arreglar PRs de rutina rojos o con conflicto.

## 1. Primero lo que está roto

1. **`main` rojo**: `gh run list --branch main --workflow tests.yml --limit 1`. Si falló, arreglar main
   es la tarea (rama `nacho/fix-main-<tema>`), con `ejecutor-tests` y `cazador-bugs`.
2. **PRs de rutina abiertos**:
   `gh pr list --state open --json number,headRefName,statusCheckRollup,mergeable` y quedate con los
   `nacho/*` y `rutina/*`.
   - **Con conflicto** (`mergeable: CONFLICTING`): `git switch` a la rama, `git rebase origin/main`,
     resolvé (en `docs/tareas-*.md` casi siempre es conservar las dos líneas), `git push
     --force-with-lease` (solo en ramas de rutina, nunca en `main`).
   - **Rojo**: leé el log del check que falló (`gh run view <id> --log-failed`, solo errores), reproducí
     con `ejecutor-tests` y el filtro del test, y si la causa no es obvia pasalo por `cazador-bugs`.
     Máximo 3 intentos por PR (contá los commits `fix:` que sumó la rutina). Al tercero sin verde:
     `gh pr close <n> --comment "<diagnóstico>"`, marcá la tarea `⚠ Bloqueada (AAAA-MM-DD): <motivo>,
     PR #n cerrado` en un PR chico de docs, y seguí.
3. **4 PRs `nacho/` abiertos o más**: no abras otro. Terminá la corrida.

## 2. Elegir la tarea

Para las dos prioridades, primero la sección **"QA — bugs abiertos"** de `tareas-nacho.md` (la llena la
rutina de QA), con gravedad "bloquea" antes que el resto; entre ellas, las `Regresión de #<PR>` primero
(regla 14 del README: si el arreglo no sale en esta corrida, `git revert` de ese PR). Después:

- **`nacho`**: las `N-xxx` en el orden de la tabla "Orden de ataque" (**M8 primero**); si no queda
  ninguna tomable, las heredadas `S-xxx`.
- **`slatex`**: las heredadas `S-xxx` en el orden de sus hitos (tabla de "Heredadas de Slatex":
  S-M1 → S-M5; las que no figuran en ningún hito, después, por prioridad A → B → C); si no queda
  ninguna, las `N-xxx`.

Saltá:
- ⏸ (incluye "decide el usuario"), ⚠ Bloqueada, N-211, N-702, la meta de FPS de N-204 y todo lo de
  "Para cuando haya playtesting";
- lo que necesita la PC (ComfyUI, Blender, generar imágenes, render con GPU real, FPS con ventana): si
  no dice "necesita PC", agregáselo en el mismo PR de tu tarea y seguí;
- lo que ya tenga PR abierto o rama `origin/nacho/<ID>-*` (otra corrida la reclamó). Excepción: una
  reserva abandonada (solo `chore: claim <ID>`, más de 2 h, sin PR) se retoma sobre la misma rama
  según la regla 15 del README; nunca se borra;
- personajes (modelo y apariencia): no hasta que el usuario lo pida (decisión del 2026-09-29). S-311
  (personaje de gelatina, `tareas-slatex.md`) es de Slatex; sus ítems no se toman, y toda tarea N o S
  que toque el cuerpo, el ragdoll, los clips o la apariencia del personaje (accesorios, emotes,
  proporciones) queda en pausa mientras siga abierta, aunque no tenga ⏸ (decisión del 2026-09-30).

Si una heredada todavía trae modelos de ChatGPT anotados (`Sol`, `Astra`, `Luna`), ignoralos: se
trabaja con Opus 5.5 y los agentes de acá. Antes de empezar una tarea, verificá en el código que no esté ya hecha (a veces se hizo y no se marcó): si lo está, marcala con el hash que
la hizo en un PR de docs y elegí otra.

**Reclamala enseguida**, antes de trabajar, para que la otra corrida no la tome:
```bash
git switch -c nacho/<ID>-<tema-corto> origin/main
git commit --allow-empty -m "chore: claim <ID>"
SKIP_TESTS=1 git push -u origin HEAD     # rama en origin = tarea reclamada
```

## 3. Hacer la tarea (la rutina orquesta)

Los subagentes no pueden lanzar otros: todo lo que sigue lo decide la rutina.

1. **Plan corto**: qué archivos, qué test, qué agente. Si toca 3+ carpetas o la zona compartida, pasalo
   por `guardian-dominios`.
2. **Construir** con el agente del área, dándole el contexto completo de la tarea (pierde el tuyo), o
   vos mismo si cruza varias áreas. Revisá siempre lo que devuelva.

   | Área (carpeta) | Agente |
   |---|---|
   | Tipos de tramo y generación de la ruta (`route/segments/`, `route_streamer`, `route.gd`, terreno) | `constructor-tramos` |
   | Depósito, casas, clima y hora, cielo, fauna, historias, carteles, decorado general, mezcla del mundo, calidad (`depot/`, el resto de `route/`) | `constructor-mundo` |
   | Camión (`vehicle/`, `vehicle_presentation`; `vehicle.gd`/`.tscn` editables; sistemas nuevos como componente aparte) | `constructor-camion` |
   | Jugador, paquete fuera de su trampa, interacción, cámaras de asiento, celular, espectador (`player/`, `package/`, `interaction/`) | `constructor-jugador` |
   | Trampas (`traps/`, `data/traps/`) | `constructor-trampas` |
   | Red y Steam (`network_manager`, `proximity_voice`, relays, sincronizadores, lobby, logros, nube) | `constructor-red` (y siempre `auditor-red` después) |
   | Economía, progresión, eventos, puntaje, campaña | `constructor-progresion` |
   | UI, HUD, menús, tutorial y tips de primera vez (`scripts/ui/`) | `constructor-ui` |
   | Sonido y música (`synth_audio*`, `tools/audio/`) | `disenador-audio` |
   | Partículas y efectos | `artista-vfx` (sin ComfyUI) |
   | Animación por código, `PlayerAnimator` | `animador` (sin Blender) |
   | Shaders | `artista-shaders` (sin Blender/ComfyUI) |
   | Pulir o balancear algo que ya existe (con los simuladores) | `pulidor-jugabilidad` |
   | Tests que faltan | `escritor-tests` |
   | Rendimiento medido | `perfilador-rendimiento` |

   Si la carpeta de la tarea no está en la tabla, hacela vos y anotá en el PR "área sin constructor:
   <carpeta>": la auditoría (pilar 3) lo convierte en tarea.

3. **Test** nuevo o ampliado (skill `nuevo-test`).
4. **Correr** con `ejecutor-tests` y el filtro del área, nunca sin filtro.
5. **Falla sin causa clara**: `cazador-bugs` una vez; arreglá con su diagnóstico.
6. **Red** (RPC, autoridad, `MultiplayerSynchronizer`, joins tardíos, semilla): `auditor-red` antes del
   PR; arreglá lo que marque BUG o RIESGO alto, el resto al cuerpo del PR.
7. **Visual**: `revisor-visual`.
8. **Zona compartida o archivos de Slatex**: `revisor-gdscript` sobre el diff antes del PR.
9. **Camión** (`vehicle.gd`/`vehicle.tscn`, se editan libremente desde el 2026-09-30): tests del camión
   (`ejecutor-tests` con los filtros `vehicle` y `truck`) y `auditor-red`, porque su sincronización es la
   más delicada del juego.

Nunca en la nube: `modelador-blender`, `artista-conceptual`, `empaquetador-release` (los corren las
rutinas de la PC: `sesion-arte.md` y `pc-build.md`). `critico-diseno` y `abogado-del-diablo` son de la
rutina de revisión, no de esta.

## 4. Cerrar y subir

1. Skill `cerrar-cambio` completa: test documentado, tarea marcada `[x]` con el hash en
   `tareas-nacho.md`, aviso en `docs/avisos/` si tocó archivos de Slatex o la zona compartida (las
   heredadas casi siempre: son archivos de su dominio).
2. Subida según el README (`SKIP_TESTS=1`, PR con prefijo, `--auto --squash`). Cuerpo: qué se hizo, cómo
   se verificó, agentes usados, supuestos, avisos. Si quedó a medias, "(partial)" en el título y las
   subtareas abiertas en el cuerpo.
