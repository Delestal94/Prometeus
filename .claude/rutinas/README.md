# Rutinas: el equipo de agentes trabajando solo

Rutinas que trabajan el repo sin nadie mirando: la mayoría en la nube (triggers de Claude Code) y
dos en la PC de Nacho (Programador de tareas de Windows), para lo que necesita Blender, ComfyUI o una
GPU real. El prompt de cada una dice solo "leé y seguí `.claude/rutinas/<archivo>.md` de
`origin/main`" (más un parámetro si lo tiene): para cambiar cómo trabaja una rutina se cambia su
archivo con un PR.

## Cómo se pasan el trabajo

Ninguna rutina habla con otra: se comunican por archivos del repo y por PRs.

```
revision (lunes) ──► docs/auditorias/AAAA-MM-DD-revision.md ──┐
qa (diario) ───────► docs/qa-recorrido.md (Hallazgos) ────────┤
auditoria (diaria) ► docs/auditorias/AAAA-MM-DD-integral.md ──┼─► planificador-tareas ─► docs/tareas-nacho.md
mantenimiento (jue) ► docs arreglados + hallazgos de código ──┤                              │
lanzamiento (mes) ─► docs/marketing/ ─────────────────────────┤                              ▼
pc-build (PC, diaria) ► docs/rendimiento-pc.md ───────────────┘  construccion (2 por hora) ─► PR ─► CI ─► main
sesion-arte (PC, cada 2 h) ◄── tareas "necesita PC" + inventario + director-arte ──► PR ─► CI ─► main
```

| Rutina | Archivo | Cuándo (hora Argentina) | Rama | Qué produce |
|---|---|---|---|---|
| Desarrollador 1-5 | `desarrollador.md` (`Carril: 1`…`5`, expansión `docs/expansion-distritos/`) | cada hora, escalonados: :02, :14, :26, :38, :50 | `exp/D-xxxx-*` | una tarea `D-` → un PR |
| Construcción A | `construccion.md` (prioridad `nacho`: `N-xxx` primero) | cada hora, :07 | `nacho/N-xxx-*`, `nacho/S-xxx-*` | una tarea → un PR |
| Construcción B ⏸ | `construccion.md` (prioridad `slatex`: heredadas `S-xxx` primero) | pausada desde 2026-10-04: su cupo pasó a los desarrolladores | idem | una tarea → un PR |
| QA (juego actual) | `qa.md` | todos los días 09:00 | `rutina/qa-AAAA-MM-DD-HH` | hallazgos + tareas de bugs |
| QA expansión A y B | `qa.md` con `Foco: expansión` (§4) | todos los días 13:00 y 01:00 | `rutina/qa-exp-AAAA-MM-DD-HH` | bugs en `docs/expansion-distritos/bugs/` |
| Auditoría integral | `auditoria.md` | día por medio 07:00 | `rutina/auditoria-AAAA-MM-DD` | un pilar a fondo + últimas 48 h, ≤ 3 tareas |
| Revisión (la contra) | `revision.md` | lunes 09:00 | `rutina/revision-AAAA-MM-DD` | auditoría + tareas nuevas |
| Mantenimiento | `mantenimiento.md` | jueves 09:00 | `rutina/mant-AAAA-MM-DD` | docs al día + hallazgos |
| Lanzamiento | `lanzamiento.md` | día 1 de cada mes, 10:00 | `rutina/lanzamiento-AAAA-MM` | estado de Steam + tareas |
| Sesión de arte (PC) | `sesion-arte.md` | cada 2 h, a las :30 de las horas pares | `arte/<ID>-*` | un asset creado o refinado → un PR |
| Build y rendimiento (PC) | `pc-build.md` | todos los días 03:15 | `rutina/pc-AAAA-MM-DD` | build de Windows probada, FPS con GPU, capturas con luz real |

## Cobertura por etapa

Cada etapa del desarrollo tiene una rutina que la dispara y agentes que la hacen. Si aparece una etapa o
una carpeta de código sin fila, es un hallazgo del pilar 3 de la auditoría.

