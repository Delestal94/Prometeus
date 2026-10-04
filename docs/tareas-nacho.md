# Tareas de Nacho — Vehículo, Ruta, Ambientación y Depósito

> Reescrita entera con el mismo formato que `docs/tareas-slatex.md`: las tareas 1-127 de la
> versión anterior están cerradas o reubicadas (ver "Qué pasó con la lista anterior" al final).
> Esta lista sigue los 9 pilares de producción y **solo tiene trabajo que Nacho puede terminar
> sin esperar a Slatex y sin playtesting**.
>
> División de dominios y zona compartida: `docs/colaboracion-equipo.md`.
>
> **Lo terminado se archiva** en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md) (bloques `###` sin
> `[ ]`, ⏸ ni ⚠; lo mueve `tools/archivar-tareas.py` en el mantenimiento semanal). Un ID que no está
> acá y aparece allá está hecho: buscalo con `grep`, sin leer el archivo entero.

## Mapa dinámico — pasos solicitados por el equipo

### N-963 · Semilla dinámica por partida — A · Aviso: sí (`network_manager.gd`, zona compartida) · **[x] rama `nacho/N-963-dynamic-run-seeds`**
Pedido del equipo (2026-10-02): empezar paso a paso por las semillas. En los modos actuales, cada
nueva entrega elige una semilla distinta, estable durante esa entrega y compartida con quienes
ya están conectados y quienes entran tarde. Solo ya genera rutas distintas; faltaba cambiar la
semilla al reiniciar dentro de una sala. El mundo persistente por campaña del futuro modo Pueblo
se conectará en otro paso: continuar un guardado deberá conservar la semilla de ese mundo.
- [x] Elegir una semilla no nula al crear sala y al reiniciar; rechazar que repita la anterior.
- [x] Enviar la semilla por el payload de reinicio antes de reconstruir en el cliente; subir
  `PROTOCOL_VERSION` y conservar el handshake de entrada tardía.
- [x] Ampliar `test_world_seed.gd`: repetición forzada, semillas por partida, reinicio y late join,
  igualdad del mapa con semilla fija, variedad solo y limpieza al salir de sala.
  **[x] Hecho (2026-10-02)** — `_roll_world_seed()`, `_before_restart()`, `_restart_state()` y
  `_apply_restart_state()` en `network_manager.gd`; protocolo 28. La prueba ampliada falla 65
  verificaciones con el código anterior y pasa con el cambio. `test_protocol_version`,
  `test_menu_session_paths` y `test_net_session` pasan; lint y `check_modules` verdes.
  Aviso: `docs/avisos/2026-10-02-semillas-por-partida.md`.

### N-950 · Spike de ciudad procedural — A · Aviso: sí (módulo portable) · **[ ] en desarrollo (base mergeada en PR #260; faltan los [ ] de abajo)**
Pedido directo del equipo (2026-10-02): seis distritos, ciudad asimétrica y
variable por semilla, calles diagonales, plazas, parques y monumentos.
Rama reservada `nacho/N-950-town-spike` retomada tras más de dos horas sin
implementación ni PR. Documentación: `docs/mapa-pueblo.md`.
- [x] Base del plano versionado y determinista, seis distritos conectados,
  lotes con frente de calle y áreas verdes fuera del asfalto.
- [x] Escena independiente del barrio inicial con depósito, tres casas,
  taller, parque, plaza/monumento, mobiliario y dos salidas cerradas.
  Validación del primer paso: 100 semillas en `test_town_plan`, escena en
  `test_town_prototype`, módulo aislado portable, lint y revisión visual.
- [x] Camión, pedidos de orden libre y navegación/GPS por calles: escena
  offline `town_delivery.tscn` con jugador, carga y timbres reales, selección
  de tres clientes y regreso al depósito. Sin progreso persistente todavía.
- [ ] Medición del spike: duración, esfuerzo de carga, visibilidad y render.
- [x] Integración del arte existente (2026-10-03): viviendas variadas a escala
  nativa, clientes distintos, piezas/materiales del depósito y taller,
  estante original y árboles/bancos/farolas existentes (`town_art.gd`).
- [x] Segundo distrito construido (2026-10-03): Centro con arquitectura
  original de dos plantas, comercios, plaza/parque y corredor transitable.
  F4 guía al Centro; F1–F3 vuelven a pedidos. Campo e Industrial siguen cerrados.
  Apertura sin mover el plano; rutas entre distritos sobre 100 semillas.
- [x] Reparto entre dos distritos (2026-10-03): seis pedidos A–F, tres
  clientes iniciales y tres del Centro con timbre/modelo original. Estante
  de dos niveles accesibles, F1–F6 clientes y F7 plaza. Direcciones estables
  sobre 100 semillas; final exige resolver ambos distritos y volver al depósito.
- [x] Aceras y accesos peatonales (2026-10-03): calles diagonales/cruces,
  rampas, entradas a cada lote y caminos a plazas/parques que rodean edificios.
  Pavimento agrupado con colisión y árboles/muebles fuera del paso. Cinco
  semillas del módulo, módulo aislado y jugador real cruzando sin saltar,
  tanto en headless (componente de movimiento) como con pantalla.
- [x] Reutilización de carretera (2026-10-03): TerrainField/shader/texturas,
  StraightSegment/pintura y RouteDresser/RoutePlacement originales. Perfil
  urbano con bases niveladas y relieve natural entre ellas; vegetación, autos, mobiliario/paradas
  respetan lotes/accesos y se agrupan con DressingBatcher. Pruebas de escena
  y reparto verifican integración sin cambiar el plano ni sus direcciones.
- [x] Completar frentes libres de Barrio y Centro con parcelas compactas; generador
  v2 compatible con v1, calles/clientes intactos y accesos verdes reservados.
- [x] Escenas de ciudad completa (2026-10-03): seis distritos, siete conectores
  abiertos, doce entradas verdes y mismos seis pedidos. Almacenes Industrial/Puerto,
  farmhouses/molino en Campo, cabañas/pinos en Sierra y torre de agua.
  Suelo continuo entre zonas e índice de plataformas que conserva alturas.
- [x] Biomas de Puerto/Sierra (2026-10-03): bahía exterior con lecho físico,
  agua, muelle transitable y acceso que esquiva lotes/parques; relieve original
  en Sierra y nieve local en altura. Calles, parcelas y accesos permanecen nivelados.
  `town_biomes.gd`, `town_terrain.gd`; pruebas de 20 semillas y escena completa.
- [x] Aceras realistas (2026-10-03): 16 cm sobre asfalto, cordón vertical;
  rebajes sólo vehiculares y de accesibilidad en esquinas. `town_walkways.gd`
  y `town_prototype.gd`; `character_step` permite subir cordones sin saltar,
  comprobando cuerpo completo, techo, pared y superficie de apoyo.
- [x] Relieve urbano natural (2026-10-03): ondulaciones asimétricas entre
  plataformas; bases de torre/molino reservadas antes de generar el suelo.
- [x] Primeras calles interiores (2026-10-03): generador v3, secundarias de
  8 m en 0/1/2/4, clientes originales y generadores v1/v2 conservados.
  Sigue faltando mayor ocupación de sus interiores y manzanas completas.
- [ ] Completar manzanas interiores, horizonte y presupuesto de render.
- [ ] Campaña persistente, guardado versionado y desbloqueo de distritos.

## QA — bugs abiertos

### N-924 · `test_net_session_rejoin` pasaba con un `SCRIPT ERROR` y no probaba al ladrón por ENet — B · `Opus 5.5 · high` · Aviso: sí (`modules/net_session/tests/`, zona compartida)
Origen: cuerpo del PR #259 (2026-10-02), diagnóstico con `cazador-bugs` (2026-10-04). `_check_thief` leía la clave del
que volvió en `victim.replies[-1].identity`, pero desde #235 (protocolo 26, "identity before state") en sala llena esa
clave viaja en el identity reply (`net_admission.gd:176-178`) y el ready reply ya no la trae (`net_session.gd:715-719`).
El `SCRIPT ERROR` cortaba `_check_thief` antes de su primer `await`, el test seguía y salía con 0: la parte "alguien que
repite una clave escucha connection y la víctima se queda" no se verificaba desde #235. El módulo estaba bien.
- [x] **N-924.1** El test guarda cada clave que manda (`claims`, override de `_claim_identity()`) y el ladrón roba la
  última. **[x] Hecho (2026-10-04, rama `nacho/N-924-rejoin-thief-check`)** — sin `SCRIPT ERROR`; el chequeo del
  ladrón corre de verdad. Aviso: `docs/avisos/2026-10-04-rejoin-thief-check.md`.
- [ ] **N-924.2** `tools/run-tests.sh` (`run_one`) decide solo por código de salida: un `SCRIPT ERROR` de ejecución
  con exit 0 pasa como PASS. Marcarlo FAIL (con el mismo filtro de ruido que usa el resumen, l.284) y, antes, correr
  la batería en CI para listar y arreglar los tests que hoy pasan con errores escondidos. Con `escritor-tests` /
  `cazador-bugs`; aviso (tooling común).

### N-919 · Regresión de #208: los `--script` que llegan a `DeliveryHouse` cargan el HUD sin script — B · `Opus 5.5 · high` · Aviso: sí (`scripts/gameplay/player/player_cargo_care.gd` es de Slatex) · M8
Origen: PC build 2026-10-02 (bisect confirmado con `cazador-bugs`). El PR #208 (`6a7c408`, N-224 tipó la caja como
`DeliveryPackage` en `delivery_house.gd`) agregó la dependencia estática `DeliveryHouse → DeliveryPackage →
package_rescue → Player → player_cargo_care → Hud`. `hud.gd:154` nombra `NetworkManager`; en un `--script` el árbol
compila antes que los autoloads y da `SCRIPT ERROR: Identifier not found: NetworkManager`. El resto de la cadena
recompila bien después, pero `hud.gd` no: el nodo `HUD` de `level_base.tscn` queda como `CanvasLayer` con
`script=<null>`. El juego normal y el exportado no se afectan.
Alcance: scripts `extends SceneTree` afectados, 25 antes del #208 (los que nombran `Player`/`DeliveryPackage`) y 57
después (todo lo que llega a `route.gd`, `DeliveryHouse` o `RouteStreamer`): `bench_drive`, `render_route_dressing`,
`render_goal_lot`, `render_house_waiting`, `render_mud_segment`, `render_wheel_dust` y ~25 `test_*` (lista completa en
`D:\tmp\nm-probe\hits.txt` de la PC, fuera del repo). Consecuencias: `bench_drive` (serie diaria de la PC y paso
"Measure rendered performance" de CI) mide sin HUD desde el #208 (objects 2542 → 2255, FPS de reparto 153 → 173 el
2026-10-02: no comparables); las capturas `render_*` salen sin HUD; los tests que necesitan HUD vivo reciben un nodo
muerto sin avisar. CI no lo ve: `run-tests.sh` decide por código de salida y el smoke de `release.yml` no usa `--script`.
Hecho cuando `bench_drive` y `render_route_dressing` corren sin `SCRIPT ERROR` y el HUD de `level_base` existe con su
script (comprobado por un test), y la serie de `docs/rendimiento-pc.md` anota desde qué fila vuelve a medir con HUD.
- [x] **N-919.1** Cortar la única dependencia de afuera hacia `Hud`: `player_cargo_care.gd:66-67,77-78` usan
  `Hud.EDGE_MARGIN`; reemplazar por una constante local `EDGE_MARGIN: int = 40` (como ya hace con `BASE_HEIGHT`, l.23),
  con comentario del motivo (un `--script` compila antes que los autoloads). Probado en un worktree: 56 de 57 scripts
  compilan sin `SCRIPT ERROR` y el HUD vuelve a tener `hud.gd`. Con `constructor-jugador`; tests `cargo_care`, `hud`.
  **[x] Hecho (2026-10-02, rama `nacho/N-919-hud-script-dep`)** — `EDGE_MARGIN` local en `player_cargo_care.gd`; `bench_drive` y `render_route_dressing` corren sin `SCRIPT ERROR` y el HUD de `level_base` vuelve a tener `hud.gd` (comprobado con y sin el arreglo). Aviso `docs/avisos/2026-10-02-regresion-208-hud-sin-script.md`.
