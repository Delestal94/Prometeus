# Coordinación de equipo — Nacho y Slatex

> Este documento define cómo se reparte el trabajo entre dos personas trabajando en
> paralelo sobre el mismo repositorio, para que los cambios de uno no choquen con los
> del otro. Las tareas en sí están en `docs/tareas-nacho.md` y `docs/tareas-slatex.md`
> (las dos se reescribieron el 2026-09-24 por pilares, con IDs `N-xxx` y `S-xxx`). Este doc es el
> manual de convivencia.

## Avisos: un archivo nuevo por aviso

Cuando un cambio toca la zona compartida o un archivo del otro integrante, el aviso va en un
**archivo nuevo** `docs/avisos/AAAA-MM-DD-tema.md`, en el mismo PR: qué archivo, qué función o
señal cambió, si cambió una firma y qué tiene que hacer el otro. Nunca se edita un aviso viejo ni
este documento para avisar: un archivo por aviso no choca con los demás PRs. Los avisos hasta el
2026-09-29 están juntos en [`avisos/archivo-2026-09.md`](avisos/archivo-2026-09.md).

## El criterio: dividir por carpeta, no solo por tema

Dos personas editando el mismo archivo al mismo tiempo generan conflictos de merge
sin importar qué tan bien organizadas estén las tareas. Por eso la división real acá
es por **dominio de archivos**, y las tareas de cada lista caen naturalmente adentro
de esa frontera. Si una tarea de tu lista te obliga a tocar un archivo del otro
dominio, es señal de avisar antes de tocarlo (ver "Zona compartida" más abajo).

## Nacho — Vehículo, Ruta y Ambientación

**Dueño de:**
- `do-not-drop/scenes/gameplay/vehicle/` y `do-not-drop/scripts/gameplay/vehicle/`
- `do-not-drop/scenes/gameplay/route/` y `do-not-drop/scripts/gameplay/route/`
  (incluye `segments/`)
- `do-not-drop/scripts/presentation/vehicle_presentation.gd`
- Las partes de `level_base.tscn` que son mundo/iluminación (`WorldEnvironment`,
  `Sun`, escenografía) — no la composición general de la escena (ver zona
  compartida).
- Secciones de `docs/direccion-visual.md` y `docs/especificaciones-visuales.md`
  relacionadas a vehículo/ambientación (filas que le tocan en su propia lista).

## Slatex — Jugador, Paquetes, Interacción, UI y Progresión

**Dueño de:**
- `do-not-drop/scenes/gameplay/player/` y `do-not-drop/scripts/gameplay/player/`
- `do-not-drop/scenes/gameplay/package/` y `do-not-drop/scripts/gameplay/package/`
- `do-not-drop/scripts/gameplay/traps/`
- `do-not-drop/scripts/gameplay/interaction/`
- `do-not-drop/scripts/ui/`
- `docs/plan-desarrollo.md` Fase 5 (progresión/desbloqueos), `docs/controles-y-ui.md`.

## Zona compartida — avisar antes de tocar

Estos archivos los puede necesitar cualquiera de los dos. Regla simple: **el que va a
tocar uno de estos primero avisa en el chat del equipo qué archivo y qué función va a
cambiar**, hace el cambio en un commit chico y aislado, y avisa cuando ya está pusheado
para que el otro haga `git pull` antes de seguir.

- `do-not-drop/scripts/core/event_bus.gd`, `network_manager.gd`, `run_manager.gd`
- `do-not-drop/modules/*` (los módulos portables, `docs/modulos.md`: audio sintetizado, guardado,
  suavizado de red, presupuesto de render, acústica, ragdoll…) y sus herramientas
  `tools/check_modules.py`, `tools/portability-check.sh`
- `do-not-drop/scripts/presentation/first_person_camera.gd`, `core/render_layers.gd`
- `do-not-drop/scripts/gameplay/level_base.gd` y
  `do-not-drop/scenes/gameplay/level_base.tscn` (componen ambos dominios)
- `do-not-drop/project.godot`
- `README.md`, `docs/especificaciones-visuales.md` (cada uno edita solo las filas que
  le tocan; si hay que tocar la misma fila, coordinen antes)

**Regla de oro para la zona compartida**: preferir *agregar* (una señal nueva, una
función nueva) antes que *modificar* la firma de algo que el otro ya usa. Si hace
falta cambiar una firma existente (por ejemplo, la de `board_seat()` o una señal de
`EventBus`), avisar con más antelación — eso rompe el código del otro hasta que
actualice su copia.

## Flujo de trabajo

1. **Una rama y un PR por tarea** (`nacho/N-xxx-tema`, `slatex/S-xxx-tema`), commits chicos. El PR se
   mezcla solo (auto-merge, squash) cuando pasan los checks obligatorios: lint, tests headless y par
   de red. No hay revisión humana ni de agente: la puerta son esos checks.
2. **`git pull` antes de empezar cada sesión.** Localmente alcanza con los tests del tema
   (`tools/run-tests.sh <filtro>`); la batería entera la corren el hook `pre-push` y CI.
3. Tocar la zona compartida o un archivo del otro: cambio chico y aislado, y un aviso como archivo
   nuevo en `docs/avisos/` en el mismo PR.
4. No se edita en un PR una línea que todos los PRs tocan (fechas de "Última actualización",
   listas en el README): eso es lo que hacía chocar a los PRs entre sí.

## Cómo se armaron las 200 tareas

Las primeras ~70 de cada lista salen directo de los ítems pendientes de
`docs/especificaciones-visuales.md`, repartidos por el mismo criterio de dominio de
archivos. El resto son tareas reales del backlog del proyecto (Fase 5 y 6 del plan de
desarrollo, contenido nuevo, streaming de tramos/modo endless, pulido, documentación)
descompuestas en pasos concretos — no relleno. Cada lista tiene prioridad **A/B/C**
igual que `especificaciones-visuales.md`: A es accionable ya, B necesita arte/pipeline,
C es pulido para más adelante.
