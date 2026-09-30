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
| Construcción A | `construccion.md` (prioridad `nacho`: `N-xxx` primero) | cada hora, :07 | `nacho/N-xxx-*`, `nacho/S-xxx-*` | una tarea → un PR |
| Construcción B | `construccion.md` (prioridad `slatex`: heredadas `S-xxx` primero) | cada hora, :37 | idem | una tarea → un PR |
| QA | `qa.md` | todos los días 06:00 | `rutina/qa-AAAA-MM-DD` | hallazgos + tareas de bugs |
| Auditoría integral | `auditoria.md` | todos los días 04:00 | `rutina/auditoria-AAAA-MM-DD` | un pilar a fondo + últimas 24 h, ≤ 3 tareas |
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
| Construir código | construcción (2 por hora) | `constructor-tramos`, `constructor-mundo`, `constructor-camion`, `constructor-jugador`, `constructor-trampas`, `constructor-red`, `constructor-progresion`, `constructor-ui` |
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
   Ramas siempre desde `origin/main` recién bajado. En la nube Godot está en `$GODOT`.
3. **Nadie contesta**: no hay revisión humana ni preguntas. Si algo es ambiguo, elegí lo más
   conservador que encaje con `docs/` y escribilo como "Supuesto" en el PR. Las decisiones que solo
   puede tomar el usuario (borrar o recortar una feature, cambiar el alcance) no se
   ejecutan: se dejan como tarea ⏸ "decide el usuario" y van al cuerpo del PR.
4. **Dominios**: se trabaja solo sobre `docs/tareas-nacho.md` (las `N-xxx` y las `S-xxx` heredadas).
   `docs/tareas-slatex.md` (S-311) es de Slatex: no se toman sus ítems ni se le agregan tareas; todo
   hallazgo nuevo va a `tareas-nacho.md`. Tocar archivos de Slatex o la zona compartida exige un aviso
   nuevo en `docs/avisos/` en el mismo PR. No se pisa lo que Slatex tenga en curso (PR abierto o rama
   `origin/slatex/*`).
5. **Godot solo por agentes** (`ejecutor-tests`, `revisor-visual`, `probador-qa`, `cazador-bugs`), tests
   siempre con filtro. La batería completa la corre CI.
6. **Subida**: `SKIP_TESTS=1 git push -u origin HEAD` (nunca `--no-verify`), `gh pr create` con título en
   inglés con prefijo, `gh pr merge --auto --squash`. Los checks requeridos son la única compuerta.
7. **Sin nada que hacer, sin PR**: si la corrida no encontró trabajo o hallazgos, termina sin abrir PR.
8. **Nunca**: editar `*.uid`, `*.import`, `.godot/`, `addons/godotsteam/`; `--no-verify`; forzar sobre
   `main`; borrar ramas ajenas; reescribir historial.
9. **Un PR por corrida**, salvo arreglar PRs rojos o con conflicto (ver `construccion.md` §1).
10. Cerrá todo proceso de Godot que hayas abierto.
11. **Freno de tareas**: cada tarea que crea una rutina lleva `Origen: <rutina> AAAA-MM-DD` (auditoría
    integral, QA, revisión semanal, mantenimiento, lanzamiento, sesión de arte, PC build). Antes de
    crear, contá las tareas abiertas (sin `[x]`) de `tareas-nacho.md` con el `Origen` de tu rutina: si
    pasan de **10**, no crees ninguna esa corrida; los hallazgos quedan solo en el informe o el PR, y
    en el cuerpo decís "freno de tareas: N abiertas". Siempre entran igual: bugs de QA "bloquea" y P0
    de la auditoría. Así lo que se planifica no le gana a lo que la construcción alcanza a hacer.

## Límites de la nube

Blender y ComfyUI no están: `modelador-blender`, `artista-conceptual` y la parte de assets de
`animador`, `artista-shaders` y `artista-vfx` quedan para `sesion-arte.md` (también regenerar música
con `tools/audio/compose_music.py`). Las capturas son render por software: composición, colores y UI
valen; sombras y FPS no. Builds, FPS y luz real: `pc-build.md`; capturas de tienda y tráiler: `sesion-arte.md`.

## Los triggers de la nube

Los crea la conversación principal con la skill `schedule`. El prompt de cada uno es una línea:
`Leé .claude/rutinas/<archivo>.md de origin/main y seguilo al pie de la letra.` (construcción suma
`Prioridad: nacho` o `Prioridad: slatex`). Modelo: Opus 5.5.

## Las rutinas de la PC

La PC queda prendida y con la sesión de Windows abierta (Blender necesita pantalla). Las lanza el
Programador de tareas con `tools/pc/rutina-pc.ps1 -Rutina arte|build`, que:

- trabaja en un **clon aparte** (`Prometeus-rutina`, al lado del repo de trabajo): nunca toca la copia
  donde trabaja Nacho;
- sale enseguida si está `.claude/rutinas/PAUSA` en `origin/main` (el mismo freno de mano) o si otra
  rutina de la PC está corriendo (un solo candado: comparten la GPU de 8 GB; la de build espera hasta
  100 min, la de arte no espera);
- abre Blender minimizado con el servidor MCP prendido (`tools/pc/blender_mcp_autostart.py`) si no
  está abierto, y deja `GODOT` apuntando al Godot de la PC;
- corre `claude -p` con Opus 5.5, permisos en modo `auto` (lo que pediría permiso se niega solo) y solo
  los MCP de Blender y ComfyUI, y guarda el log en `%LOCALAPPDATA%\prometeus-rutinas\logs\`.

Tareas del Programador (registradas el 2026-09-30): "Prometeus - Sesion de arte (PC)" y "Prometeus -
Build y rendimiento (PC)", solo con la sesión de Windows abierta, máximo 3 h por corrida. También se
pueden correr en vivo pidiéndolas ("corré la sesión de arte", "corré el build de la PC"). Para ver qué
hizo una corrida, su log; para frenarlas solo en la PC, deshabilitá esas dos tareas.