| Etapa | Rutina (cuándo) | Agentes |
|---|---|---|
| Juzgar ideas antes de construirlas | revisión (lunes, antes de que construcción tome tareas `xhigh` o mecánicas nuevas) | `critico-diseno` |
| Hacerle la contra a lo hecho | revisión (lunes) | `abogado-del-diablo`, `director-arte` |
| Planificar | todas las que registran hallazgos | `planificador-tareas`, `guardian-dominios` |
| Construir la expansión (`D-xxxx`) | desarrollador 1-5 (cada hora, escalonados) | los de la tabla de carriles de `desarrollador.md` |
| Construir código | construcción (1 por hora) | `constructor-tramos`, `constructor-mundo`, `constructor-camion`, `constructor-jugador`, `constructor-trampas`, `constructor-red`, `constructor-progresion`, `constructor-ui` |
| Sonido, efectos, animación por código, shaders | construcción | `disenador-audio`, `artista-vfx`, `animador`, `artista-shaders` |
| Assets con Blender o ComfyUI, música regenerada, capturas de tienda y tráiler | sesión de arte (PC, cada 2 h) | `modelador-blender`, `artista-conceptual`, `artista-shaders`, `artista-vfx`, `animador`, `disenador-audio` |
| Pulir y balancear | construcción (tareas de revisión y QA) + QA de los domingos (simuladores) | `pulidor-jugabilidad`, `probador-qa` |
| Primera partida y tutorial | revisión, semana 1 del mes → construcción | `pulidor-jugabilidad`, `constructor-ui` |
| Accesibilidad | revisión, semana 2 del mes → construcción | `director-arte`, `constructor-ui` |
| Red y plataforma | construcción (PRs de red) + mantenimiento (jueves) + revisión, semana 3 | `constructor-red`, `auditor-red` |
| Rendimiento | QA (si hay leak) + revisión, semana 4 + build de la PC (diaria, FPS con GPU) | `perfilador-rendimiento` |
| Verificar cada cambio | construcción | `ejecutor-tests`, `escritor-tests`, `cazador-bugs`, `revisor-gdscript`, `revisor-visual` |
| Juego armado de punta a punta | QA (diario) | `probador-qa`, `cazador-bugs` |
| Auditoría del proyecto entero | auditoría (diaria) | `auditor-integral` |
| Docs, avisos, licencias | mantenimiento (jueves) | `documentador`, `guardian-dominios` |
| Página de Steam, cápsulas, calendario, devlog | lanzamiento (mensual) → sesión de arte | `estratega-steam`, `artista-conceptual`, `revisor-visual` |
| Build de prueba | build de la PC (diaria; publicar sigue ⏸ con M5) | `empaquetador-release`, `perfilador-rendimiento`, `revisor-visual` |
| Salud de las rutinas (fallas silenciosas, rutinas que dejaron de producir) | auditoría (diaria, "latido") + issue `rutina-caida` que abre la PC | `auditor-integral` |
| Decisiones del usuario | toda rutina que crea un ⏸ abre un issue `decide-usuario` (regla 12); la revisión semanal junta las respuestas | `planificador-tareas` |
| Regresiones de lo ya mezclado | QA, build de la PC y auditoría → tarea `Regresión de #PR` → construcción (arreglo o `git revert`, regla 14) | `cazador-bugs`, constructor del área |
| Dependencias del juego (Godot, GodotSteam, addons) | lanzamiento (mensual) → tarea | `estratega-steam`, `constructor-red` |
| Tareas viejas u obsoletas | revisión (lunes) → ⏸ "decide el usuario" si ya no aplican | `abogado-del-diablo`, `planificador-tareas` |
| Post-lanzamiento (reseñas, parches) | lanzamiento, dormida hasta un tag `v1.*` | `estratega-steam`, `cazador-bugs`, `pulidor-jugabilidad`, `empaquetador-release` |
| Playtesting con gente | ⏸ decisión del usuario (diferido al final): la lista vive en "Para cuando haya playtesting" de `tareas-nacho.md` | — |
| Personajes (modelo y apariencia) | ⏸ decisión del usuario; S-311 es de Slatex | — |

## Reglas comunes (todas las rutinas)

1. **Freno de mano**: si existe `.claude/rutinas/PAUSA` en `origin/main`, terminá la corrida sin hacer
   nada. Para pausar todo: commitear ese archivo (con el motivo adentro); para reanudar, borrarlo.
