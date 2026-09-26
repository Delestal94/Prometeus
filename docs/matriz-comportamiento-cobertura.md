# Matriz de comportamiento y cobertura

**Estado:** decisiones de producto iniciales adoptadas; revisión técnica pendiente
**Fecha:** 2026-09-26
**Alcance:** comportamientos observables del juego y evidencia de verificación. Esta matriz no describe cómo debe implementarse cada sistema.

## Propósito

Esta es la referencia común para responder tres preguntas por comportamiento:

1. ¿Qué debe poder hacer o ver el jugador, y bajo qué condiciones?
2. ¿Qué prueba o revisión demuestra que el comportamiento se cumple?
3. ¿Qué dominio responde por la regla y su verificación?

Las listas de tareas, el README y los comentarios de pruebas se usan como fuentes; ninguno por separado se considera una especificación normativa completa. Cuando las fuentes se contradicen, la matriz registra la decisión adoptada y anota qué documento se debe reconciliar.

## Principios de producto adoptados

El juego debe producir situaciones caóticas y graciosas en cooperación sin volver confusas las reglas ni quitarle toda agencia a quien comete un error.

- **Caos legible:** el jugador entiende qué salió mal y puede reaccionar; la sorpresa viene de combinar sistemas, no de controles ocultos.
- **Fallar genera juego:** una caja arruinada reduce el resultado, pero no saca a esa persona de la partida; puede ayudar a otra tripulación.
- **Cooperación sin asignaciones rígidas:** cualquiera puede tomar el volante o una caja libre; no hay rotación forzada ni expulsión de quien conduce.
- **Una sesión compartida:** el anfitrión manda en eventos y reinicio; los cambios de mundo sincronizan a los peers listos.
- **Modos distintos, reglas estables:** las cajas y sus trampas conservan las mismas reglas; cambia el ritmo y los objetivos del modo.
- **Humor apto para jugar en grupo:** la bocina, reacciones, pings, situaciones físicas y feedback sostienen la comedia; el chat de voz propio queda fuera del MVP.

## Convenciones

### Estado de la definición

- **Explícita:** el comportamiento está escrito en documentación vigente o en una decisión de alcance marcada como tomada.
- **Inferida:** se deduce del comportamiento actual descrito por una prueba o del conjunto de documentos; el responsable del dominio debe confirmarla.
- **Pendiente:** las fuentes declaran una decisión pendiente, parcial, futura o contradictoria.
- **Adoptada:** decisión de producto elegida para esta matriz el 2026-09-26; los responsables técnicos deben reflejarla en documentación, implementación y cobertura.
- **Implementada según fuente:** las notas o pruebas dicen que está implementada; la matriz no certifica una ejecución verde reciente.

### Evidencia de cobertura

- **CI headless:** hay un test `test_*.gd` que descubre `tools/run-tests.sh`.
- **CI red:** lo ejecuta `.github/workflows/tests.yml` mediante `tools/run-net-pair.sh`.
- **Manual:** hay un probe, benchmark, captura o procedimiento fuera de la ejecución normal de CI.
- **Sin evidencia localizada:** en esta primera pasada no encontré una verificación concreta. No significa que el comportamiento no exista.

La existencia de un test es evidencia de intención y cobertura declarada, **no** certifica que haya pasado en esta revisión. No se ejecutó la batería al crear este borrador.

## Matriz inicial

### Partida, entrega y modos

