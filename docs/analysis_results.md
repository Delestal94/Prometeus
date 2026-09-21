# Auditoría de Desarrollo — Do Not Drop

> Revisión: 2026-09-21

---

## Estado general del proyecto

El proyecto está **entre el final de la Fase 2 y el inicio lógico de la Fase 3** del [plan-desarrollo.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/plan-desarrollo.md). Tiene bastante más construido de lo que el plan originalmente anticipaba para estas fases — la base de networking (Fase 4) y el menú principal (Fase 5) se adelantaron pragmáticamente — pero el criterio subjetivo de playtesting sigue pendiente, lo cual es coherente con la filosofía del plan.

### Lo que ya existe y funciona

| Componente | Estado | Evidencia |
|---|---|---|
| **VehicleBody3D** con física Jolt | ✅ Implementado | [vehicle.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/vehicle/vehicle.gd), [vehicle.tscn](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scenes/gameplay/vehicle/vehicle.tscn) |
| **4 trampas** (Frágil, Peso Creciente, Equilibrio, Ruidoso) | ✅ Implementado | Scripts en [traps/](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/traps), Resources en [data/traps/](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/data/traps) |
| **Interfaz ITrapBehavior** + TrapDefinition | ✅ Implementado | [i_trap_behavior.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/traps/i_trap_behavior.gd), [trap_definition.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/traps/trap_definition.gd) |
| **Package** con integridad, estados, feedback | ✅ Implementado | [package.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/package/package.gd), [package_feedback.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/package/package_feedback.gd) |
| **EventBus** con relay multiplayer | ✅ Implementado | [event_bus.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/core/event_bus.gd) — 16 señales, incluye `relay()` con RPC |
| **RunManager** con puntaje multi-cargo | ✅ Implementado | [run_manager.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/core/run_manager.gd) |
| **NetworkManager** (Steam + ENet) | ✅ Implementado | [network_manager.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/core/network_manager.gd) — 271 líneas, dual transport |
| **Cámara primera persona** | ✅ Implementado | [first_person_camera.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/presentation/first_person_camera.gd) |
| **Flujo de preparación a pie** (agarrar → cargar → abordar) | ✅ Implementado | Sistema `Interactable` con 4 scripts en [interaction/](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/interaction) |
| **Player** con movimiento a pie | ✅ Implementado | [player.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/player/player.gd) |
| **Ruta con progreso y zona de entrega** | ✅ Implementado | [route.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/route/route.gd) |
| **Menú principal** con solo/host/join | ✅ Implementado | [main_menu.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/ui/main_menu.gd) |
| **HUD** con estado de paquetes, telemetría, resultados | ✅ Implementado | [prototype_hud.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/ui/prototype_hud.gd) — 14835 bytes |
| **GodotSteam GDExtension** | ✅ Instalado | `addons/godotsteam/` con binarios multiplataforma |
| **12 tests automatizados** | ✅ Implementados | [tests/](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/tests) — incluyendo `test_main_menu.gd` (no documentado en README) |
| **Level base** con flujo completo | ✅ Implementado | [level_base.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/gameplay/level_base.gd) — spawn multi-jugador, volcaduras, cargo perdido |

### Lo que NO existe todavía