2. **Sesión**:
   ```bash
   git fetch origin
   git config user.name "Nacho"
   git config user.email "delestal.miguelignacio@gmail.com"   # los hooks deducen el dueño de acá
   ```
   Ramas siempre desde `origin/main` recién bajado. En la nube Godot está en `$GODOT`. **En la nube no
   hay `gh`**: cada `gh ...` de estas rutinas se hace con la herramienta `mcp__github__*` equivalente
   (runs y logs de CI, PRs, auto-merge, issues). En la PC sí hay `gh`.
3. **Nadie contesta**: no hay revisión humana ni preguntas. Si algo es ambiguo, elegí lo más
   conservador que encaje con `docs/` y escribilo como "Supuesto" en el PR. Las decisiones que solo
   puede tomar el usuario (borrar o recortar una feature, cambiar el alcance) no se
   ejecutan: se dejan como tarea ⏸ "decide el usuario" y van al cuerpo del PR. Excepción pedida por el
   usuario el 2026-10-04: en la expansión (`D-xxxx`) las decisiones de cómo se hace las toma la rutina y
   las documenta (`desarrollador.md` §3 y `docs/decisiones/2026-10-04-expansion-decisiones-delegadas.md`).
4. **Dominios**: se trabaja solo sobre `docs/tareas-nacho.md` (las `N-xxx` y las `S-xxx` heredadas),
   salvo la rutina `desarrollador`, que trabaja solo `docs/expansion-distritos/` (las `D-xxxx`).
   `docs/tareas-slatex.md` (S-311) es de Slatex: no se toman sus ítems ni se le agregan tareas; todo
   hallazgo nuevo va a `tareas-nacho.md`. Tocar archivos de Slatex o la zona compartida exige un aviso
   nuevo en `docs/avisos/` en el mismo PR. No se pisa lo que Slatex tenga en curso (PR abierto o rama
   `origin/slatex/*`).
5. **Godot solo por agentes** (`ejecutor-tests`, `revisor-visual`, `probador-qa`, `cazador-bugs`), tests
   siempre con filtro. La batería completa la corre CI.