| ID | Comportamiento observable / criterio de aceptación | Fuente de la regla | Evidencia localizada | Responsable propuesto | Definición |
|---|---|---|---|---|---|
| RUN-01 | Una partida de entrega comienza en el depósito; el equipo puede revisar el pedido y preparar la carga antes de salir. | `controles-y-ui.md`, flujo actual del depósito | CI headless: `test_depot`, `test_main_menu` | Slatex + Nacho (zona compartida) | Explícita |
| RUN-02 | El pedido tiene una caja asignada por casa; las selecciones respetan el presupuesto de dificultad, evitan repeticiones prematuras y son deterministas para la misma semilla. | `tareas-slatex.md` S-107 | CI headless: `test_order_balancer`, `test_house_assignment` | Slatex | Explícita |
| RUN-03 | Entregar una caja a una casa registra el resultado para esa casa; la meta cierra la partida y resuelve las casas pendientes según la regla documentada. | `tareas-nacho.md`, `test_delivery_houses.gd` | CI headless: `test_delivery_houses`, `test_house_delivery_flow`, `test_run_ends_at_goal` | Nacho + Slatex | Explícita; validar el resultado de casas no visitadas |
| RUN-04 | El resultado muestra un desglose reproducible por paquete, récord y progreso ganado; los estados de entrega afectan el puntaje según la fórmula de diseño vigente. | `controles-y-ui.md`, `parametros-diseno.md` | CI headless: `test_score_breakdown`, `test_leaderboard`, `test_unlock_manager` | Slatex | Explícita |
| RUN-05 | Los eventos de ruta muestran objetivo y cuenta regresiva, se resuelven por éxito o vencimiento y no quedan activos al terminar la partida. | `tareas-slatex.md` S-101 | CI headless: `test_route_events`, `test_route_event_manager`, `test_run_relay` | Slatex + zona compartida | Explícita |
| END-01 | Endless no presenta pedidos/casas de entrega; el depósito y HUD muestran meta o distancia y récord de recorrido. | `controles-y-ui.md`, `test_depot.gd` | CI headless: `test_level_endless`, `test_depot`, `test_endless_difficulty` | Nacho + Slatex | Explícita |
| END-02 | Endless no tiene casas ni pedidos. Mantiene las reglas de las cajas/trampas y sube progresivamente la dificultad con la distancia; animales y obstáculos ambientales exclusivos de Entrega siguen fuera de Endless en el MVP. | `README.md`, N-101/N-106/N-206, `test_endless_difficulty.gd` | CI headless: `test_level_endless`, `test_endless_multi_cargo`, `test_endless_difficulty`, `test_vehicle_stress` | Nacho + Slatex | Adoptada; reconciliar la nota N-106 si cambia el alcance |

### Jugador, vehículo y paquetes

