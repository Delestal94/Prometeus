# Coordinación de equipo — Nacho y Slatex

> Última actualización: 2026-09-25
> Este documento define cómo se reparte el trabajo entre dos personas trabajando en
> paralelo sobre el mismo repositorio, para que los cambios de uno no choquen con los
> del otro. Las tareas en sí están en `docs/tareas-nacho.md` y `docs/tareas-slatex.md`
> (las dos se reescribieron el 2026-09-24 por pilares, con IDs `N-xxx` y `S-xxx`). Este doc es el
> manual de convivencia.

## El criterio: dividir por carpeta, no solo por tema

Aviso 2026-09-25: dirección sonora tranquila solicitada por el usuario, tomando
como referencia la sensación de calma de Minecraft. Se ajustan
`presentation/ingame_music.gd` (pausas, fundidos y tensión sin desafinar) y la zona
compartida `presentation/synth_audio.gd` (pájaros espaciados), con
sus pruebas de audio y criterios en `docs/audio-mundo.md`.

Aviso 2026-09-24: personalización de rostro solicitada por el usuario. Se trabaja
en `ui/cosmetics_panel.gd`, `player/player.gd`, `player.tscn` y en el perfil compartido
`core/unlock_manager.gd` para guardar ojos y boca independientes. Los nuevos assets
y helpers viven en `assets/textures/characters/faces/` y `scripts/presentation/`.
Continúa la comprobación de la biblioteca de animaciones del personaje redondeado.

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

## Aviso activo: tanda de tareas de Nacho del 2026-09-25 (zona compartida y archivos de Slatex)

Resumen de lo que toca archivos que no son solo de Nacho. Todo está cubierto por tests nuevos o
ampliados (lista del README). Hacé `git pull` antes de seguir con `level_base.gd`.

- **`gameplay/level_base.gd` / `level_endless.gd` (N-209, N-803):** lo idéntico entre los dos
  niveles pasó a `gameplay/level_common.gd` (clase base: carga en el depósito, spawn de jugadores,
  pausa, reinicio, carga perdida, vista al caerse el host). Cada nivel conserva lo suyo:
  `_prepare_mode()`, `start_delivery()`, `_physics_process()` y, en entrega, el aviso de "llegó más
  gente" en `_on_peer_level_ready()`. **Ninguna firma pública cambió** (`start_debug_delivery`,
  `start_delivery`, `restart_delivery`, `toggle_pause`, `vehicle`, `depot`, `packages`,
  `local_player`, `tipped_seconds`). Nuevo en la entrega: `stuck_seconds` y la regla de atascado
  (acelerador apretado y camión quieto 6 s termina la partida con "La camioneta quedó atascada"),
  la misma idea que Endless ya tenía. En builds de debug los niveles suman una `TrailerCamera`
  (F7 cámara libre; F5/F6/F8 rieles del tráiler, N-902).
- **`core/game_settings.gd` (N-605):** una línea en `_ready()`: `TranslationServer.set_locale("es")`.
  Los textos del mundo ya son traducibles (`translations/strings_world.csv`, claves `WORLD_*`); hasta
  que la S-509 agregue la opción de idioma, el juego queda en español aunque el sistema esté en
  inglés, para que UI y mundo no se mezclen. Cuando hagas la S-509, reemplazá esa línea por tu
  opción y sumá tu CSV a `internationalization/locale/translations` al lado del mío.
- **`project.godot`:** sección `[internationalization]` con los dos `.translation` de
  `strings_world.csv` (se generan al importar; `*.translation` está en `.gitignore`).
- **`ui/main_menu.gd` (N-403):** una línea en `_ready()` que agrega `presentation/menu_music.gd`
  (tema del menú, autocontenido, bus Music). Nada más en ese archivo.
- **`presentation/synth_audio.gd`:** funciones nuevas `engine_idle_loop()` y `engine_high_loop()`
  (capas del motor, N-401). Se sacó `radio_tune()`: la radio del depósito ahora pasa
  `assets/audio/music/mus_depot_radio_loop.ogg` (compuesta por `tools/audio/compose_music.py`) y
  nadie más la usaba.
- **`presentation/first_person_camera.gd` (N-504):** límites de mirada por asiento, leídos de un
  `Marker3D` "LookLimits" en cada punto de ojos de `vehicle.tscn` (metadatos `pitch_min`,
  `pitch_max`, `yaw_max`); nueva variable `pitch_down_limit_degrees`; si la vista queda a menos de
  10 cm de una pared, retrocede por la línea de mirada.
