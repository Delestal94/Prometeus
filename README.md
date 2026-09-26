# Prometeus

[![Tests](https://github.com/Delestal94/Prometeus/actions/workflows/tests.yml/badge.svg)](https://github.com/Delestal94/Prometeus/actions/workflows/tests.yml)

Proyecto de desarrollo de un videojuego indie (desarrollo en solitario, asistido por
IA), con el objetivo de aplicar patrones de éxito observados en juegos de Steam hechos
por 1-2 personas.

Nombre oficial del juego: **Take My Package** (desde 2026-09-22; antes el nombre de trabajo era "Do Not Drop", por eso el proyecto Godot sigue en `do-not-drop/`) — delivery cooperativo de hasta 5
jugadores: 1 conduce, hasta 4 llevan un paquete con una "trampa" cada uno (ver
`docs/definicion-proyecto.md` y `docs/requerimientos-tecnicos.md`).

## Motor
Godot 4.x — el proyecto del juego vive en `do-not-drop/`.

## Probar el prototipo

Abrí `do-not-drop/project.godot` en Godot y ejecutá con **F5**. Arranca en un
**menú principal**: "Jugar solo" entra directo sin sesión de red (el
comportamiento de siempre); "Crear sala" hostea con el transporte que esté
disponible (Steam si está corriendo, si no LAN) y entra directo a la
furgoneta sin esperar en ninguna sala — los que se sumen después aparecen
dinámicamente; "Unirse por IP" fuerza LAN y conecta a la dirección que
escribas. Los amigos de Steam también pueden sumarse aceptando una
invitación desde la lista de amigos en cualquier momento.

Atajos de línea de comandos para probar rápido sin clickear:
`-- --autostart` (solo, salteando la carga a pie), `-- --host-lan` (fuerza
LAN, sin depender de que Steam esté corriendo) y `-- --join=<ip>` (se une
por LAN a esa dirección).

**Modo Endless**: genera tramos
indefinidamente en vez de la ruta curada de 220 m, y el run termina
perdiendo (carga perdida, vuelco o salir de la ruta), nunca entregando —
ver `docs/plan-desarrollo.md` Fase 3 para el estado completo. Se entra con
el botón "Modo Endless (solo)" del menú principal, o directo por línea de
comandos:

```
<godot> --path do-not-drop -- --autostart-endless
```

(el atajo anterior pasando la escena directo con `--autostart` sigue
funcionando igual, salteando también la carga a pie:)

```
<godot> --path do-not-drop res://scenes/gameplay/level_endless.tscn -- --autostart
```

**La ruta se genera al azar en cada partida** (2026-09-22), pero **una sola
vez por sesión**: el anfitrión elige la semilla y se la pasa a cada uno que
se suma antes de que cargue el nivel (`NetworkManager.world_seed`). Hasta el
2026-09-22 cada máquina sorteaba la suya, así que en multijugador **cada
jugador veía un camino distinto** y el cliente miraba la furgoneta del
anfitrión atravesar casas que de su lado no estaban. Jugando solo la semilla
queda en 0 y la ruta se sortea fresca cada vez, como antes. en vez de un
trazado fijo, cada tramo entre una casa y la siguiente son 400-600m armados
encadenando tipos de segmento (recta, badén, chicana, puente angosto, curva
en S, ripio, zona de obras y curvas reales que doblan el rumbo del camino de
verdad). Las casas se calculan al construir la ruta: una por pasajero, con
mínimo de una si jugás solo; por eso la distancia total varía según la
tripulación. En multijugador la decide el host la primera vez que arma la ruta
de la sesión y se la pasa a cada uno que se suma junto con la semilla, así que
todos construyen las mismas casas (quien se suma después no agrega casas hasta
una partida nueva).
`CurveSegment` es el único tipo que cambia la dirección del
camino; los demás siguen siendo obstáculos dentro de un carril recto.

**El depósito** (2026-09-23): toda partida (entrega y Endless) arranca adentro del
depósito central de la empresa, con el camión estacionado mirando al portón. Elegí
**Preparar entrega**, caminá con WASD y mirá con el mouse; al acercarte a algo aparece la
acción disponible.
- **La pizarra de pedidos** (junto al camión) dice qué paquete espera cada casa y en qué
  estante está (`A-1`…`B-8`). Hay dos paquetes de cada tipo en las estanterías de
  despacho, así que hay que leerla: la casa devuelve cualquier otra caja. El mismo
  pedido figura en el cartel de cada casa y en el objetivo del HUD ("Casa 1: A-6
  (falta)"), y al agarrar una caja el aviso dice su estante.
- **E** agarra el paquete y lo deja en el rack del camión; al sentarte al volante con
  carga a bordo arranca la entrega. Si salen sin algún pedido, el juego lo avisa.
- **Vestuario** (casilleros): uniforme. **Taller** (terminal al lado del camión): camión y
  pintura, se ven al instante (los elige el anfitrión). **Suministros** (mostrador): con
  la plata del equipo, *Acolchado de estantes* (la carga sufre 25 % menos por golpes) y
  *Seguro de envío* ($30 por cada caja entregada rota), para el próximo reparto.
  **Equipo del mes** (corcho): progreso y desbloqueos.
- Cuando el camión salió y no queda nadie a pie adentro, **el portón se cierra** solo.
- Adentro no llueve (se oye en el techo), hay operarios que saludan, un autoelevador
  que frena si te le cruzás, cinta transportadora, radio, reloj con la hora real.

La entrega empieza al sentarte con la carga a bordo. Usá W/S para acelerar,
frenar y retroceder, A/D para girar y Espacio como freno de mano. **H** toca
bocina (todos la escuchan, venga de quien venga, no solo del host). Esc pausa
también durante la preparación; R reinicia.

**Entregar en las casas** (2026-09-22): frená cerca de una casa, bajate,
**E** sobre un paquete lo saca de su estante (libera el lugar y deja de
contar como carga a bordo), llevalo hasta el porche y **E** en el timbre se
lo da al vecino. El estado del paquete al momento de tocar decide la
reacción, y pasar de largo una casa penaliza: el vecino se quedó esperando.
Hasta esta versión esto era imposible — no se podía sacar un paquete ya
cargado, así que las casas de la ruta eran decorado y todas terminaban
como "no entregada" sin que nada lo puntuara.

**Abrir los paquetes** (2026-09-23): **T** (D-pad abajo) abre o cierra la
caja que tenés en las manos, la de tu asiento o la que estás mirando. Las
solapas se abren de verdad y adentro está lo que se lleva (jarrón de
porcelana, gallina, torta de bodas, masa madre), en el mismo estado que el
paquete: fisuras si está en riesgo, pedazos si se arruinó. Una caja abierta
que se vuelca o se golpea fuerte **derrama el contenido** como piezas físicas
y el paquete se pierde; y entregarla abierta baja la entrega a "con reparos".

**El celular y la foto de entrega**: con **F** sacás el celular y la pantalla
pasa a modo cámara; **click** (o RB) saca la foto de la entrega que acabás de
hacer. Da puntos por sí sola, pero lo importante viene al final: los clientes
cuyo paquete llegó golpeado se quejan en la pantalla de resultados, y la foto
de su propia puerta es lo único que cierra el reclamo. Sin foto, te lo
descuentan. Las fotos tomadas se muestran al terminar.

Podés mirar alrededor desde el asiento con el mouse; **C** vuelve a centrar la
vista hacia el frente del vehículo. Con gamepad, el **stick izquierdo** camina
o gira la camioneta, el **stick derecho** mira, su **clic** centra la vista,
los **gatillos** aceleran/frenan y el **botón sur** interactúa a pie o activa
el freno de mano al conducir. Mirar desde el asiento no cambia la dirección
del vehículo. La mirada se conserva después de las sacudidas de los impactos.

**Opciones y salir**: el menú principal tiene **Opciones** (volumen,
sensibilidad de la mirada, invertir eje Y, pantalla completa — se guardan en
`user://settings.cfg`) y **Salir**. Desde la pausa se llega a las mismas
opciones y a **Menú**, que deja la sesión limpia antes de volver.

Cualquier jugador puede pingear "¡Cuidado!" con el clic de la rueda del mouse (o
D-pad arriba en gamepad) para avisar a los demás sin depender de voice chat externo —
aparece arriba de la pantalla de todos por unos segundos, con quién lo mandó.

**Progreso, variantes y espectador** (2026-09-23): las entregas exitosas y el puntaje
acumulado se guardan en `user://unlock_progress.json`. Desde **Progreso** y
**Cosméticos** del menú se consultan los desbloqueos y se eligen uniforme, pintura y
vehículo; la Furgoneta ágil se desbloquea con 4 entregas y 350 puntos. Si sos pasajero,
tu paquete se arruinó y seguís sentado, **Tab** (Back en gamepad) alterna una cámara
espectadora detrás de la furgoneta. La pantalla de resultados ahora desglosa cada fuente
del puntaje — entregas, vecinos sin atender, fotos y multiplicador — además del total.

## Tests

**Rostros del personaje (2026-09-24):** en Personalización, la pestaña **Rostro**
permite combinar seis estilos de ojos y seis de boca, o dejar cada parte vacía.
La vista 2D y el personaje 3D muestran la misma combinación al instante. Se guarda
en el perfil, se aplica al jugador del depósito y se replica a los compañeros.
Uniforme y camión conservan sus propias pestañas y desbloqueos.

`test_character_faces` cubre selecciones independientes, guardado/migración,
preview, materiales por jugador, parpadeo y configuración de réplica.
`test_character_motion` mide el cierre de los loops (también `TurnInPlace`), que la bola del pie apoyado no
patine en `Walk` (3,6 m/s) ni en `Stroll` (1,5 m/s), que los brazos se balanceen,
que `Jump` termine en el primer cuadro de `Idle` y el alcance real de las muñecas a la caja. `render_character_faces.gd` genera capturas para revisión visual.

**La forma normal:** `tools/run-tests.sh` corre toda la batería headless en paralelo (~1 minuto)
y muestra solo el resumen y las fallas; `tools/run-tests.sh depot traps` corre solo los tests
cuyo nombre contiene esos textos. Después de clonar, `tools/setup-hooks.sh` activa el hook
`pre-push`: cada `git push` con cambios de código corre la batería y no sube nada si falla.
GitHub Actions la corre también en cada push a `main` y en cada PR. Detalle en
[CONTRIBUTING.md](CONTRIBUTING.md).

Los `render_*.gd` y `check_*.gd` necesitan pantalla y alguien que mire las capturas: no son
parte de la batería (con Claude, los corre el agente `revisor-visual`).

El balance reproducible de trampas tampoco forma parte de la batería rápida. Primero
`sim_record_drive.gd` maneja cinco rutas reales y guarda la aceleración, inclinación e impactos
de cada cuadro; después `sim_trap_balance.gd` repite esos recorridos con los siete
comportamientos y los perfiles ausente, torpe y experto, con y sin 150 ms de latencia:

```
<godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/sim_record_drive.gd
<godot> --headless --path do-not-drop --script res://tests/sim_trap_balance.gd
```

Para correr un test suelto a mano, sin abrir el editor, reemplazá `<godot>` por la ruta a tu
ejecutable (ej. `D:\Descargas\Godot_v4.7.2-stable_win64_console.exe`):

```
<godot> --headless --path do-not-drop --script res://tests/test_fragile.gd
<godot> --headless --path do-not-drop --script res://tests/test_traps.gd
<godot> --headless --path do-not-drop --script res://tests/test_interaction.gd
<godot> --headless --path do-not-drop --script res://tests/test_loading_flow.gd
<godot> --headless --path do-not-drop --script res://tests/test_multi_cargo.gd
<godot> --headless --path do-not-drop --script res://tests/test_network_roster.gd
<godot> --headless --path do-not-drop --script res://tests/test_hint_relay.gd
<godot> --headless --path do-not-drop --script res://tests/test_main_menu.gd
<godot> --headless --path do-not-drop --script res://tests/test_hud_flow.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_streaming.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_events.gd
<godot> --headless --path do-not-drop --script res://tests/test_no_dangling_state.gd
<godot> --headless --path do-not-drop --script res://tests/test_merit.gd
<godot> --headless --path do-not-drop --script res://tests/test_cards.gd
<godot> --headless --path do-not-drop --script res://tests/test_supply_vote.gd
<godot> --headless --path do-not-drop --script res://tests/test_crew_campaign_save.gd
<godot> --headless --path do-not-drop --script res://tests/test_leaderboard.gd
<godot> --headless --path do-not-drop --script res://tests/test_ping.gd
<godot> --headless --path do-not-drop --script res://tests/test_ruin_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_horn.gd
<godot> --headless --path do-not-drop --script res://tests/test_player_colors.gd
<godot> --headless --path do-not-drop --script res://tests/test_player_character.gd
<godot> --headless --path do-not-drop --script res://tests/test_driver_ik.gd
<godot> --headless --path do-not-drop --script res://tests/test_character_motion.gd
<godot> --headless --path do-not-drop --script res://tests/test_character_faces.gd
<godot> --headless --path do-not-drop --script res://tests/test_impact_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_presentation.gd
<godot> --headless --path do-not-drop --script res://tests/test_seated_body.gd
<godot> --headless --path do-not-drop --script res://tests/test_trap_visual_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_audio.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_audio_levels.gd
<godot> --headless --path do-not-drop --script res://tests/test_contact_shadows.gd
<godot> --headless --path do-not-drop --script res://tests/test_trap_audio.gd
<godot> --headless --path do-not-drop --script res://tests/test_screen_fade.gd
<godot> --headless --path do-not-drop --script res://tests/test_camera_polish.gd
<godot> --headless --path do-not-drop --script res://tests/test_interaction_highlight.gd
<godot> --headless --path do-not-drop --script res://tests/test_package_bounce_shake.gd
<godot> --headless --path do-not-drop --script res://tests/test_body_lean_sink.gd
<godot> --headless --path do-not-drop --script res://tests/test_dust_and_ambience.gd
<godot> --headless --path do-not-drop --script res://tests/test_cargo_clutter.gd
<godot> --headless --path do-not-drop --script res://tests/test_dev_camera.gd
<godot> --headless --path do-not-drop --script res://tests/test_audio_bus_routing.gd
<godot> --headless --path do-not-drop --script res://tests/test_level_endless.gd
<godot> --headless --path do-not-drop --script res://tests/test_endless_multi_cargo.gd
<godot> --headless --path do-not-drop --script res://tests/test_new_route_segments.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_difficulty.gd
<godot> --headless --path do-not-drop --script res://tests/test_delivery_houses.gd
<godot> --headless --path do-not-drop --script res://tests/test_house_delivery_flow.gd
<godot> --headless --path do-not-drop --script res://tests/test_package_unboxing.gd
<godot> --headless --path do-not-drop --script res://tests/test_package_identity.gd
<godot> --headless --path do-not-drop --script res://tests/test_phone_camera.gd
<godot> --headless --path do-not-drop --script res://tests/test_ride_sync.gd
<godot> --headless --path do-not-drop --script res://tests/test_cargo_shell.gd
<godot> --headless --path do-not-drop --script res://tests/test_sound_check.gd
<godot> --headless --path do-not-drop --script res://tests/test_session_sync.gd
<godot> --headless --path do-not-drop --script res://tests/test_settings.gd
<godot> --headless --path do-not-drop --script res://tests/test_safe_json.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_seed.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_stress.gd
<godot> --headless --path do-not-drop --script res://tests/test_legacy_user_data.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_dressing_assets.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_placement_rules.gd
<godot> --headless --path do-not-drop --script res://tests/test_render_batching.gd
<godot> --headless --path do-not-drop --script res://tests/test_house_assignment.gd
<godot> --headless --path do-not-drop --script res://tests/test_house_waiting_marker.gd
<godot> --headless --path do-not-drop --script res://tests/test_run_ends_at_goal.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_duration_budget.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_pacing.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_handling.gd
<godot> --headless --path do-not-drop --script res://tests/test_depot.gd
<godot> --headless --path do-not-drop --script res://tests/test_depot_mirror.gd
<godot> --headless --path do-not-drop --script res://tests/test_locked_traps.gd
<godot> --headless --path do-not-drop --script res://tests/test_order_balancer.gd
<godot> --headless --path do-not-drop --script res://tests/test_run_relay.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_mood.gd
<godot> --headless --path do-not-drop --script res://tests/test_more_route_segments.gd
<godot> --headless --path do-not-drop --script res://tests/test_truck_variant.gd
<godot> --headless --path do-not-drop --script res://tests/test_spectator.gd
<godot> --headless --path do-not-drop --script res://tests/test_tension_music.gd
<godot> --headless --path do-not-drop --script res://tests/test_score_breakdown.gd
<godot> --headless --path do-not-drop --script res://tests/test_endless_difficulty.gd
<godot> --headless --path do-not-drop --script res://tests/test_reference_truck.gd
<godot> --headless --path do-not-drop --script res://tests/test_wildlife_crossing.gd
<godot> --headless --path do-not-drop --script res://tests/test_flock_crossing.gd
<godot> --headless --path do-not-drop --script res://tests/test_chasing_dog.gd
<godot> --headless --path do-not-drop --script res://tests/test_road_hazards.gd
<godot> --headless --path do-not-drop --script res://tests/test_dashboard_gps.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_fuzz.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_determinism.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_quality.gd
<godot> --headless --path do-not-drop --script res://tests/test_release_build.gd
<godot> --headless --path do-not-drop --script res://tests/test_stuck_detection.gd
<godot> --headless --path do-not-drop --script res://tests/test_town_signs.gd
<godot> --headless --path do-not-drop --script res://tests/test_roadside_stories.gd
<godot> --headless --path do-not-drop --script res://tests/test_depot_campaign_board.gd
<godot> --headless --path do-not-drop --script res://tests/test_door_reactions.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_translations.gd
<godot> --headless --path do-not-drop --script res://tests/test_acoustic_space.gd
<godot> --headless --path do-not-drop --script res://tests/test_music_tracks.gd
<godot> --headless --path do-not-drop --script res://tests/test_night_lights.gd
<godot> --headless --path do-not-drop --script res://tests/test_windshield_rain.gd
<godot> --headless --path do-not-drop --script res://tests/test_seat_look_limits.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_net_smoothing.gd
<godot> --headless --path do-not-drop --script res://tests/test_level_common.gd
<godot> --headless --path do-not-drop --script res://tests/test_trailer_shots.gd
<godot> --headless --path do-not-drop --script res://tests/test_baked_ao.gd
<godot> --headless --path do-not-drop --script res://tests/test_start_yard.gd
<godot> --headless --path do-not-drop --script res://tests/check_driver_sightline.gd
<godot> --headless --path do-not-drop --script res://tests/check_steam_extension.gd
<godot> --headless --path do-not-drop --script res://scripts/gameplay/route/route_smoke_check.gd
```

Cada uno imprime `PASS` y devuelve exit code 0 si está todo bien.

### Rendimiento

`bench_drive.gd` construye el nivel real, sienta al conductor y deja que un piloto
automático recorra la ruta entera a fondo mientras mide cada frame. Corre **sin**
`--headless` (mide el render de verdad):

```
<godot> --path do-not-drop --script res://tests/bench_drive.gd -- --seconds=150
```

Imprime ms por frame (promedio, p50/p95/p99, máximo), draw calls, costo de física por
tick, *judder* de la cámara (qué tan parejo avanza lo que se ve: 0 es perfecto) y cada
frame que supere `--hitch=33` ms con su contexto. `--experiment=noshadow|shadow2|noplants|nodress|nohouses|nosegvis|notruck`
apaga una fuente de costo para medir cuánto vale. El piloto no esquiva chicanas: si se
traba lo reubica más adelante (cuenta como `rescues`).
`check_interpolation.gd` (también con ventana) verifica la interpolación física: ruedas del
camión estacionado, puertas que se abren, caja montada y la vista del conductor avanzando en
cada frame; guarda capturas `check_interpolation_*.png` en `user://` para mirarlas. Referencia del 2026-09-23 en la
máquina de desarrollo, semilla 4242: antes de optimizar 8,6 ms/frame promedio, p95 22 ms,
~6.200 draw calls y la cámara quieta en el 64% de los frames; después ~3,6–6 ms, p95
~6,5–8 ms, ~1.500 draw calls y ningún frame quieto.

FPS reales con GPU (tareas de Nacho N-204), 2026-09-24, `bench_drive.gd` con ventana a
1920×1080, 60 s por corrida, vsync apagado. PC de desarrollo: AMD Ryzen 5 7600X, NVIDIA
RTX 4060 Ti (driver 596.36, GL Compatibility sobre OpenGL 3.3), 32 GB de RAM. `--endless`
maneja Endless y `--mood=` fuerza clima y hora.

| Modo | Clima / hora | FPS prom. | 1 % más bajo | p95 ms | Draw calls prom. |
|---|---|---|---|---|---|
| Reparto | día | 156 | 93 | 8,0 | 1.837 |
| Reparto | atardecer | 139 | 85 | 9,9 | 2.748 |
| Reparto | noche | 159 | 94 | 8,4 | 1.974 |
| Reparto | lluvia (día) | 164 | 104 | 7,8 | 1.798 |
| Endless | día | 380 | 219 | 3,6 | 530 |
| Endless | atardecer | 312 | 188 | 4,2 | 1.465 |
| Endless | noche | 375 | 244 | 3,5 | 625 |
| Endless | lluvia (día) | 393 | 261 | 3,3 | 535 |

La meta de 60 FPS estables a 1080p se cumple con margen (el 1 % más bajo nunca baja de 85).
El atardecer es el caso más caro en los dos modos (más draw calls; lo más probable son las
sombras largas del sol bajo, sin medir todavía). Una vez compilados los shaders no hay tirones; los que aparecen son de
los primeros segundos o de cuando el piloto reubica el camión. La física promedia 0,55-0,75 ms
por tick con picos de 12-19 ms. Falta medir el preset bajo en una PC modesta (N-205).

`bench_route_shocks.gd` mide qué tan fuerte golpea cada tipo de tramo a la carga
(headless, `--fixed-fps 60`, `-- --cruise=50` o `--cruise=30`); la tabla está en
`docs/parametros-diseno.md` ("Golpes por tipo de tramo").

`bench_route_duration.gd` mide cuánto dura una entrega manejándola: arma la ruta real para
cada semilla y cantidad de casas, y un piloto automático la recorre a velocidad de crucero,
frenando en cada casa (cada parada suma 25 s). Corre headless y más rápido que el tiempo
real con `--fixed-fps 60`:

```
<godot> --headless --fixed-fps 60 --path do-not-drop --script res://tests/bench_route_duration.gd -- --seeds=1-20 --houses=1,2,3,4
```

Imprime una línea por corrida y una tabla por cantidad de casas (minutos promedio, máximo y
mínimo, velocidad media). Resultados en `docs/parametros-diseno.md` ("Duración de la entrega").

- `test_house_delivery_flow` — el loop entero de una entrega: cargar una
  caja, volver a sacarla en la parada, que llevarla a pie no cuente como
  carga perdida, tocar el timbre, y que eso puntúe. Cada uno de esos pasos
  estaba roto o sin puntuar antes de existir este test.
- `test_package_unboxing` — abrir y cerrar una caja (solapas y contenido),
  que el contenido siga el estado del paquete, que una caja abierta volcada
  derrame el contenido como cuerpos físicos (y una cerrada no), y que el
  vecino note una caja entregada abierta.
- `test_package_identity` — cada trampa viaja en su propia caja impresa, con
  su contenido, su colisión, la etiqueta que lo declara y sus abolladuras.
- `test_phone_camera` — el celular elige la puerta correcta, archiva una
  sola foto por entrega, y la foto es lo que hace caer el reclamo del
  cliente al final (sin ella, el reclamo descuenta). También en un cliente,
  donde la casa solo se entera de la entrega por el registro que manda el host.
- `test_ride_sync` — en red, las cajas y los jugadores que van en la caja del
  camión se mandan en coordenadas del camión y cada peer los pone sobre *su*
  copia (antes rebotaban, atravesaban paredes y parecían caerse); el que va
  parado atrás se mueve y gira con el camión; `controls_enabled` se replica
  (un cliente no podía manejar); una caja ancha en el estante no se mete en
  la pared.
- `test_route_terrain` — el terreno: colisión igual a lo que se ve, sin escalones en las
  uniones, relieve real, borde que no deja caer al vacío, el camión sube la loma, y un
  modelo importado apoyado sobre el terreno conserva todos sus materiales (la valla salía
  gris).
- `test_sound_check` — "Sonidos del juego" (Opciones): cada sonido aparece por quién lo
  toca y qué es (el motor del autoelevador y el del camión por separado), se silencia con
  una copia muda que sigue sonando, "Solo" deja uno, se desmutea, el silencio alcanza a los
  que aparecen después y, con la lista abierta, todo suena aunque el juego esté en pausa.
- `test_cargo_shell` — las cajas, los jugadores y lo suelto chocan con la cáscara
  cinemática del camión, no con el camión: dos camiones iguales, uno con 80 kg de
  cajas sueltas atrás, aceleran, se golpean y frenan exactamente igual; la cáscara
  sigue al camión a toda velocidad (las cajas siguen adentro después del golpe) y
  salta con él si se lo mueve a mano (playtest 2026-09-25: andaba a tirones y una
  caja salió por adelante).
- `test_session_sync` — segunda tanda de multijugador: lo que se le manda al que
  entra tarde (partida en curso, entregas, cajas ya entregadas, portón), la caja
  entregada que desaparece en todos, cargar y soltar dentro del camión en marcha,
  la entrada de "atender caja" solo del que está sentado ahí (y que vence), el
  alcance de un pasajero medido desde su asiento, interacciones remotas solo al
  alcance, sin bonus por fotos de casas salteadas, y una sesión que termina sin
  dejar su mundo ni borrar a los jugadores.
- `test_world_seed` — que todos los peers construyan el **mismo** mundo: misma
  semilla, misma ruta; semilla distinta, ruta distinta; y que jugar solo
  (semilla 0) siga variando entre partidas.
- `test_settings` — las opciones del jugador: que el volumen llegue al bus
  de audio de verdad, que los valores se recorten en vez de dejar el juego
  mudo o imposible de mirar, que `use_card` sea reasignable y que sobrevivan
  a cerrar el juego.
- `test_cards` — que solo se repartan Rescate, Descuento y Re-voto; que cada
  una se consuma al funcionar y que Rescate no se pierda si no hay evento.
- `test_supply_vote` — mayoría, desempate por la oferta más barata y compra
  final en el depósito sin descontar dos veces la plata del equipo.
- `test_crew_campaign_save` — guardado seguro del dinero, suministros y
  progreso por color; un JSON corrupto se aparta y vuelve a la campaña inicial.
- `test_fragile` — umbrales de daño, estados e independencia entre paquetes.
- `test_traps` — las otras tres trampas: peso creciente, equilibrio y ruidoso.
- `test_interaction` — agarrar, dejar en el asiento y subirse a manejar; el que está
  sentado no ve el indicador de su propio asiento.
- `test_multi_cargo` — varias trampas a la vez, y que perder una no termine
  la entrega de todos.
- `test_network_roster` — quién está en la sesión, quién es anfitrión, y que
  jugar solo siga siendo "una sesión de uno" (sin abrir sockets).
- `test_hint_relay` — el texto de ayuda de una trampa (ej. la cuenta
  regresiva del peso creciente) le llega a todos, no solo se lee del lado
  del anfitrión.
- `test_main_menu` — que el menú cargue y que cada botón/atajo elija el
  transporte que promete (crítico: "Crear sala" y "Unirse por IP" tienen que
  terminar en el mismo transporte o nunca se van a encontrar); que el inicio
  muestre un solo "¡JUGAR!" y pocos botones (el campo de IP vive en "Unirse a
  una sala") y que Esc vuelva un nivel.
- `test_stuck_detection` — N-803: un camión trabado con el acelerador apretado (chasis
  apoyado en un obstáculo, ruedas en el aire) termina la entrega a los 6 s
  (`level_base.gd` `STUCK_SECONDS`); estacionado sin pisar el acelerador, no.
- `test_start_yard` — #170: ninguna ruta arranca con una loma ni un túnel en el portón, el
  camión no usa CCD (frenaba su posición y la carga lo atravesaba) y saliendo a fondo no
  cabecea más de 20 °/s y una caja suelta sigue atrás.
- `test_town_signs` — N-601: cada pueblo tiene cartel de entrada con nombre y de salida
  tachado, a la derecha y mirando al camión, nombres sin repetir y los mismos por semilla.
- `test_roadside_stories` — N-602: historias de banquina (camioneta de la competencia
  volcada, gallina con la caja rota, cartel "entregamos (casi) todo") como mucho una cada
  800 m, fuera del asfalto, sólidas donde se chocan e iguales para todos; la camioneta con
  la trompa en la cuneta y el texto del cartel dentro del panel (también traducido).
- `test_depot_campaign_board` — N-603: "Días sin accidentes" suma por partida sin cajas
  rotas y vuelve a 0 con una rota; la pared de fotos guarda las últimas 8 y borra las viejas,
  cada foto con su chinche y la pared sin pisar el pizarrón del equipo.
- `test_door_reactions` — N-604: el vecino reacciona a cada resultado (salta, revisa la
  caja, se agarra la cabeza, devuelve la caja equivocada, deja una nota) con una de 5
  frases elegida por semilla, en todos los clientes; mirando a la calle, con el globo
  delante de la lamparita del porche y la nota sobre la cara de la puerta en los 5 modelos.
- `test_world_translations` — N-605: todos los textos del mundo están en
  `translations/strings_world.csv` en español e inglés con los mismos marcadores, no hay
  claves de más ni de menos, el juego arranca en español y cambiar el idioma cambia el mundo.
- `test_acoustic_space` — N-402: eco largo dentro de los túneles y más corto bajo el techo
  del depósito, apagado al aire libre; una cámara pegada al camión desde afuera no cuenta
  como adentro (lluvia, #68).
- `test_music_tracks` — N-403: el menú tiene su tema y la radio del depósito su programa,
  los dos en loop por el bus Music, con origen y licencia anotados.
- `test_night_lights` — N-304: de noche faroles y faros de autos estacionados brillan con
  destello y las ventanas se encienden; al atardecer más tenue, de día nada; los halos no
  se ocultan como un bloque del largo de la ruta y cada uno conserva su tamaño.
- `test_windshield_rain` — N-303: gotas en el parabrisas solo con lluvia y solo desde
  adentro; los limpiaparabrisas (en tándem, paralelos, sin cruzarse ni salirse del vidrio)
  barren con el mismo reloj que limpia el shader.
- `test_reference_truck` — el camión de referencia: puertas que abren y se apuntan, el
  conductor sube por su puerta, ruedas sobre el piso y (N-301) juntas de paneles oscuras de
  20 mm en la cara exterior de cada panel, sin colisión, que se mueven con su puerta.
- `test_seat_look_limits` — N-504: cada asiento tiene sus límites de mirada (el conductor
  no mira a través del techo ni de la mampara) y la vista retrocede si queda pegada a una pared.
- `test_vehicle_net_smoothing` — N-208: con 150 ms de lag y 50 de jitter el camión del host
  se dibuja en el cliente sin saltos de más de 10 cm por cuadro (antes, varios), y un
  teletransporte salta en vez de deslizarse.
- `test_level_common` — N-209: entrega y Endless heredan lo común de `level_common.gd` sin
  redefinirlo, y los dos arrancan su partida.
- `test_trailer_shots` — N-902/N-905/N-906: los planos del tráiler y del devlog están
  guardados, cada uno encuentra un mundo con su tramo lejos del depósito, los rieles son
  suaves; el vuelco tumba el camión, queda tumbado y tira las cajas, sin HUD ni carteles
  flotantes y con las puertas cerradas; la casa de noche, el tren y el ciervo se reproducen
  y quedan en cuadro (el camión frena en la casa y en la barrera, no atropella al ciervo).
- `test_baked_ao` — N-308.1: casas, vehículos estacionados y del depósito y props grandes
  traen oclusión horneada en colores de vértice y `LowpolyMaterials` la multiplica en el
  albedo; la vegetación no; vidrios, marcos y faroles quedan blancos, ninguna esquina más
  oscura que el `FLOOR` del horneado y cada modelo por debajo de 2× sus vértices.
- `test_release_build` — builds de release (N-210): `project.godot` tiene
  `config/version` y el menú la muestra; los presets de CI
  (`tools/export/export_presets.cfg`) exportan Windows y Linux sin `tests/` ni `.blend`, y
  `.github/workflows/release.yml` los usa en cada tag `v*` y sube los zip al release.
- `test_loading_flow` — flujo integrado de preparación, bloqueo de abordaje
  prematuro, carga, inicio, pausa, resultados, reinicio y atajo de desarrollo.
- `test_route_streaming` — el streaming de tramos de Endless: `RouteStreamer` encadena
  tramos con curvas (cursor `Transform3D`, como `route.gd`), genera por delante del
  objetivo y libera lo que quedó atrás midiendo a lo largo del camino, nunca repite el
  mismo tipo dos veces seguidas ni se aleja más de 80° de −Z, y 5 km recorridos nunca se
  cruzan consigo mismos con los nodos vivos acotados.
- `test_flock_crossing` — el rebaño de ovejas con el camión real: pasar de largo a toda
  velocidad atropella una (multa, golpe y cartel en el HUD), esperar deja cruzar a todas y
  la bocina las dispersa fuera del asfalto.
- `test_chasing_dog` — el perro del pueblo corre al lado del camión ladrando sin tocarlo,
  se rinde a los ~150 m y la bocina lo manda a casa. Es el Shiba Inu con esqueleto: nunca
  galopa quieto, galopa a la par del camión y sus ladridos no van a ritmo fijo.
- `test_road_hazards` — en rutas reales: ramas y troncos solo con lluvia, sólidos y siempre
  dejando un carril libre; el rebaño solo en zona de campo y el perro solo en pueblo.
- `test_dashboard_gps` — el GPS del tablero muestra la distancia por la ruta a la próxima
  casa que espera, su código y una flecha hacia ella; al terminar las casas apunta a la
  llegada, y en Endless muestra la distancia y el récord.
- `test_route_fuzz` — 500 semillas × 1-4 casas sobre el plan de la ruta (nunca se cruza
  consigo misma) y 20 rutas construidas (casas y jardines fuera del asfalto, árboles
  sólidos a más de 2 m del carril, sin escalones de más de 0,3 m bajo el camino y sin
  cortes hasta la meta); cada falla nombra su semilla.
- `test_world_determinism` — el nivel entero construido dos veces con la misma semilla da
  las mismas posiciones de todo (ruta, decorado, jardines, depósito, cajas en los
  estantes), los mismos pedidos, códigos de estante y clima.
- `test_world_quality` — cada nivel de calidad gráfica (Baja / Media / Alta) fija sombras,
  distancia de dibujado del decorado, partículas y escala 3D, se aplica en caliente y a lo
  que carga después, y se guarda con las opciones.
- `test_leaderboard` — el top de puntajes local de `RunManager`: ordena,
  recorta a 10 entradas, marca correctamente un nuevo récord y sobrevive a
  guardar/cargar de disco (usa un archivo de prueba aparte, no el guardado
  real).
- `test_ping` — el sistema de pings: `EventBus.request_ping()` atribuye
  correctamente al emisor, y `Player._send_ping()` llega hasta ahí con la
  posición y el mensaje reales.
- `test_ruin_feedback` — el paquete arruinado explota en confeti una sola vez,
  en su propia posición (no en el origen del mundo), y se limpia solo al
  terminar.
- `test_horn` — la bocina atribuye correctamente a quien la toca (aunque no
  sea el host) y el "honk" sintetizado en código es audio real, no silencio. Con el
  ciervo a menos de 30 m adelante, la bocina lo espanta: se va al monte sin cruzar, o
  cruza de una si estaba congelado en el carril; de lejos no le hace nada.
- `test_player_colors` — cada jugador tiene un cuerpo visible (antes no había
  ninguno) con un color distinto y determinístico por `peer_id`, y ni la cámara a pie ni
  las de asiento cargan manos de relleno: las únicas manos en pantalla son de un personaje.
- `test_player_character` — el cuerpo del jugador es el personaje redondeado de Astra
  (`sm_char_player_rounded.glb`): trae los clips Idle/Walk/Jump/PickUpPackage/PickUpHigh/Sit/TurnInPlace, los
  huesos del IK de manejo, mide lo que un jugador y mira a −Z, la camiseta es la
  superficie 0 y lleva el color del equipo (el ribete, un tono más oscuro), todas sus
  mallas van en la capa del cuerpo propio y sentado reproduce Sit. Agarrar según la altura:
  `PickUpHigh` dura lo mismo que `PickUpPackage`, no se agacha (el del piso sí) y agarra más
  alto; el peso sale de la altura del agarre (caja en el piso 0, a la cintura 1) y a media
  altura se reproduce la mezcla horneada, que queda a mitad de camino. Pasos al girar:
  `TurnInPlace` es más lento que `Walk`, levanta cada pie más de 4 cm y lo vuelve a apoyar
  donde estaba (siempre queda uno en el piso); `movement_state()` lo elige parado y girando
  rápido, no caminando, ni con un giro lento, ni en el aire (con histéresis), la velocidad
  de giro sale del giro real del cuerpo, un giro no corta un pickup y `anim_state`
  `TurnInPlace` reproduce el clip en loop. El fondo del tiro del short tiene peso de los
  muslos (más de 0,5; antes 0), así sentado no cuelga en punta entre las rodillas.
- `test_driver_ik` — sentado al volante, las muñecas del personaje llegan a los dos
  puntos del volante con `SkeletonIK3D` (sin cilindros ni guantes sueltos en el volante),
  la bocina lleva su propia mano derecha al centro y la devuelve al aro, y al levantarse se
  liberan los solvers y los puntos.
- `test_impact_feedback` — el golpe de FOV al chocar: solo reacciona la cámara
  del asiento que estás usando, vuelve sola a su valor base, y nunca toca
  `Engine.time_scale` (eso frenaría la física de todos, no solo tu vista).
- `test_vehicle_presentation` — ruedas y volante rotan de verdad (nativo de
  `VehicleWheel3D`), la dirección del volante sigue a la de la rueda, los
  faros iluminan y parpadean en impactos fuertes, las luces de freno
  reaccionan al frenado real, y el motor sintetizado responde a velocidad y
  carga. `tests/run_vehicle_network.ps1` corre lo mismo en dos procesos
  reales para confirmar que se replica al cliente, no solo al host.
- `test_seated_body` — un jugador sentado ya no desaparece: su cuerpo sigue
  la pose del asiento cuadro a cuadro (incluso cuando la furgoneta se
  mueve), sin reparentar el nodo replicado.
- `test_trap_visual_feedback` — Peso Creciente se ve crecer y hundirse, y
  Ruidoso se ve temblar (con fase propia por paquete); ninguno toca el
  `RigidBody3D` real.
- `test_world_audio_levels` — la mezcla del mundo y del camión, medida: genera cada sonido
  (motor, golpes, bocina, viento, pájaros, lluvia, cruce, perro, timbre, depósito...), lo mide en
  dBFS, le suma su nivel de `world_mix.gd` y exige quedar a ±2 dB del objetivo de su clase
  (`docs/audio-mundo.md`). `-- --report` imprime la tabla completa.
- `test_vehicle_audio` — el golpe suena más fuerte cuanto más fuerte es el
  impacto (y no suena si es lejano), y el chirrido de neumáticos sigue el
  patinaje real de las ruedas.
- `test_trap_audio` — cada trampa tiene su sonido propio: campanita para
  Frágil (más grave si se arruina), gemido para Ruidoso que sube con la
  agitación, crujido para Peso Creciente que se reinicia al resolver el
  puzzle.
- `test_screen_fade` — el fundido a negro (al sentarse, al reiniciar) se
  oscurece y vuelve solo a transparente.
- `test_camera_polish` — head bob al caminar, FOV distinto al cargar un
  paquete, sacudida más fuerte en los asientos traseros, y sacudida
  (sin golpe de FOV) al arruinarse un paquete.
- `test_interaction_highlight` — los paquetes brillan al apuntarlos y dejan
  de brillar al mirar para otro lado; los asientos muestran verde/rojo
  según si alguien está sentado, para todos los clientes.
- `test_package_bounce_shake` — el paquete rebota al apoyarlo y tiembla al
  recibir un golpe (para cualquier trampa, no solo Ruidoso), y ninguno de
  los dos efectos pisa la escala que ya usa Peso Creciente.
- `test_body_lean_sink` — la carrocería exterior se inclina en curvas y
  frenadas y se hunde con el peso de la carga, sin tocar nunca la física
  real del vehículo.
- `test_dust_and_ambience` — hay viento de ambiente siempre sonando, y las
  ruedas levantan polvo al andar y dejan de hacerlo al frenar del todo.
- `test_cargo_clutter` — la caja de herramientas y el termo sueltos en la caja de carga
  no pueden desincronizar el camión: no están en ninguna capa (no tocan paquetes ni
  jugadores), en un cliente el camión está congelado y lo posiciona el host, y en el
  host pesan menos del 1 % del camión.
- `test_dev_camera` — la cámara de tercera persona de desarrollo (F9, solo
  en build de debug) prende, apaga y restaura la cámara anterior
  correctamente.
- `test_audio_bus_routing` — el motor, el golpe de impacto, el chirrido de
  neumáticos y la bocina rutean al bus "Interior" o "Exterior" según si la cámara
  activa de ese cliente está adentro de la furgoneta o no.
- `test_level_endless` — el modo endless (`level_endless.tscn`) arranca el
  streaming de tramos con el vehículo real, la distancia recorrida se
  trackea de verdad, y una sesión larga simulada no acumula segmentos ni
  nodos sin liberar.
- `test_new_route_segments` — los tres tramos más nuevos: la curva en S
  alterna 4 bloques (el doble que el chicane), la zona de obras angosta un
  solo lado en vez de alternar, y el ripio efectivamente baja
  `wheel_friction_slip` al entrar y lo restaura al salir (verificado con
  frames de física reales, no solo que el `Area3D` exista).
- `test_route_placement_rules` — las reglas de generación del decorado
  (`route_dresser.gd`, 2026-09-23): nada invade la ruta (una cerca de jardín
  llegó a quedar sobre el asfalto), ningún objeto sólido se pisa con otro,
  todo apoya en el suelo por cada uno de sus pies (puntas de raíz, ruedas,
  ambos extremos de un tronco) y no solo por el centro, cada cosa aparece
  solo en su zona (faroles y paradas en el pueblo, fardos
  en el campo), la ruta pasa por más de un tipo de lugar, y la misma semilla
  arma exactamente el mismo mundo en todos los jugadores.
- `test_house_assignment` — una casa por pasajero (jugadores − 1, mínimo 1), en línea la
  cantidad la fija el host una vez por sesión y el que se suma usa esa, cada casa
  espera la caja que le asignó la pizarra del depósito desde que carga el nivel (se ve
  en su cartel, con el estante), y con la caja equivocada el vecino la devuelve sin
  gastar la entrega.
- `test_house_waiting_marker` — cada casa que espera entrega se reconoce desde la ruta: luz
  de porche, globo amarillo sobre el techo, buzón con su número en los dos costados y un
  cartel en V (un tablero hacia cada sentido de la ruta) con el código de la caja que pidió,
  el mismo de la pizarra; todo delante del porche de cada modelo de casa. Cuando se registra
  su entrega (o se pasa de largo) se apaga y se baja, y no toca a las demás casas. El panel
  del timbre (N-302) cuelga en la pared de cada modelo, del lado del picaporte, entre el marco
  y el postigo, con el botón a ~1,2 m del porche y el número de la casa; está encendido
  mientras la casa espera y se apaga con la entrega, y se toca justo delante de él.
  Capturas a 120 m, 40 m, del jardín y del timbre de cerca en cada modelo (con ventana):
  `tests/render_house_waiting.gd` `-- --mood=soleado_dia` / `--mood=soleado_noche`.
- `test_run_ends_at_goal` — la entrega termina en la meta, no en la última casa: con todas
  las casas hechas la partida sigue, y termina (entregada) al detener el camión en la zona
  de la meta.
- `test_route_duration_budget` — la regla de oro de 2-5 minutos por entrega, sin manejar:
  con 1 a 4 casas, el largo de tramo que planea `route.gd` (presupuesto de tiempo, más
  corto con más casas) y la ruta que construye de verdad para varias semillas duran
  entre 2 y 5 minutos a la velocidad media que midió `bench_route_duration.gd`, contando
  cada parada.
- `test_route_pacing` — el ritmo de la ruta en 200 semillas y 1-4 casas, sobre el plan de
  `route.gd` (`plan_spine()`): algo pasa al menos cada 250 m (tramo difícil, curva cerrada o
  casa), nunca dos tramos difíciles seguidos, los últimos 80 m antes de cada casa son recta o
  curva suave, y los difíciles se vuelven más frecuentes hacia el final. Construye una ruta
  para comprobar que el camino es el del plan.
- `test_vehicle_handling` — el manejo en números, para la clásica y la ágil: 0 → 50 km/h,
  frenado desde 50, radio de giro a 20 km/h y que no vuelquen en la curva más cerrada a
  45 km/h. Falla si algo se mueve más de ±10 % de lo medido (`docs/parametros-diseno.md`,
  "Manejo"); `-- --measure` imprime los valores y barre la velocidad de vuelco.
- `test_depot` — el depósito de salida: los 14 paquetes en su estante con código único y
  apoyados en la bandeja, el equipo aparece adentro y bajo techo, un pedido por casa en
  la pizarra, cada estación abre su pantalla solo antes de salir, los suministros se
  cobran una vez y el acolchado protege la carga, salir sin el pedido se avisa y el
  portón se cierra recién cuando el camión salió y no queda nadie a pie. En Endless la
  pizarra no queda vacía: dice "RUTA SIN FIN" con el récord de distancia, sin pedidos.
  Señalización: cada estación tiene su cartel colgante, las flechas del piso salen de
  al lado del spawn y apuntan a cada una (y las del camión, al portón), y desde donde
  aparece el equipo se leen al menos 4 carteles (dentro de la imagen, de frente, con
  letra de 20 px o más a 1080p y sin nada que los tape).
  Capturas del depósito (con ventana): `tests/render_depot.gd` → `user://depot_*.png`.
- `test_depot_mirror` — el espejo del vestuario refleja de verdad: cuelga en la pared de
  los lockers mirando al salón, la cámara reflejada queda detrás del vidrio con el plano
  cercano sobre él y su encuadre es justo el vidrio (espejado izquierda-derecha), muestra
  tu propio cuerpo sin el vidrio, y solo renderiza si hay alguien cerca; antes de eso
  saca una foto del salón (medio segundo después de arrancar, con la cámara sin
  interpolar), para que de lejos no se vea negro.
- `test_locked_traps` — el depósito empieza solo con Frágil y Equilibrio; las otras cinco
  trampas aparecen según la curva del perfil, perfiles v2 migran sin perder desbloqueos,
  siempre hay cajas suficientes para las casas y en línea manda la lista del host.
- `test_order_balancer` — 1000 semillas por cada cantidad de casas verifican el presupuesto
  de dificultad, la separación de trampas difíciles al principio, que no haya repeticiones
  prematuras y que siempre entre una trampa accesible; la misma semilla repite el pedido.
- `test_run_relay` — en línea el cliente recibe del host el inicio de la partida (con el mismo
  evento de ruta) y los resultados tal cual, los anota en su propio leaderboard y su perfil
  cuenta la entrega; la plata del equipo no se paga dos veces.
- `test_world_mood` — clima y hora del día: misma semilla, mismo clima para todos; semillas
  distintas cubren los 4 climas y las 3 horas; nunca se modifica el `Environment` compartido
  de la escena; la lluvia moja el asfalto y la noche sube los faros; pájaros de día, grillos
  de noche y ninguno con lluvia, y los loops de ambiente suenan y cubren todo su buffer; en
  otoño las hojas se ponen ocres y los pinos siguen verdes. Para ver uno a mano:
  `-- --mood=lluvia_noche` (soleado/nublado/lluvia/niebla × dia/atardecer/noche).
- `test_more_route_segments` — loma (el camino sube y vuelve a nivel), túnel sólido e
  iluminado, y el paso a nivel que baja barreras sólidas, deja pasar el tren y reabre;
  quien se suma a mitad del cruce retoma la fase del host (barreras bajas, tren pasando).
- `test_truck_variant` — la furgoneta ágil maneja distinto, la pintura cambia la carrocería
  sin tocar el material importado, ambas se replican y respetan los desbloqueos.
- `test_spectator` — solo un pasajero sin caja que salvar puede pasar a la cámara de
  persecución (Tab), y la vista vuelve sola al bajarse.
- `test_tension_music` — música con pausas y fundidos suaves, afinación estable y una capa
  discreta de tensión solo ante carga en riesgo; vuelve a la calma al resolverse.
- `test_score_breakdown` — el desglose de resultados siempre suma el puntaje mostrado.
- `test_endless_difficulty` — el endless se endurece con la distancia sin encadenar tres
  tramos difíciles.
- `test_contact_shadows` — las sombras de contacto falsas (no hay SSAO ni `Decal` en GL
  Compatibility): una franja que se esfuma en metros alrededor de la huella; cada auto
  estacionado de la ruta tiene la suya apoyada sobre el terreno vértice por vértice (nunca
  enterrada), cada casa una por bloque de paredes, y el depósito bajo sus autos, el contenedor
  y los pallets.
- `test_render_batching` — que el horneado del decorado para render
  (`dressing_batcher.gd`, 2026-09-23) sea solo eso: la misma semilla armada
  con piezas sueltas y horneada da exactamente las mismas piezas en las
  mismas posiciones (nada perdido, movido ni duplicado), las mismas
  colisiones, los animales siguen siendo nodos, las casas quedan en una sola
  malla y todo se dibuja con una fracción de las instancias. También que los
  sonidos sintetizados se generen una sola vez.
- `test_route_dressing_assets` — que el arte nuevo de la ruta (2026-09-23) caiga donde
  significa algo: cada tramo peligroso con su señal mirando al conductor, la flecha
  de curva doblando para el mismo lado que la ruta, el cartel "entrega adelante" del
  lado de la casa, guardarraíl del lado de afuera de cada curva, jardines apoyados en
  el terreno, el granero junto a la casa de campo, el molino girando y el cielo
  (montañas + nubes pintadas por shader) presente en la ruta y en el endless.
  Semilla fija.
- `test_legacy_user_data` — al renombrar el juego a "Take My Package" (2026-09-22)
  Godot empezó a guardar en otra carpeta de `user://`, y las opciones y el
  leaderboard parecían borrados. Verifica que se copien una sola vez desde la
  carpeta vieja ("Do Not Drop"), sin pisar datos nuevos ni volver a aparecer
  después de un reset.
- `test_vehicle_stress` — bug bash automatizado: 60s de aceleración a fondo
  con dirección oscilante a través de los 7 tipos de tramo, revisando que
  posición/velocidad nunca exploten a NaN/Inf y que la red de seguridad de
  "fuera de la ruta" atrape una caída antes de que se vuelva una caída real
  a través del mundo.
- `test_endless_multi_cargo` — las 4 trampas activas a la vez en modo
  endless, durante 20s de manejo sostenido real: nada se rompe, ninguna
  trampa deja de trackearse.
- `test_route_difficulty` — con el pool de `RouteStreamer` en 7 tipos, nunca
  aparecen 3 segmentos "difíciles" (chicane, puente angosto, curva en S,
  ripio, zona de obras) seguidos.
- `test_delivery_houses` — el sistema de casas de entrega de la ruta curada:
  se construyen `house_count` casas, cada timbre reacciona según el estado
  del paquete entregado (o si no se entregó nada), y la meta resuelve
  automáticamente cualquier casa que nadie tocó.
- `check_driver_sightline` — verifica que nada tape la vista del conductor
  (tablero, volante, o un "vidrio" que en realidad sea opaco). Las mallas
  transparentes y la carrocería vista desde adentro no cuentan como bloqueo.
- `route_smoke_check` — colisiones de la ruta y detección de la zona de entrega.

La prueba de controles de cámara requiere una ventana real: el controlador
headless de Godot no captura el mouse. Se abre brevemente y se cierra sola:

```
<godot> --path do-not-drop --resolution 320x180 --script res://tests/test_look_controls.gd
```

Comprueba mouse/stick, límites de giro, centrado, orientación relativa al asiento,
sacudidas, bloqueo en pausa/menús, movimiento a pie y velocidad de giro a 30/120 FPS.

## Multijugador

Hay dos transportes detrás de la misma interfaz `MultiplayerPeer` de Godot, y
`NetworkManager` elige solo:

- **Steam (así se juega de verdad).** Sala de Steam relayeada por Valve: sin
  abrir puertos, sin firewall, con NAT punch-through. Es lo que usan PEAK y
  Lethal Company. Requiere tener instalada la extensión **GodotSteam**, que ya
  trae el `SteamMultiplayerPeer` incorporado.
- **ENet (desarrollo local).** Un socket UDP común contra `127.0.0.1`. Se queda
  porque para probar dos instancias en la misma máquina Steam es incómodo: P2P
  entre dos copias con la misma cuenta no funciona bien.

El proyecto **compila y testea sin GodotSteam instalado** — todo lo de Steam se
alcanza por `Engine.get_singleton` / `ClassDB.instantiate`, nunca por nombre. Si
la extensión no está, `NetworkManager` cae a ENet solo.

### GodotSteam (ya instalado)

**GodotSteam GDExtension 4.22.1** está en `do-not-drop/addons/godotsteam/`, con
binarios precompilados para Windows, Linux, macOS y Android. Declara
`compatibility_minimum = 4.4`, así que funciona con nuestro 4.7.2.

No hace falta activar ningún plugin: el `plugin.cfg` que trae es solo un
*actualizador* opcional, y la GDExtension carga sola desde su `.gdextension`.

`steam_appid.txt` está en el repo con **480** (Spacewar, la app de ejemplo de
Valve). Sirve para desarrollo: da P2P y NAT punch-through sin tener un app id
propio. **No se puede publicar con ese id** — cuando haya app id real, se
reemplaza.

Para que Steam funcione de verdad hace falta, además, **tener Steam abierto y
con sesión iniciada**. Si no lo está, `NetworkManager` cae a ENet solo; podés
comprobar en qué estado está con:

```
<godot> --headless --path do-not-drop --script res://tests/check_steam_extension.gd
```

> Si clonás el repo en otra máquina (o agregaste algún script con
> `class_name` nuevo), corré una vez
> `<godot> --headless --path do-not-drop --import` antes de los tests: Godot
> registra ahí tanto las GDExtensions como las clases globales
> (`class_name`), y sin ese paso ni la extensión de Steam carga ni un
> `class_name` nuevo se puede referenciar por nombre, aunque los archivos
> estén.

> Al exportar, usá las **plantillas normales de Godot**, no las de GodotSteam.
> Con la versión GDExtension, mezclarlas trae problemas.

### Prueba de conexión local (manual, dos procesos)

El test siempre fuerza el transporte **ENet** (no AUTO), a propósito: si Steam
está corriendo en la máquina, AUTO elegiría Steam, y el P2P de Steam entre dos
instancias con la misma cuenta no anda bien — no tiene sentido pelear con esa
limitación acá, cuando lo que este test verifica es la conectividad local.

Corré el anfitrión en una terminal y el cliente en otra:

```
<godot> --headless --path do-not-drop --script res://tests/net_smoke.gd -- --host
<godot> --headless --path do-not-drop --script res://tests/net_smoke.gd -- --client
```

Ambos imprimen `PASS` si se encuentran.

Con tres jugadores (tareas de Nacho N-207), `tools/run-net-trio.sh` levanta un anfitrión y dos
clientes ENet en localhost (el segundo entra 6 s tarde) y compara que los tres vean la misma
semilla, las mismas casas, los mismos pedidos, la misma ruta y la misma fase del cruce de tren
(`GODOT=<ejecutable sin _console> tools/run-net-trio.sh`).

**Usá el ejecutable normal de Godot, no el que termina en `_console.exe`.**
En Windows, las reglas del firewall quedan atadas a la ruta exacta del
ejecutable — una regla aprobada para `Godot_v4.7.2-stable_win64.exe` no cubre
`Godot_v4.7.2-stable_win64_console.exe`, aunque sean la misma versión. Con el
binario equivocado, el anfitrión abre el puerto pero nunca ve llegar a nadie,
en silencio (sin ventana, tampoco hay pop-up de permiso que aceptar). Podés
revisar qué reglas tenés con:

```powershell
Get-NetFirewallRule -DisplayName "Godot Engine" | Get-NetFirewallApplicationFilter
```

Si ninguna regla apunta al ejecutable que estás usando, esa es la causa.

Para levantar el juego salteando la fase de carga a pie (útil al iterar sobre el
manejo):

```
<godot> --path do-not-drop -- --autostart
```

## Documentación

### Vigente (proyecto actual: Take My Package)
- `docs/investigacion-mercado.md` — investigación de 20 juegos de Steam hechos por 1-2
  personas: equipo, ventas, motor, tiempo de desarrollo. (Contexto general, sigue
  vigente como referencia de fondo.)
- `docs/checklist-exito.md` — items replicables extraídos de esa investigación.
  (Igual de vigente, son patrones generales.)
- `docs/mecanicas-candidatas.md` — banco de mecánicas transversales reutilizables
  (recurso de referencia general para futuras decisiones).
- `docs/definicion-proyecto.md` — **definición del concepto actual** (Take My Package).
- `docs/inventario-assets.md` — **la lista de assets**: qué existe, qué falta integrar y qué falta crear.
- `docs/requerimientos-tecnicos.md` — stack técnico, motor, networking, arte, diseño
  de adicción/rejugabilidad.
- `docs/arquitectura.md` — arquitectura de software del proyecto (componentes,
  patrones, estructura de carpetas).
- `docs/plan-desarrollo.md` — plan de desarrollo por fases, con Definition of Done.
- `docs/parametros-diseno.md` — valores numéricos iniciales de cada trampa y fórmula
  de puntaje.
- `docs/controles-y-ui.md` — esquema de controles y flujo de UI/lobby.
- `docs/convenciones-godot.md` — Input Map, capas de física, estructura real de
  carpetas y convenciones de nombres dentro del proyecto Godot (`do-not-drop/`).
- `docs/direccion-visual.md` — punto de vista del jugador (FOV, límites de cámara),
  paleta de colores, iluminación, qué se ve y qué no, efectos visuales y pipeline de
  arte para la Fase 6.
- `docs/especificaciones-visuales.md` — inventario numerado de 100 mejoras concretas
  de modelado, animación, ambientación, cámara e interacción entre modelos, con
  prioridad por costo/impacto.
- `docs/colaboracion-equipo.md` — cómo se reparte el trabajo entre dos personas en
  paralelo (Nacho y Slatex): división por dominio de archivos, zona compartida y
  flujo de trabajo sugerido.
- `docs/tareas-nacho.md` / `docs/tareas-slatex.md` — 100 tareas cada una, repartidas
  por dominio (vehículo/ruta/ambientación vs. jugador/paquetes/interacción/UI/
  progresión) para minimizar conflictos al trabajar en paralelo.
- `docs/agregar-vehiculo.md` — convención que `VehiclePresentation` espera de
  cualquier vehículo (nombres de nodo, no rutas fijas) para sumar uno nuevo sin
  tocar ese script.

### Archivado (`docs/historial-exploracion/`)
Documentos de una etapa de exploración anterior, **superados** por el pivote a
"Do Not Drop" (hoy Take My Package). Se conservan como registro del proceso, no como referencia vigente:
- `mvp-candidatos.md`, `ideas-candidatas.md`,
  `opcion-descartada-aseguradora-paranormal.md`.