| ID | Comportamiento observable / criterio de aceptación | Fuente de la regla | Evidencia localizada | Responsable propuesto | Definición |
|---|---|---|---|---|---|
| PLAY-01 | Cada jugador controla su personaje desde su propio dispositivo; teclado/gamepad y ayudas en pantalla corresponden al último dispositivo usado. | `controles-y-ui.md` | CI headless: `test_settings`, `test_look_controls` (puede saltarse sin pantalla), `test_player_character` | Slatex | Explícita |
| PLAY-02 | Un jugador puede recoger, cargar, soltar, montar y atender una caja; la caja no queda asignada a dos jugadores tras acciones simultáneas. | `controles-y-ui.md`, comentarios de `net_pair.gd` | CI headless: `test_package_handling`, `test_interaction`, `test_package_identity`; CI red: `net_pair.gd` | Slatex | Explícita |
| PLAY-03 | Una caja se puede abrir para inspeccionar su contenido; el estado abierto produce las consecuencias descritas para derrame y entrega con reparos. | `controles-y-ui.md` | CI headless: `test_package_unboxing`, `test_package_identity` | Slatex | Explícita |
| PLAY-04 | Cada trampa tiene estados, entradas y condiciones de recuperación comprensibles; una caja puede pasar por OK, riesgo y arruinada con feedback correspondiente. | `controles-y-ui.md`, `economia-y-contramedidas.md` | CI headless: `test_fragile`, `test_liquid_trap`, `test_explosive_trap`, `test_hostile_trap`, `test_traps`, `test_trap_visual_feedback` | Slatex | Explícita; falta validar la matriz completa por trampa |
| PLAY-05 | El conductor puede acelerar, frenar/retroceder, girar, usar freno de mano, bocina y mirar/centrar la vista; el pasajero usa acciones primaria, secundaria y direccional según la trampa. | `controles-y-ui.md` | CI headless: `test_vehicle_handling`, `test_horn`, `test_look_controls`; visual: `check_interpolation.gd` | Nacho + Slatex | Explícita; gamepad requiere revisión en dispositivo |
| PLAY-06 | Quien ocupa primero el asiento de conductor conserva el volante hasta salir; no hay rotación forzada. Cualquiera puede tomar un asiento libre y nadie puede expulsar a quien ya conduce. Al bajar, personaje y cámara recuperan postura normal. | `controles-y-ui.md`, reglas actuales de asiento | CI headless: `test_interaction`, `test_ride_sync`, `test_seated_body`, `test_driver_ik`; CI red: `net_pair.gd` | Slatex + Nacho | Adoptada |
| PLAY-07 | Tras entregar una caja montada, el asiento de conductor sigue disponible durante la ruta; una entrega no puede bloquear el avance normal del equipo. | `test_driver_reboard_after_delivery.gd` | CI headless: `test_driver_reboard_after_delivery` | Slatex + Nacho | Adoptada |
| PLAY-08 | Los vehículos se mantienen conducibles y estables sobre las rutas previstas, incluidos desniveles, terreno y cargas. | `tareas-nacho.md`, pruebas de integración | CI headless: `test_vehicle_handling`, `test_vehicle_stress`, `test_route_terrain`; visual/manual: `bench_drive.gd` | Nacho | Explícita; faltan umbrales acordados de manejo |
| PLAY-09 | Una caja arruinada no deja a su dueño sin participar: otra persona puede ayudar a atenderla; dos peers ayudan a la vez y un tercero no aumenta la fuerza. La ayuda debe dar feedback y mérito, sin permitir duplicar recompensas. | S-109 (diseño propuesto en `tareas-slatex.md`) | Sin cobertura localizada; el test `test_assist.gd` está pendiente | Slatex | Adoptada; implementación pendiente |
| PLAY-10 | En Entrega, un pasajero ausente puede perder la caja; un jugador torpe todavía tiene oportunidades de rescate/casi-pérdida y una persona experta suele salvarla. La latencia no vuelve injusta una trampa. | S-108, objetivos propuestos en `tareas-slatex.md` | Sin simulador; S-108 completo sigue pendiente | Slatex + Nacho | Adoptada con objetivos cuantitativos S-108: ausente 80–100% de pérdidas, torpe 30–55% y al menos una casi-pérdida por viaje, experto <12%; +150 ms sube experto menos de 8 puntos |

### Multijugador y persistencia