- [x] **N-919.2** Identificar el `SCRIPT ERROR` que sigue en `tests/test_depot_mirror.gd` (ya afectado antes del #208) y
  arreglarlo. Con `cazador-bugs`; tests `depot_mirror`.
  **[x] Hecho (2026-10-02, rama `nacho/N-919-hud-script-dep`)** — causa: `depot.gd` precargaba como tipo `run_manager.gd`, `crew_progression.gd`, `rescue_hook.gd` y `vehicle_faults.gd` (nombran `EventBus`; #202, N-224.3): todo `--script` que nombra `Depot` dejaba `/root/RunManager` sin script. Pasan a `Node` sin tipo, como en `PackageAutoloads`; `test_dynamic_dispatch_budget` ajustado. Ojo: un `.godot/` local viejo (caché de clases anterior a los módulos) da `Parse Error` falsos; `--import` lo arregla.
- [x] **N-919.3** Tests: (a) `player_cargo_care.EDGE_MARGIN == Hud.EDGE_MARGIN`, cargando `hud.gd` con `load()` en
  runtime; (b) un chequeo que falle si un `--script` deja el HUD de `level_base` sin script, o que `run-tests.sh` y CI
  traten `SCRIPT ERROR: Compile Error` como falla (así la próxima dependencia estática no pasa en silencio). Con
  `escritor-tests`; tests `hud`, `run_tests`.
  **[x] Hecho (2026-10-02, rama `nacho/N-919-hud-script-dep`)** — `tests/test_hud_script_loads.gd`: llega a `DeliveryHouse` y `Depot` estáticamente y exige HUD con `hud.gd`, `RunManager` con script, los cuatro scripts compilables y los dos `EDGE_MARGIN` iguales; falla (9) con el código de antes. La opción de que `run-tests.sh` trate `SCRIPT ERROR` como falla queda sin hacer: el test cubre las dos cadenas conocidas; `level_common.gd` sigue precargando `vehicle_faults.gd` y `rescue_hook.gd` (un `--script` que nombre `LevelCommon` puede repetirlo).
- [ ] **N-919.4** Correr `bench_drive` (reparto y Endless) y anotar en `docs/rendimiento-pc.md` desde qué fila mide de
  nuevo con HUD y que las filas desde el #208 hasta el arreglo no son comparables. Con `perfilador-rendimiento`
  (necesita PC); aviso `docs/avisos/2026-10-02-regresion-208-hud-sin-script.md` en el mismo PR que N-919.1.

### N-409 · Precalentar shaders en la pantalla de carga — B · `Opus 5.5 · high` · Aviso: sí (`loading_screen.gd` de Slatex; `modules/` compartida) · **[x] rama `nacho/N-409-shader-prewarm`**

Pedido del usuario (2026-10-01), pensando en PCs sin placa de video: GL Compatibility compila cada shader la
primera vez que algo se dibuja con él, bloqueando ese cuadro.
- [x] `ShaderWarmer` (`modules/scene_loader/shader_warmer.gd`): junta una muestra por forma distinta de dibujar
  (material y formato de malla, multimesh, partículas, Label3D/Sprite3D; también lo oculto) y la dibuja en
  miniatura frente a la cámara, unas pocas por cuadro y adaptándose al tiempo de cuadro, detrás de la tapa.
  `SceneLoader._settle()` la corre antes de los revelados (`prewarm_shaders`); `LoadingScreen._warm_samples()` suma
  los 7 efectos de caja rota (`PackageRuinEffects.spawn`).
- [x] Medido (RTX 4060 Ti, `perfilador-rendimiento`): **caché caliente** (del segundo arranque en adelante) el peor
  cuadro al revelar depósito y ruta baja de 114 a 45 ms (+0,35 s de tapa). **Caché fría** (primer arranque): la
  rotura de caja Frágil baja de 684 a ~150 ms y Explosiva de 152-163 a 52-64 ms; el revelado total de 17,5 a 6,8 s; pero
  la tapa dura ~5 s más.
- [ ] **No resuelto (primer arranque)**: el cuadro del cambio de escena compila cielo, entorno, camión y jugador de
  una vez (~4,7 s en frío); las luces del depósito y de la ruta piden variantes que la grilla no ve (se compilan al
  revelarlas); los tirones al empezar a manejar (~400 ms en frío) no cambian. Siguiente paso posible: encender las
  luces antes de precalentar, y precalentar el cielo/sol/camión en un mundo aparte antes del cambio de escena.

### N-408 · Una pantalla de carga que no se congela y la regresión del flujo menú → jugable — A · `Opus 5.5 · xhigh` · Aviso: sí (`main_menu.gd`, `hud.gd`, `scripts/ui/` de Slatex; `modules/` y `network_manager.gd` compartidos) · **[x] rama `nacho/N-408-loading-no-freeze`**

Pedido del usuario (2026-10-01): con N-407 la pantalla quedaba congelada 9-12 s en "Armando la ruta…" y el sonido
se cortaba. Regresión del flujo completo (mapa, batería, QA real solo/endless/par/trío): todo anda; los hallazgos,
todos arreglados acá:
- [x] **Congelamiento al armar el nivel** (P1; perfilador: `Route._ready` 5,8 s en un solo bloque). La ruta se arma
  por cuadros (`FrameSlicer`, presupuesto 12 ms; terreno y adaptación en `WorkerThreadPool`; mundo idéntico bit a
  bit, `test_route_golden`); aviso `2026-10-01-n408-ruta-por-cuadros.md`. Mientras carga la escena, los modelos se
  precargan en hilos y los 34 sonidos del nivel se sintetizan en un hilo (`SynthAudio.warm()`).
- [x] **La tapa se levanta cuando el juego está listo de verdad**: espera a `SceneLoader.BUSY_GROUP` (la ruta) y a
  que el jugador propio exista (un cliente: hasta que el anfitrión lo spawnea), muestra depósito y ruta de a uno
  por cuadro (cada primer dibujo en su cuadro) y espera 8 cuadros fluidos; la barra llega al 100 % a la vista.
- [x] **El anfitrión no atendía la red mientras armaba** (P2): consecuencia de lo anterior, resuelto con él.
- [x] **Sonido**: la música del menú sigue bajo la pantalla de carga (`carry_audio`) y se funde bajo el nivel; la
  primera frase de la música del juego entra a los 1,5-3 s (antes 18-35 s de silencio).
- [x] **Reinicio de la entrega** (anfitrión y clientes) por la pantalla de carga: antes `reload_current_scene()`
  congelaba ~4 s.
- [x] **Menú**: "Crear sala Endless" (antes el anfitrión siempre cargaba el nivel normal); el motivo real de un
  error al crear/unirse ya no lo pisa el genérico "error %d"; si la conexión se cae con el nivel ya armándose, la
  pantalla de carga vuelve al menú con el motivo (`redirect_to`) y una invitación de Steam en ese momento queda
  pendiente (`NetworkManager.defer_lobby`).
- [x] **El que entra tarde** recupera el mouse cuando el arranque de la entrega le saca la tarjeta de inicio.
- [x] El espejo del depósito saca su primera foto cuando el depósito está a la vista.
- [x] Tests nuevos: `test_scene_loader_gates`, `test_synth_audio_warm`, `test_route_async_build`,
  `test_menu_to_level`, `test_menu_session_paths`, `test_level_loading_paths`; ampliados `test_route_gen`,
  `test_render_budget`, `test_route_golden`, `test_loading_flow`, `test_tension_music`.
- [x] **El depósito por cuadros** (rama `nacho/N-408b-depot-slices`, aviso `2026-10-01-n408-deposito-por-cuadros.md`):
  `Depot` arma en rebanadas de 12 ms bajo un cargador (`is_built`, `built`, `loading_progress()`), el nivel espera a
  depósito y ruta, y su primer dibujo se parte en ~13 pasos (`reveal_steps()`, uno por cuadro: 190-250 ms en uno
  → máx. 45-100 ms). Cuadro del swap 430-500 → 325-415 ms: lo que queda es el resto del nivel (HUD, vehículo,
  cajas, primer dibujo del mundo), sin partir. También: flechas del piso planas (parecían flotar: apuntaban en 3D),
  texturas del depósito con respaldo de color liso y `DepotAtmosphere` acotado (`test_depot_textures`).
- [ ] Siguen en un cuadro grande: el swap (~110 ms de `_ready` del nivel + ~150 ms del primer dibujo del mundo).
  `test_route_golden` difiere en Windows en el 4.º decimal (golden escrito en Linux): CI manda. Medir con GPU
  cuánto baja el cuadro de la ruta con N-408c (necesita PC: `perfilador-rendimiento`).
- [x] **N-408c** El primer dibujo de `World/Route` (150-220 ms) partido como el depósito **[x] Hecho (2026-10-02, rama
  `nacho/N-408c-route-reveal`)** — `Route.reveal_steps()` (helper `route_reveal.gd`): 12 pasos, uno por cuadro bajo la
  tapa; las piezas son los hijos de la ruta en el orden en que se armaron, con las baldosas del terreno y las celdas de
  `BatchedDressing` como piezas propias. Solo vuelve a mostrar lo que estaba visible. Test `test_route_async_build`
  (`_test_reveal_steps`). Sin medir con GPU (la nube dibuja por software).

### N-407 · Pantalla de carga entre el menú y el nivel — B · `Opus 5.5 · medium` · Aviso: sí (`main_menu.gd`, `scripts/ui/` de Slatex; `modules/` compartida) · **[x] rama `nacho/N-407-loading-screen`**

Pedido del usuario (2026-10-01): al tocar "¡JUGAR!" el menú se congelaba en su último frame mientras el nivel
cargaba y se armaba.
- [x] Módulo portable `scene_loader` (`SceneLoader`): carga la escena en un hilo
  (`ResourceLoader.load_threaded_request`) con la tapa ya puesta, la instancia con la tapa arriba y la saca recién
  cuando la escena nueva dibujó `settle_frames` frames (compilación de shaders y subida de mallas: el tirón que se
  veía). Mínimo 0,9 s en pantalla, fundido de 0,25 s, input tragado mientras está, `cancel()` mientras carga,
  `failed` si la ruta no carga. Hooks `_build_cover(cover)` y `_show_progress(ratio, stage)`.
- [x] `scripts/ui/loading_screen.gd` (`LoadingScreen extends SceneLoader`): arte propio
  (`tx_ui_loading_background_1920.png`, ComfyUI con `artista-conceptual`, semilla 1407, `art/concept/loading/`,
  fila en `art/ai-registro.md`: la camioneta saliendo al amanecer con cajas volando del techo) y el logo del menú en
  el mismo lugar, tinta abajo, tarjeta con cinta del modo ("JUGAR SOLO", "CREAR SALA", "UNIRSE A LA SALA", "MODO
  ENDLESS"), caja de cartón que salta sobre la ruta, etapa ("Cargando el camión…" → "Armando la ruta…" → "¡A
  repartir!"), barra y un consejo al azar (nunca el mismo dos veces seguidas). Textos `UI_LOADING_*`.
- [x] `main_menu.gd`: `_go_to_level(path, mode)` pasa por `LoadingScreen.go()`; un segundo toque no arma otra
  carga; si la conexión se cae mientras carga (`_on_session_failed`) o llega una invitación de Steam, se cancela y
  el menú queda con el error.
- [x] Tests `test_scene_loader` (módulo, también en `portability-check.sh`) y `test_loading_screen`. Capturas:
  `tests/render_loading_screen.gd` (`revisor-visual` con GPU, 2026-10-01: arte sin estirar, logo 420×210, tarjetas
  legibles también a 1024×600, el nivel cargado en hilo sin texturas negras ni rosas).
- [ ] Fuera de alcance: el reinicio de la entrega (`restart_delivery`, ya tiene fundido a negro) y la vuelta al menú.

## Hecho fuera de lista: auditoría de rendimiento (2026-09-29)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: red por Steam y bugs del playtest (2026-09-29)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: túneles del tren y repaso de las cascadas (2026-09-29)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: cascadas en las puntas del río (2026-09-28)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Hecho fuera de lista: repaso del depósito tras playtest (2026-09-27)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Cómo leer esta lista

- **ID**: `N-<pilar><número>` (N-101 es pilar 1, tarea 01). Subtareas `N-101.1`, `N-101.2`…
  con `[ ]` / `[x]`.
- **Prio**: **A** hacer ya (cierra algo roto o a medias) · **B** suma valor claro · **C** pulido.
- **Esfuerzo**: el modelo es siempre **Opus 5.5**; lo que cambia por tarea es el esfuerzo de
  razonamiento (ver "Cómo trabajar una tarea").
- **Aviso**: `sí` = toca la zona compartida o un archivo de Slatex. No hay que esperarlo: se deja
  el aviso en `docs/colaboracion-equipo.md` **en el mismo commit**, con un cambio chico y aislado
  (agregar antes que cambiar firmas).
- **Hecho cuando**: el criterio verificable. Sin eso la tarea no se marca.
- **Sin playtesting**: lo que antes era "falta playtesting" se reemplazó por mediciones con código
  (bots, benchmarks, tests, capturas). Lo que necesita gente jugando está en "Para cuando haya
  playtesting" y **no se hace ahora**.

### Cómo trabajar una tarea (Claude Code con Opus 5.5)

Modelo fijo: **Opus 5.5**. Cada tarea trae anotado el esfuerzo recomendado (`/effort` en Claude
Code antes de empezarla):

| Esfuerzo | Cuándo | Ejemplos |
|---|---|---|
| **low** | Cambios mecánicos o de documentación sin decisiones. | N-307, N-701, N-804 |
| **medium** | Decisiones ya tomadas en la tarea, textos, un archivo, assets con script conocido. | N-101, N-202, N-308, N-601 |
| **high** (por defecto) | Una mecánica o sistema en 1-3 archivos con su test. | N-102, N-104, N-302, N-501 |
| **xhigh** | Red (RPC, autoridad, varios procesos), refactors de archivos compartidos, cambios que tocan 4+ archivos. | N-206, N-207, N-208, N-209, N-504 |
| **max** | Nunca de entrada: solo si xhigh no resolvió un bug después de pasarlo por `cazador-bugs`. | — |

Subir un nivel si la tarea falla una vez con el esfuerzo anotado; bajar uno para las subtareas
chicas de una tarea grande ya encaminada.

Además, siguiendo `CLAUDE.md`: los tests se corren con el agente `ejecutor-tests` y un filtro
(`tools/run-tests.sh route`), las capturas y todo lo que necesite pantalla con `revisor-visual`, y
un test que falla sin causa clara con `cazador-bugs`. Al cerrar: `[x]` + hash del commit acá, test
anotado en la lista del README y, si hubo aviso, la entrada en `colaboracion-equipo.md`.

---

### N-908 · Quien entra tarde no sabe qué cajas llevan los demás — B · `Opus 5.5 · xhigh` · Aviso: sí (`player.gd`, `package_handling.gd`, `seat_tending.gd`, dominio de Slatex) · **[x] rama `nacho/N-908-late-join-carry`**
Origen: mantenimiento 2026-10-01. `carried_package` solo viaja en el broadcast `player.rpc(&"pick_up")` al levantar
(`scripts/gameplay/package/package_handling.gd:61`, `scripts/gameplay/player/player.gd:302-305`). En el cliente que entra
tarde `SeatTending._holder_of()` (`scripts/gameplay/interaction/seat_tending.gd:188-196`) da null, así que
`lap_reserves()` (`seat_tending.gd:128`) da false y `CargoSeatPoint._can_board` / `_free_bay` muestran asientos y
bahías libres que el host tiene reservados; además ve a los compañeros sin pose de carga. Hecho cuando un test en
`test_late_join_seating.gd` (o el de seat tending) cubre la vista cliente con una caja en el regazo (`lap_reserves`
true) y el reenvío del host a un peer nuevo.
- [x] ~~**N-908.1** En el host, `Player._on_peer_level_ready`, tras `sync.update_visibility(peer_id)`: `if
  is_instance_valid(carried_package): rpc_id(peer_id, &"pick_up", carried_package.get_path())`. Respaldo:
  `_holder_of` en el cliente busca al jugador con autoridad = `package.tender_peer_id` cuando `is_held`. Con
  `constructor-red` y después `auditor-red`; tests `late_join`, `seat_tending`.~~
- [x] ~~**N-908.2** Test de vista cliente con caja en regazo y de reenvío de `pick_up` a un peer nuevo. Con
  `escritor-tests`; tests `late_join`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-908-late-join-carry`)** — `player_net_visibility.gd` `refresh_peer()`: el host,
  tras `update_visibility(peer_id)`, reenvía `pick_up` a ese peer solo si el jugador tiene caja (mismo RPC, canal 0
  confiable, después del spawn). `seat_tending.gd` `_holder_of()`: respaldo por `tender_peer_id` solo con `is_held` y
  `lap_mount_path`. Sin RPC nuevo: `PROTOCOL_VERSION` igual. `test_late_join_seating` (fase "late carry") y etapa nueva
  en `net_pair.gd`. `auditor-red`: sin BUG ni riesgo alto; quedan riesgos bajos (respaldo con el tender que ya lleva otra
  caja, reenvío desde un jugador ya en `queue_free`, el test no mira el orden spawn → RPC, trío con un tercero tarde).
  Aviso `docs/avisos/2026-10-01-n908-caja-en-mano-al-entrar-tarde.md`.

### N-909 · El plan de animales de carga es siempre el mismo — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `nacho/N-909-cargo-animal-seed`**
Origen: mantenimiento 2026-10-01. `cargo_animals.gd:493` (y 250, 379, 417; `_world_seed()` en 522) usa
`NetworkManager.world_seed` tal cual: jugando solo vale 0, así que sale el mismo animal, en el mismo tramo, con la
misma caja en todas las partidas; en sala se repite cada partida (no mezcla `world_completed_runs`). Solo host, no
toca `PROTOCOL_VERSION`. Hecho cuando `test_cargo_animals.gd` prueba que con seed 0 dos corridas dan planes
distintos y que con seed fijo `completed_runs` 0 vs 1 dan planes distintos.
- [x] ~~**N-909.1** En `_on_run_started` del host: `_run_seed = hash([world_seed, world_completed_runs])` si
  `world_seed != 0`, si no `randi()` de un RNG con `randomize()`; usarlo en `_next_leg`, `_pick`, `_snatch` y
  `_kick_box`. Con `constructor-mundo`; tests `cargo_animals`.~~
- [x] ~~**N-909.2** Tests de las dos propiedades del "Hecho cuando". Con `escritor-tests`; tests `cargo_animals`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-909-cargo-animal-seed`, `512da58`)** — `CargoAnimals._roll_run_seed()` en
  `_on_run_started` (y perezoso en `_run_seed()` si se pide un tramo antes): en sala `hash([world_seed,
  world_completed_runs])`, solo una tirada nueva con `randomize()`. Lo usan `_next_leg`, `_pick`, `_snatch` y
  `_kick_box`. `test_cargo_animals` (`_test_run_seed`, 40 tramos): solo, dos corridas distintas; en sala, mismo
  seed y corridas → mismos tramos, otra cantidad de corridas → otros.

### N-910 · `cargo_animal_ended` y `cargo_animal_alert` en el mismo frame confunden al cliente — C · `Opus 5.5 · medium` · Aviso: no · **[x] rama `nacho/N-910-cargo-animal-same-frame`**
Origen: mantenimiento 2026-10-01. `cargo_animal_view.gd:102-110` (y 303, 308), solo cliente. El cooldown es 3.5 s y la
salida del perro 3.0 s (margen 0.5 s); si llegan juntos `ended` y el `alert` siguiente: (a) mismo animal/caja: entra
a la rama "repetición para recién llegado" con estado LEAVE y no muestra el ataque nuevo; (b) otro perro: `_clear()`
hace `queue_free` del "Dog" viejo y en el mismo frame se agrega otro "Dog", Godot lo renombra, la ruta de
`DistractPoint` no coincide con la del host y el cliente no puede tirarle el palo. Hecho cuando un test simula
`ended` + `alert` en el mismo frame en vista cliente y ve el ataque nuevo con la ruta del `DistractPoint` correcta.
- [x] ~~**N-910.1** Exigir `state != State.LEAVE` en la rama de repetición y hacer `remove_child` (o free) del perro
  viejo antes del `add_child`. Con `constructor-mundo`; tests `cargo_animals`.~~
- [x] ~~**N-910.2** Test del mismo frame (casos a y b). Con `escritor-tests`; tests `cargo_animals`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-910-cargo-animal-same-frame`, `44be81e`)** — la rama de repetición de `_on_alert` saltea `LEAVE`, y un alerta nueva llama `_clear(true)`, que saca del árbol (`remove_child`) las piezas viejas antes del `queue_free` (desde `_exit_tree` sigue sin sacarlas). Test `_test_same_frame` en `test_cargo_animals`: (a) mismo perro y caja → animal nuevo en WARN; (b) otra caja → el perro nuevo se llama `Dog` y `Dog/DistractPoint` es su punto del palo.

### N-911 · Origen y licencia de `mus_ingame_loop.ogg`: reemplazarla — C · `Opus 5.5 · low` · Aviso: no · necesita PC
Origen: mantenimiento 2026-10-01. `do-not-drop/assets/audio/music/mus_ingame_loop.ogg` (la música de cada partida) no
está en `assets/audio/music/LICENCIA.md`; entró con la importación inicial del repo (cc12c0e, 2026-09-25), no sale de
`tools/audio/compose_music.py`; quizá derive de `art/audio/music1.m4a` (sin referencias ni procedencia). Ya lo marcó
la auditoría 2026-09-29 §5.10 sin tarea. Bloquea la declaración de IA y las licencias de Steam. Opciones: (a) el
usuario documenta origen y licencia en `LICENCIA.md` y en `art/ai-registro.md` si es IA; (b) reemplazarla por una pista
compuesta con `compose_music.py` (sesión de arte en la PC) y borrar `music1.m4a`. Recomendación: (b) si el origen no
es 100 % propio. Hecho cuando la pista figura en `LICENCIA.md` con origen y licencia (o fue reemplazada y
`music1.m4a` borrado).
- [x] **N-911.1** Decidió el usuario (2026-10-04, issue #170): **(b)**, reemplazarla por una pista de `compose_music.py`.
- [ ] **N-911.2** Componer la pista nueva con `tools/audio/compose_music.py` (sesión de arte en la PC), cargarla en
  `LICENCIA.md` y borrar `art/audio/music1.m4a`. Con `disenador-audio`.
Nota lanzamiento 2026-10: la página de Steam y su declaración de IA no pueden cerrarse hasta resolver esto
(`docs/marketing/estado-steam.md` §1). La frase de "música sin IA" del borrador solo vale con la opción (b).

### N-912 · Botón "Invitar amigos" y presencia enriquecida de Steam — A · `Opus 5.5 · xhigh` · Aviso: sí (`net_session.gd`, `network_manager.gd`, `main_menu.gd`; zona compartida) · ⏸ M5
Origen: lanzamiento 2026-10. El lobby de amigos y aceptar invitaciones existen (`modules/net_session/net_session.gd:380`,
`:437`), pero ni `activateGameOverlayInviteDialog` ni `setRichPresence` aparecen en `scripts/` ni `modules/`: el anfitrión
solo puede invitar desde la lista de amigos de Steam y los amigos no ven qué hace el grupo. Hecho cuando un test del
módulo `net_session` (con el singleton de Steam simulado) comprueba que invitar llama al diálogo con el lobby actual y que
la presencia cambia entre menú, depósito y ruta ("Repartiendo · 3/8"), y que sin Steam (LAN) ambos son no-op. Si toca RPC o
replicación, `PROTOCOL_VERSION` según `docs/convenciones-godot.md` §6.
- [ ] **N-912.1** Método `invite_friends()` en `net_session.gd` (sin nombres del juego) y botón en el depósito y el menú
  de pausa del anfitrión. Con `constructor-red` y después `auditor-red`; tests `net_session`.
- [ ] **N-912.2** `set_presence(clave, valor)` en el módulo y adaptador en `scripts/` que lo llama al cambiar de estado y
  de cantidad de jugadores. Textos por `tr()`. Con `constructor-red`; tests `net_session`.
- [ ] **N-912.3** Prueba real con AppID propio entre dos PCs: se suma al paso manual de N-215 (después de N-901).

### N-913 · Mando y Steam Deck: voz en el mando y teclado en pantalla — B · `Opus 5.5 · high` · Aviso: sí (`project.godot`, `cosmetics_panel.gd`, `main_menu.gd`) · ⏸ M5
Origen: lanzamiento 2026-10. `voice_talk` no tiene evento de mando (`do-not-drop/project.godot:166`) y pulsar-para-hablar
es el valor por defecto (`scripts/core/proximity_voice.gd:22-23`); el apodo (`scripts/ui/cosmetics_panel.gd:39`) y la IP
(`scripts/ui/main_menu.gd:102`) no se pueden escribir sin teclado: no se llama a `showFloatingGamepadTextInput`. Hecho
cuando un test de entrada ve `voice_talk` con evento de mando, otro verifica que los dos campos piden el teclado de
Steam si está disponible (no-op sin Steam), y el listado de acciones sin mando queda solo en las de desarrollo.
- [ ] **N-913.1** Asignar un botón de mando a `voice_talk` sin pisar otro, y que la ayuda en pantalla (`HUD_PAD_*`) lo
  muestre. Con `constructor-ui`; tests `input`, `hud_prompts`.
- [ ] **N-913.2** Llamar al teclado en pantalla de Steam al enfocar el apodo y la IP con mando. Con `constructor-ui`;
  tests `cosmetics`, `main_menu`.
- [ ] **N-913.3** Prueba en un Steam Deck (manual) y rendimiento a 1280×800: lo anota el usuario.

### N-914 · Guardado en la nube: rutas de `user://` para Steam Auto-Cloud — B · `Opus 5.5 · xhigh` · Aviso: no · ⏸ M5
Origen: lanzamiento 2026-10. Todo el progreso vive en `user://` (`unlock_manager.gd:9`, `crew_progression.gd:6`,
`run_manager.gd:119`, `game_settings.gd:13`, `depot_campaign_board.gd:21-22`) y no hay `use_custom_user_dir`. Auto-Cloud no
necesita código pero sí la lista exacta de rutas por sistema. Hecho cuando `docs/marketing/steam-cloud.md` lista cada
archivo con su ruta en Windows y Linux, marca qué sube y qué no (`user://telemetry/` y `user://trailer_still.png`
excluidos; decisión sobre `depot_photos/`), y un test recorre el código buscando `user://` y falla si aparece una ruta
que no está ni en la lista ni en la de exclusiones.
- [ ] **N-914.1** Inventario de rutas y documento. Con `documentador`; tests `cloud_paths`.
- [ ] **N-914.2** Test del inventario. Con `escritor-tests` (y `constructor-red` si hay que mover algo).
- [ ] **N-914.3** Cargar las reglas en Steamworks: lo hace el usuario, después de N-901.

### N-915 · Capturas y plano de tráiler con lo nuevo (8 jugadores, barro, animales, depósito) — A · `Opus 5.5 · high` · Aviso: no · ⏸ M5 · necesita PC
Origen: lanzamiento 2026-10. `art/marketing/capturas/` (10 PNG) muestra las caras anteriores a N-506 y nada de la
cuadrilla de 8, el barro (N-108), los animales (N-109) ni el depósito rediseñado (N-319); el guion del tráiler
(`docs/marketing/trailer.md`) no tiene planos de barro ni de depósito con 8 jugadores y no hay video grabado. Detalle
de las 7 escenas: `docs/marketing/estado-steam.md` §3.2. Necesita PC (ventana y GPU; la toma la sesión de arte). Se hace
cuando N-319 esté cerrada. Hecho cuando hay 7 capturas 1920×1080 nuevas en `art/marketing/capturas/` con las caras
actuales, sin HUD salvo la 1, revisadas por `revisor-visual` (de noche el camión se lee), y el guion suma los dos planos.
- [ ] **N-915.1** Ampliar `tests/render_store_shots.gd` / `trailer_shot.tscn` con las 7 escenas del doc. Con
  `revisor-visual`; tests `trailer_shots`.
- [ ] **N-915.2** Sacar y revisar las capturas. Con `revisor-visual`.
- [ ] **N-915.3** Sumar los planos de barro y de depósito con 8 al guion y grabar el tráiler. Con `revisor-visual`.
  Las cápsulas son S-903 (corregida).

### N-916 · Fecha, Steam Direct, precio, idiomas y promesa de la página — A (decisión) · `Opus 5.5 · low` · Aviso: no
Origen: lanzamiento 2026-10 (`docs/marketing/estado-steam.md` §2 y §6). Cinco decisiones juntas porque se condicionan:
(1) fecha: Early Access 2027-01-22 sin Next Fest (A) o correrlo a 2027-03-12 para entrar al Next Fest 22-feb a 1-mar,
inscripción hasta 2027-01-10 (B; recomendado, verificar que Next Fest exige juego sin lanzar); (2) pagar Steam Direct
(USD 100, 30 días de espera) antes del 2026-10-16; (3) precio, objetivo $8-15, propuesta ≈9,99; (4) idiomas: no sumar
ninguno hasta cerrar N-211 fase 7b; (5) qué promete la página: sin voz hasta N-212.2 y "hasta 8 jugadores" solo tras
probarlo con gente real por Steam. Hecho cuando las cinco quedan escritas en `docs/decisiones/` y las fechas de
`docs/plan-desarrollo.md` coinciden.
- [x] **N-916.1** Decidió el usuario (2026-10-04, issue #174): las cinco recomendaciones. Escritas en
  `docs/decisiones/2026-10-04-lanzamiento-steam.md`.
- [x] **N-916.2** Aplicar: fechas en el plan (`docs/plan-desarrollo.md`, Early Access 2027-03-12 y Next Fest de
  febrero 2027). S-901 y S-904 toman el precio (≈ USD 9,99) del archivo de decisión cuando se retomen.
- [ ] **N-916.3** ⏸ Pagar Steam Direct (USD 100) antes del 2026-10-16: lo hace el usuario con su cuenta de Steamworks
  (es plata real). Después: N-901 (AppID propio).

## Orden de ataque (hitos)

| Hito | Objetivo | Tareas |
|---|---|---|
| **M1 — Cerrar lo que está a medias** | Nada del mundo que se comporte distinto en cada jugador ni que quede sin usar. | N-201, N-202, N-203, N-101, N-102, N-701, N-702 |
| **M2 — Ritmo y guía del jugador** | Una entrega de 2-5 minutos donde siempre se sabe adónde ir. | N-103, N-104, N-105, N-501, N-502, N-503 |
| **M3 — Base técnica** | Rendimiento medido en ventana real, red de 3+ jugadores probada, Endless con curvas. | N-204, N-205, N-206, N-207, N-208, N-209, N-801, N-802 |
| **M4 — Vida y variedad** | IA ambiental, audio del mundo, narrativa ambiental, detalles del camión. | N-106, N-107, N-301 a N-308, N-401 a N-405, N-601 a N-604 |
| **M5 — Preparación de lanzamiento** ⏸ | Builds, tienda, tráiler. N-901 pospuesta a la iteración de lanzamiento. | N-210, N-703, N-901 a N-906, N-911, N-916, N-912 ⏸, N-913 ⏸, N-914 ⏸, N-915 ⏸ (+ S-903 y S-907). Orden: N-916.3 (pago, usuario), N-911, N-901, N-912, N-914, N-913, N-915 |
| **M6 — Mecánicas de la competencia** | Lo que Backseat Drivers y RV There Yet? hacen bien, adaptado a la carga. | N-704, N-505, N-213, N-214, N-212, N-109, N-406, N-108, N-110, N-311, N-113, N-111, N-112, N-114 (N-907 ⏸) |
| **M7 — Pedidos del usuario** | Correr, una meta que sea un lugar, un segundo cuerpo y el diario del día siguiente. | N-115, N-116, N-312, N-606 |
| **M8 — Auditoría 2026-09-29** | Lo que la auditoría encontró roto o flojo: cada pasajero con su propia acción, puntaje y red honestos, textos traducibles, menos trabajo por frame, repo liviano. Va **antes** que lo que quede de M6/M7. | N-919, N-705, N-117, N-805, N-118, N-119, N-222, N-313 ⏸, N-314, N-223, N-315, N-224, N-225, N-316, N-317, N-318, N-319, N-706, N-226, N-227, N-228, N-229, N-238, N-240, N-239, N-321, N-908, N-909, N-910, N-320, N-922, N-920, N-921 |
| **M9 — Módulos portables** | Lo genérico del juego en carpetas que se copian a otro proyecto y funcionan, garantizado por CI (`docs/modulos.md`). Pedido del usuario 2026-09-30. Va en paralelo a M8: cada fase es un PR chico. | N-230, N-231, N-232, N-233, N-234 |
| **S — Heredadas de Slatex** | Todo lo que era de Slatex (jugador, paquetes, UI, progresión), con sus hitos S-M1 a S-M5. Va **después de M8**. | Ver "Heredadas de Slatex" más abajo |

Dentro de un hito, el orden de la tabla es el recomendado.

---

## M9 — Módulos portables

Pedido del usuario (2026-09-30): que las piezas genéricas del juego puedan llevarse a otro proyecto con
la seguridad de que funcionan. Análisis, reglas, catálogo y plan de fases en `docs/modulos.md`. Todo es
zona compartida (`modules/`), y las fases 3 y 4 tocan archivos de Slatex: aviso en cada PR.
**Las tareas abiertas las está haciendo Nacho en su sesión local (2026-09-30): no las toma la rutina de
construcción hasta que este párrafo desaparezca.**

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## M8 — Auditoría 2026-09-29

Pedido del usuario: arreglar todo lo que marcó la auditoría (`docs/auditorias/2026-09-29.md`), salvo
revisión humana de PRs ni agente revisor (no se quieren: la puerta son los checks obligatorios). Varias tocan
archivos de Slatex: aviso en `colaboracion-equipo.md` en el mismo PR, como siempre.

### N-313 · El ragdoll con el cuerpo real — B · `Opus 5.5 · high` · Aviso: sí (`player_ragdoll.gd`) · ⏸ personajes en pausa (S-311)
Origen de la pausa: auditoría integral 2026-09-30, A-102 (mismo trabajo que S-311.48; `constructor-jugador.md:43`: personajes y ragdoll no se tocan).
Hoy esconde al personaje y dibuja seis cápsulas turquesa (`player_ragdoll.gd:20,56-62`). Hecho cuando
el modelo real del jugador (con su color) es el que vuela y cae; lo mínimo, el modelo entero pegado al
torso físico; lo ideal, `PhysicalBoneSimulator3D`. Captura con `revisor-visual`.

### N-224 · Menos despacho dinámico — C · `Opus 5.5 · high` · Aviso: sí (varios)
251 `.call(&"…")`, 233 `.get(&"…")` y 112 rutas `/root/`: un renombre rompe en runtime. Por archivo,
empezando por `crew_progression.gd` y `route_event_manager.gd`: referencias tipadas (`class_name`) o
dependencias por `setup()`. Desde 2026-10-04, **hasta 6 archivos por PR** (los siguientes por conteo): de a uno se
gastaba una corrida entera y 9 trabajos de CI por archivo. El conteo baja en cada una.
- [x] **N-224.1** `crew_progression.gd` (2026-09-30, rama `nacho/N-224-crew-progression-typed`): `NetworkManager`,
  `RunManager` y `RouteEventManager` por constantes tipadas (`NETWORK_MANAGER`…, `get_node_or_null(...) as`), así que un
  renombre falla al compilar. En el archivo: `.call` 15 → 1, `.get(&` 4 → 0, `/root/` 14 → 6; en `scripts/`: `.call`
  313 → 299, `.get(&` 284 → 280, `/root/` 122 → 114. Queda EventBus por nombre (los tests lo cambian por un `Node`).
  Trinquete: `test_dynamic_dispatch_budget.gd` (presupuesto por archivo y que cada constante sea el script del autoload).
- [x] **N-224.2** `route_event_manager.gd` (2026-09-30, rama `nacho/N-224-route-event-manager-typed`): `CrewProgression`,
  `NetworkManager` y `RunManager` por constantes tipadas (un solo `_network()`), trampas como `TrapDefinition` y la carga
  como `DeliveryPackage`. En el archivo: `.call` 4 → 2 (los dos relays de EventBus), `/root/` 5 → 4, `.set(&` 1 → 0,
  `.get("…")` sobre nodos y recursos 10 → 2 (`role`/`occupant` de las áreas de asiento, sin script). El preload cruzado
  con `crew_progression.gd` compila. `test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` y chequea los handles
  de los dos autoloads (`HANDLES`).
- [x] **N-224.3** `depot.gd` (2026-10-01, rama `nacho/N-224-typed-dispatch`, `98ac259`): el que más tenía (65).
  `NetworkManager`, `CrewProgression`, `UnlockManager` y `RunManager` por constantes tipadas con un accesor cada uno
  (`_network()`, `_crew()`…, se va `_autoload(name)`), señales conectadas por la señal, paquetes como `DeliveryPackage`,
  trampas como `TrapDefinition`, contenidos como `PackageContent`, gancho y averías como `RescueHook`/`VehicleFaults`.
  En el archivo: `.call` 31 → 1 (relay de EventBus), `.get(&` 33 → 1 (`seat_node_path`: los tests meten jugadores
  falsos en el grupo `player`), `/root/` 1 → 5 (un accesor por autoload). En `scripts/`: `.call` 296 → 266,
  `.get(&` 287 → 255, `/root/` 128 → 132. `test_dynamic_dispatch_budget.gd` suma `depot.gd` a `BUDGETS` y comprueba
  sus handles (`SCRIPT_HANDLES`).
- [ ] **N-224.4** El resto por conteo (`grep -c` de los patrones de `PATTERNS` en `scripts/`), hasta 6 archivos por PR. Sumar
  cada archivo a `BUDGETS` del test. Siguientes: `package_rescue.gd` (31), `player_cargo_care.gd` (24),
  `trailer_shot.gd` (24), `mud_segment.gd` (22).
  - [x] `trailer_shot.gd` (2026-10-01, rama `nacho/N-224-trailer-shot-typed`): la herramienta del tráiler y de las
    capturas de tienda. El nivel, la ruta, el camión y el anclaje de carga por `preload` (`level_base.gd`, `route.gd`,
    `vehicle.gd`, `package_mount_point.gd`: sin `class_name`), `NetworkManager` por la constante `NETWORK_MANAGER`, y
    la cámara (`TrailerCamera`), el tramo (`RouteSegment`, `RailCrossingSegment`), el cruce de ciervos
    (`WildlifeCrossing`), la casa (`DeliveryHouse`), el jugador (`Player`) y las cajas (`DeliveryPackage`) por clase.
    En el archivo: 24 → 1 uso (`.call` 12 → 0, `.get(&` 11 → 0, `/root/` 1 → 1; también `.set(&` 6 → 0); en
    `scripts/`: `.call` 272 → 260, `.get(&` 273 → 262. `test_dynamic_dispatch_budget.gd` suma el archivo y su handle.
    `test_trailer_shots.gd` y `render_store_shots.gd` cargan `trailer_shot.gd` con `load()` en vez de `preload`: el
    nivel, el camión y el jugador nombran autoloads que un `--script` todavía no tiene al compilar. Sin aviso
    (`scripts/tools/` y `tests/` no son de nadie). Siguientes: `mud_segment.gd` (22), `player.gd` (21),
    `package_feedback.gd` (21).
  - [x] `package.gd` (2026-10-01, rama `nacho/N-224-package-typed`): trampas como `TrapDefinition`/`ITrapBehavior`
    (sin `has_method`), el que agarra como `Player`, red como `NetSession`; las búsquedas de autoloads en
    `package_autoloads.gd` (nuevo, `PackageAutoloads`), porque el archivo estaba en 1000 líneas (queda en 995).
    `RunManager`, `CrewProgression` y `RouteEventManager` siguen por nombre: precargarlos desde el paquete rompe la
    compilación (ciclo con `crew_progression.gd`/`route_event_manager.gd` y autoloads aún no cargados en los tests).
    En el archivo: `.call` 21 → 9 (5 del camión, que los tests reemplazan por falsos; 3 de autoloads; relay de
    EventBus), `.get(&` 4 → 3, `/root/` 10 → 1. En `scripts/`: `.call` 290 → 278, `.get(&` 284 → 283, `/root/`
    132 → 127. `test_dynamic_dispatch_budget.gd` suma los dos archivos y exige que `NetworkManager` sea `NetSession`.
    Aviso `docs/avisos/2026-10-01-n224-package-tipado.md`.
  - [x] `package_rescue.gd` (2026-10-01, rama `nacho/N-224-package-rescue-typed`): la trampa como `ITrapBehavior`
    (11 métodos directos), `params` de `TrapDefinition`, la bomba desactivada como `ExplosiveTrapBehavior`, el
    que sostiene como `Player`, `RunManager` y la red (`NetSession`) por `PackageAutoloads`. Quedan por
    nombre el camión (falsos en el grupo `vehicle`), los métodos de `RunManager` (ciclo), `world_seed` (no está en
    `NetSession`), el `seat_node_path` de `view_basis_of` (falsos en `player`) el anclaje de regazo (sin `class_name`) y el `mode` de la radio
    (`truck_radio.gd` nombra autoloads sin prefijo: tiparla los mete en el grafo de compilación del paquete).
    En el archivo: 30 → 13 usos (`.call` 19 → 7, `.get(&` 8 → 6, `/root/` 3 → 0); en `scripts/`: 705 → 688.
    `test_dynamic_dispatch_budget.gd` suma el archivo. Aviso `docs/avisos/2026-10-01-n224-package-rescue-tipado.md`.
    Siguientes: `player_cargo_care.gd` (24), `trailer_shot.gd` (24), `mud_segment.gd` (22).
  - [x] `player_cargo_care.gd` (2026-10-01, rama `nacho/N-224-cargo-care-typed`): el jugador como `Player`, la caja
    como `DeliveryPackage`, `GameSettings` por la constante `GAME_SETTINGS` (preload; el test comprueba que sea el
    script del autoload), el perfil como `UnlockProfile` y `RunManager` por `PackageAutoloads`. Quedan por nombre
    solo los de `RunManager` (`care_supply_count`, `is_running`, `cargo`, `results`: ciclo de compilación). En el
    archivo: 28 → 7 usos (`.call` 5 → 1, `.get(&` 17 → 4, `/root/` 6 → 2); en `scripts/`: `.call` 276 → 272,
    `.get(&` 286 → 273, `/root/` 124 → 120. `test_dynamic_dispatch_budget.gd` suma el archivo y su handle.
    Aviso `docs/avisos/2026-10-01-n224-cargo-care-tipado.md`.
    Siguientes: `trailer_shot.gd` (24), `mud_segment.gd` (22).
  - [x] `seat_tending.gd` (2026-10-01, rama `nacho/N-224-seat-tending-typed`): el que más tenía tras N-228 (32 usos
    por nombre). La caja como `DeliveryPackage`, el jugador como `Player` y el asiento como `CargoSeatPoint`
    (`class_name` nuevo en `seat_point.gd`; el `SeatPoint` del módulo no tiene `seated_peer`/`owns_mount`/
    `looks_at_mount`); `has_method(&"tend_package")` pasa a `is Player`. Quedan por nombre los anclajes (sin
    `class_name`) y el RPC `tend_package`. En el archivo: `.call` 14 → 0, `.get(&` 18 → 0; en `scripts/`: `.call`
    276 → 261, `.get(&` 286 → 267. `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0. Aviso
    `docs/avisos/2026-10-01-n224-seat-tending-tipado.md`. Siguientes: `trailer_shot.gd` (24), `mud_segment.gd` (22),
    `player.gd` (21), `package_feedback.gd` (21).
  - [x] `mud_segment.gd` (2026-10-01, rama `nacho/N-224-mud-segment-typed`): el punto de empuje, la grúa y el
    registro de historias por `preload` (`mud_spot.gd`, `mud_crane.gd`, `mud_run_log.gd`), la red como `NetSession` y el
    `freeze` del camión como propiedad de `VehicleBody3D`. Quedan por nombre los jugadores del grupo `player` (los
    tests meten `FakePlayer`), `carries` del camión (`vehicle.gd` sin `class_name`), el relay de EventBus y
    `CrewProgression`/`RunManager`: precargar sus scripts desde acá rompe los dos autoloads bajo `--script` (`route.gd`
    arrastra este archivo y esos scripts nombran `EventBus` antes de que existan; lo vio `test_mud_segment`). En el
    archivo: `.call` 10 → 5, `.get(&` 8 → 7, `/root/` 6 → 4, `.set(&` 3 → 0. `test_dynamic_dispatch_budget.gd` suma el
    archivo. Sin aviso (`route/` y `tests/`). Siguientes: `player.gd` (21), `package_feedback.gd` (21),
    `player_interaction.gd` (18), `level_base.gd` (18).
  - [x] `rail_crossing_segment.gd` (2026-10-01, rama `nacho/N-224-rail-crossing-typed`): el paso a nivel. La sesión
    por la constante `NETWORK_MANAGER` (preload de `network_manager.gd`, accesor `_network()`: `world_seed`,
    `is_online`, `is_host` directos; `world_seed` no está en `NetSession`). En el archivo: 6 → 1 uso (`.call` 2 → 0,
    `.get(&` 1 → 0, `/root/` 3 → 1). `test_dynamic_dispatch_budget.gd` suma el archivo y su handle. Sin aviso
    (`route/` y `tests/`).
  - [x] `player_interaction.gd` (2026-10-01, rama `nacho/N-224-player-interaction-typed`): lo apuntado como
    `Interactable` (`can_interact`/`interact` directos; la sonda junta solo `Interactable`), el `aim_bonus` del perro
    de `DogDistractPoint`, la red como `NetSession` (`_network()`) y la vista del contenido por preload
    (`PACKAGE_CONTENTS_VIEW`). Quedan por nombre `highlight` (sin base común), `request_ping` de EventBus y
    `request_use_card` de CrewProgression (ciclo). En el archivo: 21 → 6 usos (`.call` 13 → 3, `.get(&` 1 → 0,
    `/root/` 7 → 3). `test_dynamic_dispatch_budget.gd` suma el archivo. Aviso
    `docs/avisos/2026-10-01-n224-player-interaction-tipado.md`. Siguientes: `player.gd` (21), `level_base.gd` (19),
    `run_manager.gd` (18), `cargo_animals.gd` (16).
  - [x] `level_base.gd` (2026-10-01, rama `nacho/N-224-level-base-typed`): la ruta como `RouteScript` (preload de
    `route.gd`, sin `class_name`), las casas como `DeliveryHouse`, la meta como `RouteGoalLot`, `driver_peer_id` por
    `VehicleScript` (preload de `vehicle.gd`) y las señales `house_resolved` / `wrong_package_offered` conectadas por
    la señal (se fue el `has_signal`). En el archivo: 18 → 0 usos (`.call` 4 → 0, `.get(&` 14 → 0). La baseline del
    lint bajó 1. `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0. Aviso
    `docs/avisos/2026-10-01-n224-level-base-tipado.md`. `run_manager.gd` ya no tiene usos por nombre tras N-225.5.
    Siguientes: `player.gd` (21), `cargo_animals.gd` (16).
  - [x] `truck_radio_view.gd` (2026-10-01, rama `nacho/N-224-truck-radio-view-typed`): el dial y el programa de la
    radio. La radio como `TruckRadio` (`mode`, `mode_key()` estático, `mode_changed`/`news_announced` conectadas por la
    señal) y los sonidos por el `preload` inferido de `synth_audio_radio.gd` (antes tipado `Script`, que obligaba a
    `.call`: `warm`, los dos loops, el clic y la cortina). En el archivo: `.call` 6 → 0, `.get(&` 1 → 0.
    `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0. Sin aviso (`presentation/` libre y `tests/`).
  - [x] `windshield_rain.gd` (2026-10-01, rama `nacho/N-224-windshield-rain-typed`): la lluvia y el barro del
    parabrisas. Solo la sesión como `NetSession` (`local_id`). El resto queda por nombre con razón: `driver_peer_id`
    y `presentation_engine_running` del camión y `viewer_inside()` de su presentación, porque `vehicle.gd` crea este
    nodo por `reference_truck.gd` y `vehicle_presentation.gd` llega a `vehicle.gd` por `cargo_clutter.gd` (precargar
    cualquiera de los dos es un ciclo). En el archivo: `.call` 2 → 1, `.get(&` 2 → 2, `/root/` 2 → 2.
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`presentation/` libre y `tests/`).
  - [x] `cargo_animals.gd` (2026-10-01, rama `nacho/N-224-cargo-animals-typed`): el camión por `preload` de
    `vehicle.gd` (`VehicleScript`, accesor `_truck()`: `carries`, `point_velocity`, `rear_cargo_open`), la red por la
    constante `NETWORK_MANAGER` (`world_seed`, `is_host`, la señal `peer_level_ready` sin `has_signal`), el contenido
    como `PackageContent` y el arranque de la gaviota escribe `_has_previous_velocity` directo. Quedan por nombre el
    relay de EventBus y `RunManager.is_running` (ciclo de compilación). En el archivo: 17 → 5 usos (`.call` 6 → 1,
    `.get(&` 4 → 1, `/root/` 6 → 3, `.set(&` 1 → 0). `test_dynamic_dispatch_budget.gd` suma el archivo y su handle.
    Sin aviso (`route/` y `tests/`). Siguientes: `package_feedback.gd` (14), `depot_panel.gd` (13), `player.gd` (13),
    `package_contents_view.gd` (13), `seat_point.gd` (13).
  - [x] `low_visibility_event.gd` (2026-10-01, rama `nacho/N-224-low-visibility-typed`): el barro en el parabrisas. El
    nivel como `LevelCommon`, el camión por `preload` de `vehicle.gd` (`driver_peer_id`; la velocidad sin el
    `is RigidBody3D`) y la ruta por `preload` de `route.gd` (`houses`, `stop_road_distance`, `road_distance`; se van
    los `has_method`). Queda por nombre el `route` del nivel (solo `level_base.gd` lo tiene y precargar los niveles
    vuelve por `level_common.gd`, que precarga este archivo). En el archivo: `.call` 2 → 0, `.get(&` 4 → 1.
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`route/` y `tests/`).
  - [x] `package_feedback.gd` + `package_trap_visuals.gd` (2026-10-01, rama `nacho/N-224-package-feedback-typed`): el
    padre como `DeliveryPackage` (`package_id`, `trap_definition` como `TrapDefinition`, `content_definition()` como
    `PackageContent`, `_is_run_active()`), `GameSettings` por la constante `GAME_SETTINGS` (accesor `_settings()`) y
    los comportamientos de trampa como `HostileTrapBehavior`/`ExplosiveTrapBehavior`/`LiquidTrapBehavior`. Queda por
    nombre solo `EventBus`. En los dos archivos: `.call` 11 → 0, `.get(&` 6 → 0, `/root/` 4 → 2; en `scripts/`:
    `.call` 214 → 203, `.get(&` 216 → 210, `/root/` 111 → 109. `test_dynamic_dispatch_budget.gd` suma los dos
    archivos y el handle. Aviso `docs/avisos/2026-10-01-n224-package-feedback-tipado.md`. Siguientes:
    `depot_panel.gd` (13), `player.gd` (13), `package_contents_view.gd` (13), `seat_point.gd` (13).
  - [x] `vehicle_faults.gd` (2026-10-01, rama `nacho/N-224-vehicle-faults-typed`): los efectos y los puntos de
    reparación como `EFFECTS`/`REPAIR_SPOT` (preload inferido, sirve de tipo: `show_fault`, `show_phone_mirror`,
    `driver_mirror_parts`, `fault_id`, `faults` directos), el que sostiene el celular como `Player` (`carried_package`,
    `reach_origin`; el nodo plano de los tests no carga nada y usa su posición) y los `Dictionary.get(&"mirror")`
    por `has`. Quedan por nombre los del camión (`driver_peer_id`, `is_door_open`, `set_rear_cargo_open`):
    `test_vehicle_faults` mete un `FakeVan`. En el archivo: `.call` 6 → 2, `.get(&` 5 → 1, `.set(&` 3 → 0.
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`vehicle/` y `tests/`). Siguientes:
    `depot_panel.gd` (13), `cargo_animal_view.gd` (11), `seat_point.gd` (13).
  - [x] `depot_panel.gd` (2026-10-01, rama `nacho/N-224-depot-panel-typed`): las compras a un `Depot` tipado
    (`_depot_node() -> Depot`: `buy_supply`, `buy_supply_discounted`, `team_money`, `supplies`; el del nivel por
    `LevelCommon.depot`), las cajas como `DeliveryPackage` y las señales de `EventBus` y `UnlockManager` conectadas
    directo. Quedan por nombre `orders` y `boss_notes()` del `depot` que pasa la estación (`test_depot_panel` usa un
    stand-in que no es `Depot`). En el archivo: 12 → 2 usos (`.call` 5 → 1, `.get(&` 5 → 1, `/root/` 2 → 0).
    `test_dynamic_dispatch_budget.gd` suma el archivo. Aviso `docs/avisos/2026-10-01-n224-depot-panel-tipado.md`.
    Siguientes: `cargo_animal_view.gd` (13), `wildlife_crossing.gd` (13), `seat_point.gd` (13),
    `package_contents_view.gd` (13); después `hud_pause.gd` (`level.get(&"depot")`, tipar a `LevelCommon`).
  - [x] `order_balancer.gd` (2026-10-01, rama `nacho/N-224-order-balancer-typed`): el sorteo de pedidos del depósito.
    Las trampas como `TrapDefinition` (`id`, `difficulty`; arrays internos `Array[TrapDefinition]`) y las cajas como
    `DeliveryPackage` (`trap_definition`); lo que no es una trampa (un hueco nulo) se salta como antes. En el archivo:
    `.get(&` 8 → 0, nada por nombre; en `scripts/`: `.get(&` 175 → 167. `test_dynamic_dispatch_budget.gd` suma el
    archivo con todo en 0. Aviso `docs/avisos/2026-10-01-n224-order-balancer-tipado.md`.
  - [x] `wildlife_crossing.gd` (2026-10-01, rama `nacho/N-224-wildlife-crossing-typed`): el ciervo con el tipo de
    `wildlife_animal.gd` (`ANIMAL_SCRIPT` por preload inferido, sin `class_name`: `steered`, `run`,
    `freeze_in_headlights`, `tumble` directos). Quedan por nombre `team_money`/`spend` de `CrewProgression` (ciclo de
    compilación, como en `mud_segment.gd`) y el relay de EventBus. En el archivo: `.call` 7 → 2, `.get(&` 1 → 1,
    `/root/` 3 → 3, `.set(&` 1 → 0. `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`route/` y
    `tests/`). Siguientes: `package_contents_view.gd` (13), `seat_point.gd` (13), `package_pickup_point.gd` (12),
    `cargo_animal_view.gd` (11), `player.gd` (13).
  - [x] `flock_crossing.gd` (2026-10-01, rama `nacho/N-224-flock-crossing-typed`): las ovejas con el tipo de
    `wildlife_animal.gd` (`ANIMAL_SCRIPT` por preload inferido, `sheep: Array[ANIMAL_SCRIPT]`: `run`, `idle`,
    `tumble`, `steered` directos), como el ciervo. Quedan por nombre `team_money`/`spend` de `CrewProgression` (ciclo
    de compilación, como en `wildlife_crossing.gd`). En el archivo: `.call` 3 → 1, `.get(&` 1 → 1, `/root/` 2 → 2,
    `.set(&` 1 → 0. `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`route/` y `tests/`).
  - [x] `play_area.gd` (2026-10-01, rama `nacho/N-224-play-area-typed`): el borde del mapa. El nivel como
    `LevelCommon` (`local_player`, `depot` como `Depot`), el jugador como `Player` (`seat_node_path`), el camino del
    infinito como `SegmentStreamer` (`_nearest_on_path` directo, sin `has_method`) y el terreno de la ruta como
    `TerrainField` (`spans`). Quedan por nombre `_streamer` y `route` del nivel y `terrain` de la ruta
    (`level_endless.gd`, `level_base.gd` y `route.gd` sin `class_name`; precargar los niveles vuelve por
    `level_common.gd`, que precarga este archivo). En el archivo: `.call` 1 → 0, `.get(&` 6 → 3.
    `test_play_area.gd` carga el script con `load()` (tipar a `LevelCommon` nombra autoloads sueltos bajo
    `--script`) y prueba también el borde en el infinito. `test_dynamic_dispatch_budget.gd` suma el archivo. Sin
    aviso (`gameplay/` raíz y `tests/`).
  - [x] `package_contents_view.gd` (2026-10-01, rama `nacho/N-224-contents-view-typed`): la caja como
    `DeliveryPackage` (`package.gd` no carga la vista, sin ciclo; `package_id`, `trap_state`, `contents_spilled`,
    `is_open` y `content_definition()` directos) y el contenido como `PackageContent` (`localized_name`,
    `condition_text`, `pick_note`, `model`, `box_size`). Queda por nombre el `connect` al EventBus (un test puede
    reemplazarlo por un Node). En el archivo: 13 → 1 uso (`.call` 5 → 0, `.get(&` 7 → 0, `/root/` 1 → 1).
    `test_dynamic_dispatch_budget.gd` suma el archivo. Aviso `docs/avisos/2026-10-01-n224-contents-view-tipado.md`.
  - [x] `seat_point.gd` (2026-10-01, rama `nacho/N-224-seat-point-typed`): los asientos de la carga (`CargoSeatPoint`). El
    jugador como `Player` (`_carried_by()`; el stand-in de `LateJoinSeating` no es `Player` y cuenta como "no carga
    nada"), los anclajes por `preload` de `package_mount_point.gd` (`MountPoint`, `occupied_by` directo) y la caja
    como `DeliveryPackage` (`tender_peer_id`); `has_method(&"tend_package")` pasa a `is Player`. En el archivo:
    `.get(&` 13 → 0, nada por nombre. `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0. Aviso
    `docs/avisos/2026-10-01-n224-seat-point-tipado.md`. Siguientes: `player.gd` (13), `spectator_camera.gd` (12),
    `package_pickup_point.gd` (12), `cargo_animal_view.gd` (11).
  - [x] `phone_camera.gd` (2026-10-01, rama `nacho/N-224-phone-camera-typed`): la foto de entrega. Las casas como
    `DeliveryHouse` (`porch_position`, `house_index`, `delivered`, `outcome`; lo que no es una se salta) y el camión
    por `preload` de `vehicle.gd` (`has_manual_gearbox`, `driver_peer_id`; se va el `has_method`). En el archivo:
    `.call` 1 → 0, `.get(&` 5 → 0, nada por nombre. `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0.
    Sin aviso (`presentation/` libre y `tests/`).
  - [x] `player_seat_pose.gd` (2026-10-01, rama `nacho/N-224-seat-pose-typed`): subir y bajar de los asientos. La
    cámara del asiento como `SeatCamera` (`activate`/`deactivate`), el `InteractionArea` del asiento como `SeatPoint`
    (`release_occupant`) y la sesión como `NetSession` (`is_online`, `is_host`); lo que no es uno se salta, como hacían
    los `has_method`. Queda por nombre el RPC `release_occupant` al host (como todo RPC). En el archivo: `.call` 5 → 0,
    `has_method` 3 → 0, `/root/` 2 → 2. `test_dynamic_dispatch_budget.gd` suma el archivo. Aviso
    `docs/avisos/2026-10-01-n224-seat-pose-tipado.md`. `route_smoke_check.gd` (7) no se puede tipar: es un
    `--script` y nombrar `route.gd`, `DeliveryHouse` o `RouteGoalLot` compila scripts que nombran `NetworkManager`
    antes de que existan los autoloads.
  - [x] `package_pickup_point.gd` (2026-10-01, rama `nacho/N-224-pickup-point-typed`): agarrar y ayudar a cargar una
    caja. La caja como `DeliveryPackage` (`is_held`, `is_loaded`, `trap_definition`, `assist_available`/`assist_prompt`/
    `can_assist`/`set_assistant`/`take_by` directos, sin `has_method`), el feedback como `PackageFeedback` y el jugador
    como `Player` (`carried_package`, `reach_origin()`; un stand-in del grupo `player` tiene las manos libres y alcanza
    desde su posición). Queda por nombre el RPC `assist_package`. En el archivo: `.call` 9 → 0, `.get(&` 3 → 0.
    `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0. Aviso
    `docs/avisos/2026-10-01-n224-pickup-point-tipado.md`. Siguientes: `player.gd` (13), `spectator_camera.gd` (12),
    `cargo_animal_view.gd` (11).
  - [x] `cargo_animal_view.gd` (2026-10-01, rama `nacho/N-224-cargo-animal-view-typed`): lo que se ve de la gaviota,
    el perro y las abejas. El director (el padre) como `CargoAnimals` (`vehicle`, `packages` directos), el camión por
    `preload` de `vehicle.gd` (`VehicleScript`: `carries` directo), la caja como `DeliveryPackage`
    (`get_half_extents()`, `package_id`) y el perro con el tipo de `wildlife_animal.gd` (`_dog`: `run`, `idle`,
    `steered`, `standing_clip`, `ground_speed`). Queda por nombre solo el `connect` al EventBus (un test puede
    reemplazarlo por un Node). En el archivo: 13 → 1 uso (`.call` 5 → 0, `.get(&` 4 → 0, `.set(&` 3 → 0,
    `has_method` 1 → 0, `/root/` 1 → 1). `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`route/` y
    `tests/`). Siguientes: `player.gd` (13), `spectator_camera.gd` (11), `level_common.gd` (11).
  - [x] `player.gd` (2026-10-01, rama `nacho/N-224-player-typed`): la red como `NetSession` (`is_host()` en
    `_exit_tree`), el perfil por `_profile()` tipado con `UNLOCK_MANAGER` (preload de `unlock_manager.gd`, sin
    `class_name`; no rompe los autoloads bajo `--script`: `selected_*`, `cosmetic_is_auto`, `cosmetic_color`,
    `mark_tip_seen` directos), la caja de `pickup_high_weight_for_package` como `DeliveryPackage` y
    `trap_definition.id` directo. Queda por nombre el EventBus (`carry_changed`, `tutorial_tip_requested`: un test
    puede reemplazarlo por un Node). En el archivo: `.call` 5 → 0, `.get(&` 4 → 0, `/root/` 9 → 4; en `scripts/`:
    `.call` 177 → 172, `.get(&` 186 → 185, `/root/` 109 → 106. La baseline del lint bajó 1.
    `test_dynamic_dispatch_budget.gd` suma el archivo y su handle. Aviso `docs/avisos/2026-10-01-n224-player-tipado.md`.
    Siguientes: `spectator_camera.gd` (11), `level_common.gd` (11).
  - [x] `delivery_house.gd` (2026-10-01, rama `nacho/N-224-delivery-house-typed`): la caja que llega al timbre como
    `DeliveryPackage` (`package_id`, `trap_state`, `is_open`, `_publish_care()` y `consume()` directos; se van los
    `has_method` y el `queue_free` de respaldo, que ninguna caja real usaba) y la sesión por la constante
    `NETWORK_MANAGER` (preload de `network_manager.gd`: `world_seed` no está en `NetSession`). Queda por nombre el
    EventBus (dos `connect`: un test puede reemplazarlo por un Node). En el archivo: `.call` 2 → 0, `.get(&` 5 → 0,
    `/root/` 3 → 3; en `scripts/`: `.call` 172 → 170, `.get(&` 185 → 180. `test_dynamic_dispatch_budget.gd` suma el
    archivo y su handle; `test_delivery_houses.gd` toca el timbre con cajas reales (`package.tscn`) en vez de nodos
    con `trap_state` inventado. Sin aviso (`route/` y `tests/`). Siguientes: `spectator_camera.gd` (10), `play_area.gd` (9),
    `dashboard_gps.gd` (9), `vehicle_presentation.gd` (9).
  - [x] `player_sprint.gd` (2026-10-01, rama `nacho/N-224-player-sprint-typed`): correr. La caja pesada por
    `trap_definition.id` directo, la sesión por la constante `NETWORK_MANAGER` (preload de `network_manager.gd`:
    `world_seed` no está en `NetSession`) y el perfil como `UnlockProfile` (`mark_tip_seen`). Queda por nombre
    `ground_roughness` de la ruta (grupo `route`: `route.gd` sin `class_name` y los tests meten suelos falsos). En el
    archivo: `.call` 2 → 1, `.get(&` 2 → 0, `/root/` 3 → 3. `test_dynamic_dispatch_budget.gd` suma el archivo y su
    handle. Aviso `docs/avisos/2026-10-01-n224-player-sprint-tipado.md`.
  - [x] `mud_segment.gd` (2026-10-01, rama `nacho/N-224-mud-segment-typed`): ya estaba en `BUDGETS` desde N-108 y es el
    que más usos por nombre tiene en `scripts/` (16), pero casi todos son forzados. "Manos ocupadas" (`carried_package`,
    `seat_node_path`) se lee una sola vez en `_hands_busy()`. Quedan por nombre los `FakePlayer` de
    `test_mud_segment.gd` (`as Player` los dejaría fuera y nadie empujaría), `carries` del camión y `CrewProgression`/
    `RunManager` (precargar `vehicle.gd`, `crew_progression.gd` o `run_manager.gd` desde acá rompe la compilación bajo
    `--script`: `route.gd` lo carga y esos scripts nombran autoloads sueltos) y el relay de EventBus. En el archivo:
    `.get(&` 7 → 5; en `scripts/`: `.get(&` 180 → 178. Presupuesto ajustado en `test_dynamic_dispatch_budget.gd`. Sin
    aviso (`route/` y `tests/`). Para bajar más hay que pasar `test_mud_segment.gd` a jugadores reales. Siguientes (fuera
    de `BUDGETS`): `spectator_camera.gd` (12), `dashboard_gps.gd` (10), `vehicle_presentation.gd` (9), `play_area.gd` (9).
  - [x] `spectator_camera.gd` (2026-10-01, rama `nacho/N-224-spectator-camera-typed`): la vista de espectador y la toma
    de resultados. La sesión como `NetSession` (`local_id()`), el jugador local como `Player` (`_seated`,
    `tended_package`), la caja como `DeliveryPackage` (`trap_state`), la toma de resultados por `preload` de
    `results_orbit.gd` (`RESULTS_ORBIT.new()`: `target`, `frame_parked` directos, se va el `set_script`) y la meta como
    `RouteGoalLot` (`is_bay_occupied`, `results_direction`, `results_focus`). Quedan por nombre `RunManager.is_running`
    (precargar `run_manager.gd` desde la presentación del camión rompe la compilación bajo `--script`) y
    `driver_peer_id` del camión (`vehicle.gd` precarga la presentación que crea esta cámara). En el archivo: 12 → 4
    usos (`.call` 5 → 0, `.get(&` 5 → 2, `/root/` 2 → 2; también `.set(&` 1 → 0). `test_dynamic_dispatch_budget.gd`
    suma el archivo; `test_spectator.gd` prueba también la toma de resultados. Sin aviso (`presentation/` libre y
    `tests/`). Siguientes: `dashboard_gps.gd` (10), `vehicle_presentation.gd` (9), `play_area.gd` (9), `run_tally.gd` (9).
  - [x] `dashboard_gps.gd` (2026-10-02, rama `nacho/N-224-dashboard-gps-typed`): el GPS del tablero. La ruta por
    `preload` de `route.gd` (`ROUTE`: `houses`, `stop_road_distance`, `road_distance`, `goal_bay_number`, `goal_target`
    directos) y las cajas de `bomb_codes()` como `DeliveryPackage` (`care_state`; lo que no es un paquete en el grupo
    `cargo` se saltea, como antes sin `care_state`). Quedan por nombre `RunManager.current_distance` y `best_score` (la
    presentación del camión crea el GPS: precargar `run_manager.gd` rompe la compilación bajo `--script`) y el handle de
    EventBus. En el archivo: 10 → 4 usos (`.call` 5 → 1, `.get(&` 3 → 1, `/root/` 2 → 2).
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`presentation/` libre y `tests/`). Siguientes:
    `vehicle_presentation.gd` (9), `run_tally.gd` (9).
  - [x] `vehicle_presentation.gd` (2026-10-02, rama `nacho/N-224-vehicle-presentation-typed`): la presentación del
    camión. El camión por `preload` de `vehicle.gd` (`Vehicle`; `cargo_clutter.gd` ya lo precarga desde acá, así que
    no suma ciclo): `variant_id`, `maximum_speed_kmh` y la caja de cambios como `VehicleGearbox` (`enabled`, `gear`)
    directos; las cajas del grupo `cargo` como `DeliveryPackage` (`is_loaded`, `mass`; lo que no es un paquete se
    saltea, como antes) y la cámara de espectador por su script (`stop()`). Queda por nombre solo el handle de
    EventBus. En el archivo: 9 → 1 uso (`.call` 1 → 0, `.get(&` 7 → 0, `/root/` 1 → 1); en `scripts/`: `.call`
    172 → 171, `.get(&` 163 → 156. `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`presentation/`
    libre y `tests/`). Siguientes: `run_tally.gd` (8), `sound_audit.gd` (8), `vehicle_effects.gd` (7).
  - [x] `service_stop_shop.gd` (2026-10-02, rama `nacho/N-224-service-stop-shop-typed`): el mostrador de la estación
    de servicio (N-110 y su arreglo #236, el que más usos tenía: 32). La red como `NetSession` (`local_id`,
    `is_online`, `is_host`, `peer_ids`, `is_peer_ready`) y la votación como `CoopVote` (`active`, `offers`, `close_on`,
    `send_state_to`). Quedan por nombre `ShopVoteManager.open_shop` (del juego, sin `class_name`), `CrewProgression`,
    `RunManager` y `VehicleFaults` (sus scripts nombran autoloads y tiparlos rompe la compilación bajo `--script`:
    `test_service_stop` precarga el mostrador) y la estación y su mostrador (`service_stop.gd` precarga este script).
    En el archivo: 32 → 21 usos (`.call` 20 → 13, `.get(&` 11 → 7, `/root/` 1 → 1). `test_dynamic_dispatch_budget.gd`
    suma el archivo y exige que `ShopVoteManager` sea `CoopVote`. Sin aviso (`route/` es de Nacho y `tests/`).
    Siguientes: `mud_segment.gd` (14), `vehicle_presentation.gd` (9), `route.gd` (9), `run_tally.gd` (9).
  - [x] `route_smoke_check.gd` (2026-10-02, rama `nacho/N-224-route-smoke-check-typed`, reserva retomada): el
    chequeo de la ruta que corre `tools/run-tests.sh`. La ruta por `preload` de `route.gd` (`route_length`,
    `goal_transform`, `_path_points`, `houses`, `house_count`) y el lote de la meta como `RouteGoalLot`
    (`parking_pose()`). En el archivo: 7 → 0 usos (`.call` 1 → 0, `.get(&` 6 → 0); en `scripts/`: `.call` 170 → 169,
    `.get(&` 156 → 150. Sus dos líneas largas se partieron (sale de la línea base del lint).
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`route/` y `tests/`). Siguientes:
    `mud_segment.gd` (13), `package_rescue.gd` (13), `rejoin_keepsake.gd` (9), `sound_audit.gd` (8), `route.gd` (8).
  - [x] `route.gd` (2026-10-02, rama `nacho/N-224-route-typed`): la ruta de la entrega. La sesión por la constante
    `NETWORK_MANAGER` con un accesor `_network()` (`world_seed`, `world_house_count`, `peer_ids`, `is_host()`;
    `rail_crossing_segment.gd` ya precarga `network_manager.gd` desde esta ruta) y la estación como `ServiceStop`,
    leída de su `ServiceStopSegment` (`in_bay`). En el archivo: 9 → 1 uso (`.call` 2 → 0, `.get(&` 5 → 0, `/root/`
    2 → 1; también `.set(&` 1 → 0); en `scripts/`: `.call` 172 → 170, `.get(&` 155 → 150.
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`route/` y `tests/`). Siguientes:
    `mud_segment.gd` (14), `package_rescue.gd` (13), `rejoin_keepsake.gd` (9), `run_tally.gd` (9).
  - [x] `rejoin_keepsake.gd` (2026-10-02, rama `nacho/N-224-rejoin-keepsake-typed`): lo que se guarda de quien se
    va y vuelve (N-221). El que se fue como `Player` (`seat_node_path`, `net_in_vehicle`, `net_position`,
    `carried_package`), el camión por `preload` de `vehicle.gd` (`is_door_open`, `set_door_open`; se va el
    `has_method`) y el anclaje del regazo por `preload` de `package_mount_point.gd` (`occupied_by`): ninguno tiene
    `class_name`. Un `remember()` con algo que no es un `Player` se trata como "sin jugador". En el archivo: 9 → 0
    usos (`.call` 4 → 0, `.get(&` 5 → 0); en `scripts/`: `.call` 170 → 166, `.get(&` 150 → 145.
    `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`scripts/gameplay/` sin dueño y `tests/`).
    Siguientes: `mud_segment.gd` (14), `package_rescue.gd` (13), `run_tally.gd` (9), `crew_progression.gd` (9).
  - [x] `vehicle_effects.gd` (2026-10-02, rama `nacho/N-224-vehicle-effects-typed`): humo, esquirlas, marcas de
    frenada y el corte de color del golpe. La presentación por `preload` de `vehicle_presentation.gd` (`vehicle` y dos
    accesores nuevos, `wheels()` e `is_seat_camera()`, en vez de leer `_wheels`/`_seat_cameras` por nombre), el camión
    por `preload` de `vehicle.gd` (`presentation_engine_running`) y `GameSettings` por la constante `GAME_SETTINGS`
    (`camera_shake_scale`; el test comprueba que sea el script del autoload). Quedan los dos accesores `/root/`
    (EventBus, por nombre porque un test lo cambia por un `Node`, y GameSettings). En el archivo: 7 → 2 usos (`.get(&`
    5 → 0); en `scripts/`: `.get(&` 145 → 140. `test_dynamic_dispatch_budget.gd` suma el archivo y su handle.
    `test_dust_and_ambience.gd` y `render_exhaust.gd` cargan `vehicle_effects.gd` con `load()`: ahora precarga
    `vehicle.gd`, que nombra autoloads que un `--script` no tiene al compilar. Sin aviso
    (`presentation/` sin dueño salvo `vehicle_presentation.gd`, que es de Nacho, y `tests/`). `run_tally.gd` se saltó:
    sus 9 usos son todos sobre `RunManager`, que no se puede precargar (nombra autoloads y lo carga `net_trio.gd` por
    `--script`); solo `handed_over` bajaría (por `run_deliveries.gd`). Siguientes: `sound_audit.gd` (8, reproductores
    2D/3D sin base común), `run_session.gd` (8), `vehicle_prediction.gd` (7), `truck_radio_knob.gd` (6).
  - [x] `sound_audit.gd` (2026-10-02, rama `nacho/N-224-sound-audit-typed`): el silenciador de "Sonidos del juego".
    Los reproductores como lo que son (`AudioStreamPlayer`, `2D` o `3D`: no comparten una base con `stream`,
    `playing`, `bus`, `volume_db` ni `play`) por helpers tipados chicos (`_stream`, `_set_stream`, `_is_playing`,
    `_bus`, `_set_volume_db`, `_playback_position`, `_play`); `players()` ya junta solo esos tres tipos. En el archivo:
    8 → 0 usos (`.call` 2 → 0, `.get(&` 6 → 0; también `.set(&` 2 → 0); en `scripts/`: `.call` 166 → 164, `.get(&`
    140 → 134. `test_dynamic_dispatch_budget.gd` suma el archivo con todo en 0. Sin aviso (`presentation/` libre y
    `tests/`). Siguientes: `run_session.gd` (8), `vehicle_prediction.gd` (7), `truck_radio_knob.gd` (6),
    `run_scoring.gd` (6).
  - [x] `vehicle_prediction.gd` (2026-10-02, rama `nacho/N-224-vehicle-prediction-typed`): la predicción del
    cliente que maneja (N-218). El camión por `preload` de `vehicle.gd` (`driver_peer_id`, `set_controls()` y tres
    accesores nuevos, `throttle_input()`, `steer_input()` y `handbrake_input()`, en vez de leer `_throttle`,
    `_steering_input` y `_handbrake` por nombre). Sin cambios de red (`auditor-red`: OK, `PROTOCOL_VERSION` igual).
    En el archivo: 7 → 0 usos (`.call` 2 → 0, `.get(&` 5 → 0); en `scripts/`: `.call` 161 → 159, `.get(&` 129 → 124.
    `test_dynamic_dispatch_budget.gd` suma el archivo. `test_vehicle_prediction.gd` lee `EXIT_BLEND_SECONDS` con
    `load()`: `VehiclePrediction` ahora arrastra `vehicle.gd`, que nombra autoloads que un `--script` no tiene al
    compilar (`net_pair.gd` la sigue nombrando: corre como escena, con autoloads). Sin aviso (`vehicle/` y `tests/`).
    Siguientes: `run_session.gd` (8), `truck_radio_knob.gd` (5), `fault_repair_spot.gd` (5).
  - [x] `run_session.gd` (2026-10-02, rama `nacho/N-224-run-session-typed`): la parte de escena del ingreso tardío
    (N-225.5). La escena como `LevelCommon`, el depósito como `Depot` y la persiana como `DepotRollerDoor` (`is_open`,
    `set_open()`) en un helper `_depot_door()`; una escena que no es un nivel sigue contando como puerta abierta. Sin
    cambios de red. En el archivo: 8 → 0 usos (`.get(&` 7 → 0, `.call` 1 → 0). `test_dynamic_dispatch_budget.gd` suma
    el archivo; `test_session_sync.gd` comprueba la lectura del anfitrión (abierta y cerrada) y una escena sin nivel.
    Aviso `docs/avisos/2026-10-02-n224-run-session-tipado.md`. Siguientes: `truck_radio_knob.gd` (5),
    `fault_repair_spot.gd` (5), `hud_cargo_panel.gd` (5). (`run_tally.gd` reclamada por otra corrida.)
  - [x] `truck_radio_knob.gd` (2026-10-02, rama `nacho/N-224-radio-knob-typed`): la perilla de la radio. La radio
    como `TruckRadio` (`mode`, `cycle()` y los estáticos `next_mode`/`mode_key`), como ya hacía `truck_radio_view.gd`:
    solo `truck_radio.gd` precarga este archivo, así que no suma nada al grafo de un `--script`. Queda el `.get(&` de
    `carried_package` del jugador: el contrato de interactuables recibe cualquier nodo y el `FakePlayer` de
    `test_truck_radio.gd` lleva caja sin ser `Player`. En el archivo: 5 → 1 uso (`.call` 3 → 0, `.get(&` 2 → 1); en
    `scripts/`: `.call` 158 → 155, `.get(&` 118 → 117. `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso
    (`vehicle/` y `tests/`). La reserva `nacho/N-224-run-tally-typed` (solo el claim) se dejó: `run_tally.gd` ya se
    había saltado por `RunManager`. Siguientes: `fault_repair_spot.gd` (5), `hud_cargo_panel.gd` (5).
  - [x] `fault_repair_spot.gd` (2026-10-04, rama `nacho/N-224-fault-repair-spot-typed`, reserva retomada): el punto
    de arreglo de una avería. El dueño como `VehicleFaults` (`repair_prompt`, `repair_method`, `is_driver`, `fix`;
    `vehicle_faults.gd` precarga este archivo y ya nombra `Player`, así que no suma nada al grafo de un `--script`) y el
    jugador como `Player` para `carried_package`: el `Node3D` de `test_vehicle_faults.gd` no es `Player` y no carga nada,
    igual que antes. En el archivo: 5 → 0 usos (`.call` 4 → 0, `.get(&` 1 → 0); en `scripts/`: `.call` 156 → 152,
    `.get(&` 117 → 116 (líneas). `test_dynamic_dispatch_budget.gd` suma el archivo. Sin aviso (`vehicle/` y `tests/`).
    Siguientes (fuera de `BUDGETS`): `run_tally.gd` (9, reserva `nacho/N-224-run-tally-typed` de solo el claim),
    `vehicle.gd` (7), `network_manager.gd` (7), `run_scoring.gd` (6), `proximity_voice.gd` (6), `hud_cargo_panel.gd` (5).
  - [x] `run_tally.gd` (2026-10-04, rama `nacho/N-224-run-tally-typed`, reserva retomada): el resumen de la
    pantalla de "se fue el anfitrión" (N-222). `run_manager.gd` no se puede precargar (nombra autoloads; `net_trio.gd`
    carga este archivo por `--script`) ni sumar un método público (ya tiene 20, tope del lint), así que el registro
    entra por argumentos tipados: `has_unfinished_run(run)`/`of(run)` pasan a `unfinished(results, elapsed_seconds)`
    y `count(deliveries, cargo, endless, expected_houses, distance, elapsed_seconds)`, `handed_over()` sale de
    `run_deliveries.gd` por `preload`, y `hud_pause.gd` arma el resumen con `_unfinished_tally()` sobre el autoload
    `RunManager` tipado. En el archivo: 9 → 0 usos (`.call` 1 → 0, `.get(&` 8 → 0); en `scripts/`: `.call` 152 → 151,
    `.get(&` 116 → 109 (líneas). `test_dynamic_dispatch_budget.gd` suma el archivo; `test_host_gone_tally.gd` suma
    el caso "con resultados ya no está sin terminar". Aviso `docs/avisos/2026-10-04-n224-run-tally-tipado.md`
    (`hud_pause.gd` es de Slatex). Siguientes (fuera de `BUDGETS`): `vehicle.gd` (7), `network_manager.gd` (7),
    `run_scoring.gd` (6), `proximity_voice.gd` (6), `hud_cargo_panel.gd` (5).

### N-321.4 · Borrar `forest_ground.gdshader` — C · `Sonnet 5.5 · low` · Aviso: no
Origen: auditoría 2026-09-29 §5. Decidió el usuario (2026-10-04, issue #147): borrarlo. 0 referencias en
`.gd`/`.tscn`/`.tres`. Hecho cuando `do-not-drop/shaders/forest_ground.gdshader` y su `.uid` no están y
`.claude/agents/artista-shaders.md` ya no lo nombra.
- [ ] **N-321.4** `git rm` del shader y su `.uid`; sacarlo de la lista de `artista-shaders.md`.

## 1. Game Design

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 2. Programación y arquitectura técnica

### N-204 · FPS reales con GPU — A · `Opus 5.5 · medium` · Aviso: no · **[x] `90ecef4`**

El #93 viejo midió CPU/física en headless; el costo de dibujado nunca se midió.

- [x] Correr `tests/bench_drive.gd` **con ventana** (agente `revisor-visual`) en la PC de desarrollo, en las
  tres horas del día y con lluvia, en entrega y Endless. Anotar FPS promedio, 1 % más bajo y draw calls
  (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`).
- [x] Meta: 60 FPS estables a 1080p en la PC de desarrollo y ≥ 45 FPS con el preset bajo (N-205). **[x] 2026-10-01
  (base `a6c56f6` + rama `nacho/N-220-gpu-audit`)** — 16 corridas de 90 s por la pantalla de carga del juego
  (`--via-loader`), Reparto y Endless × día / atardecer / noche / lluvia × preset Alto y Bajo. Alto: el peor caso
  (Reparto al atardecer) promedia 117 FPS y su 1 % bajo es 71 (p99 14,1 ms); el resto, 140-152 en Reparto y 332-391 en
  Endless. Bajo: promedio mínimo 137 y 1 % bajo mínimo 69 (la meta es 45). 0-3 frames de más de 33 ms por corrida, el
  peor de 72 ms. Tabla en README → Rendimiento.
- [x] Resultado en README → Rendimiento, con la PC usada.
- Medido el 2026-09-24 (tabla en README → Rendimiento): reparto 139-164 FPS, 1 % más bajo 85-104; Endless 312-393. Queda abierto medir el preset bajo en una PC modesta (no hay una a mano).
- [ ] Medir el preset Bajo en una PC modesta de verdad. No hay una a mano. En esta PC el Bajo solo gana 9-17 % en Reparto
  (el juego va limitado por la CPU, ~1 núcleo, no por la GPU); con 4× los píxeles (`--render-scale=2.0`) y con 7× al
  atardecer el cuadro no se mueve (146 / 109 FPS en Reparto, 197 en Endless), y con 2 núcleos físicos tampoco, así
  que lo que queda sin cubrir es una CPU de un hilo más lenta. `bench_drive.gd --quality=low` (nuevo) lo mide el día que
  haya una (un playtester con una PC modesta, o la rutina en otra máquina).

### N-211 · Pasada de calidad de código "nivel AAA" — A · `Opus 5.5 · xhigh` · Aviso: sí · rama `refactor/quality-pass`

Pedido del usuario (2026-09-27): arquitectura, modularidad, responsividad y variables a nivel
profesional en todo el repo, incluidos archivos de Slatex. Un commit por fase, batería completa verde
en cada una, API pública y nombres de nodos intactos. Detalle para Slatex en `docs/colaboracion-equipo.md`.

- [x] **Fase 1 · Lint:** `gdlintrc` + `tools/lint.sh` con línea base que solo baja (CI + `pre-push`);
  `face_catalog.gd`/`render_layers.gd` a `core/`. `62ed50b`
- [x] **Fase 2 · Depósito:** `depot.gd` 1629 → ~550 en 7 componentes. `c9986c9`
- [x] **Fase 3 · Ruta:** `route_dresser.gd` 1241 → ~330 (`RoutePlacement`, `RouteSignage`,
  `RouteWildlife`, `RoutePowerLines`); `route.gd` 1042 → 736 (`RoutePlanner`, `RouteProps`).
  `1a86faa` `603fefd`
- [x] **Fase 4 · Jugador:** `player.gd` 1191 → 925 (`PlayerAnimator`, `PlayerAppearance`); componentes
  tipados `var player: Player`. `b1026bf`
- [x] **Fase 5 · UI:** el HUD dejó de ser una cadena de herencia de 6 niveles; ahora es `Hud`
  (`scripts/ui/hud/hud.gd`, antes `prototype_hud.gd`) con 5 componentes. `main_menu._build_ui()`
  se partió por sección. `696e147` + el commit del menú.
  - [x] `Hud._build_ui()` (~200 líneas) partido en siete constructores por zona de pantalla.
- [x] **Fase 6 · Búsquedas de nodos:** auditadas las 103. Casi todas son legítimas: partes de GLB importados
  buscadas por su nombre de Blender (contrato con el pipeline de arte, cubierto por `test_reference_truck`
  y afines) o consultas globales por grupo. Solo 4 corrían en cada frame; las 3 de fauna (perro, ovejas,
  ciervo) ahora cachean el camión en `_vehicle()`. La de `reference_truck` recorre los jugadores (≤5) y queda.
- [x] **Fase 7a · i18n de la UI:** los textos de `scripts/ui/**` a `translations/strings_ui.csv`
  (es = texto de siempre, en = primera traducción), con `test_ui_translations`.
- [x] ~~**Fase 7b · i18n del resto:** textos visibles en `core/` (eventos de ruta, desbloqueos, cartas,
  suministros, caras), `gameplay/` (contenidos de paquetes, avisos del depósito, historias) y los
  `display_name` de los `.tres` de trampas/contenidos.~~ **[x] Hecho (2026-10-01)**: casi todo ya había
  salido con N-805 (claves en `core/`, nombres de trampa y contenidos por clave, `ui_theme.trap_icon()` por
  clave). Quedaban la nota de la práctica de cuidado y el respaldo "Clic izq./der." (`care_practice`,
  `care_guide`) y el manejo de la torre de copas desalineado con su clave. `test_ui_translations` ahora
  ve literales sin tilde (dos o más palabras con una de `SPANISH_WORDS`), barre `modules/` y compara cada
  `data/contents/*.tres` con sus claves. Aviso: `docs/avisos/2026-10-01-n211-7b-i18n.md`.
- [x] **Fase 8 · Responsividad:** capturas del HUD y el menú en 16:9, 16:10 (Steam Deck), 21:9 y 4:3.
  16:9/16:10/21:9 bien. Arreglado: en 4:3 todo el HUD se dibujaba al 75% (letra de 6-7 px) — ahora
  `Hud.layout_scale()` maqueta siempre en 720 de alto lógico (HUD y tarjeta); el aviso de interacción
  pisaba la barra de ruta (ahora va en el flujo del dashboard); el chip de plata dejaba un óvalo vacío
  (`Hud.set_economy_visible()`); "furgoneta" → "camión". Todo con aserciones en `test_hud_flow`.
  - [ ] A confirmar: en las capturas la escena 3D del depósito salió más fría en una tanda que en otra;
    probablemente el clima/`WorldMood` al azar de cada corrida (nada de iluminación cambió en esta rama).
- [x] **Aparte:** ~~faltan 14 `.uid` en `main` (Godot los genera en cada clon con valores distintos);
  commitearlos en un PR chico cuando nadie tenga copias sin trackear.~~ **[x] Cerrada (2026-10-01):** hoy faltan 0, lo arregló #127 (auditoría integral 2026-10-01).
- [ ] Bajar la línea base del lint (quedan ~990 líneas de más de 120 columnas, casi todas en tests).

### N-215 · Repetir la prueba por Steam después de los PR #34 y #35 — A · manual (con un amigo) · Aviso: no

Es la prueba que falta para dar por cerrado el lag del 2026-09-29. Hay que hacerla con dos PCs distintas
por Steam (Spacewar 480), no con dos ventanas en la misma PC: ahí V-Sync reparte los FPS y aparece un
lag que entre dos PCs no existe.
- [ ] El camión ya no "sigue andando" segundos después de soltar las teclas. Queda el atraso de un ping
  más 100 ms, que es lo que ataca N-218.
- [ ] La caja cargada por el cliente va en sus manos, sin atraso.
- [ ] El lag no crece con el tiempo: en Reparto, con las 14 cajas, a los 5 minutos se siente igual que al
  empezar.
- [ ] Anotar el ping aproximado y los monitores de los dos (60 o 144 Hz).
- [ ] Del playtest anterior: con la ventana maximizada no aparece la tarjeta fantasma del menú, y el log no
  muestra "Depth of field blur".
- Si el lag acumulado vuelve, correr `test_net_bandwidth_budget` y revisar si alguien agregó una
  propiedad `ALWAYS` grande. Después, N-216 para medir en vivo.

### N-216 · HUD de red y simulación de mala conexión — A · `Opus 5.5 · high` · Aviso: sí (`network_manager.gd`) · **[x] rama `nacho/N-216-net-overlay-sim`**

Fase 0 de `docs/investigacion-red.md`: medir antes de seguir optimizando.
- [x] Overlay (F3 u opción) con ping, pérdida, KB/s de entrada y salida y bytes en cola. En Steam sale de
  `Steam.getConnectionRealTimeStatus`; en LAN, de `ENetPacketPeer`.
  `scripts/presentation/net_stats_overlay.gd` (acción `toggle_net_stats` en F3, `--net-stats` lo abre al
  arrancar): lo monta `NetworkManager`, arranca oculto y se arma recién al mostrarse; una fila por conexión
  directa y los totales, a 2 Hz, coloreados por gravedad. Los números salen de `scripts/core/net_stats.gd`
  (`NetStats.sample()`): Steam por conexión (claves de GodotSteam 4.22.1 verificadas en el binario); en LAN,
  ping, varianza y pérdida por peer, y el tráfico como total del host (`ENetConnection.pop_statistic`). ENet
  no expone la cola de envío: en LAN esa columna queda en "—".
- [x] `--net-sim=lag,jitter,pérdida` usando la simulación de Steam (`NETWORKING_CONFIG_FAKE_PACKET_*`,
  expuesta por GodotSteam 4.22.1) y el `--fake-lag` que ya existe para ENet.
  Steam: config global al iniciar Steam (`NetworkManager._apply_steam_net_sim`), mitad del lag en cada
  dirección, jitter 0..`jitter` ms y pérdida por paquete. LAN: `VehicleNetSmoother.configure_sim()` retiene
  las poses del camión `lag` + 0..`jitter` ms y pierde su parte (`NetworkManager.pose_net_sim()`, vacío en
  Steam para no simular dos veces).
- [x] Perfil de prueba estándar: 150 ms, ±20 ms y 2 % de pérdida. Documentarlo en el README.
  `--net-sim` solo o `--net-sim=standard`; README, sección "Medir la red y simular mala conexión".
- Tests: `test_net_stats` (nuevo: parseo, ids de Steam contra GodotSteam, KB/s desde contadores, filas de
  Steam y ENet, overlay oculto → F3 → visible → F3 → oculto), `test_vehicle_net_smoothing` (jitter y pérdida
  de `--net-sim`) y `tools/run-net-pair.sh` (el overlay lee el enlace ENet real en host y cliente, línea
  `NETSTATS`). Sin RPC ni replicación nueva: `PROTOCOL_VERSION` sigue en 4. Aviso
  `docs/avisos/2026-09-30-n216-net-overlay-sim.md`.
- [ ] Ver el panel con Steam real entre dos PCs (junto con N-215): que cada fila muestre ping, KB/s y cola, y
  que `--net-sim` en el cliente suba el ping unos 150 ms. **Necesita PC:** dos máquinas con Steam abierto; en
  CI no hay cliente de Steam y en una sola PC el P2P con la misma cuenta no anda.

### N-217 · Suavizado de jugadores y cajas remotas, y sync a 30 Hz — A · `Opus 5.5 · xhigh` · Aviso: sí (`player.gd`, `package.gd` de Slatex)

Fase 2 de `docs/investigacion-red.md`. Hoy los jugadores remotos (`player.gd _apply_net_state`) y las cajas
del cliente (`package.gd _process`) se colocan con el último valor que llegó, sin suavizar. Con el jitter
de internet saltan.
**[x] Hecho (2026-10-01, rama `nacho/N-217-snapshot-smoothing`, #224)** — `PROTOCOL_VERSION` 23 y 24 (el 22 es de N-110). Aviso:
`docs/avisos/2026-10-01-n217-suavizado-remoto.md`. Tests: `test_remote_pose_smoothing` y
`test_remote_carry_alignment` (nuevos); `test_net_pose_smoother`, `test_vehicle_net_smoothing`,
`test_carry_prediction` y `test_net_stats` ampliados.
- [x] El buffer genérico es `NetPoseSmoother` (`modules/net_pose_smoother`, ya separado del camión cuando se
  hicieron los módulos; no se renombró). Ahora toma el reloj de quien manda (`clock_ms()`, tiempo de física),
  calcula el desfasaje con la llegada menos demorada del último segundo, guarda poses `local` (en el espacio
  del camión, se dibujan sobre el camión de este peer) y da `latest_pose()`. Lo usan el camión, los jugadores
  remotos (`player_ride.gd push_net_pose/apply_net_state`) y las cajas del cliente (`package.gd _push_net_pose`).
  El WIP de la sesión cortada (`scripts/core/net_snapshot_buffer.gd`, que buscaba `NetworkManager` desde
  adentro) se pasó al módulo y se borró.
- [x] Colchón adaptativo: `delay()` = 2 intervalos + 2 × jitter (RFC 3550), entre 50 y 200 ms, con cambios
  suavizados al 5 %. Los huecos largos de una caja quieta (`NetRestThrottle`, 2 Hz) no cuentan como intervalo.
- [x] Jugador y caja a 1/30 s. Cada pose lleva `net_time` (int, último en el `SceneReplicationConfig`, así su
  setter ve el paquete entero); el jugador manda `net_yaw` (en el espacio del camión si viaja) en vez de
  `rotation`; la pose entra al buffer con la señal `synchronized` del sincronizador (paquete entero), y la
  cabeza, `locomotion_speed` y `jump_anim_time` viajan en el mismo buffer (`drawn_extra`). En un camión
  inclinado el giro del pasajero se manda relativo al rumbo del camión. `test_net_bandwidth_budget`: host →
  cliente estable 117,7 → 80,5 KB/s, todo moviéndose 154 → 107,1; subida del host 6,8 → 4,6 Mbit/s.
- [x] Revisión de `auditor-red`: la caja en manos de un jugador remoto se dibuja sobre su cuerpo tal como se
  lo dibuja (`carrier_peer_id`, `hold_offset`, `PackageNetPose`), en el host y en un tercer peer: de 27 cm a
  menos de 1 cm caminando con 40 ms de lag. Al soltar, el que la llevaba la lleva de sus manos a la copia
  del host en 0,25 s en vez de saltar 0,3-0,7 m para atrás.
- [x] Alcance: el host juzga a un jugador remoto por su pose más nueva (`reach_origin()` en el servidor), no
  por la dibujada en el pasado, y suma `NetStats.reach_slack()` (5 m/s × ida y vuelta, tope 1,5 m) en
  `Interactable._within_reach`, abrir caja, asistir y pasar de mano.
- [ ] Probar con dos PCs por Steam (con N-215): jugadores caminando y cajas en el camión con `--net-sim` en el
  cliente, que no salten. **Necesita PC.**

### N-218 · Predicción del camión para el conductor cliente — A · `Opus 5.5 · xhigh` · Aviso: sí (módulo nuevo, `network_manager.gd`) · **[x] rama `nacho/N-218-driver-prediction`**

Fase 3 de `docs/investigacion-red.md`. Hoy el volante del conductor cliente tiene un ping más 100 ms de
atraso.
- [x] El cliente que maneja descongela su copia del camión y la simula con sus inputs numerados.
  `scripts/gameplay/vehicle/vehicle_prediction.gd` (`VehiclePrediction`, uno por camión): el cliente al volante
  numera el input de cada tick y lo manda (`submit_driver_input(seq, …)`) mientras maneja; mientras el camión del host
  también se simula (`net_simulating`: no congelado por carga, estacionamiento o fin de corrida) descongela su copia y
  le aplica las mismas fuerzas (`vehicle.gd _drive()`, compartido con el host). `--no-drive-prediction` la apaga.
- [x] El host devuelve su pose con el último input procesado. El cliente compara contra su historial y
  corrige suave (posición en ~150 ms), sin re-simular. Módulo nuevo `modules/net_prediction/`: el host reproduce los
  inputs uno por tick (`NetInputBuffer`, colchón de 2, el último se sostiene si se pierde uno) y replica cuál
  representa su pose (`net_input_seq`); el cliente (`NetPredictionReconciler`) corrige posición (~92 % en 150 ms, a
  lo sumo 10 cm por tick, zona muerta 2 cm), rumbo (antes, 3° por tick) y, despacio y solo pasado 0,5 m/s, la
  velocidad; salta pasados 3 m o 45°. Medido: corregir la velocidad rápido (como la posición) hace oscilar la
  suspensión y deja las poses 30 veces más lejos. Las velocidades, el volante y la fuerza del motor viajan por
  proxies `net_*` para que el sincronizador no pise lo que predice el cliente. El barro (`mud_segment.gd`) aplica su
  agarre y su freno también a la copia predicha (con el estado replicado); empujes, grúa y choques con animales le
  llegan como corrección. Al dejar de manejar, la copia se vuelve a congelar y la diferencia con el búfer de poses
  se funde en 0,3 s. `PROTOCOL_VERSION` 25.
- [x] Las cajas siguen en el host y se dibujan en el espacio del camión del cliente (`net_in_vehicle`). Sin cambios:
  el camión predicho se dibuja interpolado, como el del host, y `PackageNetPose`/`Player.Ride` ya toman ese camino;
  `cargo_clutter.gd` lo sigue por ticks en ese caso.
- [x] Test con `--fake-lag`: el volante responde en el mismo tick, y la corrección no salta más de 10 cm
  por frame. `tests/test_vehicle_prediction.gd` (dos camiones en dos mundos de física, enlace de 150 ms + jitter y
  5 % de pérdida: error mediano 1,5 cm, peor corrección 1 cm por tick; un freno que solo siente el host, a 0,34 m;
  reinicio del host → salto; cambio de conductor → se congela sin saltar), `modules/net_prediction/tests/` y una etapa
  nueva de `tools/run-net-pair.sh` (dos procesos reales: el cliente maneja 2 s, error mediano 2 cm, peor corrección
  6 mm por tick, líneas `DRIVE`).
- [ ] Probar con Steam real entre dos PCs (y `--net-sim` en el cliente): que el volante se sienta inmediato y que
  el camión no "tironee" en curvas ni en el barro. **Necesita PC** (junto con N-215).
- Descartado: pasarle la autoridad del camión al conductor. El host terminaría simulando las cajas sobre
  un camión que llega atrasado, y volverían las cajas que atraviesan las paredes.

### N-220 · Auditoría gráfica con ventana real y física con el camión lleno — B · `Opus 5.5 · high` · Aviso: no · **[x] rama `nacho/N-220-gpu-audit` (salvo el opcional de los cachés)**

Lo que la auditoría headless no pudo medir (`revisor-visual` o `perfilador-rendimiento` con pantalla).
- [x] Draw calls, sombras, transparencias y partículas en Reparto y en Endless: comparar antes y después del
  PR #35. **[x] 2026-10-01** — experimentos `nodress|nosegvis|noshadow|nolights|noparticles|notransp|nobatch|...`
  del bench (nuevos: `noparticles`, `nolights`, `notransp`, `nobatch`) y un censo de la escena; tablas en
  `docs/rendimiento-pc.md`. El costo es de CPU y de cuántos objetos se dibujan: el decorado vale 50 % del frame del
  Reparto (1.297 multimeshes de 2,6 instancias), las mallas de tramos 33 %, camión 12 %, casas 10 %, luces 9 %, sombras
  8 % (36 % al atardecer, que es por qué es el caso caro); partículas y las 74 mallas transparentes, ruido. El PR #35
  (Endless, 45 s en frío, `b1ff656` → `96c353a`): draw calls 1.079 → 442 (−59 %), 294 → 376 FPS; el Reparto no cambia
  (2.644 → 2.641). Contra la referencia del 09-24 (`f5d50dd`): el Reparto pasó de 1.927 a 2.644 draw calls (+37 %) y
  de 195 a 143 FPS por un mundo más grande (mallas 2.992 → 5.210, 8 → 26 `SpotLight3D`, ruta 1.412 → 2.086 m);
  Endless 464 → 445 draw calls (plano).
- [x] Física de Jolt con 5 jugadores y el camión lleno (objetos activos y pares de colisión). **[x] 2026-10-01** —
  `bench_drive.gd --players=5 --cargo=full` (cuatro `Player_<peer>` falsos sentados y siete cajas, en un proceso). Jolt no
  informa los monitores `PHYSICS_3D_*` (valen 0): el bench cuenta `RigidBody3D` despiertos (3 → 11-14 de 147) y parte el
  tick en scripts y paso de Jolt (0,50 + 0,40 ms → 0,91 + 0,70 ms, el paso nunca pasa de 3 ms); 156 → 130 FPS, p99 9,4 →
  11,4 ms. Los pares de colisión no se pueden leer con Jolt (queda dicho). Detalle en `docs/rendimiento-pc.md`.
- [x] Hallazgo de esa medición, arreglado: derramar una caja arruinada costaba 40-110 ms en un tick de física (picos de
  101 ms por tick con el camión lleno) por `create_convex_shape(true, true)` en `package_contents_view.gd`; con
  `(true, false)` son < 2 ms. Pico por tick 101 → 28-42 ms, frame máximo 109 → 36 ms. Test en `test_package_unboxing`
  (falla con el código viejo: 227 ms). Aviso `docs/avisos/2026-10-01-spill-convex-hull.md`.
- [x] Tiempo de carga del menú y del nivel, y memoria. **[x] 2026-10-01** — `tests/bench_load_times.gd` (nuevo): motor →
  menú dibujado 3,6 s; botón → cubierta arriba 4,5 s en Reparto la primera vez (3,3 s con cachés calientes) y 1,5 / 0,9 s en
  Endless; sin frames de más de 23 ms en los primeros 120 después; memoria estática 136 MiB en el menú, 448 con el Reparto
  (pico 479), 205 con Endless solo; al volver al menú 340 MiB estables en cuatro idas y vueltas, 0 huérfanos.
- [ ] Opcional: vaciar los cachés `static` de mallas al volver al menú. No es un leak: el "1693 Mesh
  leaked at exit" son cachés acotados. **Medido y no hecho (2026-10-01):** son ~200 MiB estáticos y ~150 MiB de video
  sobre el menú, repartidos en más de 25 `static var` de `depot_kit.gd`, `dressing_batcher.gd`, `route_segment.gd`,
  `synth_audio*.gd`... sin un registro común (no es trivial), y vaciarlos haría la segunda carga del Reparto pasar de
  3,3 a 4,5 s. No crecen entre idas y vueltas. Si algún día hace falta, un `static func clear_caches()` por módulo y un
  llamado desde el menú.
- Observación: la corrida diaria de `pc-build` mide en frío (sin la pantalla de carga) y marca como tirones de 300-500 ms
  lo que el jugador no ve (8 de 16 corridas contra 0 de 16 con `--via-loader`). Conviene sumar `--via-loader` a esa
  corrida; es de la rutina (`.claude/rutinas/pc-build.md`), no se tocó.

### N-221 · Red defensiva: validación de RPC y reconexión — B · `Opus 5.5 · xhigh` · Aviso: sí (zona compartida) · **[x] rama `nacho/N-221-rpc-guard-rejoin`** (salvo el AppID, ⏸ N-901)

Fase 4 de `docs/investigacion-red.md`.
- [x] Validador común para RPC `any_peer`: remitente, `NaN`/`inf` en poses, tamaño de diccionarios y un
  límite de pedidos por segundo por peer. **[x] 2026-09-30:** `RpcGuard` en el módulo `net_session`
  (`modules/net_session/rpc_guard.gd`, estático): `sender_ok()`, `from_host()`, `allow_request()` (cupo por
  peer: 40 de golpe, 20/s; el host nunca gasta), `finite_float/vec2/vec3/transform()`, `dict_ok()`,
  `args_ok()`, `text_ok()`. Aplicado a los 36 `any_peer` (también los de los módulos: `NetEventBus.request`,
  `NetSession._report_level_ready`, `SteamVoice`, `CoopVote`, `Interactable`, `SeatPoint`; `interaction`
  pasa a depender de `net_session`). `NetEventBus.request()` era un RPC que relayaba cualquier evento:
  ahora solo los de `request_cooldowns` (`ping_sent`, `horn_honked`), con argumentos planos, y `EventBus`
  chequea su forma. El volante descarta `NaN` (`clampf()` lo dejaba pasar).
- [x] Test que recorra todos los `@rpc("any_peer"` y exija el chequeo del remitente. **[x]** `test_rpc_guard`
  (juego y módulos): remitente, `allow_request()` en los confiables que no vienen del host, chequeo por tipo
  de parámetro (sigue un nivel de llamadas: mismo archivo, la clase que extiende, `Clase.función()`),
  `_sync_color_slots` y `_receive_campaign` en el mismo canal, y el bus que no deja pedir hechos del juego.
  Casos del validador en `net_session__test_rpc_guard`. `EXCEPTIONS` vacía.
- [x] Reconexión: el que se cae a mitad de una partida vuelve a su lugar. **[x]** Lo sólido: misma
  identidad, mismo color (slot de N-226) y con él el mérito. `NetSession` reconoce al que vuelve (Steam ID;
  en LAN un hash del token del proceso con un nonce de la sesión que viaja en el handshake) y llama al hook
  `_peer_returned` y a `peer_rejoined(old, new)`; si vuelve antes de que el host note la caída (con los
  timeouts de 45 s es lo normal), la conexión vieja se cae como fantasma (`drop_peer()`: sale del roster,
  suelta caja y asiento, se cierra con timeout corto). `NetworkManager` reserva el slot del que se fue
  mientras haya otros libres; con la sala llena lo toma el que entra, pero arranca sin el mérito ni la carta
  (`inherits_color_slot()`). `PROTOCOL_VERSION` 14 → 15; al mezclar con `main` se quedó el N-226.2 de #123
  (`PlayerColorSlot`, host en 0) y de este PR solo la reserva de slots. Tests: `test_network_rejoin`,
  `net_session__test_net_session_rejoin` y la última etapa de `net_pair` (sale con la caja, vuelve desde el
  mismo juego y recupera slot y mérito). Aviso: `docs/avisos/2026-09-30-n221-rpc-y-reconexion.md`.
  - [x] Recupera posición, asiento y caja. **[x] 2026-10-01, rama `nacho/N-221-rejoin-restore`:** al irse se
    sigue soltando todo en el acto (S-209), pero el host anota qué tenía (`RejoinKeepsake`,
    `scripts/gameplay/rejoin_keepsake.gd`, en `peer_removed`) y, si vuelve la misma identidad (señal nueva
    `NetSession.peer_returned(id, anterior)`, también con el mismo id), lo spawnea desde la nota: en el camión si
    estaba (su asiento si sigue libre, abriéndole la puerta del chofer; si se lo tomaron, a mitad de corrida otro
    asiento o la caja como un join tardío), a pie donde estaba si tiene sentido (antes de la corrida en el
    depósito; a mitad, a menos de 40 m del camión) y con su caja en las manos si nadie la tocó (suelta, sin
    estantear ni perder, sin otro que la haya levantado, a menos de 3 m). Un fantasma que se suelta en el mismo
    frame: el que vuelve se spawnea el frame siguiente, cuando el viejo ya soltó asiento y caja. Sin RPC nuevo.
    Tests: `test_rejoin_keepsake` y las dos etapas de rejoin de `net_pair` (vuelve donde estaba y con su caja,
    también sobre un fantasma). Revisión de `auditor-red` (misma rama): la caja devuelta no cuenta como rescate
    (`_rescue_pending` se conserva), antes de la corrida con su asiento ocupado aparece al lado y no encima, el
    asiento se decide después de devolverle la caja y la puerta del chofer que se le abrió se cierra si el asiento
    no lo toma, y el reintento del spawn es una conexión de una vez, no un `await` (un nivel liberado no sigue).
    Sigue faltando: en LAN no se lo reconoce si reinició el juego (token nuevo); el fantasma de un crash con Steam
    no está probado con sockets reales (por ENet sí: `net_pair`); vuelve mirando hacia adelante (el spawn no
    lleva yaw: sumarlo cambia el protocolo); a pie a menos de 40 m del camión vuelve donde estaba aunque el
    terreno de ese tramo todavía no esté armado en su copia (el rescate al suelo seguro lo cubre, sin probar).
  - [x] Pedir la identidad antes del estado completo. **[x] misma rama:** con la sala llena en LAN el host manda
    solo `{version, session, identify}`, el que entra contesta su eslabón (`NetAdmission.answer_identify()`) y recién ahí
    (fantasma suyo o lugar libre: `NetAdmission.on_identity()`) recibe el estado y carga el nivel; si no, oye
    "full" (o "connection" si repite un eslabón ajeno) sin cargar nada. Su respuesta de listo ya no trae
    identidad y el host no la lee (`identified`). `PROTOCOL_VERSION` 24 → 26 (25 reservado para N-218, con una
    entrada provisoria en el historial). Tests: `net_session__test_net_session_rejoin` (sin sockets
    y por ENet: el que vuelve suelta al fantasma antes de cargar, extraño y ladrón sin estado),
    `test_network_rejoin`. Un joiner preguntado que no contesta oye "connection" a los 5 s
    (`NetAdmission.identify_timeout_seconds`) en vez de ocupar la conexión de sobra 45 s.
    Aviso: `docs/avisos/2026-10-01-n221-rejoin-restore.md`.
  - [ ] Nota para cuando exista la UI de silenciar (`SteamVoice`): el silencio y el volumen se guardan por peer id
    (`_muted`, `_peer_volume`), así que el que vuelve con otro id llega sin silenciar; y para un fantasma no llega
    `peer_disconnected` (`SceneMultiplayer.disconnect_peer()` lo bloquea), así que sus entradas quedan hasta que
    termina la sesión. Cuando haya UI: moverlo con `peer_returned(id, anterior)` (o guardarlo por
    `peer_identity()`) y olvidarlo con `peer_removed`. Sin UI todavía, queda para entonces.
- [x] Seguimiento de la auditoría de #125 (`auditor-red`), rama `nacho/N-221-followups`. La caja de un
  fantasma conserva su ventana de rescate: `NetSession.peer_removed` (antes de `roster_changed`, una vez por
  salida), que `package.gd` escucha en lugar de `multiplayer.peer_disconnected`. Sala llena: ENet acepta una
  conexión de más y `NetAdmission` (módulo) decide; el que vuelve recupera el lugar de su fantasma y un extraño
  oye "full" (en Steam al autenticar, en LAN con la respuesta de listo). `_report_level_ready` fuera del cupo
  (solo cuenta un reporte que el host debe); `request_drop` y `release_occupant` con reserva crítica
  (`RpcGuard.allow_critical_request`); `name_ok`/`path_ok` para los `StringName` y `NodePath` de RPC
  (`supply_id`, `offer_id`, `event_name`, `recipient_path`) y la regla en `test_rpc_guard`. Los slots de los que
  se fueron viajan en el handshake y en `_sync_color_slots`. El recién llegado que toma un slot reservado ya no
  pisa la entrada de campaña del que se fue (se aparta y se le devuelve), y la reserva que tomó un joiner que no
  entró, o que volvía a otro slot, vuelve a su dueño. `_settle_now` ya no le devuelve 20 s a un fantasma soltado.
  Segunda pasada de `auditor-red`: identidad LAN como cadena de hashes (Lamport; un valor repetido se rechaza
  y el peer vivo sigue), el rechazado se corta a los 0,5 s (`NetAdmission.refuse`), el que vuelve a una sala
  llena sin fantasma oye "full" antes de que se mueva nada, el fantasma se suelta con
  `SceneMultiplayer.disconnect_peer()` (sin "max channels: 0" ni fantasma visible) y el reinicio recorre solo
  los clientes con enlace (`_linked_clients`). Tercera pasada (en el PR #145): un solo "listo" por joiner y solo
  de uno admitido o sin lugar (un rechazado ya no llega a `complete_auth`), el eslabón de un intento rechazado
  por sala llena se anota (`advance`) y el rechazo en ENet espera el ack (`peer_disconnect_later`, corte duro a
  3 s).
  `PROTOCOL_VERSION` 19 → 20 (el 17, el 18 y el 19 los tomaron N-228.4, N-228.8 y N-228.5). Tests: `test_network_rejoin`, `test_network_roster`, `test_rpc_guard`,
  `net_session__test_rpc_guard`, `net_session__test_net_session_rejoin` (sala llena por ENet) y la última etapa
  de `net_pair` (fantasma real con la caja en crisis). Aviso: `docs/avisos/2026-10-01-n221-seguimiento-red.md`.
- [x] ~~Regla en `convenciones-godot.md`: subir `PROTOCOL_VERSION` con cada cambio de RPC o de replicación.~~
  **[x] Hecho (2026-09-30)** — rama `nacho/ci-faster-prs`: §6, con cómo elegir el número sin chocar con otro PR
  en vuelo; N-221 suma §0.2, junto con `RpcGuard` y el color. Filas NET-07 y NET-08 en
  `matriz-comportamiento-cobertura.md`.
- [ ] Antes de jugar con gente de afuera: AppID propio (N-901). ⏸ N-901 pospuesta (iteración de lanzamiento).
### N-921 · El nivel deja estado global sin restaurar al liberarse: 3D del diario y reverb del depósito — B · `Opus 5.5 · medium` · Aviso: sí (`hud_newspaper.gd` es de Slatex; `modules/acoustics/` es zona compartida) · M8
Origen: auditoría integral 2026-10-02, A-1.2 (P1). `hud_newspaper.gd:66-68` pone `disable_3d = true` en el viewport raíz
y solo lo devuelve `_on_finished()`; no hay `_exit_tree`. Si el host reinicia mientras un cliente todavía lee el diario
(`level_common.gd:436-458` recarga en todos), ese cliente juega la partida siguiente sin 3D. `AcousticSpace.apply`
(`modules/acoustics/acoustic_space.gd:42-58`) deja la reverb prendida en el bus `SFX`: quien sale al menú desde el
depósito o un túnel oye el menú con eco.
Hecho cuando un test libera el HUD con el diario abierto y `disable_3d` vuelve a `false`, y otro comprueba que salir del
árbol del depósito o de la ruta devuelve el bus `SFX` a la reverb `open`.
- [ ] **N-921.1** `HudNewspaper._exit_tree()` restaura `disable_3d`; test que libera el HUD con el diario abierto
  (ampliar `test_newspaper_scene.gd`). Con `constructor-ui`; tests `newspaper_scene`.
- [ ] **N-921.2** Volver a `open` al salir del árbol del depósito o la ruta (adaptador del juego, o `AcousticSpace` si
  corresponde); test en `test_acoustics`/del módulo. Con `disenador-audio`; tests `acoustic`.
- [ ] **N-921.3** Aviso nuevo en `docs/avisos/` en el mismo PR (hoy lo cubre `2026-10-02-auditoria-tareas.md`; uno
  propio si cambia algo más). Con `documentador`.

## 3. Arte y dirección visual

### N-307 · Inventario y dirección visual al día — A · `Opus 5.5 · low` · Aviso: no · **[x] `220e6e0`**

- [x] `docs/inventario-assets.md`: sacar el ⛔ de la furgoneta (ya está integrada), marcar ✅ los cables entre
  postes y los autos nuevos, revisar cada 🟡.
- [x] `docs/direccion-visual.md`: cerrar los `[ ]` que ya están resueltos (escala de personajes, LOD, motion
  blur descartado) y dejar abiertos solo los vigentes. Antes #100.

### N-324 · Humo de escape suave y claro — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-324-exhaust-smoke-4`**

`scripts/presentation/vehicle_effects.gd:11` y `:60-114` (`_try_build_exhaust`): `SMOKE_COLOR` gris 0,32 con alfa 0,42 y
`SphereMesh` 6×3 de 0,15 m unshaded; desde la caja se ve una hilera de 5-6 puntitos oscuros de borde nítido. Además la
`scale_curve` 0,5 → 3,2 queda en 0,5 → 1 porque `Curve` recorta a `max_value` 1 (el mismo bug está en
`package_ruin_effects.gd:203` y `route_river_falls.gd:326`, fuera de esta tarea). Subir `max_value` solo no lo arregló en
la captura de N-320: pide color más claro y otra forma. Desentona con el polvo claro y suave de N-320.
**Necesita PC** (GPU real para las capturas; la toma la sesión de arte). Origen: sesión de arte 2026-10-01 (`director-arte`,
área materiales y efectos).
Receta: quad billboard de 0,45 m con el material de degradé radial de `WheelDust._puff_material()` (volverlo estático y
reusarlo, no copiarlo); color gris claro tibio (0,80; 0,80; 0,78) con alfa en rampa [0 → 0,30 → 0,18 → 0] en offsets
[0; 0,12; 0,45; 1]; `grow.max_value` 3 con escala 0,4 → 2,6; rotación aleatoria ±180 y velocidad angular ±25; amount 14,
lifetime 1,6; dirección atrás y algo arriba, gravedad +0,35; `amount_ratio` según acelerador como hoy; color × luz según la
hora y alfa × 0,6 con lluvia/niebla, como `wheel_dust.gd`.
Hecho cuando: (a) en capturas desde la caja y atrás (`rear`), de día y de noche, en ralentí y a fondo, ninguna partícula
tiene borde visible ni es más oscura que el asfalto detrás; (b) el último puff mide ≥ 1 m en pantalla y el primero ≤ 0,25 m;
(c) a fondo tapa ≤ 10 % de la puerta trasera abierta; (d) un test (`test_dust_and_ambience.gd` u otro de efectos del
vehículo) fija `curve.max_value >= max(puntos)`, material billboard sin sombra y con alfa, y sin `SphereMesh`; las capturas
salen de un `tests/render_*.gd` reproducible (ampliar `render_wheel_dust.gd` o uno nuevo), revisadas con `revisor-visual`;
y el inventario §7 y `docs/especificaciones-visuales.md` #50 están al día.
**Intento 2026-10-01 (sesión de arte, 3 vueltas, no se subió): desde `rear` y desde la caja el humo no se lee.** Con la
receta tal cual, el humo era invisible: +0,007 de luminancia sobre el asfalto en `rear`. En la vuelta 3 se usó alfa máx.
0,85, quad de 0,6 m (0,33 → 1,5 m), 28 partículas × 2,4 s, salida a 1,4-2,2 m/s y color 0,86. Con eso de costado sí se lee
como estela (3-4 puffs, el mayor de ~1 m), pero desde atrás y desde la caja la estela se ve de punta y se apila en un solo
disco difuso (de día `idle_rear` +0,12, `launch_rear` +0,03, `launch_cargo` +0,04). De noche (luz ×0,55) no se ve:
+0,008 / +0,03. Bordes y oscuridad (a) bien en las tres vueltas, y tapa ~0 % de la puerta.
No repetir: alfa y tamaño solos no alcanzan. Para la próxima vuelta: (1) que el caño salga hacia el costado (hacia −X,
bajo el chasis) o que la estela tenga componente lateral y suba más, para que se despliegue en vez de quedar de punta a la
cámara; (2) piso de brillo de noche (no ×0,55 de un gris); (3) degradé propio del humo, porque el de
`WheelDust.puff_material()` (1 → 0,55 a medio radio) baja el alfa efectivo. Alternativa de dirección (`director-arte`):
dejarlo casi invisible y que se note solo en ralentí y al arrancar; si se elige, cambia el "hecho cuando" (b)/(d).
Parche de la vuelta 3 (emisor, `WheelDust.puff_material()` estático, test ampliado y `tests/render_exhaust.gd` con
planos `rear`/`cargo`/`side` × ralentí/arranque a ≤ 10 km/h/a fondo, cada uno con un camión nuevo) y capturas de las tres
vueltas: `D:/tmp/n324-intento/` y `D:/tmp/exhaust{,2,3}/` en la PC (fuera del repo).
**Intento 2 2026-10-01 (sesión de arte, 3 vueltas, no se subió): la causa de fondo es dónde nace el humo.**
`_try_build_exhaust()` ubica el caño con el AABB de todas las mallas de `body_visuals`, que incluye la rampa bajada y las
puertas abiertas: el humo nace en la punta de la rampa, ~2,5 m detrás de la cola y afuera del costado (distancias del log:
cámara de la caja a 3,7 m del caño, `rear` a 4,8 m). Por eso, en todas las vueltas, desde `rear` quedaba al lado o detrás de la
cámara (un solo disco) y desde la caja, lejos y fuera del vano. Esto pasa también en el juego, no solo en la captura.
- Vuelta 1 (hacia −X, gris de noche 0,52, degradé propio): de costado, columna; desde `rear` la tapa la puerta izquierda
  abierta (+7) y desde la caja no entra al vano.
- Vuelta 2 (atrás y arriba `(-0.3, 0.6, 1)`, gravedad +0,9, alfa máx. 1, primer puff 0,22 m y último 1,26 m, gris de noche
  0,62): la mejor. `rear` +48 de día y de noche, caja de noche +21, de día ~0; sin bordes, tapa 0 % de la puerta, nada
  a < 1,5 m de la cámara. Falla (b): un solo puff desde `rear`/caja, y de costado parecen bolitas de espuma con alfa 1.
- Vuelta 3 (caño anclado a `FloorCollision` + `RearLeftWheel`, a 0,3 m sobre la ruta, columna lenta, gravedad +0,5): el
  caño quedó demasiado bajo y los puffs nacen medio enterrados (corte recto contra el asfalto y bandas). Retroceso.
Para la próxima: volver a los valores de la vuelta 2 y solo arreglar el ancla del caño. Ancla en la cola de la caja (sin
rampa ni puertas), justo bajo el piso de la caja (`SMOKE_PIPE_HEIGHT` ~0,75 sobre la ruta, no 0,3), y comprobar la
posición en tiempo de ejecución, no con cuentas de `vehicle.tscn`: en la vuelta 3 las distancias del log no coincidieron
con la cuenta. Partículas suaves o `proximity_fade` si el puff toca el piso. Parche de la vuelta 3 (incluye
`exhaust_anchor()`, test del ancla y `render_exhaust.gd`) en `D:/tmp/n324-intento2/`; capturas de las vueltas 1-3 en
`D:/tmp/exhaust{4,5,6}/`.
**Intento 3 2026-10-01 (sesión de arte, 3 vueltas, no se subió): el ancla quedó resuelta, el humo sigue sin verse desde
atrás ni desde la caja.** Lo que sirve y se reusa: `exhaust_anchor()` sale solo de `FloorCollision` (forma fija; la rueda
mueve su `position` con la suspensión y en la vuelta 1 dejó el caño 0,65 m bajo el asfalto): (−0,88; −0,055; 4,49) en el
camión, 0,61 m sobre la ruta medido con un rayo hacia abajo, igual en las 18 tomas; el emisor cuelga de `vehicle`, no
del arte. `test_dust_and_ambience` (ancla en la cola sin rampa ni puertas, 0,5-1,0 m por rayo, curva, billboard, sin
`SphereMesh`) y `test_vehicle_presentation` en verde. `render_exhaust.gd` con `--mood=night` que da noche de verdad
(`WorldMood.pick()` lee `--mood=` de la línea de comandos y pisaba el atajo) y `--nosmoke` (falta fijar la rampa entre
corridas: no coinciden y el diff sale sucio).
- Vuelta 1 (valores de la vuelta 2 del intento 2): caño enterrado; humo invisible desde `rear` y caja.
- Vuelta 2 (ancla fija, hacia (−0,6; 0,7; 0,6)): la puerta izquierda abierta tapa la estela desde `rear`; de costado,
  halos casi blancos contra la caja blanca.
- Vuelta 3 (hacia (−0,2; 0,75; 0,9), gris de día 0,78, alfa máx. 0,85, 28 × 2,4 s): igual de invisible desde `rear` y caja;
  de costado, 2 discos sueltos.
**Pista para la próxima: en las tres vueltas hay 1-2 puffs en pantalla aunque el log dice `emitting true` (ratio 0,7-1)
y son 28 × 2,4 s (~11 vivos).** No es (solo) de valores: antes de tocar color o alfa, `cazador-bugs` tiene que contar las
partículas vivas y dónde se dibujan (quads opacos de depuración, o `amount_ratio`/`emitting` puestos cada frame en
`update_exhaust()` que reinician la emisión, orden de transparencias con la caja, `visibility_aabb`). Si un cuarto intento
tampoco lo logra, pasa a ⏸ con la alternativa de `director-arte` (casi invisible, solo en ralentí y al arrancar).
Parche de la vuelta 3 y hojas de capturas en `D:/tmp/n324-intento3/`; capturas en `D:/tmp/exhaust{7,8,9}/`.
**Intento 4 2026-10-01 (sesión de arte): resuelto.** `cazador-bugs` encontró la causa: `render_exhaust.gd` hacía la
precarga de 2,5 s con la cámara a ~70 m mirando a otro lado y la ponía sobre el camión dos cuadros antes de la toma; las
`GPUParticles3D` no simulan fuera de toda cámara, así que el emisor tenía ~3 cuadros de vida (de ahí 1-2 puffs). Además el
`damping` (0,8-1,2) frenaba cada puff a los 0,6-0,9 m y subían en columna, tapados por la puerta izquierda.
- [x] **N-324.1** ~~Rehacer emisor y material según la receta y ampliar el test.~~ **[x] Hecho (2026-10-01, sesión de
  arte)** — `vehicle_effects.gd`: quad billboard 0,44 m con degradé propio (`smoke_puff_material()`, estático y cacheado;
  no el de `WheelDust`, que baja el alfa a medio radio), 28 × 2,4 s, crece ×0,5 → ×2,86, rampa de alfa [0; 0,85; 0,55; 0],
  gris por hora `SMOKE_GREY_BY_TIME` (0,78/0,68/0,5), alfa × 0,6 con lluvia/niebla, dirección (−0,15; 0,35; 1), velocidad
  1,6-2,2, `damping` 0,2-0,4, subida 0,4; caño en `exhaust_anchor()` (de `FloorCollision`, 0,6 m sobre la ruta);
  `visibility_aabb` de 30 m hacia atrás; sin emisión a < 1,5 m de la cámara. `test_dust_and_ambience` ampliado (ancla por
  rayo, curva con `max_value`, billboard sin sombra con alfa, sin `SphereMesh`, damping y dirección).
- [x] **N-324.2** ~~Capturas reproducibles antes/después.~~ **[x] Hecho (2026-10-01)** — `tests/render_exhaust.gd`
  (`rear`/`cargo`/`side` × ralentí/arranque/a fondo, `--mood=night`, `--nosmoke` para restar), con la cámara puesta antes
  de la precarga y `rear` a 6,8 m del caño. `revisor-visual` con GPU real, contra `--nosmoke`: estela de 6-8 puffs desde
  `rear` y la caja, de día y de noche; +19 a +29 de luminancia sobre el humo en ralentí y +5 a +20 andando, ningún píxel
  del humo más oscuro que el asfalto; el último puff ~1 m y el primero < 0,25 m; puerta trasera tapada 0,5 % a fondo
  (peor caso 7 % al arrancar). Antes: `D:/tmp/exhaust9/`; después: `D:/tmp/exhaust11/` (en la PC, fuera del repo).
- [x] **N-324.3** ~~Actualizar inventario §7 y `docs/especificaciones-visuales.md` #50.~~ **[x] Hecho (2026-10-01)**.
- Límite conocido: como toda `GPUParticles3D`, el humo se congela mientras ninguna cámara ve su `visibility_aabb` (p. ej.
  la cabina mirando adelante) y sigue desde ahí. En ralentí, desde la caja, solo se ven 2-3 puffs tenues.

### N-326 · Texturas de detalle sin cruz de corte en 256 — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-326-detail-seams`**

`do-not-drop/assets/textures/detail/tx_detail_{earth,grass,plaster,stone}_512.png` tienen una cruz de corte duro en
x/y = 256: salto de gradiente en la línea central contra la mediana de las demás (earth 18,1 / 9,5; grass 14,2 / 8,6;
plaster 23,7 / 16,2; stone 19,0 / 13,0); `roof_shingles` tiene una posible junta en x = 256 (9,2 contra 0,5). Los crudos de
ComfyUI `art/concept/textures/tex_*_seed*.png` no la tienen: la mete `to_detail()` de `art/tools/make_detail_textures.py`
(mezcla con `np.roll` y una máscara de caja desenfocada que no llega a 1 sobre la cruz). Se ve en el terreno de pasto y
tierra (`route_terrain.gdshader`), el barro (`mud_segment.gd`), el piso del depósito (plaster ×4, `depot_hall.gd:47`), las
paredes de casa (plaster) y el hormigón/zócalos (stone).
**Necesita PC** (la toma la sesión de arte). Origen: sesión de arte 2026-10-04 (`director-arte`, área texturas e imágenes
2D). Aviso: no; `art/tools/` y `do-not-drop/assets/textures/` no están en la zona compartida ni en el dominio de nadie en
`docs/colaboracion-equipo.md`, pero las texturas las usan los dos dominios (mundo y casas), así que el PR lo dice en la
descripción.
Receta: en `to_detail()` sacar `np.roll` y la máscara; volver periódico el gris con la descomposición periódica + suave
(Moisan 2011, con `np.fft`); pasa-altos con desenfoque gaussiano circular (FFT o `np.pad(mode="wrap")`, sigma = size/10) en
lugar del espejado; misma normalización (`DETAIL_MEAN` 0,86, `DETAIL_SPREAD` 0,28); modo `--from-raw` que regenere las 10
desde los crudos con semilla fija, sin ComfyUI. 512² L, mismo camino y nombre. Reimportar con
`scripts/tools/texture_import_3d.gd`.
Hecho cuando: (a) las 10 pasan la métrica: gradiente medio en columna/fila 255|256 y en el borde 511→0 ≤ 1,15 × la
mediana de las demás; (b) media 0,86 ± 0,005 y desvío 0,07 ± 0,005; (c) sin líneas rectas ni cuadrícula en
`render_terrain_review.gd`, `render_depot.gd`, `render_mud_segment.gd` y `render_town_delivery.gd`, revisadas por
`revisor-visual` y por `director-arte` contra lo que las rodea, sin superficies de color plano; (d) un solo comando
(`python art/tools/make_detail_textures.py --from-raw`) regenera las 10; (e) `texture_import_3d` en verde.
- [x] ~~**N-326.1** Reescribir `to_detail()` (periódico + pasa-altos circular) y agregar `--from-raw` con una métrica de
  costura reutilizable. Con `artista-conceptual`; tests `texture_import_3d`.~~ **[x] Hecho (2026-10-04)** —
  `make_detail_textures.py`: `periodic_component()` (Moisan), `circular_blur()` (gaussiano por FFT, sigma size/10) y
  `hide_border()` (fundido de ±32 px solo junto al borde de repetición, peso exacto 0 en el borde y 1 desde 32 px; no se
  aplica a `wood_planks` ni `roof_shingles`, donde duplicaba juntas); `--from-raw` y `--check` (`seam_ratio()`).
- [x] ~~**N-326.2** Regenerar las 10, reimportar y capturar las 4 escenas antes/después. Con `revisor-visual` y
  `director-arte`; tests `texture_import_3d`.~~ **[x] Hecho (2026-10-04)** — costura central antes → después: grass
  1,88 → 1,02, earth 1,91 → 0,96, stone 1,43 → 0,97, plaster 1,17 → 1,02, bark 7,74 → 0,98; las 10 en media 0,86 ± 0,002
  y desvío igual al de antes ± 0,0005. No llegan a ≤ 1,15 por juntas del dibujo (aceptadas mirando el mosaico 2×2):
  gravel 1,34 (el crudo ya da 1,34), wood_planks 3,08 (rendija real en y≈256) y roof_shingles 10,7 (juntas de teja).
  `revisor-visual` (GPU real) y `director-arte`: sin cruz ni cuadrícula en las 4 escenas, brillo igual, plaster se lee
  como cemento; `texture_import`, `terrain`, `depot` 11/11.
- Fuera de esta tarea (sin tarea propia todavía): (1) el splash `ui/backgrounds/tx_ui_boot_splash_1920.png` usa Arial Black
  en vez del logo de S-306 y dice "DELIVERY COOPERATIVO"; (2) `textures/terrain/tx_terrain*_seamless.png` no tienen
  referencias (limpieza); (3) `director-arte` 2026-10-04: `wood_planks` corta las 13 tablas en la misma x (recta
  vertical en cada vuelta; puede notarse en `depot_furnishing.gd:172`/`:374`, `depot_zones.gd:454`), escalonar los cortes
  (P2); `roof_shingles` 2-3 tejas que no casan en el borde y `bark` con vetas que se esfuman en el borde horizontal (P3);
  (4) en `town_delivery_customer` el lote y el sendero de la casa son verde y beige planos sin grano junto al pasto con
  textura: REHACER con el material del terreno y detail de plaster o gravel (P2, `artista-shaders`).

## 4. Audio y diseño sonoro

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 5. UI / UX (en el mundo)

La UI de pantalla es de Slatex. Nacho se encarga de la guía **dentro del mundo**, que no necesita
tocar el HUD.

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 6. Narrativa y guion (narrativa ambiental del mundo)

La premisa, los clientes y los textos de las cajas son de Slatex (su S-601 a S-605). Nacho cuenta la
historia **con el entorno**, sin esperar esos textos.

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 7. Producción y gestión de proyecto

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 8. QA (sin playtesting)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## 9. Negocio, marketing y distribución

> **⏸ Pospuesto (2026-09-28):** estamos en desarrollo y refinamiento, así que lo de publicar en Steam
> y promocionar el juego queda para una iteración de lanzamiento. Las tareas marcadas ⏸ no se trabajan
> ni cuentan como pendientes hasta que se reabra esta sección.

### N-901 · Steamworks y AppID propio — A (decisión) · `Opus 5.5 · medium` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

Hoy se usa el AppID 480 (Spacewar), que no se puede publicar.

- [ ] Crear la cuenta de Steamworks y pagar el Steam Direct (USD 100 por juego). Anotar el AppID en
  `steam_appid.txt` y en `network_manager.gd` (aviso).
- [ ] Volver a verificar el flujo de invitación de amigos con el AppID real (la crítica §7 avisa que nunca se
  probó con el juego real). Se hace junto con N-215 y N-912.3.
- Nota lanzamiento 2026-10: Steam Direct tiene 30 días de espera entre el pago y poder lanzar; fecha de pago en N-916.
  Sin AppID no hay logros (S-907), nube (N-914) ni prueba real.

## Mecánicas tomadas de la competencia (2026-09-28)

Salen de `docs/analisis-competencia-backseat-rv.md` (Backseat Drivers y RV There Yet?); la columna
**M-xx** es el id de ese documento, donde está el razonamiento completo. Los IDs siguen el pilar al que
pertenece cada tarea. A diferencia del resto de la lista, varias tocan el dominio de Slatex (paquetes,
jugador, UI): se asignaron a Nacho a pedido del usuario, así que llevan **Aviso: sí** y, antes de
empezarlas, conviene pasar el plan por `guardian-dominios`.

| ID | M-xx | Tarea | Prio |
|---|---|---|---|
| N-704 | — | Corregir el diferencial y pasar las ideas grandes por crítica | A |
| N-505 | M-02 | Indicaciones rápidas con voz de personaje | A |
| N-213 | M-04 | Carga que sale del camión y rescate afuera | A |
| N-214 | M-03 | Averías del camión reparables con el kit | A |
| N-212 | M-01 | Voz por proximidad | A |
| N-109 | M-06 | Animales que se meten con la carga | B |
| N-406 | M-09 | Radio del camión con función | B |
| N-108 | M-05 | Tramo de barro/pendiente con salida cooperativa | B |
| N-110 | M-07 | Paradas de servicio en la ruta | B |
| N-311 | M-08 | Cosméticos para encontrar en el mundo | B |
| N-113 | M-11 | Evento de visibilidad limitada para el conductor | C |
| N-111 | M-14 | Modo "Mudanza" (viaje largo) | C |
| N-112 | M-10 | Modo party "Clientes a bordo" | C |
| N-114 | M-12 | Caja de cambios manual como variante | C |
| N-907 | M-13 | Friend Pass y demo separada (⏸ pospuesta) | C |

### N-212 · Voz por proximidad — A · `Opus 5.5 · xhigh` · Aviso: sí (jugador y red)

Brecha más grande frente a los dos juegos. Empezar por un prototipo solo con Steam.

> **Veredicto `critico-diseno` (N-704.3, 2026-09-28): a favor con cambios.** La voz posicional da los clips
> (el "¡FRENÁ!" que el conductor no oye), pero cuesta L, toca red y jugador, y los bugs de voz fueron la
> queja número uno en los dos juegos. Condiciones: empezarla **después de N-505**; solo Steam (N-212.4 se
> resuelve "LAN sin voz"); tope de 5 días y, si no anda estable con 5 jugadores, se congela; interruptor
> general, pulsar para hablar por defecto y silenciar por jugador; el filtro "a través de la chapa" es
> extra (alcanza con atenuación 3D). Sugiere bajarla a prioridad B (no es condición para la demo).

- [x] **N-212.1** Steam: captura y envío con la voz de GodotSteam (`startVoiceRecording` / `getVoice` /
  `decompressVoice`) por un canal no confiable, fuera de la simulación autoritativa. `649c7fa`
  `core/proximity_voice.gd` (autoload `ProximityVoice`): graba mientras se aprieta `voice_talk` (Z), manda
  por RPC `unreliable_ordered` en el canal 3 y el que recibe descomprime y emite `voice_received`.
  Probado con un Steam falso; **falta probarlo con Steam real** (entra con la prueba de N-212.2).
- [x] **N-212.2** (rama `nacho/N-212-voice-playback`, `e527214`) Reproducción en `AudioStreamPlayer3D` en la cabeza del jugador; dentro de la cabina se
  oyen todos, afuera se atenúa y pasa por el bus Exterior con filtro (se oye "a través de la chapa").
  Módulo `net_session`: `VoicePlayback` (`AudioStreamGenerator` con búfer de jitter de 60 ms, tope de 0,3 s
  que descarta lo viejo, se calla sola a los 0,5 s, `carry_in_room()` / `carry_in_open(muffled)`).
  `proximity_voice.gd` le cuelga una ("VoiceChat") al jugador que habla, en su `Head` o en su asiento; los
  dos en el camión (cámara de asiento + sentado) → bus `Interior` sin atenuación, si no → `Exterior` con
  atenuación 3D (no se oye a 28 m) y apagada si uno está a bordo (sentado o parado en la caja) y el otro
  no. Volumen = el del compañero × "Voces"; silenciar, volumen 0 o apagar la voz lo cortan en el acto; se
  libera al irse (`peer_removed`) o al terminar la sesión (también si se va el host: `session_failed`).
  `SteamVoice` decodifica como mucho 120 paquetes/s por peer (ráfaga 30). Sin RPC nuevo. Tests
  `test_proximity_voice_playback` y `modules/net_session/tests/test_voice_playback`. **Falta probarlo con
  Steam real** (con N-212.1): necesita PC.
- [x] ~~**N-212.3** Pulsar para hablar (con tecla configurable) y detección de voz, silenciar y volumen por
  jugador, y un interruptor general en Opciones. Hecho en `649c7fa`: `GameSettings.voice_chat_enabled`
  (apagado hasta que exista N-212.2) y `voice_push_to_talk` (por defecto; apagado = micrófono abierto),
  la tecla reasignable y `ProximityVoice.set_peer_muted()` / `set_peer_volume()`. **Falta:** mostrarlos en
  Opciones y en una lista de jugadores (UI de Slatex, `options_panel.gd`).~~
  **[x] Hecho (2026-10-01, rama `nacho/N-212-voice-options`)** — `scripts/ui/options_voice_section.gd`
  (`OptionsVoiceSection`, debajo de "Sonidos del juego" en Opciones): "Chat de voz" y "Pulsar para hablar" (gris con
  la voz apagada), aviso de solo Steam y "Voces de la tripulación": una fila por compañero (de
  `CrewPanel.build_entries()`, sin uno mismo) con color, "Silenciar" y volumen 0-1 sobre `ProximityVoice`; se rearma
  al abrir y si cambia el roster con el panel abierto. `voice_talk` (Z) entra en las teclas reasignables. Sigue
  apagada por defecto hasta probarla con Steam real (supuesto conservador). Test `test_voice_options`;
  `controles-y-ui.md` al día. Aviso `docs/avisos/2026-10-01-n212-opciones-de-voz.md`. Sin botón de mando para hablar
  (no había; queda para N-913, voz en el mando).
- [x] **N-212.4** LAN/ENet: `AudioEffectCapture` o dejarlo fuera del MVP (decidir y anotar). `649c7fa`
  Decidido: **LAN sin voz** (condición de `critico-diseno`); la razón quedó en `proximity_voice.gd`.
- [ ] Medir con `auditor-red` el ancho de banda con 5 jugadores. Test de que el apagado general no
  captura el micrófono. El test ya está (`test_proximity_voice.gd`, `649c7fa`); falta medir el ancho de
  banda (con N-212.2).

### N-406 · Radio del camión con función — B · `Opus 5.5 · high` · Aviso: sí (trampa Ruidoso) · **[x] rama `nacho/N-406-truck-radio`**

- [x] **N-406.1** Perilla en el tablero que cualquiera puede girar: tranquila / fuerte / noticiero /
  apagada. Estado en el host.
  - `gameplay/vehicle/truck_radio.gd` (`TruckRadio`, junto a `VehicleFaults`, lo agrega `level_common.gd`) y
    `truck_radio_knob.gd` (un `Interactable` que cuelga del camión junto al GPS del tablero, mismo nombre en cada
    par para `request_interact`). El host cicla apagada → tranquila → fuerte → noticiero y lo replica con un RPC
    propio (`_set_mode`), y al que entra tarde se lo manda `peer_level_ready`. Sin señales nuevas en `EventBus`.
  - Vista y sonido en cada par: `presentation/truck_radio_view.gd` (perilla que gira, nombre del modo, línea del
    noticiero) y música sintetizada por el bus Interior (`synth_audio_radio.gd`, con su propio caché; se
    arman en un hilo con `warm()`).
- [x] **N-406.2** Música tranquila calma la trampa Ruidoso; la fuerte la altera.
  - `noisy_trap_behavior.gd` lee `radio_mode` del contexto (que arma `package_rescue.gd` desde el grupo
    `truck_radio`): tranquila +4/s de decaimiento pasivo; fuerte sacudidas ×1,25 y decaimiento ×0,4. Números en
    `data/traps/noisy.tres` y `docs/parametros-diseno.md`; con la radio apagada (el arranque) el balance de
    `sim_trap_balance` no cambia.
- [x] **N-406.3** El noticiero anuncia el próximo evento de ruta ("inspección más adelante").
  - Con el noticiero puesto, `route_event_started` (relevado a todos) suena con un jingle y muestra "Atención:
    inspección más adelante" sobre la perilla durante 7 s; al poner el noticiero con un evento abierto lo repite.
    Una línea por evento de `RouteEventManager.EVENTS`, con `tr()` (`WORLD_RADIO_NEWS_*`).
- [x] Test `test_truck_radio.gd`: el estado se sincroniza y modifica la agitación de Ruidoso. Aviso:
  `docs/avisos/2026-09-30-n406-truck-radio.md`.
- [x] `revisor-visual` sobre la perilla y el cartelito: hecho en el PR #116 (perilla y cartel legibles, texto más
  grande). `auditor-red` revisó `_set_mode`, el tardío y el reinicio: sin hallazgos; el cooldown de la perilla
  (250 ms en `TruckRadio.cycle()`, en el host) se arregló en `nacho/N-406-radio-cooldown`.
- [ ] Necesita PC: prueba a mano de que el tripulante a pie en la cabina llega a la perilla (el conductor y los
  sentados no: `E` sentado los levanta).

### N-311 · Cosméticos para encontrar en el mundo — B · `Opus 5.5 · medium` · Aviso: sí (cosméticos del jugador)

- [ ] Además de los que se desbloquean con mérito, algunos gorros aparecen en el depósito, en las paradas
  (N-110) o en el jardín de un cliente. Recogerlos exige bajarse o desviarse unos metros.
- [ ] Se guardan en la campaña por color de jugador, como el mérito. Test de guardado y carga.

### N-111 · Modo "Mudanza" (viaje largo) — C · `Opus 5.5 · xhigh` · Aviso: sí (modo nuevo, zona compartida)

- [ ] 20-40 min con una carga grande y paradas de servicio (N-110), sobre el streamer de Endless.
- [ ] Guardado a mitad de camino en cada parada. Test de la duración con el bot de N-102.

### N-112 · Modo party "Clientes a bordo" — C · `Opus 5.5 · xhigh` · Aviso: sí (modo nuevo, zona compartida)

> **Veredicto `critico-diseno` (N-704.3, 2026-09-28): en contra; postergar a después del lanzamiento.**
> Mete un rol con objetivo opuesto al grupo en un juego cuyo pilar es cooperar; con 5 jugadores como máximo,
> cada saboteador es un cargador menos; el "pasajero caótico" ya son las trampas; el griefing sigue sin
> resolver y un modo nuevo en la zona compartida cuesta M-L. Alternativa barata si se retoma: carta/evento de
> ruta "Cliente a bordo" con un NPC que molesta 30-60 s, manejado por el host y reutilizando bocina y radio
> (N-406). Revisarla como contenido de actualización cuando haya datos de jugadores reales.

- [ ] Solo si N-704.3 le da luz verde. Uno o dos jugadores son pasajeros caóticos (cliente apurado,
  chico) que ganan puntos propios molestando dentro de límites: bocina, radio, abrir una caja ajena.
- [ ] Límites duros para que el sabotaje no arruine la partida (enfriamientos, lo que no pueden tocar).

### N-907 · Friend Pass y demo separada — C · `Opus 5.5 · medium` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

Es de publicación en Steam: queda pospuesta como el resto del pilar 9 (ver la nota de esa sección).

- [ ] Averiguar en Steamworks cómo funciona el Friend Pass (Backseat Drivers lo usa) y si se puede
  combinar con nuestro lobby de Steam. Decisión anotada en `docs/plan-desarrollo.md` Fase 7.
- [ ] Evaluar publicar la demo (hito del 2026-12-18) como app aparte para acumular deseados.
- Depende de N-901 (AppID propio).

---

## Pedidos del usuario: correr, meta, personaje flaco y diario (2026-09-29)

Cuatro tareas que pidió el usuario después de ver el juego terminado de punta a punta. Van en el hito
**M7**, en este orden (de la más chica a la más grande). Tres tocan el dominio de Slatex (jugador, UI de
personalización y resultados): llevan **Aviso: sí** y conviene pasar el plan por `guardian-dominios`
antes de empezar.

| ID | Tarea | Prio |
|---|---|---|
| N-115 | Correr | A |
| N-116 | Parada final: estacionamiento de camiones de reparto | A |
| N-312 | Personaje flaco y alto | A |
| N-606 | El diario del día siguiente | A |

### N-115 · Correr — A · `Opus 5.5 · high` · Aviso: sí (`player.gd`, `player_animator.gd`, `player_carry.gd`, daño de paquetes y controles de Slatex) · rama `nacho/N-115-sprint`

> Hoy el jugador tiene una sola velocidad (`Player.WALK_SPEED` = 3,6 m/s). Correr sirve sobre todo para
> llegar a tiempo a una caja caída (los 30 s de rescate de N-213) y para moverse por el depósito.

- [x] **N-115.1** Mantener Correr (Shift en teclado, clic del stick izquierdo en gamepad; reasignable en
  Opciones como el resto) sube la velocidad a ~6 m/s. Sin estamina: el juego es cooperativo y casual.
  Hecho: acción `sprint` en `project.godot`, reasignable (`GameSettings`, fila "Correr" en Opciones),
  `player_sprint.gd` (componente nuevo del jugador). Rama `nacho/N-115-sprint`.
- [x] **N-115.2** **Se puede correr con una caja en brazos, con el riesgo que conlleva** (decisión del
  usuario, 2026-09-29). Es una apuesta: llegás antes, pero la caja la paga.
  - Con caja se corre algo menos (~5 m/s); la caja de Peso Creciente ya cargada solo deja trotar.
  - Cada paso de carrera sacude la caja: daño chico por paso por el camino de daño de siempre (lo aplica el
    host), que cada trampa siente a su manera: el Frágil más que ninguno, la Torta/Equilibrio se inclina,
    el Líquido derrama, la gallina del Ruidoso se altera y cacarea.
  - Tropezón: corriendo con caja, un giro brusco, una pendiente o ripio, o chocar con algo puede hacer
    tropezar (chance por semilla, más alta cuanto peor el terreno): la caja cae al suelo con golpe, como
    un `drop_carried()` con impacto.
  - Se tiene que ver venir: la caja rebota en los brazos, cruje, y la primera vez sale el consejo
    "Correr con la caja la sacude".
  - Sin correr sentado, manejando ni arriba del camión en movimiento.
  - Hecho: 6 / 5 / 4,2 m/s; el paso sacude la caja por `package_run_shake.gd` -> `on_carried_step()` de cada
    trampa (lo aplica el host por el camino de daño de siempre, suavizado por el relleno y la cinta); el tropezón sale de un dado puro de
    (semilla, jugador, paso) que tira el host con el peligro que informa el dueño (giro, pendiente, ripio y
    banquina con `Route.ground_roughness()`, choque) y suelta la caja con golpe de 6 m/s; rebote y crujido de la
    caja (solo la malla) y consejo "Correr con la caja la sacude" (`tutorial_catalog.gd`). Números en
    `docs/parametros-diseno.md`; diseño en `docs/jugabilidad-paquetes-rescate.md`. El cacareo de la gallina del
    Ruidoso al correr no se hizo (solo se agita); la caja cruje con el sonido de madera de siempre.
- [x] **N-115.3** Clip `Run` nuevo en `art/rounded_character/animation_library.py` (zancada con fase de
  vuelo, brazos más abiertos) y elegido por `PlayerAnimator` por velocidad, con la misma histéresis que
  Walk/Stroll. En primera persona: balanceo más marcado y el FOV se abre un poco (+4°, suavizado).
  Pasos más rápidos en el sonido.
  - [x] Parte de código: `PlayerAnimator` elige `Run` por velocidad con histéresis (entra sobre 4,6 m/s, sale
    bajo 4,0) y, si la librería no lo tiene, reproduce Walk acelerado (`RUN_FALLBACK_MAX_SCALE` 1,9); primera
    persona con FOV +4° suavizado y balanceo x 2,6; pisadas nuevas (`synth_audio_steps.gd`, `FOOTSTEP_DB` en
    `world_mix.gd`) al ritmo de la carrera. Hoy no había pisadas de ningún tipo: solo suenan corriendo.
  - [x] **Clip `Run` en Blender** (`art/rounded_character/animation_library.py` + reexportar el glb). Hecho
    (rama `nacho/N-115-run-clip`): `GAITS['Run']`, 0,33 s en loop a 6 m/s, 6 pasos/s de 1 m (un ciclo = 2 m = una
    pisada sonora), vuelo de ~0,09 s, torso inclinado, rebote marcado, brazos abiertos con más recorrido;
    `check_clearance` 52 (Walk 58). `PlayerAnimator` lo encuentra (sin respaldo) y su escala baja hasta 4/6 para
    que no patine al salir. Tests: `test_player_sprint`, `test_character_motion`. Aviso
    `docs/avisos/2026-10-01-n115-run-clip.md`.
  - [ ] Captura del clip con `revisor-visual` (en juego). Revisado en Blender con renders laterales y de ¾.
- [x] **N-115.4** Red: el estado de carrera viaja como `anim_state` (el dueño lo decide, los demás solo
  reproducen el clip).
  Hecho: `anim_state` = `Run` + `locomotion_speed` (ya replicados); los otros pares cuentan las pisadas y el
  rebote de la caja desde eso. RPCs nuevos en el hijo `Sprint` del jugador (`submit_run_step`, `play_stumble`):
  `NetworkManager.PROTOCOL_VERSION` sube a 5. Falta `auditor-red`.
- Test: `test_player_sprint.gd` (velocidad al correr con y sin caja, no corre sentado ni manejando, correr
  con caja daña más que caminar, el tropezón deja la caja en el suelo y es igual en host y cliente con la
  misma semilla, elige `Run`, el otro par ve el mismo clip). Captura del clip con `revisor-visual`.
  Hecho el test (`test_player_sprint.gd`, más `test_world_audio_levels` con la pisada); la captura del clip
  espera al clip de Blender. Aviso: `docs/avisos/2026-09-30-n115-correr.md`.
- Hecho cuando: se corre a pie en la ruta y en el depósito, con animación propia, y correr con una caja
  la sacude y puede hacerte tropezar.

### N-116 · Parada final: estacionamiento de camiones de reparto — A · `Opus 5.5 · high` · Aviso: no · **[x] rama `nacho/N-116-goal-lot`** (revisión visual hecha 2026-10-01; queda N-116.5)

> Hoy la meta es un arco de hormigón con la palabra META, una barrera y un `GoalArea`
> (`route.gd::_build_goal()`): se termina al pasar por abajo. Pedido del usuario: una parada final de
> verdad, la base de la empresa en el pueblo, donde se deja el camión.

- [x] **N-116.1** Playa de estacionamiento "Base Take My Package — {pueblo}" en lugar del arco (sacarlo de
  `route.gd` a `route/route_goal_lot.gd`): explanada plana de ~40 × 30 m al final de la ruta, asfalto con
  cordón, cerco perimetral, cartel grande de la empresa, garita con barrera que se levanta cuando llega el
  camión, faroles que se prenden de noche (`WorldMood`), 5-6 bahías pintadas con camiones de la empresa
  estacionados y **una bahía libre marcada** (número grande pintado, flecha y conos). Los camiones
  estacionados son sólidos: chocarlos es un golpe normal (`vehicle_impact`), la carga lo siente.
  - `route_goal_lot.gd` (`RouteGoalLot`) y `route_goal_lot_kit.gd` (cajas de colores fundidas en una malla,
    modelos fundidos en una malla por modelo: ~40 draw calls en total). Losa de 40 × 30 m con cordón y cerco
    (paneles translúcidos), portón de 9 m con garita y barrera que sube al acercarse un camión (un `Area3D` de
    52 × 66 m que cubre la playa y su entrada; también despierta a los repartidores), galpón al fondo con seis portones y el cartel de la
    empresa en el techo ("BASE TAKE MY PACKAGE — {pueblo}"; el pueblo es el último nombre de
    `TownSign.names_for_seed`, que ningún pueblo de la ruta usa). Seis bahías de 4,2 × 8,8 m: cinco con el
    camión de referencia (`truck_reference_lowpoly.glb`, un `MultiMesh`, puertas cerradas, sin
    estantes y con vidrios translúcidos) más un colisionador de caja cada uno; la libre (sorteada por semilla, numerada
    desde 1-4) tiene el piso verde, el borde amarillo, el número pintado de 3 m, la flecha, cuatro conos
    (`RigidBody3D` dormidos: se voltean si los golpeás) y un cartel "LIBRE" sobre el galpón.
  - Terreno: `route_terrain.gd` suma `platforms` (rectángulo nivelado con alto propio, girado con el camino,
    con 12 m de mezcla): el suelo bajo la losa y el galpón queda a la misma altura que el final del camino.
    La ruta reserva `clear_zones` (nada plantado) y el camino denso sigue hasta la bahía (`_path_points`: GPS y
    control de "fuera de ruta"). `route_planner.gd`: el último tramo también termina calmo (recta o curva
    suave en los últimos ~150 m), así no hay puente, riel ni túnel sobre la playa.
  - Faroles: cuatro, con vidrio encendido de noche (`LowpolyMaterials.light_up`), halo (`night_flares.gd` lee
    `halo_points`) y una luz `OmniLight3D` cada uno más otra sobre la bahía libre; la luz se apaga en calidad
    baja (`WorldQuality`), quedan el brillo y el halo.
- [x] **N-116.2** Terminar = estacionar: la partida termina cuando el camión queda **frenado dentro de la
  bahía libre** (misma regla que la zona de entrega: casi quieto durante ~1,5 s), no al cruzar un arco. El
  GPS y la guía apuntan a la bahía ("Estacioná en la bahía 7"). Estacionar derecho (menos de 10° de
  desvío) suma una línea chica en los resultados, "Estacionamiento prolijo" (toca `run_manager.gd`,
  zona compartida: aviso; si complica, queda para después).
  - Adentro = la nariz y la cola del camión (dos puntos de su eje) entre las líneas de la bahía;
    `RouteGoalLot.bay_occupied_changed` reemplaza a `GoalArea` y `route.gd` lo traduce a
    `delivery_entered/exited` / `is_vehicle_in_delivery`, así que `level_base.gd` (frenado ≥ 1 s a < 1,5 m/s,
    lo decide el host) no cambió. GPS: "BAHÍA N" y flecha a `route.goal_target()`; el nombre del tramo dice
    "Estacioná en la bahía N"; `HUD_ARRIVED` / `HUD_BACK_TO_ZONE` hablan de la bahía.
  - "Estacionamiento prolijo" sin tocar `run_manager.gd` (no hay aviso): la playa está en el grupo
    `run_stories` y `RunManager.world_stories()` ya le pide `result_stories()` al terminar (host); mide el
    desvío del eje del camión con el de la bahía (de frente o de culata) y da la línea con menos de 10°.
- [x] **N-116.3** Vida en la base: un par de repartidores NPC (`DepotWorker`) descargando otro camión, un
  carro con cajas, una manguera de lavado. Nada que se mueva por la bahía libre.
  - Otro camión de la empresa, con las puertas traseras abiertas, en un costado; un repartidor va y viene
    entre la cola y el carro, otro revisa la carga (frases con `tr()`); carro con cajas y cajas en el suelo;
    del otro lado una canilla con manguera verde y charco. Los repartidores duermen (`process_mode`
    deshabilitado) hasta que un camión entra al área de la playa.
- [x] **N-116.4** Es el último plano antes del diario (N-606): la órbita de resultados muestra el camión
  estacionado en la base.
  - `results_orbit.gd`: con el camión en la bahía no da la vuelta (el galpón y los camiones vecinos tapan):
    oscila 0,9 rad a cada lado del pasillo, a 12 m y 4,5 m de alto, mirando la cabina, con el cartel de la
    empresa de fondo (`SpectatorCamera.orbit_results` lo pide a la playa).
- Endless no tiene meta: no cambia.
- Test: `test_route_goal_lot.gd` (la playa queda plana y sin árboles ni casas encima, la bahía libre es
  alcanzable desde la ruta, pasar sin frenar no termina, frenar en la bahía sí, igual en host y cliente);
  actualizar los tests que buscan `GoalArch*`/`GoalArea`. Capturas de día y de noche con `revisor-visual`.
  - [x] `test_route_goal_lot.gd` (nuevo: 4 rutas construidas + playas sueltas + un nivel entero) y ajustados
    `test_run_ends_at_goal`, `test_dashboard_gps` y `route_smoke_check`. Ningún test nombraba `GoalArch*`.
    El otro camino de host/cliente: la playa sale entera de la semilla y solo el host termina la partida
    (sin RPC nuevo ni cambio de `PROTOCOL_VERSION`).
  - [x] ~~Capturas de día y de noche (`revisor-visual`): `tests/render_goal_lot.gd -- --mood=soleado_dia` y
    `--mood=soleado_noche` (aproximación, portón, bahía, vista aérea, descarga y el plano de resultados). Mirar
    sobre todo: si el cartel y la bahía libre se leen desde el asiento del conductor (`check_driver_sightline.gd`),
    el tamaño de los textos y el remate de la losa contra el camino.
    **[x] Hecho (2026-10-01, rama `nacho/N-116-visual-review`)** — 7 planos × día/noche en la PC con GPU, sin
    bloqueantes: losa contra el camino limpia (sin escalón ni z-fighting), sin mallas negras ni objetos flotando,
    camiones, repartidores y faroles bien; el cartel de la base se lee desde `gate`/`bay` y la bahía libre se
    encuentra de día y de noche por contraste. `check_driver_sightline.gd` no sirve acá (solo mira el propio
    camión): la vista del conductor la dan `approach`, `approach_near` y `bay` (ojo a 2,3 m). Lo mejorable va a N-116.5.
- [ ] **N-116.5** Bahía libre legible desde la entrada y de noche — C · necesita PC. Origen: revisión visual
  2026-10-01. En `approach_near` (≈40 m) el cartel "LIBRE n" mide ~25 px y no se lee, y el número pintado se ve
  como una mancha; de noche ni la bahía libre ni el cartel de la base tienen luz propia (a 90 m la base son
  puntos de faroles). Hacer: cartel "LIBRE n" más grande y emisivo (`LowpolyMaterials.light_up`) o una baliza
  sobre la bahía libre; spot u emisión sobre la bahía de noche; el "n" del piso más grueso y sin deformar de
  cerca; el charco de la manguera como decal de borde suave en vez de un rectángulo plano. Hecho cuando en
  `render_goal_lot.gd` el "LIBRE n" se lee en `approach_near` de día y de noche (revisado con `revisor-visual`).
  Con `constructor-mundo` (o `artista-vfx` para la luz); tests `goal_lot`.
- Hecho cuando: la ruta termina en una base con bahías y la partida se cierra al dejar el camión en su
  lugar.

### N-312 · Personaje flaco y alto — A · `Opus 5.5 · xhigh` · Aviso: sí (apariencia y personalización del jugador, de Slatex) · ⏸ personajes en pausa (S-311)
Origen de la pausa: auditoría integral 2026-09-30, A-102.

> Un segundo cuerpo jugable, en contraste con el redondeado de hoy: flaco, alto, cuello y brazos largos.
> Se elige en la personalización; los dos juegan igual.

- [ ] **N-312.1** Modelo en `art/tall_character/`, con el mismo camino que `art/rounded_character/`
  (`build_character.py`, `head_shape.py`, render de revisión, validación en Godot): **mismo esqueleto y
  mismos nombres de huesos**, camiseta con el color del equipo, manos tipo manopla, zapatos grandes. Se
  exporta a `assets/models/characters/sm_char_player_tall.glb`. La cara (`CharacterFace`) necesita la
  forma de la cabeza nueva (`HEAD_*` por cuerpo; ver `LEEME.md` del redondeado).
- [ ] **N-312.2** Clips para sus proporciones con `animation_library.py`: Idle, Walk, Stroll, Jump,
  PickUpPackage, PickUpHigh, Sit, TurnInPlace y el `Run` de N-115 (la zancada sale del largo de pierna,
  los pies no deben patinar). Revisar la pose de manejo (IK del volante y pedales) y la de carga.
- [ ] **N-312.3** Elegir cuerpo en el panel de personalización ("Redondeado / Flaco y alto"), guardado y
  replicado con el resto de la apariencia (`player_appearance.gd`). **La cápsula de colisión y la altura
  de la cámara no cambian**: el cuerpo es solo visual, así nadie tiene ventaja ni se rompen puertas,
  asientos o estantes.
- [ ] **N-312.4** ⏸ personajes en pausa (S-311) · Opcional: el Jefe del diario (N-606) y los NPC del depósito usan este cuerpo (hoy los NPC
  siguen con el modelo viejo `sm_char_player_lowpoly.glb`).
- Test: ampliar `test_player_character.gd` para los dos cuerpos (huesos que usa el juego, clips
  presentes, cara ni enterrada ni flotando) y un caso de red donde cada par ve el cuerpo que eligió el
  otro. Capturas de frente, tres cuartos, caminando, corriendo y manejando con `revisor-visual`.
- Hecho cuando: se puede jugar con el personaje flaco y alto, con todas sus animaciones, y los demás lo
  ven.

### N-606 · El diario del día siguiente — A · `Opus 5.5 · xhigh` · Aviso: sí (`hud_results.gd`, apodo en jugador y personalización)

> Diseño completo en [`docs/diario-final.md`](diario-final.md). Al terminar el recorrido, escena de ~30 s
> que se puede saltar: a la mañana siguiente el Jefe del depósito lee *El Eco de {pueblo}* con 3-5 noticias
> cómicas armadas con lo que pasó en la partida (pedidos que no llegaron, cajas abandonadas, averías,
> fauna atropellada, la gallina sin cinchar), con planos de cine (general, diario giratorio, insertos,
> reacción, sobre el hombro). Decisiones del usuario: lee siempre el Jefe, dura 30 s, se puede saltar,
> y los chistes usan un **apodo del juego**, no el nombre de Steam.

- [x] **N-606.1** Apodo del jugador: se escribe en la personalización (16 caracteres); si queda vacío, el
  juego asigna uno gracioso con la semilla del jugador; viaja con la apariencia.
- [x] **N-606.2** Contenido: `RunChronicle` (hechos de la partida desde el `EventBus`), `NewsDesk`
  (redacción pura, determinista por semilla), catálogo `data/newspaper/stories.json` con 3+ variantes por
  hecho, relay del host `newspaper_ready` (ids y casillas, no texto) y la página 2D mostrada antes de la
  tarjeta de resultados. Tests `test_news_desk.gd` y `test_run_chronicle.gd`.
- [x] **N-606.3** La escena (2026-10-01): set propio en su `World3D`, el Jefe sentado, diario 3D con las
  páginas en `SubViewport` (`NewspaperSpread`, diagramación del estudio N-606.6 con las noticias reales),
  cámara por rieles (`data/newspaper/shots.json`, módulo nuevo `camera_rail`), un primer plano por noticia,
  bandas en el general y la reacción, saltar manteniendo el botón 0,6 s, opción «Diario al final» en
  Opciones y la tarjeta de resultados esperando `newspaper_finished`. Reemplaza a la página 2D. Test
  `test_newspaper_scene.gd`, capturas con `tests/render_newspaper_scene.gd`. La serif OFL del relleno
  llegó con N-606.5.
- [ ] **N-606.4** ⏸ personajes en pausa (S-311) · Pulido: clips del Jefe (`SitRead`, `OpenPaper`, `TurnPage`, `LowerPaper`, `SpitTake`,
  `CirclePen`, `SipMate`), diario giratorio, curva de página, expresiones, audio (gallo, "¡extra!",
  papel, escupida) y hechos nuevos (vuelco, perro, tren).
- [x] ~~**N-606.5** Fotos reales: captura chica en el momento de un hecho (ciervo, gallina que salta,
  puerta que se abre) que va al diario con trama de puntos.~~ **[x] Hecho (2026-10-01)** — `NewsPhotographer`
  (cada jugador saca su foto del hecho, sin red) con el módulo nuevo `press_photo` (`PressPhoto`, trama de puntos);
  `NewspaperSpread` la imprime bajo la tapa con epígrafe y primer plano propio; PT Serif OFL empaquetada para el
  relleno; acercamiento sin la nariz del Jefe asomando. Test `test_newspaper_scene.gd` y
  `modules/press_photo/tests/test_press_photo.gd`; detalle en `diario-final.md` («Fotos y tipografía»).
- [x] **N-606.6** Estudio visual de la escena (2026-10-01): set, Jefe con camisa y bigote, diario de
  papel de diario con diagramación real (columnas, clasificados, foto con trama), hojas que se caen, y un
  primer plano legible por noticia. Prueba de dirección de arte para N-606.3, no la cinemática:
  `scripts/tools/newspaper_concept/`, capturas en `art/newspaper/review/`, decisiones en
  `diario-final.md` («Estudio visual de la escena»).
- Hecho cuando: cada entrega termina con el diario de esa partida, igual para todos los jugadores, y se
  puede saltar.

---

## Heredadas de Slatex (S-xxx, 2026-09-29)

> Pedido del usuario (2026-09-29): **todas las tareas de Slatex pasan a esta lista** y Slatex queda con una
> sola, S-311 (personaje 2.0 de gelatina, en `docs/tareas-slatex.md`). Conservan su ID `S-xxx` porque
> commits, tests, avisos y auditorías las nombran así.
>
> - **Dominio**: los archivos siguen siendo de Slatex (`docs/colaboracion-equipo.md`), así que casi todas
>   tocan su dominio: **cada PR lleva un aviso en `docs/avisos/`**, aunque el campo diga `Aviso: no` (ese
>   campo se escribió desde el lado de Slatex). Donde una tarea diga "aviso en `colaboracion-equipo.md`",
>   vale `docs/avisos/`.
> - **Esfuerzo**: los modelos de ChatGPT se tradujeron a Opus 5.5 (Sol → mismo esfuerzo, Astra → `xhigh`,
>   Luna → `medium`/`low`).
> - **Orden**: van **después de M8**; entre ellas, el orden S-M1 → S-M5 de su tabla.
> - **Choques con S-311**: lo del cuerpo del jugador que Slatex va a rehacer en gelatina (ragdoll #101,
>   maniquí #102, accesorios #103 / S-305, emotes S-308) queda en pausa mientras S-311 esté abierta; si se
>   hace antes, que use el rig común para que el personaje de gelatina lo herede.

### Orden de las heredadas (hitos S-M1 a S-M5)

| Hito | Objetivo | Tareas |
|---|---|---|
| **S-M1 — Cerrar lo que está a medias** | Que ningún sistema del juego quede anunciado y sin terminar. | S-101, S-102, S-103, S-104, S-105, S-203, S-210, S-804 |
| **S-M2 — Base técnica para lo que sigue** | Partir los archivos gigantes antes de sumarles UI; red robusta. | S-201, S-202, S-204, S-206, S-209 |
| **S-M3 — Onboarding y UX** | Que alguien que nunca jugó entienda qué hacer sin que se lo expliquen. | S-106, S-107, S-501, S-502, S-504, S-505, S-506, S-508, S-510 |
| **S-M4 — Balance medido y juice** | Números justificados por simulación; fallas que den ganas de clipear. | S-108, S-109, S-110, S-111, S-301, S-302, S-310, S-401 a S-404, S-601 a S-604 |
| **S-M5 — Preparación de lanzamiento** | Inglés, logo, telemetría. Tienda, cápsulas, press kit y logros (S-901, S-903, S-904, S-907) ⏸ pospuestos a la iteración de lanzamiento; capturas (S-902) y monetización (S-906) hechas. | S-509, S-306, S-905, S-805 |

Dentro de un hito, el orden de la tabla es el recomendado.

---

### 2. Programación y arquitectura técnica

#### S-201 · Partir `prototype_hud.gd` (1176 líneas) en componentes — A · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

Antes de sumar todo lo de UX (pilar 5), porque cada tarea de UI toca este archivo.

- [x] (commits `d324ecd`, `780a489`, `15ede48`, `44ff262`, `f70b064`) **S-201.1** Listar qué usan los tests del HUD (`grep -n "hud\." tests/test_hud_flow.gd` y los
  demás) para no romper esos nombres.
- [x] (commits `d324ecd`, `780a489`, `15ede48`, `44ff262`, `f70b064`) **S-201.2** Crear `scripts/ui/hud/`: `hud_cargo_panel.gd` (filas de carga e íconos),
  `hud_prompts.gd` (interacción, tapa de caja, atajos), `hud_notices.gd` (toasts, eventos, pings,
  avisos del depósito), `hud_results.gd` (pantalla de resultados), `hud_pause.gd` (pausa).
  `prototype_hud.gd` queda como el que los arma y conecta señales (objetivo: < 350 líneas).
- [x] (commits `d324ecd`, `780a489`, `15ede48`, `44ff262`, `f70b064`) **S-201.3** Mover **sin cambiar comportamiento**. Un commit por componente, tests del HUD verdes
  en cada uno (`tools/run-tests.sh hud score spectator ping`).
- [x] (commit `f70b064`) **S-201.4** Captura con `tests/render_hud.gd` antes y después: tienen que verse iguales.

#### S-202 · Partir `player.gd` (1131 líneas) — B · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

- [x] (commits `bb4a862`, `f168819`, `42d5aa2`) Separar en nodos hijos con script propio: `player_interaction.gd` (alcance, avisos, E),
  `player_carry.gd` (caja en mano), `player_seat_pose.gd` (pose sentado, manos que atienden).
- [x] (commits `f168819`, `42d5aa2`) **Las funciones `@rpc` se quedan en `player.gd`** (Godot resuelve la RPC por la ruta del nodo; si
  se mueven, se rompe la red). Esas funciones solo delegan.
- [x] (commits `bb4a862`, `f168819`, `42d5aa2`) Tests verdes: `interaction`, `seat`, `carry`, `player`, `driver` y `look`.

#### S-203 · Detectar camión atascado también en el modo entrega — A · `Opus 5.5 · high` · Aviso: sí (`level_base.gd`) · **[x]**

Nacho encontró (su #97) que el camión puede quedar encajado sin volcar ni salir de la ruta;
`level_endless.gd` ya lo detecta, `level_base.gd` no.

- [x] (commit `204cfdc`) Copiar la misma regla (6 s casi quieto con el motor pedido → termina la partida con "La
  camioneta quedó atascada"), **sin** contar el tiempo parado en el depósito, en una casa, o con el
  conductor fuera del asiento.
- [x] (commit `204cfdc`) Test en `test_stuck_detection.gd`: parado en depósito, casa o sin conductor no dispara;
  encajado contra un obstáculo con el acelerador pedido sí.

#### S-204 · Test automático de dos procesos (reemplaza "requiere playtest de red") — A · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

Cierra lo que quedaba de #79 (cosméticos en dos clientes) y #96 (dos jugadores con el mismo objeto).

- [x] (commit `200cb1b`) **S-204.1** `tests/net_pair.gd`, sobre el patrón de `tests/net_smoke.gd` (ENet en localhost,
  `--host` / `--client`): el host carga `level_base.tscn`; el cliente se une con un uniforme elegido.
- [x] (commit `200cb1b`) **S-204.2** Chequeos: el host ve el `cosmetic_id` del cliente; los dos intentan agarrar la misma
  caja en el mismo frame y solo uno la tiene; el cliente se sienta en un asiento ocupado y es rechazado;
  el cliente suelta una caja a mitad de traspaso y queda en el piso en los dos procesos.
- [x] (commit `200cb1b`) **S-204.3** `tools/run-net-pair.sh` que lanza los dos procesos y junta los códigos de salida.
  Agregado a CI como job aparte: 15-16 s en dos ejecuciones locales.

#### S-205 · Respuesta inmediata al mantener, aunque haya lag — B · `Opus 5.5 · xhigh` · Aviso: no

- [x] (rama `nacho/S-205-local-hold-feedback`) Verificado: el botón y el `tick` de la tarjeta de cuidado ya
  salían del input local; el paso, el progreso, el aviso sobre la caja y la inclinación del cuerpo sentado
  vienen del host. Ninguna mano reacciona a sostener (con o sin lag). `--fake-lag=<ms>` (y `--net-sim` en
  LAN), solo en debug, retrasa `submit_care_input` y `submit_tender_input`
  (`package/tender_input_lag.gd`).
- [x] (rama `nacho/S-205-local-hold-feedback`) "Estoy sosteniendo" local el mismo frame:
  `player/player_hold_feedback.gd` (flag `holding`, sin red) y brillo cálido de la caja
  (`package_feedback.set_local_grip`). La integridad sigue viniendo del host.
- [x] (rama `nacho/S-205-local-hold-feedback`) Test `tests/test_local_hold_feedback.gd`: con 150 ms de
  retraso el flag y el brillo cambian en la misma llamada del input y el host no recibe nada hasta el
  `flush`.
- [ ] ⏸ Pose de manos al sostener: no existe hoy y tocaría el cuerpo (en pausa mientras siga abierta
  S-311). Cuando se haga, que lea `PlayerHoldFeedback.holding`.

#### S-206 · Errores de conexión que un jugador entienda — A · `Opus 5.5 · high` · Aviso: sí (`network_manager.gd`) · **[x]**

- [x] (commit `03bd4e1`) **S-206.1** `NetworkManager.PROTOCOL_VERSION := 1` y enviarla en el handshake. Si no coincide, el
  host rechaza con motivo `version`. (El handshake ya cambió dos veces y hoy un cliente viejo solo ve un
  timeout.)
- [x] (commit `03bd4e1`) **S-206.2** En `main_menu.gd`, `_on_session_failed(reason)` traduce cada motivo a un texto con
  qué hacer: "El anfitrión tiene otra versión del juego: actualicen los dos", "No hubo respuesta en 8 s:
  revisá la IP y que el firewall de Windows permita Take My Package (ver README)", "La sala está llena".
- [x] (commit `03bd4e1`) **S-206.3** Test `tests/test_connection_errors.gd`: cada motivo muestra su texto.

#### S-207 · Unirse por código corto en LAN — C · `Opus 5.5 · high` · Aviso: sí (`main_menu.gd`, `hud.gd`) · **[x]**

- [x] (rama `nacho/S-207-room-code`) `scripts/ui/room_code.gd` (estático, `RoomCode`): IPv4 + puerto ↔ código sin O/0/I/1.
  Decisión: el puerto por defecto es implícito (8 caracteres, `K7QM-4TXA`); otro puerto suma 4 (12). Último
  carácter de control (suma ponderada mod 32). El HUD del anfitrión LAN muestra el código en vez de la IP;
  "Unirse" acepta código o IP (`RoomCode.resolve`). Steam no aplica. Aviso `docs/avisos/2026-09-30-s207-room-code.md`.
- [x] (rama `nacho/S-207-room-code`) Test `tests/test_room_code.gd`: ida y vuelta para 1000 direcciones, todo símbolo mal
  tipeado rechazado con mensaje, menú y HUD.

#### S-208 · Rendimiento del jugador, paquetes y UI — B · `Opus 5.5 · high` · Aviso: no · **[x]**

- [x] (rama `nacho/S-208-depot-bench`) `tests/bench_depot.gd`: depósito con 14 cajas y 5 jugadores simulados, 600 frames; medir
  `Performance.TIME_PROCESS` y el tiempo de `package_feedback.gd` y del HUD. `TIME_PROCESS` se imprime pero
  no se juzga: en headless por software salta varios ms entre pasadas iguales; la meta se mide llamando a mano
  los `_process` de los 14 `package_feedback` y del HUD.
- [x] (rama `nacho/S-208-depot-bench`) Meta: < 1,5 ms por frame entre paquetes + HUD. Ya se cumplía (0,67 ms); igual se
  sacó el punto caliente: `refresh_hint` reescribía BBCode y color cada frame (0,28 ms). Ahora 0,41 ms (p95 0,59).
  `hud_notices` y `package_feedback` también escriben solo si cambia. Queda: `keycaps(_base_hint())` se arma
  cada frame (~76 µs), no vale el caché. Aviso `docs/avisos/2026-09-30-s208-depot-bench.md`.
- [x] (rama `nacho/S-208-depot-bench`) Resultado anotado en el README → Rendimiento.

#### S-209 · Jugador que se desconecta en medio de la partida — A · `Opus 5.5 · xhigh` · Aviso: sí (`level_base.gd`) · **[x]**

- [x] (commits `c77194f`, `d20df06`) Cuando un peer se va: su caja en mano queda en el piso donde estaba; si estaba sentado, el
  asiento se libera; si conducía, el camión frena solo; su casa asignada sigue esperando.
- [x] (commit `5dd2771`) Probarlo con `tests/net_pair.gd` (S-204): el cliente se cierra con caja en mano y el host sigue sin
  errores.

#### S-210 · Guardados que no se corrompen — A · `Opus 5.5 · high` · Aviso: sí (`run_manager.gd` para el leaderboard) · **[x]**

- [x] (commit `c694bdf`) Función común `scripts/core/safe_json.gd`: escribe en `<archivo>.tmp` y renombra
  (`DirAccess.rename`), así un corte de luz no deja el archivo a medias; al leer, si el JSON es
  inválido, lo renombra a `<archivo>.bad` y devuelve el valor por defecto.
- [x] (commit `11328c1`) Usarla en `unlock_manager.gd`, en la campaña (S-105) y en el leaderboard de `run_manager.gd`.
- [x] (commit `11328c1`) Test `tests/test_safe_json.gd`: archivo truncado → no crashea, crea `.bad`, perfil por defecto.

---

### 3. Arte y dirección visual

#### S-301 · Íconos de Líquido, Explosivo y Hostil — A · `Opus 5.5 · medium` para el prompt, generación de imagen aparte · Aviso: no · **[x]**

El HUD ya tiene un ícono transparente propio para cada una de las 7 trampas
(`assets/ui/icons/tx_ui_trap_*_256.png`).

- [x] (commit `81ee0e3`) Generarlos con el mismo estilo que los 4 existentes: `art/tools/comfy_generate.py` con
  `art/prompts/estilo-base.md` (o la generación de imágenes, pasándole los 4 íconos de
  referencia). 256×256, fondo transparente, silueta legible a 42 px.
- [x] (commit `81ee0e3`) Nombres: `tx_ui_trap_liquid_256.png`, `tx_ui_trap_explosive_256.png`, `tx_ui_trap_hostile_256.png`.
  Mapearlos en `UiTheme.trap_icon()`.
- [x] (commit `81ee0e3`) Registrar cada imagen en `art/ai-registro.md` (declaración de IA de Steam) y en
  `docs/inventario-assets.md` §1.
- [x] (commit `81ee0e3`) Test `tests/test_trap_icons.gd`: cada `data/traps/*.tres` tiene ícono propio (ninguno cae en el
  genérico).

#### S-302 · Contenidos propios para cada trampa — B · `Opus 5.5 · high` (Blender Python) · Aviso: no · **[x]**

Las siete trampas ya tienen contenidos propios: diez modelos en total, con una segunda opción para
Equilibrio, Frágil y Ruidoso (`data/traps/*.tres` → `contents`).

- [x] (commit `bc24f07`) Modelos nuevos con `assets/tools/build_cargo_packages.py` (mismo esquema de nodos `Filler`,
  `Intact`, `Damage`, `Ruined`): **Líquido** → bidón de leche de vidrio; **Explosivo** → caja de fuegos
  artificiales; **Hostil** → mapache en una jaula de mimbre; **Equilibrio** → torre de copas (la torta
  queda como segunda opción).
- [x] (commit `bc24f07`) Un `.tres` en `data/contents/` por modelo y agregarlo al `contents` de su trampa. Segundo
  contenido para Frágil (lámpara antigua) y Ruidoso (cachorro) para que no se repitan siempre.
- [x] (commit `bc24f07`) Capturas con `tests/render_packages.gd` (revisadas en ventana: los diez
  contenidos quedan dentro de sus cajas).
- [x] (commit `bc24f07`) `test_package_unboxing.gd` ampliado: cada contenido tiene los 4 nodos.

#### S-303 · Íconos de acción del HUD — B · generación de imagen + `Opus 5.5 · high` para integrar · Aviso: no · **[x]**

- [x] (commit `d14cc56`) Agarrar, soltar, sentarse, timbre, foto, bocina, ping, abrir caja, usar carta. 128×128, mismo
  estilo que los de trampa. `assets/ui/icons/tx_ui_action_<acción>_128.png`.
- [x] (commit `d14cc56`) `UiTheme.action_icon(id)`; los avisos de interacción muestran ícono + tecla + texto corto.

#### S-304 · Celular en la mano y marco de la cámara — B · `Opus 5.5 · high` · Aviso: sí (`presentation/phone_camera.gd` no tiene dueño en el reparto)

- [ ] ⏸ Mostrar `models/props/handheld/sm_prop_phone.glb` en la mano derecha del viewmodel mientras la
  cámara del celular está abierta (hoy el GLB está sin usar, `inventario-assets.md` §2). **Ojo
  (2026-09-24):** ya no hay manos de primera persona (pedido del usuario: nada de manos que no sean
  del personaje), así que el celular no puede colgar de una; ver aviso en `colaboracion-equipo.md`.
  ⏸ (2026-09-30) Toca el cuerpo y las manos del personaje: en pausa mientras siga abierta S-311.
- [x] (rama `nacho/S-304-phone-frame`) Marco de UI del celular (bordes redondeados, hora, batería, botón de obturador) como `Control`
  en `scripts/ui/phone_frame.gd`. `PhoneFrame`: bisel con esquinas interiores redondeadas (mismo
  encuadre que antes), barra de estado con hora (arranca según `WorldMood` día/atardecer/noche y avanza
  1 min cada 6 s) y batería decorativa, obturador en el bisel derecho conectado a
  `PhoneCamera.shoot` (con el mouse capturado es decorativo: el clic ya dispara por la acción). Test `tests/test_phone_frame.gd`.

#### S-305 · Accesorios cosméticos 3D — C · `Opus 5.5 · high` · Aviso: no

- [ ] 4 accesorios low-poly con script de Blender: gorra, chaleco reflectivo, casco de obra, mochila
  térmica. `models/characters/accessories/`.
- [ ] Engancharlos con `BoneAttachment3D` (cabeza / columna) en `player.tscn`, uno por categoría.
- [ ] Desbloqueos en `UnlockManager.COSMETICS` y columna nueva en `cosmetics_panel.gd`; replicar
  `accessory_id` como `cosmetic_id`.

#### S-306 · Logo como imagen — B · generación de imagen + `Opus 5.5 · medium` · Aviso: no · **[x]**

- [x] (commit `004bb8b`) Wordmark "TAKE MY PACKAGE" en PNG transparente 2048 px de ancho, a partir de `UiTheme.logo()`
  (Lilita One + cinta amarilla), más una versión apilada cuadrada. `assets/ui/logo/`.
- [x] (commit `004bb8b`) Usarlo en el menú en lugar del logo armado con tipografía. Es la base de las cápsulas (S-903).

#### S-307 · Ilustración de fondo de resultados — C · generación de imagen · Aviso: sí (`hud.gd`) · **[x] rama `arte/S-307-results-backdrop`**

- [x] ~~La tripulación frente a la furgoneta al terminar la ruta, 1920×1080, con zona libre a la
  izquierda para el puntaje. Registrar en `art/ai-registro.md`.~~ **[x] Hecho (2026-10-01, sesión de arte)** —
  `assets/ui/backgrounds/tx_ui_results_background_1920.png` (Z-Image Turbo, semilla 902, prompt en
  `art/concept/results/prompt.txt`): porche con cajas entregadas a la izquierda, furgoneta de la marca a la derecha,
  tripulación chiquita en el medio, atardecer. Como la tarjeta de resultados va centrada, los sujetos quedan a los
  costados y el centro calmo (no "zona libre a la izquierda"). `hud.gd` la muestra solo en resultados
  (`results_backdrop`, setter de `overlay_mode`, `modulate` 0,8); test `test_hud_flow`. Aviso
  `docs/avisos/2026-10-01-s307-fondo-resultados.md`. Queda: las puertas traseras salen cerradas (abierta la
  lateral) y en 4:3 la tarjeta la tapa casi entera.

#### S-308 · Animaciones de emote — C · `Opus 5.5 · high` (Blender Python) · Aviso: no

- [ ] Saludar, señalar, pulgar arriba, agarrarse la cabeza: 4 animaciones cortas agregadas al GLB del
  jugador. Desde el 2026-09-24 el jugador es el personaje redondeado de Astra: se suman como
  poses nuevas en `art/rounded_character/build_game_export.py` (ver `assets/README.md`,
  "Personajes"). Las dispara la rueda de pings (S-505).

#### S-309 · Mantener al día la dirección visual del dominio — A · `Opus 5.5 · medium` · Aviso: sí (`especificaciones-visuales.md`, filas propias) · **[x]**

- [x] (commit `3480986`) Actualizar filas de jugador/paquetes/UI en `docs/especificaciones-visuales.md` y
  `docs/inventario-assets.md` §1-3 cada vez que se cierra una tarea de este pilar (antes #99).

#### S-310 · Fallas distintas por trampa (momentos para clipear) — B · `Opus 5.5 · high` · Aviso: no · **[x] PR #58**

Hoy toda caja arruinada tira el mismo confeti de cubitos.

- [x] (PR #58) En `package_feedback.gd`, un efecto por trampa: Frágil → esquirlas de porcelana; Líquido →
  salpicadura y charco en el piso; Explosivo → estallido de confeti y humo de colores (nada de fuego
  realista); Ruidoso y Hostil → el animal salta de la caja y escapa corriendo 3 s con física simple;
  Equilibrio → la torre se derrumba en piezas; Peso creciente → la caja se hunde con un golpe seco.
- [x] (PR #58, test en `test_ruin_effects.gd`; el animal de Ruidoso/Hostil corre 3 s como pide la tarea) Cada efecto dura < 2 s y se libera solo. Test en `test_ruin_feedback.gd` por trampa.

---

### 7. Producción y gestión de proyecto

#### S-701 · Esta lista como tablero — A · `Opus 5.5 · low` · Aviso: no

- [ ] Cada tarea cerrada: `[x]` + hash del commit en la misma línea. Si una tarea resulta más grande de lo
  pensado, partirla acá en subtareas antes de seguir.
- [ ] Una vez por semana, actualizar "Última actualización" y mover a "Hecho" lo cerrado del hito.

#### S-702 · Qué queda fuera del MVP (control de alcance) — A · `Opus 5.5 · medium` · Aviso: no · **[x]**

- [x] (commit `dbe3e48`) Sección nueva en `docs/plan-desarrollo.md` con la lista cerrada de lo que **no** se hace antes de
  Early Access: chat de voz propio, matchmaking público, cartas Prioridad e Información, tienda en ruta,
  tutorial jugable, más de 7 trampas, servidores dedicados, microtransacciones. Cualquier idea nueva se
  anota en una sección "Después del lanzamiento", no en esta lista.

#### S-703 · Avisos al día — A · `Opus 5.5 · low` · Aviso: sí

- [ ] Cada tarea con Aviso `sí` deja su entrada en `docs/colaboracion-equipo.md` en el mismo commit.
- [ ] Borrar de ese documento los avisos de más de un mes que ya no afectan a nadie (dejar solo los vigentes).

---

### 9. Negocio, marketing y distribución

> **⏸ Pospuesto (2026-09-28):** estamos en desarrollo y refinamiento, así que lo de publicar en Steam
> y promocionar el juego queda para una iteración de lanzamiento. Las tareas marcadas ⏸ no se trabajan
> ni cuentan como pendientes hasta que se reabra esta sección.
> S-905 sigue activa: es investigación de onboarding que alimenta a S-506.

#### S-901 · Texto de la página de Steam — B · `Opus 5.5 · medium` (redactar), `Opus 5.5 · medium` (revisar) · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

- [ ] `docs/marketing/steam-page.md` en español e inglés: descripción corta (≤ 300 caracteres), descripción
  larga con 5 viñetas de características, requisitos mínimos (GL Compatibility → hardware modesto),
  etiquetas (Co-op, Online Co-Op, Physics, Driving, Funny, Party Game).
- [ ] Una frase de gancho que diga los roles asimétricos: "Uno maneja. Los demás intentan que nada explote."

#### S-902 · Modo captura para imágenes y tráiler — B · `Opus 5.5 · high` · Aviso: no · ✅ (hecha pese a la pausa)

- [x] Tecla de depuración (F10, solo build de debug) que oculta todo el HUD y el viewmodel.
- [x] `tests/render_store_shots.gd`: 5 escenas fijas (depósito cargando, manejo con cajas en riesgo, entrega
  en una casa, caja explotando, resultados) a 1920×1080. Necesita ventana: la corrés vos.

#### S-903 · Cápsulas de Steam — C · generación de imagen · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

- [ ] Con el logo (S-306): tamaños vigentes (los viejos 460×215, 616×353 y 231×87 ya no se aceptan; verificar con las
  plantillas oficiales): header 920×430, small 462×174, main 1232×706, vertical 748×896, biblioteca capsule 600×900,
  hero 3840×1240 (sin texto, lo importante en el centro 860×380) y logo de biblioteca (1280 de ancho / 720 de alto,
  transparente); fondo de página 1438×810 opcional. La IA dibuja solo la escena y el logo real va encima
  (`tx_ui_logo_wordmark_2048.png`; el stacked para vertical y capsule). `assets/store/`. Registrar en `art/ai-registro.md`.
  Necesita PC (`artista-conceptual`, ComfyUI; la toma la sesión de arte). Detalle: `docs/marketing/estado-steam.md` §3.1.

#### S-904 · Press kit — C · `Opus 5.5 · medium` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

- [ ] `docs/marketing/presskit.md`: ficha (nombre, equipo, plataforma, precio objetivo $8-15, fecha
  tentativa de Early Access), descripción, características, logo, capturas (S-902), contacto.

#### S-905 · Cómo enseñan los competidores — B · `Opus 5.5 · medium` con búsqueda web · Aviso: no · **[x]**

- [x] Una página (`docs/marketing/onboarding-competidores.md`) comparando cómo PEAK, Lethal Company y
  Totally Reliable Delivery Service enseñan sus controles y sus reglas en los primeros 5 minutos, y qué
  tomar para S-506. Con fuentes. Hecha con Backseat Drivers y RV There Yet? sumados, 4 recomendaciones y
  4 tareas propuestas (rama `nacho/S-905-onboarding-research`).

#### S-906 · Registro de decisión de monetización — A · `Opus 5.5 · medium` · Aviso: no · ✅ (hecha pese a la pausa)

- [x] (commit `e61d923`) En `docs/plan-desarrollo.md`: precio único $8-15, sin microtransacciones, cosméticos solo se
  ganan jugando, actualizaciones gratis. Verificar que ningún cosmético del código tenga precio en dinero real.

#### S-907 · Logros — B · `Opus 5.5 · high` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

- [ ] Diseñar 15 logros atados a hitos que ya existen o que suma esta lista (primera entrega, primer
  explosivo desactivado, entrega perfecta con 4 casas, 10 rescates, sacar foto a una caja arruinada…).
  Tabla en `docs/plan-desarrollo.md` Fase 5.
- [ ] Sistema local en `UnlockManager` (`achievements` en el perfil) con toast. El puente a Steam queda para
  cuando haya AppID propio (hoy es el 480 de prueba).
- Nota lanzamiento 2026-10: no hay ninguna llamada `setAchievement`/`storeStats` en el código. El sistema local
  (`constructor-progresion`) se puede hacer sin AppID; el puente a Steam (`constructor-red`) espera a N-901.

---

### Para cuando haya playtesting (no se hace ahora)

Quedan registradas para no perderlas. Cuando se decida hacer playtesting, se usan los datos de
S-805 y los objetivos de S-108.

| Ítem viejo | Qué hay que observar |
|---|---|
| #41, #51, #59, #67 | Si los números de las trampas, ya ajustados por simulación (S-108), se sienten justos. |
| #47 | Tutorial con alguien que nunca vio el juego. |
| #94, #95 | Cada trampa sola y las 7 combinadas en una entrega. |
| #98 | Partida real con 4-5 personas. |

---

### Qué pasó con la lista anterior (1-100)

- **Cerradas** (89): modelado y animación del jugador y de los paquetes, interacción paquete-jugador,
  progresión y desbloqueos, las trampas Líquido/Explosivo/Hostil, cosméticos, opciones, HUD y
  resultados, guía para agregar trampas. El detalle de cada una está en el historial de git de este
  archivo (`git log -p docs/tareas-slatex.md`).
- **Reubicadas** en esta lista:
  #41/#51/#59/#67 (balance) → S-108 · #79 (cosméticos con dos clientes) y #96 (dos jugadores con el mismo
  objeto) → S-204 · #99 (especificaciones visuales) → S-309.
- **Movidas a "Para cuando haya playtesting"**: #47, #94, #95, #98.
- **Encontradas a medias en el relevamiento del 2026-09-24** (nunca estuvieron en la lista vieja):
  eventos de ruta sin resolución (S-101), mérito que nadie otorga (S-102), cartas sin uso (S-103),
  votación que nunca se abre (S-104), campaña que no se guarda (S-105), contenidos repetidos entre
  trampas (S-302), íconos faltantes para 3 trampas (S-301).

## Para cuando haya playtesting (no se hace ahora)

| Ítem viejo | Qué hay que observar |
|---|---|
| #55 | Si la variedad del Endless se siente bien o hace falta más curaduría. |
| #98 | Si los tramos se sienten repetitivos después de varias partidas. |
| #83 (parte) | Mezcla de audio con oído, después de la medida de N-404. |
| — | Si el largo medido en N-102 se siente corto o largo jugando de verdad. |

---

## Qué pasó con la lista anterior (1-127)

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Bugs de multijugador del playtest (143-149) — reporte directo del usuario, 2026-09-24

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Segunda tanda de multijugador (151-166) — cacería de `cazador-bugs`, 2026-09-24

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).

## Playtest del 2026-09-25 (172-177) — reporte directo del usuario, jugando solo de noche

Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md).
