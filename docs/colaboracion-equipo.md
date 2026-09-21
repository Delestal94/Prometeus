# Coordinación de equipo — Nacho y Slatex

> Última actualización: 2026-09-21
> Este documento define cómo se reparte el trabajo entre dos personas trabajando en
> paralelo sobre el mismo repositorio, para que los cambios de uno no choquen con los
> del otro. Las tareas en sí están en `docs/tareas-nacho.md` y `docs/tareas-slatex.md`
> (100 cada una). Este doc es el manual de convivencia.

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
- `do-not-drop/scripts/presentation/first_person_camera.gd`, `render_layers.gd`,
  `synth_audio.gd` (lo usan tanto el vehículo como el jugador)
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

## Flujo de trabajo sugerido

1. **Commits chicos y frecuentes**, no un commit gigante al final del día — más fácil
   de revisar y de resolver si hay conflicto.
2. **`git pull` antes de empezar a trabajar cada sesión**, y antes de cada `git push`.
3. Si el proyecto crece a la escala de necesitar ramas por feature, migrar a
   `git checkout -b <tu-nombre>/<tarea>` y Pull Request en vez de pushear directo a
   `main` — no hace falta todavía con dos personas y commits chicos, pero es la
   siguiente escalera si empieza a doler.
4. Antes de tocar un archivo de la zona compartida: avisar, cambiar, pushear,
   avisar de nuevo. No dejarlo para el final del día.
5. Cada uno corre la suite de tests completa (`README.md` sección Tests) antes de
   pushear — no asumir que "no lo toqué, no lo rompí": varios sistemas de este
   proyecto están más conectados de lo que parece a simple vista (ver por ejemplo el
   indicador de asiento del ítem #94, que depende de una propiedad replicada del
   jugador, no del vehículo).

## Cómo se armaron las 200 tareas

Las primeras ~70 de cada lista salen directo de los ítems pendientes de
`docs/especificaciones-visuales.md`, repartidos por el mismo criterio de dominio de
archivos. El resto son tareas reales del backlog del proyecto (Fase 5 y 6 del plan de
desarrollo, contenido nuevo, streaming de tramos/modo endless, pulido, documentación)
descompuestas en pasos concretos — no relleno. Cada lista tiene prioridad **A/B/C**
igual que `especificaciones-visuales.md`: A es accionable ya, B necesita arte/pipeline,
C es pulido para más adelante.