| ID | Comportamiento observable / criterio de aceptación | Fuente de la regla | Evidencia localizada | Responsable propuesto | Definición |
|---|---|---|---|---|---|
| NET-01 | Una versión de protocolo incompatible o un mensaje de conexión inválido se rechaza con un mensaje entendible para el jugador. | `tareas-slatex.md` S-206 | CI headless: `test_connection_errors`, `test_ping` | Slatex | Explícita |
| NET-02 | El host es autoridad sobre la sesión, el pedido, interacciones disputadas y el estado replicado de las cajas; el cliente ve un resultado coherente. | `tareas-slatex.md` S-204/S-209, pruebas de red | CI headless: `test_session_sync`, `test_network_roster`; CI red: `net_pair.gd` | Slatex + zona compartida | Explícita |
| NET-03 | Si un jugador se desconecta mientras lleva una caja, esta queda en el mundo y se libera su referencia al jugador. | `tareas-slatex.md` S-209 | CI headless: `test_no_dangling_state`; CI red: `net_pair.gd` | Slatex | Explícita |
| NET-04 | Un segundo cliente que se une tarde obtiene la misma semilla, casas, pedido, ruta y estado del cruce que el host. | `tareas-nacho.md` N-207 | Manual: `tools/run-net-trio.sh` + `net_trio.gd`; no localizado en CI | Nacho + Slatex | Explícita; cobertura CI faltante |
| NET-05 | El vehículo remoto presenta movimiento, dirección, frenado, motor y ruedas coherentes con el host. | `docs/especificaciones-visuales.md`, probe de vehículo | Manual: `tests/run_vehicle_network.ps1` + `vehicle_network_probe.gd`; no localizado en CI | Nacho + zona compartida | Explícita; cobertura CI faltante |
| NET-06 | Si el host reinicia, los clientes sincronizan el reinicio y entran al mundo nuevo; no reciben jugadores/cajas mientras aún cargan el nivel anterior. | N-152, `test_session_sync.gd` | CI headless: `test_session_sync`; integración multipeer completa no localizada en CI | Slatex + zona compartida | Implementada según fuente; falta consolidar la documentación antigua y ampliar prueba end-to-end |
| SAVE-01 | El perfil y la campaña sobreviven reinicios; un archivo corrupto se conserva para diagnóstico y se recupera con valores seguros. | `tareas-slatex.md` S-105/S-210 | CI headless: `test_crew_campaign_save`, `test_safe_json`, `test_legacy_user_data` | Slatex | Explícita |
| SAVE-02 | Mérito, cartas, dinero y suministros pertenecen al color de jugador y no se duplican al replicarse o repetirse un evento. | `tareas-slatex.md` S-102/S-105 | CI headless: `test_merit`, `test_cards`, `test_crew_progression`, `test_crew_campaign_save` | Slatex | Explícita |

### Depósito, progresión e interfaz

| ID | Comportamiento observable / criterio de aceptación | Fuente de la regla | Evidencia localizada | Responsable propuesto | Definición |
|---|---|---|---|---|---|
| DEP-01 | La pizarra identifica la caja/bin correspondiente a cada casa; el depósito permite preparar la carga y abrir estaciones antes de salir. | `controles-y-ui.md`, `test_depot.gd` | CI headless: `test_depot`, `test_depot_campaign_board`, `test_depot_mirror` | Nacho + Slatex | Explícita |
| DEP-02 | En multijugador, las decisiones de suministros se votan; la mayoría gana, un empate elige la oferta más barata y no se cobra dos veces. | `tareas-slatex.md` S-104 | CI headless: `test_supply_vote`, `test_shop_vote_manager` | Slatex | Explícita |
| PROG-01 | Las trampas aparecen según el progreso; si el conjunto desbloqueado no alcanza para el pedido, se libera una trampa de menor dificultad según la regla escrita. | `tareas-slatex.md` S-106 | CI headless: `test_locked_traps`, `test_unlock_manager`, `test_order_balancer` | Slatex | Explícita |
| UI-01 | El menú permite jugar solo, crear sala y unirse por IP; crear sala entra directamente al depósito, sin una pantalla de lobby. | `controles-y-ui.md` (flujo real, no el diagrama histórico) | CI headless: `test_main_menu`, `test_loading_flow`, `test_session_sync` | Slatex | Explícita |
| UI-02 | En online, abrir pausa no congela a los demás; solo el anfitrión puede reiniciar toda la sesión. La pérdida del host se comunica al cliente y limpia los datos de mundo antes de jugar solo. | `controles-y-ui.md`, N-152/N-158 | CI headless: `test_hud_flow`, `test_connection_errors`, `test_session_sync`; prueba multipeer completa de reinicio no localizada en CI | Slatex | Implementada según fuente; la nota de UI está desactualizada |
| UI-03 | El HUD prioriza un aviso urgente por zona, muestra el estado de todos los paquetes y adapta las ayudas al rol y dispositivo. | `controles-y-ui.md`, S-501/S-502 | CI headless: `test_hud_flow`, `test_progress_ui`, `test_settings`; visual: `render_hud.gd` | Slatex | Explícita; revisión visual manual |
| UI-04 | Texto, paleta para daltonismo, escala del HUD/subtítulos y controles reasignables se mantienen legibles y utilizables en estados relevantes. | `controles-y-ui.md`, S-502/S-503 | CI headless: `test_settings`, `test_hud_flow`; visual: `render_hud.gd` | Slatex | Explícita; cobertura visual/accessibility parcial |
| UI-05 | Todo texto dirigido al jugador tiene español e inglés, usa claves traducibles y muestra la misma cadena en todos los peers; no aparecen claves faltantes crudas. | `tareas-slatex.md` S-509 | CI headless: `test_world_translations`, `test_main_menu` | Slatex | Adoptada |
| UI-06 | No hay chat de voz propio en el MVP; los pings/emotes cubren comunicación rápida sin voz externa. | `controles-y-ui.md` | CI headless: `test_ping` | Producto/equipo | Explícita como decisión de alcance |
| UI-07 | Antes de release, el flujo completo de Entrega se puede jugar con teclado/ratón y gamepad XInput. HUD/menús se revisan a 1920×1080 y 1280×720: sin texto cortado, controles tapados ni avisos críticos ilegibles; las opciones de contraste/tamaño se revisan con capturas. | `controles-y-ui.md`, S-502/S-503 | Parcial: `test_settings`, `test_hud_flow`; revisión manual con `render_hud.gd` y dispositivo real | Slatex | Adoptada; el proceso de revisión debe registrarse por release |

