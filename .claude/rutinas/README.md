# Rutinas: el equipo de agentes trabajando solo

Rutinas en la nube (triggers de Claude Code) que trabajan el repo sin nadie mirando. El prompt de
cada trigger dice solo "leé y seguí `.claude/rutinas/<archivo>.md` de `origin/main`" (más un
parámetro si lo tiene): para cambiar cómo trabaja una rutina se cambia su archivo con un PR.

## Cómo se pasan el trabajo

Ninguna rutina habla con otra: se comunican por archivos del repo y por PRs.

```
revision (lunes) ──► docs/auditorias/AAAA-MM-DD-revision.md ──┐
qa (diario) ───────► docs/qa-recorrido.md (Hallazgos) ────────┤
auditoria (diaria) ► docs/auditorias/AAAA-MM-DD-integral.md ──┼─► planificador-tareas ─► docs/tareas-*.md
mantenimiento (jue) ► docs arreglados + hallazgos de código ──┤                              │
lanzamiento (mes) ─► docs/marketing/ ─────────────────────────┘                              ▼
                                                               construccion (2 por hora) ─► PR ─► CI ─► main
sesion-arte (a mano, en la PC) ◄── tareas "necesita PC" ◄──────────────────────────────────────┘
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
| Sesión de arte | `sesion-arte.md` | a mano, con Blender/ComfyUI abiertos | `nacho/...` | assets de las tareas "necesita PC" |

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

## Límites de la nube

Blender y ComfyUI no están: `modelador-blender`, `artista-conceptual` y la parte de assets de
`animador`, `artista-shaders` y `artista-vfx` quedan para `sesion-arte.md`. Las capturas son render por
software: composición, colores y UI valen; sombras y FPS no. `empaquetador-release` solo en vivo.

## Los triggers

Los crea la conversación principal con la skill `schedule`. El prompt de cada uno es una línea:
`Leé .claude/rutinas/<archivo>.md de origin/main y seguilo al pie de la letra.` (construcción suma
`Prioridad: nacho` o `Prioridad: slatex`). Modelo: Opus 5.5.
