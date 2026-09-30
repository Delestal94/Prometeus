# Aviso: 10 agentes nuevos y rutinas que también toman tus tareas (2026-09-29)

Lo hizo Nacho (con Claude). No cambia código del juego; suma agentes en `.claude/agents/` que también
podés usar, y el mapa "Ciclo completo" en `CLAUDE.md` dice cuál va en cada etapa.

- **`abogado-del-diablo`** (Opus, solo lectura): le hace la contra a lo que ya está hecho (features,
  PRs, assets, alcance). `critico-diseno` queda para ideas antes de construirlas.
- **`director-arte`** (Opus, solo lectura): audita modelos, texturas, imágenes, UI, animaciones y
  sonidos contra `direccion-visual.md` y el inventario, y dice qué refinar y con qué agente.
- **`planificador-tareas`**: pasa hallazgos a tareas N-/S- con el formato de las listas. Si agrega
  tareas a `tareas-slatex.md`, deja otro aviso acá diciendo cuáles.
- **`constructor-camion`**: todo lo del camión como componente aparte (`vehicle.*` siguen congelados).
- **`constructor-progresion`**: `CrewProgression`, `UnlockManager`, `ShopVoteManager`,
  `RouteEventManager`, puntaje. Puede tocar `scripts/ui/` y `run_manager.gd`, siempre con aviso.
- **`animador`**: clips del personaje (Blender → `sm_char_player_lowpoly.glb`) y `PlayerAnimator`,
  que son de tu dominio; procedurales del depósito y del mundo. Respeta que el estado lo decide el
  dueño y se replica.
- **`artista-vfx`**: partículas y efectos de pantalla (incluye `package_feedback.gd`, tuyo), con las
  opciones de accesibilidad existentes.
- **`pulidor-jugabilidad`**: refina lo que ya existe (tiempos, números, feedback) con cambios chicos
  y con test.
- **`probador-qa`**: recorre el juego armado en headless (entrega, endless, climas, par de red) y
  junta los errores que los tests sueltos no ven.
- **`estratega-steam`**: página de Steam, cápsulas, features de plataforma y calendario; escribe solo
  en `docs/marketing/`.

También: `disenador-audio` ahora sabe que `synth_audio.gd` es compartido y que `package_feedback.gd` /
`player.gd` son tuyos (aviso en el mismo PR), y arranca los refinamientos por
`tests/audio_loudness_report.gd`.

## Lo importante para vos: las rutinas ahora trabajan también `tareas-slatex.md`

Decisión de Nacho: las rutinas en la nube ya no se limitan a su lista. El sistema está en
`.claude/rutinas/README.md` (la rutina vieja `tareas-nacho.md` ahora es `construccion.md`):

- **Construcción** (2 por hora): toma una tarea de cualquiera de las dos listas y abre un PR
  `nacho/S-xxx-*` con auto-merge. Marca `[x]` con el hash en tu lista y deja un aviso acá por cada
  tarea tuya que cierre, aunque no toque tus archivos.
- **QA** (diario), **revisión** (lunes), **mantenimiento** (jueves) y **lanzamiento** (mensual) pueden
  sumar tareas a tu lista (bugs de QA arriba de todo, en "QA — bugs abiertos"); cada vez, con aviso.
- **Para que no te pisen algo en curso**: una rutina saltea una tarea tuya si tiene PR abierto, una
  rama `origin/slatex/S-xxx*`, o está marcada 🔧 en `tareas-slatex.md`. Cuando empieces una, empujá la
  rama temprano o poné 🔧 en el título.
- Las rutinas ignoran los modelos de ChatGPT anotados en tus tareas (`Sol`, `Astra`, `Luna`) y trabajan
  con los agentes de acá.
- Freno de mano: si hace falta parar todo, un archivo `.claude/rutinas/PAUSA` en `main` las detiene.