### Ruta, presentación y distribución

| ID | Comportamiento observable / criterio de aceptación | Fuente de la regla | Evidencia localizada | Responsable propuesto | Definición |
|---|---|---|---|---|---|
| WORLD-01 | Una misma semilla genera el mismo mundo/ruta; la ruta llega a la meta, no se cruza sobre sí misma y coloca casas, patios, árboles y terreno fuera de zonas inválidas. | `tareas-nacho.md` N-801/N-802 | CI headless: `test_world_seed`, `test_world_determinism`, `test_route_fuzz`, `test_route_placement_rules` | Nacho | Explícita |
| WORLD-02 | La colisión del terreno coincide con su superficie visual, no deja huecos/escalones peligrosos y el vehículo/personaje puede recuperarse de una caída según el contrato. | `test_route_terrain.gd`, especificaciones del mundo | CI headless: `test_route_terrain`, `test_route_streaming`, `test_stuck_detection` | Nacho + Slatex | Explícita; confirmar umbrales de movimiento |
| WORLD-03 | En Entrega, peligros, animales y eventos parten de la semilla/autoridad del host y dan feedback reconocible. En Endless la dificultad aumenta con la distancia y las cajas activas sostienen la presión; el set de animales/obstáculos de Entrega no se añade a Endless en el MVP. | N-106, N-206, pruebas de mundo | CI headless: `test_road_hazards`, `test_wildlife_crossing`, `test_flock_crossing`, `test_chasing_dog`, `test_endless_difficulty`, `test_trap_audio`, `test_trap_visual_feedback` | Nacho + Slatex | Adoptada; confirmar que el ajuste actual de Endless cumple el ritmo deseado |
| VIS-01 | Modelos y animaciones respetan escala, ejes, apoyo, continuidad de movimiento y dirección visual decidida. | `direccion-visual.md`, `inventario-assets.md` | CI headless: `test_refined_asset_axes`, `test_character_motion`, `test_reference_truck`; manual: scripts `render_*` y `check_*` | Nacho + Slatex | Explícita; requiere revisión visual para composición |
| AUDIO-01 | Los buses, ambiente, música, sonidos de trampa y subtítulos responden a los ajustes y al espacio acústico; no continúan indebidamente al salir/pausar. | `docs/audio-mundo.md`, pruebas de audio | CI headless: `test_audio_bus_routing`, `test_world_audio_levels`, `test_acoustic_space`, `test_music_tracks`, `test_sound_check` | Nacho + Slatex | Explícita |
| PERF-01 | Una entrega estándar dura 2–5 minutos a velocidad de crucero; Endless no tiene duración fija y aumenta la dificultad sin escalones injustos. El juego conserva FPS/memoria aceptables en el hardware objetivo. | N-102/N-206/N-204; `test_route_duration_budget.gd` | CI headless: `test_route_duration_budget`, `test_endless_difficulty`, `test_vehicle_stress`; benchmarks `bench_*`; faltan métricas recientes de PC modesta | Nacho + Slatex | Adoptada para duración; rendimiento sigue parcial |
| BUILD-01 | Un tag de release produce artefactos Windows/Linux con versión correcta, recursos presentes y arranque sin errores de carga. | `CONTRIBUTING.md`, workflow `release.yml` | CI en tag: `release.yml`; CI headless: `test_release_build` | Slatex + responsable release | Explícita; confirmar frecuencia de smoke por PR |

