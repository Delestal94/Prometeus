# Take My Package — notas para Claude

Juego cooperativo en Godot 4.7 (`do-not-drop/`, renderer GL Compatibility). Dos
integrantes con dominios separados: ver `CONTRIBUTING.md` y `docs/colaboracion-equipo.md`.

## Correr Godot: siempre a través del agente que corresponde

Nunca corras Godot (tests, capturas, import) directo desde la conversación principal:
sus logs son largos y gastan contexto.

- **Tests headless** (`tests/test_*.gd`): agente `ejecutor-tests`, que usa
  `tools/run-tests.sh` y devuelve solo el resumen. Pedile un filtro cuando alcance
  (`tools/run-tests.sh depot`), no la batería entera después de cada cambio chico.
- **Capturas y previsualización** (`tests/render_*.gd`, `check_driver_sightline.gd`,
  `check_pivots.gd`, cualquier cosa que necesite pantalla o mirar imágenes): agente
  `revisor-visual`.
- **Diagnóstico de un test que falla**: agente `cazador-bugs`.
- La batería completa la corre CI en GitHub (checks requeridos, la única compuerta). El hook
  `pre-push` solo corre lint, `check_modules` y los tests afectados por el push
  (`FULL_TESTS=1` para la batería entera): no hace falta correr todo antes de cada commit.

Los agentes están en `.claude/agents/` (versionados). En la nube, el hook de arranque
instala Godot 4.7.2 en `~/godot` y deja `GODOT` definido; las capturas corren con
`xvfb-run` (render por software).

### Orquestación

- **Un subagente no puede lanzar otro.** La conversación principal (o la rutina) es la
  única que orquesta: cuando un agente "recomienda" pasar algo por otro, lo hace ella.
- Modelos fijados en cada agente (Opus 5.5 / Sonnet 5.5 con su `effort`): los que
  corren y resumen (tests, capturas, dominios, docs) van en Sonnet con esfuerzo bajo;
  diagnóstico, red y revisión en Opus.
- **Rutinas**: el sistema completo (qué rutina corre cuándo, cómo se pasan el trabajo, reglas
  comunes y freno de mano `PAUSA`) está en `.claude/rutinas/README.md`. En la nube no hay
  Blender, ComfyUI ni GPU: eso lo hacen las rutinas de la PC, `.claude/rutinas/sesion-arte.md`
  (crear y refinar assets) y `.claude/rutinas/pc-build.md` (build de Windows y FPS), lanzadas con
  `tools/pc/rutina-pc.ps1`. No hay revisión
  humana de PRs: los checks requeridos son la única compuerta. Las rutinas trabajan solo
  `docs/tareas-nacho.md` (incluidas las `S-xxx` heredadas); `docs/tareas-slatex.md` (S-311) es
  de Slatex y no se toca.
- Los dominios que usan hooks y agentes salen de `file_domain` en
  `.claude/hooks/lib.sh`; si cambia la tabla de `docs/colaboracion-equipo.md`,
  actualizá las dos.

### Ciclo completo: qué agente para qué

| Etapa | Agentes |
|---|---|
| Cuestionar | `abogado-del-diablo` (lo ya hecho), `critico-diseno` (ideas antes de construir), `director-arte` (assets existentes), `auditor-integral` (todo el proyecto cruzando código, arte técnico, agentes, docs y pipeline; rutina diaria) |
| Planificar | `planificador-tareas` (hallazgos → tareas N-/S- con agente, esfuerzo y aviso), `guardian-dominios` |
| Construir código | `constructor-camion`, `constructor-tramos` (tipos de tramo y generación), `constructor-mundo` (depósito, casas, clima, fauna, decorado), `constructor-jugador` (jugador, paquete, interacción), `constructor-trampas`, `constructor-red` (red y Steam; siempre seguido de `auditor-red`), `constructor-progresion`, `constructor-ui` (incluye tutorial), `localizador` (traducciones, glosario, textos que no entran), `escritor-tests` |
| Crear y refinar assets | `modelador-blender`* (3D), `artista-conceptual`* (imágenes, texturas), `artista-shaders`* (materiales), `artista-vfx` (partículas y efectos), `animador`* (clips y procedurales), `disenador-audio` (SFX y música compuesta por código) |
| Pulir y balancear | `pulidor-jugabilidad` (tiempos, números, feedback, primera partida; balance con `sim_trap_balance` y `bench_*`) |
| Verificar | `vigilante-ci` (CI de cada PR recién creado; lo pide el hook `pr-ci-watch`), `ingeniero-ci` (tendencias del CI: tests inestables, shards, tiempos; issue `salud-ci`), `ejecutor-tests`, `probador-qa` (juego completo sin gente), `revisor-visual`, `cazador-bugs`, `revisor-gdscript`, `auditor-red`, `perfilador-rendimiento` |
| Cerrar y lanzar | `documentador` (y `docs/postmortems/` cuando algo del proceso falla en serio), skill `cerrar-cambio`, `empaquetador-release`, `estratega-steam` (página, cápsulas, features de Steam, calendario) |