6. **Subida**: `SKIP_TESTS=1 git push -u origin HEAD` (nunca `--no-verify`), `gh pr create` con título
   en inglés con prefijo, `gh pr merge --auto --squash`. Los checks requeridos son la única compuerta.
   `SKIP_TESTS=1` saltea los tests del `pre-push` pero no el lint: si lo rechaza, arreglá lo que marca
   (si dice que algo bajó, `bash tools/lint.sh --update-baseline` y commiteá la baseline). Sin `gdlint`
   instalado el hook no lo corre: instalalo (`pip install "gdtoolkit==4.5.0"`) antes del primer push,
   porque un PR que CI rechaza por una línea larga pierde una corrida entera (pasó en el #71).
   **Después de abrir el PR** (lo recuerda el hook `pr-ci-watch`): `vigilante-ci` con su número, y la corrida
   **espera su resultado antes de terminar**. Si queda rojo y no lo pudo arreglar, la causa va como comentario
   del PR. La corrida siguiente lo toma en §1 de `construccion.md` o `desarrollador.md`.
7. **Sin nada que hacer, sin PR**: si la corrida no encontró trabajo o hallazgos, termina sin abrir PR.
8. **Nunca**: editar `*.uid`, `*.import`, `.godot/`, `addons/godotsteam/`; `--no-verify`; forzar sobre
   `main`; **borrar ramas** (ni propias ni ajenas: el control de permisos de la nube lo bloquea y la
   corrida queda trabada esperando a un humano, como pasó el 2026-09-30; ver regla 15); reescribir
   historial.
9. **Un PR por corrida**, salvo arreglar PRs rojos o con conflicto (ver `construccion.md` §1).
10. Cerrá todo proceso de Godot que hayas abierto.
11. **Freno de tareas**: cada tarea que crea una rutina lleva `Origen: <rutina> AAAA-MM-DD` (auditoría
    integral, QA, revisión semanal, mantenimiento, lanzamiento, sesión de arte, PC build). Antes de
    crear, contá las tareas abiertas (sin `[x]`) de `tareas-nacho.md` con el `Origen` de tu rutina: si
    pasan de **10**, no crees ninguna esa corrida; los hallazgos quedan solo en el informe o el PR, y
    en el cuerpo decís "freno de tareas: N abiertas". Siempre entran igual: bugs de QA "bloquea" y P0
    de la auditoría. Así lo que se planifica no le gana a lo que la construcción alcanza a hacer.
12. **Decisiones del usuario, a la vista**: toda tarea ⏸ "decide el usuario" que crees o marques abre
    también un issue de GitHub con la etiqueta `decide-usuario` (título `<ID> · decidir: <qué>`, cuerpo
    con las opciones, tu recomendación y el link a la tarea). Antes, `gh issue list --label
    decide-usuario --state open --search "<ID>"`: si ya existe, comentá en ese. El usuario contesta
    cerrándolo con un comentario; la revisión semanal lleva esa respuesta a la tarea. Los cuerpos de PR
    que se mezclan solos no los lee nadie: el issue le llega como notificación.
13. **Cupo del plan**: si la corrida se queda sin cupo (error de límite de uso, o `api_retry` con
    `rate_limit` que no se recupera), no reintentes en la misma corrida: terminá. No borres nada: una
    reserva sin trabajo la retoma otra corrida (regla 15) y lo que ya estaba subido sigue igual.
14. **Regresiones**: cuando QA, la build de la PC o la auditoría encuentran algo que antes andaba y
    `cazador-bugs` lo atribuye a un PR ya mezclado (con `git log -S`, `git bisect` o el diff del PR), la
    tarea se titula `Regresión de #<PR>: <qué>` y dice qué PR la trajo. La construcción la toma como un
    bug de QA; si el arreglo no es obvio en una corrida, hace `git revert` de ese PR (en una rama, con PR
    y tests como cualquier cambio) y deja una tarea nueva para rehacer la feature sin la regresión.
15. **Reservas abandonadas se retoman, no se borran**: una rama `nacho/<ID>-*` sin PR abierto, cuyos
    commits propios son solo `chore: claim <ID>` y cuyo último commit tiene más de **2 h**
    (`git log origin/main..origin/<rama> --format='%s %cr'`), es de una corrida que se cayó. Tomala
    sobre la misma rama, sin borrarla ni forzar:
    ```bash
    git switch -c <rama> origin/<rama>
    git merge --no-edit origin/main
    git commit --allow-empty -m "chore: reclaim <ID>"
    SKIP_TESTS=1 git push origin HEAD
    ```
    Limpiar ramas viejas no es trabajo de las rutinas.
16. **Estado de `main`** (N-239): se mira el run de `tests.yml` **del SHA de HEAD**, no el último run de
    la rama (el auto-merge no dispara CI y el último run puede ser de un commit viejo):
    ```bash
    gh run list --workflow tests.yml --commit "$(git rev-parse origin/main)" --json conclusion,status
    ```
    - `success` → verde. `failure` → **rojo**.
    - Sin run, o en curso → **sin verificar**. `main-head-tests.yml` le dispara uno en ≤ 15 min. Mientras
      tanto, el último run terminado de main (`gh run list --branch main --workflow tests.yml --status
      completed --limit 1`) dice si sigue rojo de antes: rojo ahí cuenta como rojo. Verde ahí no prueba
      HEAD: se puede trabajar, pero lo que exige un `main` probado (la build de la PC) espera.
17. **Lista viva y archivo**: `docs/tareas-nacho.md` tiene solo lo pendiente; lo terminado está en
    `docs/tareas-nacho-archivo.md` (lo mueve `tools/archivar-tareas.py` en el mantenimiento semanal). Para
    saber si una dependencia o un hallazgo ya está hecho, `grep` del ID o del tema en los dos archivos: el
    archivo no se lee entero ni se le agregan tareas.

## Límites de la nube

Blender y ComfyUI no están: `modelador-blender`, `artista-conceptual` y la parte de assets de
`animador`, `artista-shaders` y `artista-vfx` quedan para `sesion-arte.md` (también regenerar música
con `tools/audio/compose_music.py`). Las capturas son render por software: composición, colores y UI
valen; sombras y FPS no. Builds, FPS y luz real: `pc-build.md`; capturas de tienda y tráiler: `sesion-arte.md`.

## Los triggers de la nube

Si cambia el horario de una rutina o se suma una, actualizá también `ROUTINES` en
`tools/panel/build_data.py` (cron en UTC): la sala de control (`panel/README.md`) calcula de ahí qué rutina
le toca y cuál no dejó rastro, y su workflow falla con una fila de esta tabla sin horario.

Los crea la conversación principal con la skill `schedule`. El prompt de cada uno es una línea:
`Leé .claude/rutinas/<archivo>.md de origin/main y seguilo al pie de la letra.` (construcción suma
`Prioridad: nacho` o `Prioridad: slatex`; desarrollador, `Carril: N`). La API de triggers elige el
**modelo** de la sesión que coordina; el **esfuerzo** está fijo en cada agente de `.claude/agents/`, que es
quien hace el trabajo pesado. Modelos (2026-10-04, para estirar el cupo semanal, que se agotó el 2026-10-03):

| Trigger | Modelo | Por qué |
|---|---|---|
| Desarrollador 1 (arquitectura) y 5 (red) | Opus 5.5 | decisiones de estructura y autoridad de red |
| Desarrollador 2, 3 y 4 | Sonnet 5.5 | coordinan constructores (Sonnet high) y revisores (Opus) |
| Construcción A | Sonnet 5.5 | idem; para el diagnóstico de bugs llama a `cazador-bugs` (Opus) |
| QA, mantenimiento, lanzamiento | Sonnet 5.5 | corren agentes y resumen |
| Auditoría integral, revisión semanal | Opus 5.5 | juicio sobre el proyecto entero |

## Las rutinas de la PC

La PC queda prendida y con la sesión de Windows abierta (Blender necesita pantalla). Las lanza el
Programador de tareas con `tools/pc/rutina-pc.ps1 -Rutina arte|build`, que:

- trabaja en un **clon aparte** (`Prometeus-rutina`, al lado del repo de trabajo): nunca toca la copia
  donde trabaja Nacho;
- sale enseguida si está `.claude/rutinas/PAUSA` en `origin/main` (el mismo freno de mano) o si otra
  rutina de la PC está corriendo (un solo candado: comparten la GPU de 8 GB; la de build espera hasta
  100 min, la de arte no espera);
- deja el clon en `origin/main` y **se relanza desde esa copia** (`-Fresh`): el Programador ejecuta
  el script que dejó la corrida anterior, que puede ser viejo (el 2026-09-30 una caída no abrió su
  issue por eso);
- abre Blender minimizado con el servidor MCP prendido (`tools/pc/blender_mcp_autostart.py`) si no
  está abierto, y deja `GODOT` apuntando al Godot de la PC;
- actualiza Claude Code (`npm i -g @anthropic-ai/claude-code@latest`) antes de cada corrida: con una
  versión vieja, Opus 5.5 responde 400 y la corrida muere en segundos (pasó el 2026-09-30);
- corre `claude -p` con Opus 5.5, permisos en modo `auto` (lo que pediría permiso se niega solo) y solo
  los MCP de Blender y ComfyUI, y guarda el log (UTF-8) en `%LOCALAPPDATA%\prometeus-rutinas\logs\`;
- **si la corrida falla**, abre o comenta el issue "Rutina de PC caída" (etiqueta `rutina-caida`) con el
  final del log, y lo cierra solo cuando una corrida vuelve a terminar bien. La nube no ve los logs de
  la PC: ese issue es lo único que avisa (y la auditoría lo reporta).

El clon `Prometeus-rutina` tiene que estar marcado como confiable en `~/.claude.json`
(`projects["D:/Programas/Utilities/Proyectos/Prometeus-rutina"].hasTrustDialogAccepted: true`); si no,
Claude Code ignora los permisos de `.claude/settings.json` del proyecto.

Tareas del Programador (registradas el 2026-09-30): "Prometeus - Sesion de arte (PC)" y "Prometeus -
Build y rendimiento (PC)", solo con la sesión de Windows abierta, máximo 3 h por corrida. También se
pueden correr en vivo pidiéndolas ("corré la sesión de arte", "corré el build de la PC"). Para ver qué
hizo una corrida, su log; para frenarlas solo en la PC, deshabilitá esas dos tareas.