## Trabajo restante para cerrar la cobertura

1. **Completar la auditoría de red:** `net_trio.gd` ya corre en CI y la prueba de pares registra RTT local; falta integrar `vehicle_network_probe.gd` al pipeline y fijar límites/diagnóstico para procesos colgados en toda prueba multipeer.
2. **Cerrar el probe de gameplay huérfano:** trasladar movimiento, conducción y desconexión del conductor a una prueba mantenida; retirar el probe solo después de cubrir esos casos.
3. **Implementar ayuda cooperativa (S-109):** convertir la decisión adoptada de apoyo a cajas arruinadas en mecánica, feedback, mérito y pruebas de dos/tres peers.
4. **Implementar y ejecutar el simulador S-108:** comprobar los objetivos de riesgo y casi-pérdida antes de afinar parámetros; mantener el dato por trampa y perfil.
5. **Reconciliar `controles-y-ui.md`:** esa nota todavía dice que el reinicio del host no recarga clientes, mientras N-152 lo marca hecho y `test_session_sync` ya comprueba parte del arreglo.
6. **Formalizar la revisión visual/gamepad:** registrar capturas y resultado de dispositivo real; los skips headless no equivalen a aprobación visual.
7. **Añadir los `.gd.uid` faltantes** a cuatro tests nuevos y revisar si también faltan sidecars en scripts productivos extraídos recientemente.
8. **Actualizar la estimación de duración de la suite:** README estima cerca de un minuto; una ejecución histórica de 122 entradas duró 465 segundos. Medir la suite actual antes de publicar otro presupuesto.

## Cómo mantenerla

- Una fila por resultado observable, no una fila por clase/script o por tarea de implementación.
- Cada criterio debe poder decidirse como pasa/falla; dividir filas con varios resultados independientes.
- Toda fila tiene fuente, responsable y evidencia. Si falta uno, dejarlo explícitamente pendiente.
- Cuando cambia una regla, actualizar la fila y el test en el mismo cambio; evitar duplicar criterios en listas de tareas.
- No borrar una fila porque un test se renombró: actualizar el enlace de cobertura y conservar la historia del comportamiento.
- Hacer una revisión de matriz por release y después de cambios de alcance; el dueño del producto resuelve contradicciones de diseño y los dueños técnicos proponen cómo probarlas.

## Fuentes revisadas para este borrador

- `README.md` (flujo del juego, tests, multijugador y release).
- `docs/controles-y-ui.md` (controles, flujo real de UI y lobby de referencia histórico).
- `docs/tareas-nacho.md` y `docs/tareas-slatex.md` (alcance, comportamiento esperado y pendientes).
- `docs/colaboracion-equipo.md` (reparto de dominios y decisiones compartidas).
- `docs/direccion-visual.md`, `docs/especificaciones-visuales.md` y `docs/audio-mundo.md`.
- `do-not-drop/tests/test_*.gd`, probes de red y `tools/run-tests.sh`, `tools/run-net-pair.sh`, `tools/run-net-trio.sh`.