- **`interaction/seat_point.gd` (revisión visual de N-504):** el indicador de asiento ocupado
  (la bolita verde/salmón, #94) se oculta **solo para quien está sentado en ese asiento**: al girar
  la cabeza desde el volante se veía como un disco salmón flotando en la ventanilla. Los demás lo
  siguen viendo igual. Función nueva `_local_player_seated_here()`; `test_interaction` lo cubre.
- **`README.md`:** tests nuevos anotados en las dos listas.
- **`vehicle.tscn` / `vehicle.gd` (de Nacho, aviso por si los usás):** el camión ya no tiene
  `continuous_cd` (#170: frenaba su posición y la carga lo atravesaba; los paquetes y el clutter
  conservan el suyo), la pose del camión se replica por `net_position`/`net_rotation`/`net_time`
  y en los clientes se dibuja suavizada 100 ms atrás (N-208, `vehicle/vehicle_net_smoother.gd`).
  `position`/`rotation` del camión en el cliente siguen siendo la verdad local para colisiones.

## Aviso activo: agarrar la caja según su altura (N-309, 2026-09-25)

Lo hizo Nacho (con Claude). Clip nuevo `PickUpHigh` en `sm_char_player_rounded.glb` (caja a la
cintura, sin sentadilla; mismos 1,6 s y tiempos que `PickUpPackage`). En `player/player.gd`
(de Slatex), cambio aislado: `pick_up()` calcula `pickup_high_weight` (0 = caja en el piso,
1 = a la cintura) en cada peer; `_process()` traduce `ANIM_PICKUP` a `_pickup_clip()`, que
devuelve uno de los dos clips o una mezcla horneada (`blend_clips()`, librería `pickup_blend`).
`anim_state` sigue diciendo `PickUpPackage`; no cambian firmas, señales, locks ni propiedades
replicadas. Test: `test_player_character` (ampliado). Reimportá el GLB después del `git pull`.
Pasos al girar (mismo N-309): clip nuevo `TurnInPlace` y, en `player.gd`, `_apply_look()` suma el
giro aplicado, `_update_movement_anim()` lo mide (`_measure_turn_rate()`, `turn_rate`) y elige
estado con `movement_state()` (estático): parado y girando rápido da `TurnInPlace`. Es un valor
más de `anim_state` (sin RPC ni propiedades replicadas nuevas); se agregó a los loops de
`_build_body()` y, si el GLB no lo trae, `_process()` cae a `Idle`.

## Aviso activo: animaciones del personaje redondeado rehechas (2026-09-25)

Pedido del usuario: llevar el personaje y sus animaciones a la mejor calidad posible. Lo hizo
Nacho (con Claude). Todo se regenera desde `art/rounded_character/` (`animation_library.py`,
`model_fixes.py`, `build_game_export.py`); criterios y mediciones en `REFINAMIENTO.md`.
Archivos de Slatex tocados:
- `player/player.gd`: clip nuevo `Stroll` (caminata para el stick a medias). `anim_state` sigue
  diciendo `Walk`; `_gait_clip()` elige `Walk`/`Stroll` por `locomotion_speed` (ya replicado) con
  histéresis 2,2–2,6 m/s, y `_play_clip()` conserva la fase al cambiar. `speed_scale` usa
  `WALK_AUTHORED_SPEED` (3,6, antes 3,2) y `STROLL_AUTHORED_SPEED` (1,5). Al aterrizar llama a
  `_character_face.blink()`. No cambian firmas, señales ni propiedades replicadas.
- Los clips cambiaron de largo: `Idle` 6 s, `Walk` 0,33 s, `Jump`/`PickUpPackage` 1,6 s, `Sit` 4 s.
  Los tiempos de `Jump` (0–0,84 aire, 0,9 impacto) y de `PickUpPackage` (agarre 0,42 s, caja
  arriba a 1,3 s) siguen los que ya usa `player.gd`: no hay que tocar los locks.
- `Sit` ahora apoya las manos sobre la panza (antes se hundían en ella). El IK del volante del
  conductor las sigue pisando igual.
- Tests: `test_character_motion` (ampliado) y `test_character_faces` (parpadeo). Hacé `git pull`
  y reimportá el GLB (abrir el editor alcanza) antes de tocar `player.gd`.

## Aviso activo: versión en el menú y builds de release (N-210, 2026-09-25)

- `project.godot` (zona compartida): nueva clave `application/config/version="0.1.0"`. No cambia nada
  más; el job de release la reescribe con el tag antes de exportar.
- `scripts/ui/main_menu.gd` (de Slatex): el pie decía "Prototipo 0.1" fijo; ahora dice
  "Versión <config/version>". Es la única línea tocada. `test_release_build` verifica que el menú la
  muestre.
- Nuevos, fuera de `do-not-drop/`: `.github/workflows/release.yml`, `tools/export/` (presets de CI y
  `stamp_version.py`). Cómo sacar una build: `CONTRIBUTING.md` → "Builds de release".

## Aviso activo: eventos de ruta completos y sincronizados (S-101, 2026-09-24)

Slatex amplió la zona compartida `scripts/core/run_manager.gd` sin cambiar firmas públicas:

- cada inicio limpia el estado anterior de `RouteEventManager`; el host sortea una sola vez y
  los clientes reciben el evento por `EventBus.relay`, sin volver a sortearlo ni emitirlo;
- la instantánea para quien entra tarde lleva únicamente el evento que sigue activo, con su
  tiempo y progreso, de modo que un evento ya resuelto no reaparece;
- `lost_time_bonus` anula el bono antes de calcular el resultado cuando falla Cliente
  impaciente, y el cierre de la partida cancela cualquier evento pendiente sin multa.

Los paquetes suman cuatro propiedades replicadas para Etiquetas mezcladas, Mimético y Caja
parásita. Las señales existentes conservan su firma. Pruebas focalizadas: `test_route_events`,
`test_route_event_manager`, `test_run_relay`, `test_hud_flow` y `test_score_breakdown`.

## Aviso activo: mérito individual por acciones reales (S-102, 2026-09-24)

Slatex amplió `scripts/core/run_manager.gd` sin cambiar ninguna firma pública:
cuando una foto aceptada puede desestimar el reclamo de una entrega dañada, conserva
el peer y el paquete responsables mientras emite la señal existente
`delivery_photo_taken`. `CrewProgression` usa esos datos para otorgar `photo_saved`;
las fotos de entregas intactas conservan su bono normal, pero no dan ese mérito.

También se agregó `test_merit.gd` a la lista compartida de tests del `README.md`.
Pruebas focalizadas: `test_merit`, `test_crew_progression`, trampas, manejo de paquetes
y cámara del celular.
## Aviso activo: menú principal por páginas (2026-09-25)

Pedido del usuario (tareas de Nacho #179): el menú mostraba diez botones con el mismo peso. Lo
hizo Nacho, en archivos de Slatex:
- `scripts/ui/main_menu.gd`: páginas dentro de la misma tarjeta (`enum Page`, `_show_page()`,
  `PAGE_PARENT`). Inicio: "¡JUGAR!", "Garaje" y Opciones / Cómo jugar / Salir. Jugar: solo,
  Endless, Crear sala, Unirse a una sala. Unirse: el campo de IP (`_address_field`, mismo nombre).
  Garaje: Apariencia, Progreso, Récords. `_host_session()`, `_join_by_address()` y
  `join_steam_lobby()` no cambiaron de firma; ahora muestran su página para que el estado se
  lea donde corresponde. La tarjeta es translúcida sobre una copia desenfocada del arte
  (`_build_frost()`, shader inline); en headless queda opaca.
- `scripts/ui/ui_theme.gd` `button()`: hover levanta el botón 2 px (`HOVER_LIFT`) y cada
  presión suena `SynthAudio.scanner_beep()` en el bus SFX, con un único `UiClick` en la raíz.
  Afecta a todos los botones del juego (pausa, resultados, opciones).
- `tests/test_main_menu.gd`: chequea la jerarquía y la navegación con Esc.
- Zona compartida: `presentation/synth_audio.gd` suma `scanner_beep()`;
  `presentation/sound_audit.gd` lo nombra en "Sonidos del juego".

## Aviso activo: la carga ya no empuja al camión (2026-09-25)

Playtest del usuario (tareas de Nacho #172-177): el camión andaba a tirones y una caja lo
atravesó. Lo hizo Nacho. **Capa física nueva: 7, `vehicle_shell`** (`project.godot`). El
camión (`vehicle.gd`) arma una cáscara cinemática con copias de todas sus formas; lo que va
atrás choca con la cáscara, y el camión en sí solo con el entorno (máscara 1). Regla para lo
nuevo: **nada que no sea el mundo lleva la capa 2 en su máscara**; va la 64 (capa 7). Los rayos
y consultas contra el camión (capa 2) siguen igual. Archivos de Slatex tocados, solo máscaras:
- `player/player.gd`: `ON_FOOT_MASK`/`RIDING_MASK` usan `SHELL_LAYER` en vez de la capa 2;
  `platform_floor_layers` excluye las dos; `leave_seat()` vuelve a `ON_FOOT_MASK`.
  `player.tscn`: máscara 69. `player/player_ragdoll.gd`: máscara `1 | 64`.
- `package/package.gd`: `LOOSE_MASK` (1 | 4 | 64) en lugar del 7; `package.tscn`: máscara 69;
  `package_feedback.gd` (la etiqueta suelta) y `package_contents_view.gd` (`DEBRIS_MASK`), igual.
- Zona compartida: `presentation/synth_audio.gd` rehace `ambient_wind`, `distant_road`,
  `night_crickets`, `dog_bark` y **`wood_creak`** (el crujido de Peso creciente: era el
  "ruido de interferencia"; mismo nivel que antes) y suma `_normalized()`, `_seamless_loop()` y
  `_Resonator`. Ninguna firma cambió. `vehicle_presentation.gd`: los faros de noche con tope
  de energía. `liquid_slosh`, `explosive_tick` y `hostile_hiss` pasan por la caché como el resto.
- Pedido del usuario después: "Sonidos del juego" en Opciones para encontrar el ruido. En `ui/`
  (de Slatex): `options_panel.gd` suma un botón bajo los volúmenes y `_open_sound_check()`
  (cerrar Opciones cierra también la lista); nuevo `ui/sound_check_panel.gd`. La lógica es de
  Nacho: `presentation/sound_audit.gd`. Test: `test_sound_check`.

## Aviso activo: la entrega vuelve a terminar en la meta (2026-09-24)

Decisión del usuario. `gameplay/level_base.gd` (de Slatex): la partida termina otra vez al
detener el camión en la zona de la meta (`STOP_SECONDS`), como antes de `edbf90c`; entregar
en todas las casas ya no la termina, ni tampoco alejarse de la última (`8945086`, se sacó
`_all_houses_done_and_leaving()`). Por qué: el HUD seguía mostrando la distancia a la meta,
y el presupuesto de 2-5 minutos de `route.gd` (N-102) cuenta el último tramo hasta la meta;
sin él, una entrega de una casa duraba ~1,2 min. La foto de la última casa tiene todo el
tramo final para sacarse. Llegar a la meta sigue dando por perdida la casa que nadie tocó.
Test nuevo: `test_run_ends_at_goal`.

## Aviso activo: presets de calidad gráfica (2026-09-24)

Tareas de Nacho N-205. Archivos de Slatex tocados, solo agregando:
- `core/game_settings.gd`: clave nueva `graphics_quality` (Baja / Media / Alta, por defecto
  Alta), guardada con las demás y en `reset_to_defaults()`; al cambiar llama a
  `WorldQuality.apply()`, y `_ready()` deja a `WorldQuality` mirando lo que se agrega al árbol.
  Ninguna clave existente cambió.
- `ui/options_panel.gd`: una fila "Calidad gráfica" (slider de 3 pasos que muestra el nombre del
  nivel) debajo de "Pantalla completa", y su línea en `_sync_from_settings()`.
- Lo nuevo es de Nacho: `presentation/world_quality.gd` (sombras, distancia de dibujado del
  decorado, partículas y escala 3D; no la cantidad de plantas, que movería el mundo compartido).
  Test: `test_world_quality`.

## Aviso activo: sonidos nuevos en synth_audio.gd (2026-09-24)

Tareas de Nacho N-106/N-405, zona compartida: `presentation/synth_audio.gd` gana
`dog_bark()` y `sheep_bleat()` al final del archivo, con el mismo patrón `_cached()` que el
resto. No se tocó ninguna función existente.

## Aviso activo: personaje redondeado de Astra como cuerpo del jugador (2026-09-24)

Pedido del usuario: usar en el juego el personaje que hizo Astra
(`art/rounded_character/`). Lo hizo Nacho. Archivos de Slatex tocados:
- `player/player.gd`: `CHARACTER_SCENE` apunta a `sm_char_player_rounded.glb`; clip `Sit`
  mientras `seat_node_path` no está vacío (se deriva de esa propiedad replicada, sin sync
  nueva); capas de render en todas las mallas del cuerpo; el color del equipo va a la
  camiseta (superficie 0) y a su ribete; el IK de manejo usa `upper_arm.*`→`hand.*`, se
  borraron los cilindros que hacían de brazos y al levantarse se liberan los solvers y
  los puntos del volante. El IK ahora resuelve continuo (`start(false)`): con `start(true)`
  el clip lo pisaba al frame siguiente y las manos nunca llegaban. El cuerpo sentado se
  ubica por asiento (`_seat_body_offset()`, medido con `tests/render_player_character.gd`).
- Pendiente de decidir (vehículo): sentado, el personaje ocupa ~0,88 m de ancho y los
  asientos de la caja están a 0,48–0,52 m, así que dos vecinos se superponen.
- `ui/cosmetics_panel.gd`: la vista previa del uniforme usa el modelo nuevo.
- Tests: nuevo `test_player_character`; `test_driver_ik` mide que las muñecas lleguen al
  volante.
- Los NPC (depósito, vecinos) siguen con `sm_char_player_lowpoly.glb`.

## Aviso activo: sin manos flotantes en primera persona (2026-09-24)

Pedido del usuario: que en cámara no aparezcan manos que no sean del personaje. Lo hizo
Nacho. Se borraron:
- `player.tscn` y `presentation/first_person_camera.tscn`: los nodos `LeftHand`/`RightHand`
  de las cámaras (guantes a pie, cápsulas en los asientos).
- `player/player.gd`: `_build_viewmodel_gloves`, `_pose_viewmodel_hands`, las manos que
  atendían la trampa desde el asiento (`_pose_tending_hands`, tareas de Slatex #10) y el
  color de las manos en `_apply_cosmetic`; `_reset_viewmodel_hands` pasó a
  `_clear_carry_focus` (solo apaga el desenfoque de la caja en mano).
- Zona compartida: `render_layers.gd` ya no tiene `VIEWMODEL` ni `show_viewmodel`;
  `first_person_camera.gd` dejó de llamarla.
- `vehicle_presentation.gd`: sin guantes sobre el volante; la bocina (#11) mueve el punto
  `DriverHandTargetRight` del IK, así que es la mano del personaje la que va al centro.
- Pendiente para Slatex: el feedback de mantener/tocar la trampa desde el asiento quedó sin
  manos (S-205), y S-304 (celular en la mano) ya no tiene un viewmodel donde colgarlo.

## Aviso activo: configuración de Claude Code compartida (2026-09-24)

Pedido del usuario: MCP, skills y hooks para el repo. Lo hizo Nacho (con Claude).
- **`.claude/` ahora se versiona** (agentes, skills, hooks, `settings.json`). Si tenías
  agentes propios en `.claude/agents/`, `git pull` va a quejarse de archivos sin
  seguimiento: movelos a otro lado, pulleá y compará. Lo personal va en
  `.claude/settings.local.json`.
- Hooks: chequeo de GDScript al editar, bloqueo de `*.uid`/`*.import`/`.godot/`,
  confirmación al tocar el dominio del otro (`TMP_DUENO`) e instalación de Godot en la
  nube. Skills `cerrar-cambio` y `nuevo-test`. MCP de Godot en `.mcp.json`.
- Los scripts de `.githooks/` y `tools/` se suben ya con permiso de ejecución.
- Test de Slatex tocado: `test_main_menu` ya no exige `_busy` después de aceptar una
  invitación cuando Steam no está corriendo (CI, headless): ahí `_join_steam()` falla en el
  acto y el menú tiene que soltar `_busy` y decir "No se pudo entrar…". Con Steam abierto
  sigue exigiendo `_busy`. `main_menu.gd` no cambió.

## Aviso activo: segunda tanda de multijugador (2026-09-24)

Pedido del usuario: arreglar todo lo que encontró `cazador-bugs` (detalle en
`docs/tareas-nacho.md` #151-166). Lo hizo Nacho. Zona compartida:
- `core/network_manager.gd`: peers con el nivel cargado (`is_peer_ready`,
  `peer_level_ready`), reinicio para todos (`begin_restart`, `_remote_restart`), fin de
  sesión limpio (`_end_session`, `OfflineMultiplayerPeer`, `take_failure_message`),
  timeout de 20 s; se borró `_accept_joiner`.
- `core/run_manager.gd`: `send_session_state` / `_receive_session_state` (el que entra
  tarde), `consumed_packages`, sin bonus por foto de casa salteada, foto validada.
- `level_base.gd`/`level_endless.gd`: `_on_peer_level_ready`, spawn solo a peers listos,
  el reinicio avisa a los clientes.

Archivos de Slatex:
- `player/player.gd`: `reach_origin()`, carga y soltada en coordenadas del camión,
  `_ride_frame_by_frame`, filtro de visibilidad del sincronizador, golpe de caja solo del
  host.
- `player/player_ragdoll.gd`: hereda la velocidad del camión.
- `package/package.gd`: carga relativa, `set_tender`/`tender_peer_id`,
  `_remote_consume`, histéresis.
- `interaction/interactable.gd`: alcance en `request_interact`.
- `interaction/seat_point.gd`: asigna y libera quién atiende la caja.
- `ui/main_menu.gd`: motivo de la desconexión.
- Después de verificar con probes: `player.gd` y `package.gd` limitan su sincronizador a
  peers listos en `_enter_tree`; `player.gd` no choca con las cajas mientras viaja en el
  camión en marcha (`_on_foot_mask`); los niveles conservan la vista si se cae el host.
- Tests: nuevo `test_session_sync`; `test_house_assignment` sin `_accept_joiner`.

## Aviso activo: bugs de multijugador del playtest (2026-09-24)

Pedido del usuario: siete bugs de una partida con amigos. Lo hizo Nacho (detalle en
`docs/tareas-nacho.md` #143-149). Archivos de Slatex tocados:
- `player/player.gd` y `player.tscn`: ya no se replica `position` sino `net_position` +
  `net_in_vehicle` (dentro de la caja de carga, en coordenadas del camión). Las copias
  remotas se ubican en `_process` y no se interpolan. El jugador local que va parado atrás
  se mueve con el camión (`_ride_with_vehicle`), y el manejo de plataformas del
  `CharacterBody3D` ignora la capa del camión.
- `package/package.gd` y `package.tscn`: lo mismo con `net_transform` + `net_in_vehicle`
  en lugar de `position`/`rotation`.
- Zona compartida: `core/network_manager.gd` (`server_relay` en el cliente de Steam),
  `core/run_manager.gd` (`submit_delivery_photo`, la foto de un cliente llega al host).
- Del lado de Nacho: `vehicle.gd`/`.tscn` (`carries()`, `controls_enabled` replicado,
  margen contra la pared en el estante), `cargo_clutter.gd`, `phone_camera.gd`.
- `ui/main_menu.gd`: `join_steam_lobby()` (invitación de Steam aceptada); Steam se
  inicializa al abrir el juego (`network_manager.gd` `_ready`). Test: `test_main_menu`.
- Tests: nuevo `test_ride_sync`, ampliado `test_phone_camera`; `test_new_route_segments`
  busca `ConstructionBarrierCollision` (el nodo cambió de nombre en 94af110).

## Aviso activo: partida retransmitida, trampas bloqueadas y tests en el push (2026-09-23)

Pedido del usuario: seguir con los pendientes de ambas listas y dejar el GitHub profesional,
con los tests corriendo antes de cada push. Lo hizo Nacho.
- Zona compartida: `core/run_manager.gd` — el host manda inicio (`_remote_start_run`, con el
  evento de ruta que sorteó) y resultados (`_remote_finish_run`) a los clientes; `finish_run()`
  en un cliente ya no hace nada. `level_base.gd`/`level_endless.gd`: en un cliente el
  `_physics_process` solo informa progreso, el final lo decide el host.
  `core/network_manager.gd`: `world_locked_traps` y el handshake pasa a 3 argumentos.
- Archivos de Slatex: `core/unlock_manager.gd` suma `TRAP_UNLOCKS` y `locked_traps()`.
  Tests de Slatex tocados: `test_multi_cargo` y `test_endless_multi_cargo` desbloquean las
  trampas antes de armar el nivel (el perfil de test depende de qué corrió antes).
- Nuevo: `depot.gd` `withhold_locked()`, tests `test_locked_traps` y `test_run_relay`.
- Bug reportado jugando (2026-09-24, "no me puedo subir"): `interaction/seat_point.gd` (de
  Slatex). El asiento del conductor exigía una caja montada también con la partida ya
  empezada, y con una caja en la mano desaparecía sin decir nada. Ahora la carga montada
  solo se exige para arrancar, y con una caja en la mano el asiento avisa "Dejá el paquete
  para manejar" (y no deja sentarse). Cubierto en `test_house_delivery_flow`.
- **Tests antes del push:** después de clonar/pullear, correr una vez `tools/setup-hooks.sh`.
  `tools/run-tests.sh` corre la batería en paralelo (~1 min) con un `user://` aislado por
  test. CI en GitHub Actions (`.github/workflows/tests.yml`). Ver `CONTRIBUTING.md`.

## Aviso activo: casas y paso a nivel sincronizados desde el host (2026-09-23)

Pedido del usuario: seguir con tareas pendientes. Lo hizo Nacho. En la zona compartida:
`core/network_manager.gd` suma `world_house_count` y el handshake `_accept_joiner` ahora
lleva dos argumentos (semilla y cantidad de casas): **un cliente de una versión anterior
no puede unirse** (se corta por timeout del handshake). Del lado de Nacho: `route.gd`
(`_session_house_count()`, tramos con nombre estable `Segment%d`), `route_streamer.gd`
(mismo nombre estable) y `segments/rail_crossing_segment.gd` (el host dispara el cruce por
RPC). Tests: `test_house_assignment` y `test_more_route_segments` ampliados.

## Aviso activo: el depósito de salida (2026-09-23)

Pedido del usuario: la partida arranca en un depósito con el camión estacionado, paquetes de
todos los tipos, una pizarra de pedidos (cada casa espera un paquete concreto), estaciones
para prepararse y un portón que se cierra al salir; "todo profesional". Lo hizo Nacho.
Nuevo, del lado de Nacho: `scripts/gameplay/depot/` (`depot.gd` y sus piezas: `depot_kit.gd`,
`depot_roller_door.gd`, `depot_station.gd`, `depot_worker.gd`, `depot_forklift.gd`),
`route.gd` (`start_yard`: suelo nivelado y sin árboles bajo el depósito; el primer tramo no
puede ser un túnel), `route_terrain.gd` (`flat_zones`), `route_sky.gd` (no llueve bajo techo:
grupo `roofed_area`), `synth_audio.gd` (portón, zumbido, alarma de retroceso, radio).
En la zona compartida: `level_base.gd`/`.tscn` y `level_endless.gd`/`.tscn` (nodo `Depot`,
camión en su bahía, jugadores aparecen en el depósito, pedidos al cargar el nivel en vez de
por orden del rack), `event_bus.gd` (`depot_orders_posted`, `depot_station_opened`,
`depot_supplies_changed`, `depot_notice`). En archivos de Slatex, cambios chicos:
- `core/crew_progression.gd`: `SUPPLIES`, `supplies`, `buy_supply()`, `take_supplies()`.
- `package/package.gd`: `impact_absorption` (escala cada golpe; el acolchado la baja a 0.75).
- `package/package_feedback.gd`: la cuenta regresiva del explosivo sólo se ve durante el run.
- `interaction/package_pickup_point.gd`: el aviso dice el estante ("Agarrar paquete A-3 · Frágil").
- `ui/prototype_hud.gd`: textos de inicio, objetivo con los pedidos, avisos del depósito,
  abre `ui/depot_panel.gd` (nuevo: pizarra, vestuario, taller, suministros, progreso).
- Tests: `test_house_assignment` actualizado; nuevo `test_depot`; capturas `render_depot.gd`.

## Aviso activo: paquetes que se abren (2026-09-23)

Pedido del usuario: los paquetes tenían que abrirse y mostrar el contenido, a nivel
profesional. Nacho lo hizo en archivos de Slatex:
- `scenes/gameplay/package/package.tscn`: `Box` pasó a `Node3D` (contiene el modelo); se
  quitaron `StrapX`, `StrapZ`, `Status` y `TopMark`; nuevo nodo `PackageContentsView`; se
  replican `is_open` y `contents_spilled`.
- `scripts/gameplay/package/package.gd`: `content`, `is_open`, `request_set_open()` (RPC al
  host, con chequeo de distancia), `spill_contents()` al volcarse o golpearse abierta.
- `scripts/gameplay/package/package_feedback.gd`: instancia la caja GLB según el contenido;
  un material por paquete (resaltado + tinte de estado); etiqueta de envío texturizada en el
  dorso; sin las marcas procedurales viejas.
- Nuevos: `package_content.gd`, `package_contents_view.gd`, `data/contents/*.tres`;
  `trap_definition.gd` suma `contents` y `pick_content()`.
- `scripts/gameplay/player/player.gd`: tecla `package_open` (T / D-pad abajo) y la señal local
  `package_lid_hint_changed`; `scripts/ui/prototype_hud.gd` la muestra bajo el prompt.
- Del lado de Nacho: `delivery_house.gd` (caja abierta = entrega con reparos),
  `synth_audio.gd` (`tape_rip`, `cardboard_flap`), `event_bus.gd` y `project.godot` (acción).

## Aviso activo: rediseño de la UI (2026-09-23)

Pedido del usuario: la UI se veía vieja. Nacho rehízo el sistema visual en archivos de Slatex:
- `scripts/ui/ui_theme.gd`: estilo "etiqueta de envío" (tarjetas crema con borde y sombra de
  sticker, cintas, botones que se hunden), tipografías Lilita One + Nunito (`assets/fonts/`),
  paleta nueva (`docs/direccion-visual.md` §3). Mismos nombres de funciones y constantes; nuevas:
  `title`, `tag`, `chip`, `logo`, `keycaps`, `trap_icon`, `apply`. Ojo: los paneles ahora son
  claros, así que el texto sobre ellos va en `INK`, no en `PAPER`.
- `scripts/ui/main_menu.gd`: logo a la izquierda, tarjeta de menú a la derecha.
- `scripts/ui/prototype_hud.gd`: HUD con íconos de trampa, velocímetro, fichas de tiempo y
  dinero, teclas dibujadas; resultados con puntaje destacado. `hint_label` y `shortcut_label`
  pasaron a `RichTextLabel`. Se corrigió el "DO NOT DROP" que quedaba en la pantalla previa.
- `scripts/ui/options_panel.gd`: mismo estilo.
Todos los tests de UI pasan; capturas con `tests/render_main_menu.gd` y `tests/render_hud.gd`.

## Aviso activo: assets nuevos para el dominio de Slatex (2026-09-23)

Nacho generó assets que caen en el dominio de Slatex. Ya están en el repo pero **sin
enchufar** (detalle en `docs/inventario-assets.md` secciones 1-3):
- Guantes del viewmodel (`models/characters/sm_char_viewmodel_glove_{left,right}.glb`) y el
  celular (`models/props/handheld/sm_prop_phone.glb`).
- Íconos de las 4 trampas (`assets/ui/icons/tx_ui_trap_*_256.png`) para el HUD.
- Recordatorio: las cajas por trampa `models/cargo/sm_cargo_package_*.glb` existen desde el
  lote 1 y `package.tscn` todavía no las usa.

Lo que sí tocó Nacho en archivos de Slatex: `scripts/ui/main_menu.gd` ahora pone de fondo la
ilustración `assets/ui/backgrounds/tx_ui_menu_background_1920.png` (un `TextureRect` más un tinte,
por encima del `ColorRect` de siempre). También `project.godot` (zona compartida): ícono nuevo
(`icon.png`) y splash de arranque propio.

## Aviso activo: el juego se llama "Take My Package" (2026-09-22)

Nacho cambió el nombre oficial en la zona compartida y en dos archivos de Slatex:
- `project.godot` → `config/name="Take My Package"`. Eso mueve la carpeta `user://`;
  `scripts/core/legacy_user_data.gd` copia una sola vez `settings.cfg` y
  `leaderboard.json` desde la carpeta vieja ("Do Not Drop"), llamado desde
  `GameSettings._load()` y `RunManager._load_leaderboard()`.
- `export_presets.cfg` → `product_name` y el ejecutable pasa a `TakeMyPackage.exe`.
- `scripts/ui/main_menu.gd` (título) y `scripts/ui/prototype_hud.gd` (esquina de
  marca): el texto `"DO NOT DROP"` pasó a `"TAKE MY PACKAGE"`. Es un texto más
  largo en un panel de 240 px: si se corta, ajustarlo es de Slatex.
- La carpeta `do-not-drop/` **no** se renombra.

## Aviso activo: tanda de pendientes de ambas listas, con archivos de Slatex (2026-09-23)

Pedido del usuario: implementar todo lo pendiente de las dos listas, sea de quien sea.
Detalle por ítem en `tareas-nacho.md` y `tareas-slatex.md`. En archivos de Slatex:
- `core/unlock_manager.gd`: uniforme por defecto "Color de equipo" (cada jugador su color;
  antes todos salían menta), camiones y pinturas elegibles; perfil v2 migra el menta viejo.
- `ui/cosmetics_panel.gd` (dos columnas: Uniforme / Camión y Pintura), `ui/main_menu.gd`
  (botón "Apariencia"), `ui/prototype_hud.gd` (desglose de puntaje, caja rescatada, marcador
  de ping, aviso de clima y de caja equivocada, atajo "mirar atrás").
- `player/player.gd`: manos del asiento que responden a la trampa; `package/package.gd`:
  `consume()` anima la entrega en la puerta.
- `core/game_settings.gd` / `ui/options_panel.gd`: acción reasignable `look_back` (B).
- Tests de Slatex actualizados a 7 trampas: `test_endless_multi_cargo`, `test_reference_truck`,
  y `test_hint_relay` (teardown) — este último sigue crasheando a veces al cerrar el motor,
  pasa siempre sus verificaciones; ya pasaba antes de estos cambios.

## Aviso activo: optimización de rendimiento, con archivos de Slatex (2026-09-23)

Pedido del usuario: tirones al manejar rápido. Detalle y reglas nuevas en
`docs/convenciones-godot.md` §0.1; benchmark en `tests/bench_drive.gd` (README → Rendimiento).
Del lado de Nacho: `route.gd` + `dressing_batcher.gd` nuevo (decorado horneado en MultiMesh),
`delivery_house.gd`, `vehicle.gd`, `synth_audio.gd`, `wildlife_animal.gd`, `project.godot`.
En archivos de Slatex, cambios chicos por la interpolación física:
- `player/player.gd`: el cuerpo sentado se posa en `_physics_process` (con interpolación);
  `reset_physics_interpolation()` al bajarse del asiento y en el rescate de caída.
- `package/package.gd`, `package_feedback.gd`, `package_contents_view.gd`:
  `reset_physics_interpolation()` tras cada teletransporte (soltar, montar, restos, etiqueta).
- `interaction/seat_point.gd`: el indicador solo reescribe su material cuando cambia.
- `presentation/phone_camera.gd`: sigue la pose interpolada de la cámara que reemplaza.

## Aviso activo: segunda pasada del camión, con archivos de Slatex (2026-09-24)

Pedido del usuario tras probarlo. Nacho tocó, además del camión:
- `interaction/seat_point.gd`: `tend_mount_paths` (un asiento cuida la columna de bahías
  que tiene enfrente; lo usan los 3 asientos rebatibles `RackSeat*` frente al rack).
- `package/package_feedback.gd`: el resaltado ya no pone la caja blanca; muestra un borde
  cálido fino (`HighlightOutline`, casco invertido del tamaño del cuerpo de la caja).
- `core/game_settings.gd`: HUD por defecto al 60 %, mínimo 35 %. Los `settings.cfg` viejos
  (sin la marca `hud_scale_default_60`) pasan una vez al 60 %.
- `ui/prototype_hud.gd`: con un panel con botones abierto (inicio, pausa, resultados) el
  cursor queda visible aunque el jugador local lo capture al aparecer.
- `player/player.gd`: una E ya no dispara dos interacciones (el evento de tecla y el sondeo
  de física disparaban ambos: guardaba el paquete y lo volvía a agarrar, abría y cerraba la
  puerta); la caja en mano nunca se acerca tanto que la cámara quede adentro; al levantarse
  de un asiento se para en el piso delante (o en `ExitPoint` si el asiento tiene uno: el
  conductor baja por su puerta); solo se interactúa con lo que se tiene al alcance (nada a
  través de paredes, `_within_reach`).
- `seat_point.gd`: `required_door` -- el asiento del conductor pide la puerta abierta; se
  cierra sola al sentarse y se abre al bajar. El camión ya no colisiona con jugadores desde
  su lado (máscara 5): un jugador dentro de su colisión lo hacía salir despedido.
- Se probó la interpolación física y se descartó: con el camión congelado mandaba las
  ruedas al origen del mundo y ocultaba las animaciones de puertas y el paquete al dejarlo.
  **Reactivada el 2026-09-23** (optimización): era la causa del tirón al manejar rápido (la
  cámara quedaba quieta en el 64% de los frames). Las ruedas: `vehicle.gd` saca al camión
  de la interpolación mientras está congelado (`_match_interpolation_to_freeze`). Puertas y
  paquete montado se verifican con `tests/check_interpolation.gd` (con ventana, deja capturas).
- Puertas: responden solo si se las mira (ya no se roban la E de paquetes y asientos).

## Aviso activo: camión de referencia integrado y pulido (2026-09-23)

El modelo de Slatex (`assets/models/truck_reference_lowpoly.glb`, commit 177d82c) ya está
integrado; Nacho vuelve a ser dueño de `vehicle.tscn`/`vehicle.gd`. Lo que cambió:
- `vehicle.tscn` se rehízo sobre el modelo: colisiones que calzan con lo que se ve (cabina
  convexa, piso, paredes, techo, pasos de rueda, filas de asientos), ruedas físicas sobre los
  ejes del modelo, asientos en los 7 asientos reales, y un rack profundo de 2 niveles × 3 bahías
  en la pared izquierda (las 6 `*PackageMount` de siempre, mismos nombres). Entran las tres
  formas de caja (0.65, alta 0.98, plana 0.95) y el pasillo queda ≥ 0.85 m.
- Puertas: traseras y las dos de cabina se abren/cierran (`vehicle_door_interaction.gd`,
  estado replicado en `vehicle.gd`). Reemplaza a `interaction/rear_cargo_door.gd` (borrado).
  Rampa trasera cuando las puertas están abiertas y el camión parado.
- `vehicle.gd` reasienta en la bahía los paquetes altos/planos (escucha `package_placed`):
  no hace falta tocar `package_mount_point.gd`.
- `vehicle_presentation.gd`: `bind_model()`; la inclinación/hundimiento solo se ve desde afuera.
- Detalle y medidas: `scripts/presentation/reference_truck.gd` y `tests/test_reference_truck.gd`.

## Aviso activo: sistema de casas de entrega (route.gd) necesita un cambio chico de Slatex

`route.gd` ahora construye `house_count` casas con timbre a lo largo de la
ruta en vez de una única zona de entrega (pedido del usuario, 2026-09-21;
detalle completo en `docs/tareas-nacho.md` #101-108). Construido entero del
lado de Nacho, sin tocar ningún archivo de Slatex.

**Resuelto (2026-09-22), tocando archivos de Slatex por decisión explícita
del usuario** ("pulir todo a nivel profesional"). El gap que bloqueaba el
flujo completo era que no se podía volver a levantar un paquete ya montado
(`is_loaded == true`) para bajarlo caminando hasta una casa, así que **las
tres casas de la ruta eran inalcanzables y todas resolvían como "missed"** —
y nada escuchaba `route.house_resolved` de todos modos, así que entregar
bien, entregar roto o pasar de largo daban el mismo puntaje. Archivos de
Slatex modificados, todos con cambios chicos y aislados:

- `scripts/gameplay/interaction/package_pickup_point.gd` — se ensanchó
  `get_prompt()`/`interact()` para poder bajar un paquete cargado, liberando
  el `occupied_by` del mount del que salió. El caso original (agarrar del
  piso) no cambió.
- `scripts/ui/prototype_hud.gd` — resultados con puertas, quejas de clientes
  y fotos; etiquetas separadas para eventos de ruta y avisos (antes se
  pisaban entre sí y con el prompt de interacción); botones de Opciones y de
  volver al menú en la pausa.
- `scripts/ui/main_menu.gd` — botones Opciones y Salir; la paleta pasó a
  `scripts/ui/ui_theme.gd`, ahora compartida con el HUD en vez de duplicada.
- `scripts/gameplay/player/player.gd` — dos líneas en `_apply_look()` para
  respetar la sensibilidad e inversión de `GameSettings`.

Zona compartida tocada en el mismo pase: `event_bus.gd` (dos señales nuevas
de entrega), `run_manager.gd` (registro y puntaje de entregas, quejas y
fotos), `level_base.gd` (conecta las casas con el puntaje) y
`scripts/presentation/first_person_camera.gd` (la misma sensibilidad).

El número de casas es `max(jugadores - 1, 1)`; desde 2026-09-23 lo fija el host una
vez por sesión y viaja en el handshake (`NetworkManager.world_house_count`), y la
pizarra del depósito asigna una caja concreta a cada casa desde la semilla.

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

## Aviso S-103 · 2026-09-24

Slatex agregó la acción compartida `use_card` a `project.godot` (G / D-pad izquierda),
sin cambiar ninguna acción existente. En `depot.gd` se agregaron únicamente
`request_discounted_supply()` y `buy_supply_discounted()` para que Descuento siga el
mismo camino autoritativo y sincronizado de las compras normales; no se modificaron
firmas existentes. `README.md` suma `test_cards.gd` a la batería. Antes de continuar
trabajo en esos archivos compartidos, hacer `git pull` después del aviso de push.

## Aviso S-104 · 2026-09-24

Slatex agregó `test_supply_vote.gd` a la lista compartida de pruebas de `README.md`.
La implementación queda aislada en `shop_vote_manager.gd` y `depot_panel.gd`; no
cambia firmas compartidas ni vuelve a modificar `depot.gd`. Hacer `git pull` tras
el aviso de push antes de editar la misma sección de tests del README.

## Aviso S-105 · 2026-09-24

Slatex agregó `test_crew_campaign_save.gd` a la lista compartida de pruebas de
`README.md`. La implementación está aislada en progresión/UI y suma
`scripts/core/safe_json.gd`; no cambia firmas de la zona compartida. Hacer
`git pull` tras el aviso de push antes de editar la misma sección del README.

## Aviso S-203 · 2026-09-25

Slatex amplió la detección de camioneta atascada de `level_base.gd`, sobre la base
agregada por N-803. El contador ahora se reinicia en el depósito, junto a una casa y
cuando no hay conductor, aunque todavía quede fuerza de motor del frame anterior.
No cambia firmas compartidas. `test_stuck_detection.gd` cubre las tres exclusiones
además del bloqueo real contra un obstáculo.

## Aviso S-210 · 2026-09-25

Slatex pasó el guardado del leaderboard en `run_manager.gd` al helper común
`safe_json.gd`; no cambió sus firmas ni su formato. También migró el perfil de
`unlock_manager.gd` y mantuvo la campaña sobre el mismo helper. `README.md` suma
`test_safe_json.gd`, que verifica la cuarentena `.bad` y los valores por defecto
ante JSON truncado.

## Aviso S-107 · 2026-09-25

Slatex cambió la selección interna de `post_orders()` en `depot.gd`: ahora delega
el orden de trampas al módulo puro `order_balancer.gd` y después toma la caja
correspondiente de los mismos estantes. No cambió ninguna firma pública. El
handshake de `network_manager.gd` también comparte las partidas completadas del
anfitrión para que todos calculen exactamente el mismo pedido. Hacer `git pull`
antes de editar esos sectores compartidos.

## Cómo se armaron las 200 tareas

Las primeras ~70 de cada lista salen directo de los ítems pendientes de
`docs/especificaciones-visuales.md`, repartidos por el mismo criterio de dominio de
archivos. El resto son tareas reales del backlog del proyecto (Fase 5 y 6 del plan de
desarrollo, contenido nuevo, streaming de tramos/modo endless, pulido, documentación)
descompuestas en pasos concretos — no relleno. Cada lista tiene prioridad **A/B/C**
igual que `especificaciones-visuales.md`: A es accionable ya, B necesita arte/pipeline,
C es pulido para más adelante.

# Aviso S-108 · 2026-09-26

El simulador reproducible de balance de trampas agrega dos herramientas aisladas en `tests/`,
documenta objetivos y resultados en `docs/parametros-diseno.md` y añade sus comandos al
`README.md` compartido. El ajuste queda limitado a parámetros de `data/traps/*.tres`; no cambia
comportamientos ni archivos del dominio de Nacho.