| Componente | Fase planificada | Notas |
|---|---|---|
| Streaming de tramos (mundo procedural) | Fase 3 | No hay `route_streamer.gd` ni `route_segment.gd` |
| GameManager (FSM de flujo alto nivel) | Fase 5 | Documentado en [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md) y [convenciones-godot.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/convenciones-godot.md), no existe como script |
| UnlockManager (progresión/guardado) | Fase 5 | Documentado como autoload, no implementado |
| AudioManager | Fase 6-7 | Documentado como autoload, no implementado |
| StateMachine genérica reutilizable | — | Documentada en [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md), no existe `core/state_machine/` |
| Lobby screen (como escena separada) | Fase 5 | Documentado como `lobby/lobby.tscn`, pero **reemplazado intencionalmente**: el host salta directo al nivel y los jugadores se unen mid-session ([main_menu.gd:L16-18](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/ui/main_menu.gd#L16-L18)). Es una divergencia de diseño, no una carencia |
| Pantalla de resultados (escena separada) | Fase 5 | Documentado como `results_screen.tscn`, no existe (los resultados se muestran in-HUD) |
| Resources de vehículos/tramos | Fase 3+ | `data/vehicles/` y `data/route_segments/` no existen |
| Sistema de pings/emotes | Fase 5+ | Documentado en [controles-y-ui.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/controles-y-ui.md), no implementado |
| Bocina (`drive_horn`) | — | Documentada en controles, no en Input Map ni código |

---

## Discrepancias entre documentación y código

Estas son las diferencias concretas donde la documentación dice una cosa y el código real dice otra.

### 1. Estructura de carpetas real vs. documentada

> [!IMPORTANT]
> La estructura de [convenciones-godot.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/convenciones-godot.md) sección 3 y [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md) sección 1 difiere significativamente de lo que hay en disco.

**Documentado** (convenciones-godot.md, sección 3):
```
scenes/
  main_menu/
    main_menu.tscn
  lobby/
    lobby.tscn
  gameplay/
    ...
  ui/
    hud.tscn
    results_screen.tscn
scripts/
  core/
    state_machine.gd
    event_bus.gd
    game_manager.gd
    run_manager.gd
    unlock_manager.gd
    network_manager.gd
  gameplay/
    package/
      package_state_component.gd
      package_net_sync_component.gd
    route/
      route_segment.gd
      route_streamer.gd
data/
  vehicles/
    van_default.tres
  route_segments/
    straight.tres, curve_left.tres, ...
```

**Real**:
```
scenes/
  ui/
    main_menu.tscn        ← NO está en scenes/main_menu/
  gameplay/
    level_base.tscn
    vehicle/vehicle.tscn
    package/package.tscn
    player/player.tscn
    route/route.tscn
  presentation/
    first_person_camera.tscn
scripts/
  core/
    event_bus.gd           ✅
    network_manager.gd     ✅
    run_manager.gd         ✅
    (NO: state_machine.gd, game_manager.gd, unlock_manager.gd)
  gameplay/
    level_base.gd
    interaction/           ← NO documentado
    package/
      package.gd           ← NO es "package_state_component.gd"
      package_feedback.gd  ← NO es "package_net_sync_component.gd"
    player/
      player.gd            ← NO documentado en detalle
    route/
      route.gd             ← NO es "route_segment.gd"/"route_streamer.gd"
    traps/                 ✅ coincide
    vehicle/
      vehicle.gd
      vehicle_input_component.gd  ✅
  presentation/
    first_person_camera.gd
  ui/
    main_menu.gd
    prototype_hud.gd       ← NO es "hud.gd" ni está en scenes/ui/hud.tscn
data/
  traps/                   ✅ coincide
  (NO: vehicles/, route_segments/)
```

### 2. Autoloads: documentados vs. registrados

| Autoload | Documentado | En project.godot |
|---|---|---|
| EventBus | ✅ | ✅ |
| NetworkManager | ✅ | ✅ |
| RunManager | ✅ | ✅ |
| GameManager | ✅ (posición 3) | ❌ No registrado, no existe |
| UnlockManager | ✅ (posición 2) | ❌ No registrado, no existe |
| AudioManager | ✅ (posición 6) | ❌ No registrado, no existe |

> [!NOTE]
> Los tres que faltan corresponden a fases futuras (5-7), así que su ausencia es esperada. Pero el doc los presenta como parte de la estructura actual, no como planificados.

### 3. Input Map: documentada vs. real

La tabla de [convenciones-godot.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/convenciones-godot.md) sección 1 no incluye varias acciones que **sí** existen en `project.godot`:

| Acción | En project.godot | En docs |
|---|---|---|
| `look_left` / `look_right` / `look_up` / `look_down` | ✅ | ❌ No documentada |
| `look_center` | ✅ | ❌ No documentada (mencionada en README pero no en la tabla) |
| `walk_forward` / `walk_backward` | ✅ | ❌ No documentada |
| `package_action_primary` | ✅ | ❌ Marcada como "pendiente de implementar" |

El doc dice que `package_action_primary` "se agregan cuando la Fase 2 sume las trampas restantes" — pero la Fase 2 ya está implementada y la acción **ya existe** en `project.godot`.

### 4. EventBus: señales documentadas vs. reales

**En [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md)** (sección 5, ejemplos):
- `package_state_changed(package_id, new_state)` ✅
- `package_ruined(package_id, cause)` ✅
- `run_started(route_id, players)` ✅
- `run_ended(score, results)` ✅
- `vehicle_impact(force, position)` ✅ (como `strength, impact_position`)

**Señales reales no documentadas** (en [event_bus.gd](file:///d:/Programas/Utilities/Proyectos/Prometeus/do-not-drop/scripts/core/event_bus.gd)):
- `cargo_registered` — registra cada paquete con display name
- `package_hint_changed` — texto de ayuda de trampas
- `package_integrity_changed` — integridad numérica
- `package_damaged` — daño recibido
- `vehicle_telemetry` — velocidad en km/h
- `route_progress_changed` — progreso, metros restantes, sección
- `delivery_status_changed` — en zona de entrega + tiempo detenido
- `start_requested`, `restart_requested`, `pause_requested` — peticiones de UI
- `interaction_prompt_changed` — prompts contextuales

La arquitectura muestra 5 señales como "ejemplos", pero hay 16 reales. La func `relay()` (RPC multiplayer) tampoco está documentada.

### 5. Composición de entidades: documentada vs. real

La [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md) describe componentes que **no existen como scripts/nodos separados**:

| Componente documentado | Existe | Realidad |
|---|---|---|
| `VehicleInputComponent` | ✅ | Existe como script separado |
| `VehicleAudioComponent` | ❌ | No existe (Fase 6-7) |
| `VehicleDamageComponent` | ❌ | No existe |
| `TrapBehaviorComponent` | ❌ como nodo separado | La trampa se inyecta directamente en `Package` |
| `PackageStateComponent` | ❌ como script separado | Integrado en `package.gd` |
| `PackageFeedbackComponent` | Parcial | Existe como `package_feedback.gd` |
| `PackageNetSyncComponent` | ❌ | No existe (Fase 4) |
| `PlayerInputComponent` | ❌ como separado | Integrado en `player.gd` |
| `PlayerRagdollComponent` | ❌ | No existe (Fase 6) |
| `PlayerNetSyncComponent` | ❌ | No existe (Fase 4) |

> [!NOTE]
> Esto no es un error — el código tomó un camino más pragmático (integrar la lógica en un solo script por entidad en vez de fragmentar en muchos componentes). Pero la documentación describe un grado de separación que no se materializó y puede confundir.

### 6. Plan de desarrollo — Definition of Done de Fase 1

En [plan-desarrollo.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/plan-desarrollo.md), los ítems de la Fase 1 siguen todos como `[ ]` (no marcados), pero **la mayoría están resueltos**:

| Ítem | Estado real |
|---|---|
| VehicleBody3D responde a inputs con manejo aceptable | ✅ Implementado |
| Package con FragileTrapBehavior y parámetros | ✅ Implementado |
| Feedback visual de estados OK/EnRiesgo/Arruinado | ✅ Implementado (package_feedback.gd + HUD) |
| EventBus emite señales y listeners confirman | ✅ Implementado (16 señales + RunManager + HUD) |
| Ruta de punta a punta con resultado | ✅ Implementado (route + delivery zone + results) |
| Capas de física configuradas | ✅ Implementado (6 capas en project.godot) |
| Criterio subjetivo de diversión | ❓ **Pendiente (el más importante)** |

### 7. README — Test no documentado

El [README.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/README.md) lista 10 tests + 1 visual. Pero existe `test_main_menu.gd` en el directorio de tests que **no aparece en el README**.

### 8. Título inconsistente entre documentos

- [plan-desarrollo.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/plan-desarrollo.md): "Delivery Chaos Co-op"
- [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md): "Delivery Chaos Co-op"
- [requerimientos-tecnicos.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/requerimientos-tecnicos.md): "Delivery Chaos Co-op"
- [definicion-proyecto.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/definicion-proyecto.md): "Do Not Drop"
- [README.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/README.md): "Do Not Drop"
- `project.godot`: "Do Not Drop"

"Delivery Chaos Co-op" parece ser un nombre anterior que quedó en los títulos de los docs más técnicos. El nombre de trabajo actual es **Do Not Drop**.

---

## Resumen de qué hay que refinar

### Prioridad Alta (documentación que puede confundir activamente)

1. **Actualizar la estructura de carpetas** en [convenciones-godot.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/convenciones-godot.md) sección 3 para reflejar lo que realmente hay en disco. Es el doc que más se consulta al programar y está desactualizado.

2. **Actualizar la tabla de Input Map** en [convenciones-godot.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/convenciones-godot.md) sección 1: agregar `look_*`, `walk_*`, `look_center` y marcar `package_action_primary` como ya implementado.

3. **Marcar los checkboxes de la Definition of Done** de Fase 1 y Fase 2 en [plan-desarrollo.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/plan-desarrollo.md) que ya están resueltos.

4. **Clarificar en [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md) y [convenciones-godot.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/convenciones-godot.md) qué autoloads/componentes son actuales vs. planificados** — actualmente se leen como si todos existieran.

### Prioridad Media (limpieza y consistencia)

5. **Unificar el título** "Delivery Chaos Co-op" → "Do Not Drop" en los encabezados de [plan-desarrollo.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/plan-desarrollo.md), [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md), y [requerimientos-tecnicos.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/requerimientos-tecnicos.md).

6. **Agregar `test_main_menu.gd`** al README.

7. **Actualizar la sección de señales del EventBus** en [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md) con las 16 señales reales y documentar el patrón `relay()`.

### Prioridad Baja (para cuando toque esos sistemas)

8. Decidir si la composición por componentes separados de [arquitectura.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/arquitectura.md) (PackageStateComponent, PlayerInputComponent, etc.) sigue siendo la meta al escalar a multiplayer, o si la integración actual (todo en un script) es la arquitectura definitiva — y actualizar el doc en consecuencia.

9. Agregar a [controles-y-ui.md](file:///d:/Programas/Utilities/Proyectos/Prometeus/docs/controles-y-ui.md) los controles de mirada desde asiento (mouse look, stick derecho, C/clic del stick para centrar) que ya están implementados y documentados en el README pero no en el doc de controles.

---

## Siguiente paso sugerido

El bloqueo real del proyecto no es la documentación — es el **playtesting subjetivo** que ambas fases (1 y 2) marcan como pendiente y que es el criterio de salida más importante. Todo lo construido técnicamente funciona; la pregunta que queda es si jugarlo se siente divertido.

¿Querés que actualice la documentación con las correcciones listadas, o preferís priorizar otra cosa?