\* necesitan Blender o ComfyUI en la PC para la parte de assets; su parte de código corre en cualquier lado.
Qué rutina dispara cada etapa (incluidas las dormidas: post-lanzamiento, playtesting): tabla "Cobertura por
etapa" de `.claude/rutinas/README.md`.
Pasada de refinamiento típica: `director-arte` / `abogado-del-diablo` → `planificador-tareas` → el
constructor o artista de cada tarea → `ejecutor-tests` + `revisor-visual` → `cerrar-cambio`.

## Módulos portables (`do-not-drop/modules/`)

Lo genérico vive en `modules/<nombre>/` (reglas, catálogo y fases pendientes: `docs/modulos.md`).
Adentro de un módulo no se nombra nada del juego (autoloads, `res://scripts/`, clases del juego):
`python tools/check_modules.py` lo comprueba en un segundo y CI corre además
`tools/portability-check.sh` (cada módulo solo en un proyecto vacío, con sus `tests/`). Un script
nuevo que no sabe de paquetes, camión ni HUD va en un módulo, con `module.cfg` y test propio; el
juego lo conecta desde un adaptador chico en `scripts/`. `modules/` es zona compartida.

## Hooks de este repo (`.claude/settings.json`)

- Al editar un `.gd`, Godot lo carga con los autoloads y, si no compila, el error
  vuelve como feedback: arreglalo antes de correr tests.
- Al crear un PR (`gh pr create` o la herramienta MCP de GitHub), el hook `pr-ci-watch` pide lanzar el
  agente `vigilante-ci` con ese número: espera el CI, deja el auto-merge si queda verde y arregla lo obvio
  si queda rojo. Así no se encolan PRs rojos.
- No se editan a mano `*.uid`, `*.import`, `.godot/` ni `addons/godotsteam/` (el hook
  lo bloquea). Tocar un archivo del dominio del otro integrante está permitido sin
  confirmación: el hook recuerda que el mismo commit lleve el aviso de qué cambió, un
  archivo nuevo en `docs/avisos/` (dueño según `TMP_DUENO=nacho|slatex` en
  `.claude/settings.local.json`, o el mail de git).

## Antes de empezar una tarea

Las rutinas trabajan `docs/tareas-nacho.md` a toda hora: una sesión a mano que toma una tarea sin
avisar termina haciendo lo mismo que una rutina en paralelo (pasó con N-229.1, PRs #117 y #123).
Antes de tocar código:
- Saltá la tarea si ya tiene PR abierto o rama `origin/nacho/<ID>-*`.
- Reclamala como las rutinas (`.claude/rutinas/construccion.md` §2): rama `nacho/<ID>-<tema>` desde
  `origin/main` con un commit vacío `chore: claim <ID>`, pusheada. Si la sesión tiene su propia rama
  asignada, igual pusheá la de reclamo (una por tarea; no se borra) y trabajá en la tuya.
- Si el cambio toca RPC o replicación, el número de `PROTOCOL_VERSION` se elige como dice
  `docs/convenciones-godot.md` §6.

## Al terminar un cambio

Seguí la skill `cerrar-cambio` (y `nuevo-test` para escribir el test). En resumen:

- Test nuevo o ampliado para lo que se cambió, con su descripción en el encabezado del test
  (`tools/list-tests.sh` arma el índice; no hay lista a mano que mantener).
- Actualizar `docs/tareas-nacho.md` / `docs/tareas-slatex.md` y, si se tocó la zona
  compartida o archivos del otro integrante, un aviso: un archivo nuevo en `docs/avisos/` (`AAAA-MM-DD-tema.md`).
  Nunca se edita un archivo que todos los PRs tocan (así no chocan entre sí).
- Commits con prefijo (`feat:`, `fix:`, `docs:`…), en inglés.
