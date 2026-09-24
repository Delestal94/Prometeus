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

**La forma normal:** `tools/run-tests.sh` corre toda la batería headless en paralelo (~1 minuto)
y muestra solo el resumen y las fallas; `tools/run-tests.sh depot traps` corre solo los tests
cuyo nombre contiene esos textos. Después de clonar, `tools/setup-hooks.sh` activa el hook
`pre-push`: cada `git push` con cambios de código corre la batería y no sube nada si falla.
GitHub Actions la corre también en cada push a `main` y en cada PR. Detalle en
[CONTRIBUTING.md](CONTRIBUTING.md).

Los `render_*.gd` y `check_*.gd` necesitan pantalla y alguien que mire las capturas: no son
parte de la batería (con Claude, los corre el agente `revisor-visual`).

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
<godot> --headless --path do-not-drop --script res://tests/test_leaderboard.gd
<godot> --headless --path do-not-drop --script res://tests/test_ping.gd
<godot> --headless --path do-not-drop --script res://tests/test_ruin_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_horn.gd
<godot> --headless --path do-not-drop --script res://tests/test_player_colors.gd
<godot> --headless --path do-not-drop --script res://tests/test_impact_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_presentation.gd
<godot> --headless --path do-not-drop --script res://tests/test_seated_body.gd
<godot> --headless --path do-not-drop --script res://tests/test_trap_visual_feedback.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_audio.gd
<godot> --headless --path do-not-drop --script res://tests/test_trap_audio.gd
<godot> --headless --path do-not-drop --script res://tests/test_screen_fade.gd
<godot> --headless --path do-not-drop --script res://tests/test_camera_polish.gd
<godot> --headless --path do-not-drop --script res://tests/test_interaction_highlight.gd
<godot> --headless --path do-not-drop --script res://tests/test_package_bounce_shake.gd
<godot> --headless --path do-not-drop --script res://tests/test_body_lean_sink.gd
<godot> --headless --path do-not-drop --script res://tests/test_dust_and_ambience.gd
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
<godot> --headless --path do-not-drop --script res://tests/test_session_sync.gd
<godot> --headless --path do-not-drop --script res://tests/test_settings.gd
<godot> --headless --path do-not-drop --script res://tests/test_world_seed.gd
<godot> --headless --path do-not-drop --script res://tests/test_vehicle_stress.gd
<godot> --headless --path do-not-drop --script res://tests/test_legacy_user_data.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_dressing_assets.gd
<godot> --headless --path do-not-drop --script res://tests/test_route_placement_rules.gd
<godot> --headless --path do-not-drop --script res://tests/test_render_batching.gd
<godot> --headless --path do-not-drop --script res://tests/test_house_assignment.gd
<godot> --headless --path do-not-drop --script res://tests/test_depot.gd
<godot> --headless --path do-not-drop --script res://tests/test_locked_traps.gd
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
  mudo o imposible de mirar, y que sobrevivan a cerrar el juego.
- `test_fragile` — umbrales de daño, estados e independencia entre paquetes.
- `test_traps` — las otras tres trampas: peso creciente, equilibrio y ruidoso.
- `test_interaction` — agarrar, dejar en el asiento y subirse a manejar.
- `test_multi_cargo` — varias trampas a la vez, y que perder una no termine
  la entrega de todos.
- `test_network_roster` — quién está en la sesión, quién es anfitrión, y que
  jugar solo siga siendo "una sesión de uno" (sin abrir sockets).
- `test_hint_relay` — el texto de ayuda de una trampa (ej. la cuenta
  regresiva del peso creciente) le llega a todos, no solo se lee del lado
  del anfitrión.
- `test_main_menu` — que el menú cargue y que cada botón/atajo elija el
  transporte que promete (crítico: "Crear sala" y "Unirse por IP" tienen que
  terminar en el mismo transporte o nunca se van a encontrar).
- `test_loading_flow` — flujo integrado de preparación, bloqueo de abordaje
  prematuro, carga, inicio, pausa, resultados, reinicio y atajo de desarrollo.
- `test_route_streaming` — la pieza base de streaming de tramos (Fase 3): que
  `RouteStreamer` genere tramos por delante de un objetivo, libere los que
  quedaron muy atrás y nunca repita el mismo tipo dos veces seguidas. Es
  aparte de la ruta curada a mano (`route.gd`), que sigue siendo la que se
  juega hoy.
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
  sea el host) y el "honk" sintetizado en código es audio real, no silencio.
- `test_player_colors` — cada jugador tiene un cuerpo visible (antes no había
  ninguno) con un color distinto y determinístico por `peer_id`.
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
- `test_dev_camera` — la cámara de tercera persona de desarrollo (F9, solo
  en build de debug) prende, apaga y restaura la cámara anterior
  correctamente.
- `test_audio_bus_routing` — el motor, el golpe de impacto y el chirrido de
  neumáticos rutean al bus "Interior" o "Exterior" según si la cámara
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
- `test_depot` — el depósito de salida: los 14 paquetes en su estante con código único y
  apoyados en la bandeja, el equipo aparece adentro y bajo techo, un pedido por casa en
  la pizarra, cada estación abre su pantalla solo antes de salir, los suministros se
  cobran una vez y el acolchado protege la carga, salir sin el pedido se avisa y el
  portón se cierra recién cuando el camión salió y no queda nadie a pie.
  Capturas del depósito (con ventana): `tests/render_depot.gd` → `user://depot_*.png`.
- `test_locked_traps` — las trampas que el perfil todavía no desbloqueó (Líquido, Explosivo,
  Hostil) no aparecen en el depósito, desbloquearlas las pone en los estantes, y en línea
  manda la lista del host (viaja en el handshake con la semilla).
- `test_run_relay` — en línea el cliente recibe del host el inicio de la partida (con el mismo
  evento de ruta) y los resultados tal cual, los anota en su propio leaderboard y su perfil
  cuenta la entrega; la plata del equipo no se paga dos veces.
- `test_world_mood` — clima y hora del día: misma semilla, mismo clima para todos; semillas
  distintas cubren los 4 climas y las 3 horas; nunca se modifica el `Environment` compartido
  de la escena; la lluvia moja el asfalto y la noche sube los faros; pájaros de día, grillos
  de noche y ninguno con lluvia, y los loops de ambiente suenan y cubren todo su buffer. Para ver uno a mano:
  `-- --mood=lluvia_noche` (soleado/nublado/lluvia/niebla × dia/atardecer/noche).
- `test_more_route_segments` — loma (el camino sube y vuelve a nivel), túnel sólido e
  iluminado, y el paso a nivel que baja barreras sólidas, deja pasar el tren y reabre;
  quien se suma a mitad del cruce retoma la fase del host (barreras bajas, tren pasando).
- `test_truck_variant` — la furgoneta ágil maneja distinto, la pintura cambia la carrocería
  sin tocar el material importado, ambas se replican y respetan los desbloqueos.
- `test_spectator` — solo un pasajero sin caja que salvar puede pasar a la cámara de
  persecución (Tab), y la vista vuelve sola al bajarse.
- `test_tension_music` — la capa de tensión sigue el riesgo de la carga y se calma con lo
  que ya está perdido.
- `test_score_breakdown` — el desglose de resultados siempre suma el puntaje mostrado.
- `test_endless_difficulty` — el endless se endurece con la distancia sin encadenar tres
  tramos difíciles.
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
