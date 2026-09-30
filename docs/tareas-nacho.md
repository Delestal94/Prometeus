# Tareas de Nacho — Vehículo, Ruta, Ambientación y Depósito

> Reescrita entera con el mismo formato que `docs/tareas-slatex.md`: las tareas 1-127 de la
> versión anterior están cerradas o reubicadas (ver "Qué pasó con la lista anterior" al final).
> Esta lista sigue los 9 pilares de producción y **solo tiene trabajo que Nacho puede terminar
> sin esperar a Slatex y sin playtesting**.
>
> División de dominios y zona compartida: `docs/colaboracion-equipo.md`.

## QA — bugs abiertos

### N-227 · El equipo cobra por las cajas que no entrega; el bono de tiempo nunca se paga — A · `Opus 5.5 · high` · Aviso: sí (`run_manager.gd`, zona compartida)
Origen: auditoría integral 2026-09-30, A-4.1 (P0, bug). Hoy `payout = cargo_points + time_bonus`
(`crew_progression.gd:169-171`). `cargo_points` saltea las cajas entregadas en la puerta
(`run_manager.gd:592-594`): solo cobran las que siguen en el camión. Los `delivery_points` (150/75/20,
rescates, fotos, plazos) no pasan a plata. Endless no trae `cargo_points` (`run_manager.gd:728-738`). El bono
`50 * (1 - elapsed/75)` (`run_manager.gd:9,611`) da siempre 0: la entrega más corta dura 125 s y desde N-119
el mínimo son 2 casas (~200 s); por eso el castigo de Cliente impaciente tampoco hace nada
(`route_event_manager.gd:187-190`). Los docs dicen lo contrario (`cartas-y-eventos-de-ruta.md:5`,
`economia-y-contramedidas.md:5-6`). Ningún test lo ve: `test_crew_progression.gd:18-19` usa un diccionario
inventado y `render_hud.gd:52` y `render_store_shots.gd:137` muestran un `time_bonus: 340` imposible.
**La fórmula del pago queda pendiente de decisión del usuario** (pregunta 2 del informe: puntos de puerta,
pago fijo por casa u otra cosa; si se borra el bono de tiempo en favor de los plazos). El test y los mocks
no dependen de esa decisión y pueden hacerse ya. Hecho cuando un test con una entrega real comprueba que
`team_money` sube, los mocks de `render_hud` y `render_store_shots` usan valores alcanzables y los tres docs
dicen lo que hace el código.
- [ ] **N-227.1** Test con una entrega real (no un diccionario inventado) que compruebe que `team_money` sube; arreglar los mocks de `render_hud.gd` y `render_store_shots.gd`. Con `constructor-progresion` y después `escritor-tests`; tests `crew_progression`.
- [ ] **N-227.2** (bloqueada por la pregunta 2) Implementar la fórmula elegida y actualizar `cartas-y-eventos-de-ruta.md`, `economia-y-contramedidas.md` y `parametros-diseno.md`. Con `constructor-progresion`; tests `crew_progression`, `run_manager`.

## Hecho fuera de lista: auditoría de rendimiento (2026-09-29)

Auditoría de `perfilador-rendimiento` (headless, Endless con 4 cajas, `Performance` cada 10 ticks):
- `route_streamer.gd`: cada tramo de Endless ahora pasa por `DressingBatcher.merge_segment_geometry`
  al generarse, como los del Reparto (`route.gd`); antes cada spawn sumaba ~500 nodos. Flag
  `batch_geometry` para benches.
- `route_segment.gd`: `_materials` es `static` (un material por color para todos los tramos); antes
  cada tramo creaba 5 (+274 recursos por spawn). Los que tiñen ya duplicaban.
- `test_level_endless` lo verifica (tramos sin cajas sueltas, material de ruta compartido).
- Descartado: el "1693 Mesh leaked at exit" son cachés `static` acotados (modelos × 2 estaciones ×
  3 luces), no crecen con la partida. Telemetría, audio sintetizado, sueño y CCD de cuerpos ya bien.
- Pendiente: al generarse un tramo, `TIME_PHYSICS_PROCESS` pasó de ~3 ms a ~24 ms durante decenas
  de frames (medido antes del merge, que no toca la física): hay que perfilarlo con ventana real. Faltan
  también draw calls, sombras y transparencias con `revisor-visual`, y física con camión lleno.

## Hecho fuera de lista: red por Steam y bugs del playtest (2026-09-29)

Playtest por Steam (Spacewar, dos PCs por internet): la caja que cargaba el cliente lo seguía con
atraso y el camión "seguía andando" después de soltar las teclas. Medido: el host le mandaba a cada
cliente 527-1263 KB/s contra los 256 KB/s que Steam permite por conexión, y Steam encolaba el resto.
- `package.tscn`: `care_state` (diccionario de 19 claves, 85 % de cada envío) pasa de `ALWAYS` a
  `ON_CHANGE`; `package.tscn` y `player.tscn` sincronizan a 60 Hz fijos (antes, por frame de render).
  Peor caso ahora: 105 KB/s por cliente. `test_net_bandwidth_budget` lo cuida (tope 128 KB/s).
- `package.gd predict_carry()` + `player_carry.gd`: el cliente dibuja la caja en sus manos al
  instante; el host sigue decidiendo. `test_carry_prediction`.
- `network_manager.gd`: `no_nagle` en el peer de Steam (5 ms menos por mensaje).
- `main_menu.gd`: el vidrio esmerilado se reacomoda diferido; al cambiar el tamaño de la ventana
  quedaba una segunda tarjeta desplazada detrás (`render_main_menu.gd` lo chequea).
- `player.gd`: sin `CameraAttributesPractical` en GL Compatibility (el DOF nunca se veía y avisaba
  en cada carga).
- Pendiente (plan por fases en `docs/investigacion-red.md`): HUD de red y `--net-sim`, interpolación
  con buffer para jugadores y cajas (y recién ahí bajar a 30 Hz), tolerancia de alcance por ping,
  predicción del conductor, validación genérica de RPC y reconexión.

## Hecho fuera de lista: túneles del tren y repaso de las cascadas (2026-09-29)

~~El tren aparecía de la nada a 42 m de la ruta~~ **[x] Hecho (2026-09-29)** — Pedido del usuario.
La vía del paso a nivel entra en un túnel en cada punta: portal de piedra nuevo
(`sm_env_rail_tunnel_portal.glb`, builder `portal` de `assets/tools/build_rail_crossing.py`: arco con
dovelas y clave, jambas, pilastras, cornisa y parapeto, muros de ala, relleno detrás, túnel de 12 m que
se oscurece a negro por color de vértice). `RailCrossingSegment` lo pone rígido en ±42 m
(`tunnel_mouths()`), el tren arranca adentro del túnel cercano y termina adentro del lejano, y un
vagón se dibuja solo mientras está antes del fondo de un túnel (`_place_train()`). `route.gd` pasa las
bocas a `RouteTerrain.tunnels`: loma detrás de cada portal (`_tunnel_hill()`), corte a nivel adelante y
hueco en el terreno donde cruzaría el túnel (`_in_tunnel_bore()`); sin árboles en la vía ni frente a los
portales. `conform_geometry()` respeta la meta `&"rigid"` (la vía también es rígida ahora).
`LowpolyMaterials` suma `portal_stone`, `portal_trim` y `tunnel_soot`. Tests `test_route_terrain`
(`_check_tunnel`) y `test_more_route_segments`; capturas `render_rail_tunnel.gd`.

~~Cascada con aspecto de cinta plana~~ **[x] Hecho (2026-09-29)** — Pedido del usuario ("más
profesional"). La lámina se curva (abombada al centro, bordes hacia atrás) y se dibuja en dos capas
(cuerpo profundo + velo de hilos blancos más rápido), bordes irregulares que titilan; la espuma es un
remolino que se aleja aguas abajo en vez de una estrella; bruma de partículas al pie (`_add_mist()`);
rocas asentadas en el punto más bajo bajo su huella (ninguna cuelga sobre la orilla), columnas anchas
abajo y angostas arriba, menos aplastadas y menos oscuras. Test `test_river_water`.

## Hecho fuera de lista: cascadas en las puntas del río (2026-09-28)

~~El agua del río terminaba contra el pasto como un charco aislado~~ **[x] Hecho (2026-09-28)** —
Pedido del usuario tras mirar capturas. `route/route_river_falls.gd` (nuevo, lo llama
`RouteTerrain.build()`) sigue el centro del cauce (`RouteTerrain.river_centre()`, sacado de
`_river_factor()`) hasta donde se acaba el agua de cada lado y ahí arma una cascada: una cinta que
cae corta y empinada desde un labio 2,6–5 m sobre el agua (`shaders/river_fall.gdshader`: chorros
que bajan, espuma en el labio y al pie, charco de espuma), con pilas de rocas del bosque en
proporción natural (`_add_column()`, nunca estiradas ni aplastadas) que forman el acantilado, lo
enmarcan y tapan de dónde sale el agua, piedras en el charco y en la orilla, y un tono de piedra
mojada (más oscuro que las rocas secas del bosque). Sin RNG: igual en todos los clientes; sin
colisión, como las rocas del bosque. Test `test_river_water` (`_check_falls`), capturas
`render_river_fall_*`.

## Hecho fuera de lista: repaso del depósito tras playtest (2026-09-27)

~~Parpadeos, taller, vestuario, oficina, pizarras y zona de carga~~ **[x] Hecho (2026-09-27)** —
Depósito (repartido en `depot_hall/furnishing/dressing/order_board.gd` tras N-211): se sacó el solape del revestimiento (`DepotLayout.LINER_SPLIT`), las etiquetas de los estantes
y los textos del piso dejaron de parpadear y la zona de carga se rehízo (`_build_loading_zone`,
franjas `DepotKit.stripes` sin cortes). El taller tiene piso propio, lámpara, tambor, cubiertas
y una terminal nueva (`_build_workshop_kiosk`) dentro del área. El vestuario suma alfombra,
cascos, chalecos y cesto. La cinta termina en x 5 para no tapar la puerta de la oficina, que
ahora tiene marco y cartel. La pizarra de pedidos tiene hasta 7 renglones que se ajustan al
tamaño, y los carteles achican el título si no entra (`DepotLabels.fit_label`). Se movieron el póster del
chaleco, el póster de frágil y la pared de fotos, que quedaban escondidos. La viga del estante
del camión, el "OK" sobre las cajas, los pedidos de tripulaciones grandes y el reinicio al sumarse
gente están en el aviso de `colaboracion-equipo.md`. Tests: `test_depot` (`_test_layout`),
`test_depot_campaign_board`, `test_order_balancer`, `test_trap_visual_feedback`.

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

## Orden de ataque (hitos)

| Hito | Objetivo | Tareas |
|---|---|---|
| **M1 — Cerrar lo que está a medias** | Nada del mundo que se comporte distinto en cada jugador ni que quede sin usar. | N-201, N-202, N-203, N-101, N-102, N-701, N-702 |
| **M2 — Ritmo y guía del jugador** | Una entrega de 2-5 minutos donde siempre se sabe adónde ir. | N-103, N-104, N-105, N-501, N-502, N-503 |
| **M3 — Base técnica** | Rendimiento medido en ventana real, red de 3+ jugadores probada, Endless con curvas. | N-204, N-205, N-206, N-207, N-208, N-209, N-801, N-802 |
| **M4 — Vida y variedad** | IA ambiental, audio del mundo, narrativa ambiental, detalles del camión. | N-106, N-107, N-301 a N-308, N-401 a N-405, N-601 a N-604 |
| **M5 — Preparación de lanzamiento** ⏸ | Builds, tienda, tráiler. N-901 pospuesta a la iteración de lanzamiento. | N-210, N-703, N-901 a N-906 |
| **M6 — Mecánicas de la competencia** | Lo que Backseat Drivers y RV There Yet? hacen bien, adaptado a la carga. | N-704, N-505, N-213, N-214, N-212, N-109, N-406, N-108, N-110, N-311, N-113, N-111, N-112, N-114 (N-907 ⏸) |
| **M7 — Pedidos del usuario** | Correr, una meta que sea un lugar, un segundo cuerpo y el diario del día siguiente. | N-115, N-116, N-312, N-606 |
| **M8 — Auditoría 2026-09-29** | Lo que la auditoría encontró roto o flojo: cada pasajero con su propia acción, puntaje y red honestos, textos traducibles, menos trabajo por frame, repo liviano. Va **antes** que lo que quede de M6/M7. | N-705, N-117, N-805, N-118, N-119, N-222, N-313 ⏸, N-314, N-223, N-315, N-224, N-225, N-316, N-317, N-318, N-706, N-226, N-227 |
| **S — Heredadas de Slatex** | Todo lo que era de Slatex (jugador, paquetes, UI, progresión), con sus hitos S-M1 a S-M5. Va **después de M8**. | Ver "Heredadas de Slatex" más abajo |

Dentro de un hito, el orden de la tabla es el recomendado.

---

## M8 — Auditoría 2026-09-29

Pedido del usuario: arreglar todo lo que marcó la auditoría (`docs/auditorias/2026-09-29.md`), salvo
revisión humana de PRs ni agente revisor (no se quieren: la puerta son los checks obligatorios). Varias tocan
archivos de Slatex: aviso en `colaboracion-equipo.md` en el mismo PR, como siempre.

### N-705 · Puertas automáticas y repo limpio — A · `Opus 5.5 · medium` · Aviso: no
- [x] Lint obligatorio en la protección de `main` (el #39 entró en rojo) y `test_proximity_voice` en verde.
- [x] Auto-merge solo para ramas del repo (nunca forks). PR #40. El agente revisor que sumaba se sacó
  en el #46: gastaba el cupo del plan en cada PR.
- [x] Worktrees extra, 26 ramas locales y 35 remotas ya integradas, y el stash, borrados (2026-09-29;
  respaldo de lo útil del stash en `../Prometeus-stash-backup/`).
- [x] `main` ya no exige la rama al día ("Require branches to be up to date" apagado): los PRs
  encolados se mezclan solos sin actualizarlos a mano; CI corre igual sobre `main` en cada push.
- [x] `builds/` pesado: no hizo falta reescribir el historial. Los ejecutables **nunca llegaron a GitHub**
  (0 commits con `builds/` en origin, que pesa 189 MB); vivían solo en el `.git` local, retenidos por el
  stash. Borrado el stash, `git gc` bajó el `.git` local de 475 a 194 MB. Nadie tiene que volver a clonar.
- [x] El repo borra solo la rama de un PR al mezclarlo (`delete_branch_on_merge`).

### N-117 · Una acción propia por trampa, en el mundo y no en la tarjeta — A · `Opus 5.5 · xhigh` · Aviso: sí (trampas, `player_seat_pose.gd`, `player_cargo_care.gd`, HUD de Slatex)
Hoy las 7 trampas son 3 acciones: Frágil no deja hacer nada ("Nothing the passenger does protects
it"), Equilibrio/Ruidoso/Líquido/Hostil son el mismo botón mantenido (`player_seat_pose.gd:26`,
`{"steady": holding, "calm": holding}`) y Explosivo/Peso creciente son flechas. El playtest del
2026-09-28 ya lo dijo: "se leía como una tarea que nunca termina". Hecho cuando cada trampa pide un
gesto distinto, que se ve en el mundo (brazos, cuerpo, caja) y no solo en la tarjeta del HUD, y ningún
pasajero es espectador.
- [x] **N-117.1** Diseño, pasado por `critico-diseno` (2026-09-29, "construir con cambios"). Un botón,
  un verbo por trampa, con ícono sobre la caja; nada de mouse (en el asiento mueve la cámara y es el
  cursor que sacó el playtest del 28/09) ni reglas ocultas:
  - **Frágil = Amortiguá:** un toque del primario en una ventana de ~0,35 s antes del bache (el camino ya
    avisa); mantener no hace nada; espera después de cada toque.
  - **Equilibrio = Contrapesá:** primario mantenido + A/D (stick X) hacia el lado contrario a la
    inclinación que se ve en la caja. Sin tres zonas ni castigo por corregir de más.
  - **Líquido = Fregá:** alternar izquierda/derecha, sin primario (la única de ritmo intenso).
  - **Ruidoso = Abrazalo:** queda el primario mantenido (la trampa de aprendizaje).
  - **Hostil = Leelo:** queda (mantener tranquilo / soltar enojado); el humor tiene que verse en la caja.
  - **Explosivo = Pedí el código:** la secuencia se sortea en el host por partida (hoy es fija,
    `data/traps/explosive.tres`: `[up, left, down]`, se memoriza) y la ve **el conductor** en el tablero.
  - **Peso creciente = Asegurá:** queda la secuencia, y también cuentan las flechas del asistente
    (`package.gd` `assistant_peer_id`).
  Medida sin humanos: un bot que mantiene el primario todo el tiempo pierde ≥80 % en 5 de 7; matriz
  cruzada (el bot experto de cada trampa jugando las otras pierde fuera de la diagonal); cada trampa
  sigue en ausente 80-100 % / torpe 30-55 % / experto <12 % (`tests/sim_data/balance_report.md`), y el
  experto con +150 ms no sube más de 8 puntos.
- [x] **N-117.2** Tanda 1: Explosivo sorteado y replicado con el código en el tablero del conductor;
  toque de Frágil (+ test de red con dos clientes); bot "siempre mantiene" en el arnés de balance.
  Aviso: `docs/avisos/2026-09-29-n117-tanda1.md`. Números en `docs/parametros-diseno.md` ("Tanda 1 de N-117").
  - Explosivo: código sorteado en el host por caja y sesión (`roll_seed`), viaja en `care_state["sequence"]`
    con `reader` (conductor u dueño); lo muestra `DashboardGps` (línea "CÓDIGO ↑ ← ↓"), la tarjeta del dueño
    dice "Pedí el código", el cartel de la caja y el hint no nombran flechas. Los flancos de entrada
    (`direction_pressed`, `tap`) se gastan en el host (antes los tapaba `_last_input`).
  - Frágil: toque del primario en 0,35 s antes de un golpe anunciado (1/10 del daño), espera de 1 s,
    mantener no protege. Hallazgo que el diseño no tenía: los baches **no golpean** (la suspensión se los come,
    ya medido en N-105) y `HOLD_PROTECTION` le daba a Frágil 72 % menos de golpe al que mantiene. Se agregó
    el aviso de bache (`RoadImpacts`) y el golpe por bache tomado a más de 35 km/h
    (`bump_jolt_per_speed`, en 0 se apaga); **a decidir**: si ese golpe entra así o se sube el badén.
  - Arnés: perfil "siempre mantiene" y tabla antes/después. Siempre-mantiene pierde 80 %+ en 4 de 7 (antes 3);
    Frágil 0 → 100 / 49,2 / 2,8 % (con 3 baches sintéticos por recorrido: los grabados no golpean);
    Hostil ya estaba fuera de objetivo antes (83,2 % torpe).
  - Test de red: `net_trio.gd` (código de bomba igual en los tres y un toque de un cliente llegando al host).
    No entra en `run-tests.sh`: correr `tools/run-net-trio.sh`.
- [x] **N-117.3** Tanda 2: Equilibrio con A/D y Líquido alternado, con lo que se ve en el mundo
  (inclinación, charco). Aviso: `docs/avisos/2026-09-29-n117-tanda2.md`; números en `docs/parametros-diseno.md`
  ("Tanda 2 de N-117").
  - Equilibrio, "Contrapesá": dos ejes continuos `lean` (A/D) y `lean_fwd` (W/S), o el stick, en el marco de la
    vista del jugador (`gather_package_input`); el host los pasa al marco del camión con la base del asiento de ese
    jugador (`push_in_truck`; LeftSeat mira a la derecha del camión, RackSeat a la izquierda) y los combina como
    `steady` (solo con el primario mantenido; el ayudante al medio). La corrección es cuánto empuja contra la
    dirección de la inclinación (`tilt_dir`); una caja cabeceando se endereza empujando a lo largo del camión. Sin eje `lean` (el ayudante del rack en solo)
    sigue enderezando como antes.
  - Líquido, "Fregá": cada golpe al otro lado en `direction_pressed` (A/D o el stick) seca `scrub_amount`; el mismo
    lado, o mantener el primario, no seca; un golpe suelto tras una pausa solo reinicia. A pie hay que mantener el
    primario (frena la caminata, como con los códigos).
  - Se ve en el mundo: la caja inclinada y el charco que crece y baja ya existían; el cuerpo sentado se inclina
    hacia el lado del contrapeso o balancea con el fregado (`gesture_state()` a `care_state["gesture"]`, lo leen
    todos los pares; la cabeza va hacia `truck_right * push` en cualquier asiento, con test). La tarjeta pasa a "¡CONTRAPESÁ!" (WASD en el marco de la pantalla del jugador, o stick) y
    "¡FREGÁ!", con teclas que parpadean y se encienden con el eje local.
  - Arnés: gesto nuevo para torpe/experto/siempre-mantiene. Siempre-mantiene pierde 80 %+ en **6 de 7** (antes 4);
    Equilibrio 100 / 45,2 / 0 y Líquido 100 / 38,0 / 0; Hostil sigue fuera de objetivo desde antes.
  - Red: `net_trio.gd` cubre ahora también un cliente que friega (seis golpes A D A D A D por el RPC, `scrub=5` en
    los tres); el eje `lean` lo cubre `test_trap_gestures.gd` (incluida la limpieza en `submit_care_input`).
- [x] **N-117.4** Tanda 3: flechas del asistente en Peso creciente; íconos de verbo sobre cada caja y un
  tip por trampa (`_show_first_trap_tip`); la tarjeta del HUD pasa a ser guía, no el juego.
  Aviso: `docs/avisos/2026-09-29-n117-tanda3.md`; números en `docs/parametros-diseno.md` ("Tanda 3 de N-117").
  - Asegurá: el ayudante (`assistant_peer_id`) avanza el mismo paso que el tender; misma flecha a la vez = un paso;
    un error de cualquiera cuesta lo mismo. `net_trio.gd` cubre a un cliente ayudante completando una secuencia.
  - Verbo en el mundo: `PackageVerb` + `Box/VerbIcon` (Amortiguá, Contrapesá, Fregá, Abrazalo, Leelo con `:)`/`>:(`,
    Asegurá con las flechas que faltan); la bomba, su cartel "PEDÍ EL CÓDIGO". Solo mientras la caja pide algo.
  - Tips: cada uno explica su verbo con la tecla correcta (Frágil y explosivo arreglados).
  - Tarjeta como guía: revisadas las siete; ninguna se juega leyendo la tarjeta.
  - Hostil a objetivo: `command_seconds` 9 y `correct_decay` 16; torpe 83,2 a 50,0 %. El resultado global del reporte
    sigue en "REQUIERE AJUSTE" solo por las casi-pérdidas por viaje torpe (0,73, objetivo ≥ 1: Ruidoso 0 %,
    Frágil 0,8 %).
- Abierto (decisión del equipo): qué trampas salen en solo (el único jugador maneja y nadie atiende
  cajas en ruta) y si el conductor aguanta leer el código además de averías y espejo.

### N-805 · Todo texto visible pasa por `tr()`, y el test lo ve — A · `Opus 5.5 · high` · Aviso: sí (`package_care.gd`, `hud_results.gd`) · **[x] PR #44**
- [x] `test_ui_translations` recorre también `scripts/gameplay` y `scripts/core` (lista de excepciones
  explícita). Hoy solo mira `scripts/ui` y queda verde con 24 literales en español en `package_care.gd`.
- [x] `package_care.gd` a claves `HUD_CARE_*` (113 claves en total); `network_manager._fail()` y los `reason` de
  `level_base.gd` pasan a claves (`hud_results` ya hace `tr(reason)`). Continúa N-211 fase 7b.
- [x] ~~Queda: `display_name` de los `.tres`, "MULTIJUGADOR" en `hud_pause.gd`, "GARAJE" en `main_menu.gd`, y que
  los textos que arma el host llegan al cliente en el idioma del host.~~ **[x] Hecho (2026-09-30)**: los nombres
  de trampa viajan como clave (`TrapDefinition.name_key()`) y cada par los traduce: tarjetas de carga, resultados,
  carteles de las casas (`Depot.assignments()` → `[id, clave, código]`) y la puerta que rechaza la caja. Nadie
  muestra el `display_name` de un `.tres`. Claves nuevas para "MULTIJUGADOR", "PAUSA", "RESULTADO", "GARAJE" y
  "silenciado". `test_ui_translations` lo vigila y `test_house_waiting_marker` prueba un par en inglés. Aviso:
  `docs/avisos/2026-09-30-n805-textos-del-host.md`.
- [x] ~~Las pistas de carga (`package_hint_changed`, `get_hint()`, `care.message` de `package_care.gd`) se traducen en
  el host y viajan ya armadas.~~ **[x] Hecho (2026-09-30)**:
  - Viajan como línea `LocText` (`[clave, args...]`, `scripts/core/loc_text.gd`) y cada par las traduce al
    mostrarlas: la señal, `care.message`, los bloqueos de herramienta y `care_state["hint"]`.
  - Las trampas sobreescriben `hint_text()`.
  - `PROTOCOL_VERSION` pasa a 4.
- [x] ~~`hud_prompts._action_id_for_prompt()` busca palabras en español en el prompt ya traducido.~~ **[x] Hecho
  (2026-09-30)**:
  - Busca por claves traducidas en el idioma del jugador.
  - Los prompts de los montajes de `vehicle.tscn` y "Subirse a manejar" pasan a claves (seguían en español
    también en inglés).
  - Test: `test_hint_relay`. Aviso: `docs/avisos/2026-09-30-n805-pistas-y-prompts.md`. Commit `d44b061`.

### N-118 · Endless también puntúa la carga — A · `Opus 5.5 · high` · Aviso: sí (`run_manager.gd`) · **[x] PR #42**
`run_manager.gd:692` ("never subtracted"): el modo de los récords ignora el núcleo del juego. Hecho
cuando el puntaje es distancia + bonus por caja intacta al final (y cero por perdida), la tabla de
Endless se renombra para no mezclar récords viejos, y un test reconstruye la fórmula.

### N-119 · Jugar solo no es la ruta más vacía — A · `Opus 5.5 · high` · Aviso: no · **[x] PR #43**
Hecho: mínimo 2 casas (`RoutePlanner.MIN_CREW_HOUSES`) y, en solo, los pedidos salen solo de trampas que
se protegen manejando (`depot.gd` `SOLO_TRAPS`: Frágil y Equilibrio), porque el único jugador maneja y
nadie cuida cajas en ruta. `UnlockManager.locked_traps()` guarda cajas para 2 casas. Tests
`test_house_assignment`, `test_depot`, `test_cargo_overboard`.

### N-222 · Si el host se va, la partida termina con resultados — A · `Opus 5.5 · xhigh` · Aviso: sí (`hud_pause.gd`, `level_base.gd`) · **[x] rama `nacho/N-222-host-leaves-results`**
Corrección: el cliente ya ve una pantalla de "desconectado" que dice que el anfitrión se fue
(`hud_pause.gd:166`), pero sin nada de lo jugado. Lo mínimo: esa pantalla muestra lo entregado hasta ese
momento (casas, cajas intactas, distancia) desde el estado que el cliente ya tiene, y el test de red de
tres lo cubre. Migración de host: después del lanzamiento.
- [x] La pantalla de desconexión suma "Hasta acá: N de M casas entregadas, X de Y cajas sanas, D m recorridos
  en m:ss" (o la variante de Endless) con lo que el cliente ya tiene (`RunTally`, sin RPCs nuevos); el nivel
  frena su copia de la partida (`level_common._stop_orphaned_run`) para que no puntúe ni tape la pantalla con
  resultados. `current_distance` ahora también se lleva en modo entrega. Tests: `test_host_gone_tally.gd` y la
  fase `GONE` de `net_trio.gd`. Aviso: `docs/avisos/2026-09-30-n222-host-se-va.md`.
- [x] (nota de `auditor-red`) Si el host se va con la pantalla de resultados abierta, el cliente la cambia por la de
  desconexión y pierde los resultados completos (ya pasaba antes). Podría quedarse en resultados.
  Hecho: con los resultados abiertos se quedan (`hud_pause._on_connection_lost` → `HudResults.show_host_gone()`); la
  nota del invitado pasa a "El anfitrión se fue y la sala se cerró", "Volver a intentar" queda gris con el motivo en el
  tooltip y "Volver al menú" con el foco. `HudPrompts.can_restart()` da `false` sin sesión (antes, ya offline, R habría
  recargado el nivel como partida solo). Sin RPCs nuevos. Tests: `test_host_gone_tally.gd` y `test_hud_flow.gd`. Aviso:
  `docs/avisos/2026-09-30-n222b-resultados-quedan.md`. Rama `nacho/N-222b-results-stay-host-leaves`.

### N-226 · Color estable del jugador asignado por el anfitrión — B · `Opus 5.5 · xhigh` · Aviso: sí (`network_manager.gd` compartida; `player.gd` y `scripts/ui` de Slatex)
Origen: auditoría integral 2026-09-30, A-4.3 (P1). Esfuerzo M. Mérito y cartas se identifican por un "color
estable" (`cartas-y-eventos-de-ruta.md:12-14`), pero el color sale de `PLAYER_COLOR_KEYS[posmod(peer_id, 5)]`
(`crew_progression.gd:134-135`, `player.gd:41-43`, `hud_results.gd:151`, `depot_panel.gd:274`). ENet da ids
aleatorios: el color cambia entre sesiones y con 5 jugadores ~96 % de las veces dos comparten color, así que
alguien que vuelve a la campaña puede heredar el mérito o la carta de otro. Hecho cuando el anfitrión asigna un
índice de color por orden de llegada, lo replica en el roster, la campaña se guarda por ese índice y un test con
ids aleatorios grandes verifica colores distintos y estables.
- [ ] **N-226.1** Índice de color asignado por el anfitrión y replicado en el roster. Con `constructor-red`; después `auditor-red`; tests `network_roster`.
- [ ] **N-226.2** Leer el color desde ese índice en `crew_progression.gd`, `player.gd`, `hud_results.gd` y `depot_panel.gd`; guardar la campaña por índice. Con `constructor-progresion`; tests `crew_progression`.
- [ ] **N-226.3** Test con ids de peer aleatorios grandes. Con `escritor-tests`; tests `network_roster`.

### N-313 · El ragdoll con el cuerpo real — B · `Opus 5.5 · high` · Aviso: sí (`player_ragdoll.gd`) · ⏸ personajes en pausa (S-311)
Origen de la pausa: auditoría integral 2026-09-30, A-102 (mismo trabajo que S-311.48; `constructor-jugador.md:43`: personajes y ragdoll no se tocan).
Hoy esconde al personaje y dibuja seis cápsulas turquesa (`player_ragdoll.gd:20,56-62`). Hecho cuando
el modelo real del jugador (con su color) es el que vuela y cae; lo mínimo, el modelo entero pegado al
torso físico; lo ideal, `PhysicalBoneSimulator3D`. Captura con `revisor-visual`.

### N-314 · Antialiasing y texturas 3D con mipmaps — B · `Opus 5.5 · medium` · Aviso: sí (`project.godot`)
- [x] MSAA por preset: Baja sin MSAA, Media 2×, Alta 4× (`WorldQuality`, PR #45). Falta compararlo en
  captura con `revisor-visual`.
- [ ] Las 35 texturas 3D sin compresión ni mipmaps (`compress/mode=0`, `mipmaps/generate=false`)
  se reimportan con VRAM + mipmaps desde el editor (el hook bloquea editar `.import` a mano).

### N-223 · Menos trabajo por frame — B · `Opus 5.5 · high` · Aviso: sí (`level_base.gd`, `seat_point.gd`) · **[x] rama `nacho/N-223-less-per-frame`**
`route.gd` busca linealmente en las muestras del camino dos veces por tick; `play_area.gd`,
`seat_point.gd`, `route_sky.gd` y `route_event_manager.gd:377` escanean grupos/hijos por frame.
Cachear el índice del camino (ventana ±2 alrededor del último) y bajar las señales del HUD a 8 Hz.
Hecho con `bench_drive` antes/después anotado acá.
- [x] Hecho (2026-09-30):
  - Ventana alrededor del último índice en `route.gd` (±4 puntos del camino; las muestras de tramo siguen con búsqueda completa: son pocas y una horquilla haría fallar la ventana) y `route_streamer.gd` (Endless, ±3 tramos + memo de la última consulta, que tres llamadores pedían por tick con el mismo punto), con caída a la búsqueda completa. Test `test_route_lookup_cache` (compara contra la búsqueda completa en 8 rutas, con saltos y una posición NaN).
  - Señales del HUD a 8 Hz (`level_base._emit_hud_signals`), el cambio de estado de entrega al instante.
  - `seat_point.gd`: una pasada por frame del grupo `player` para todos los asientos.
  - Se dejaron como estaban: `route_event_manager.gd:377` (corre al resolver un evento, no por tick; solo se sacó `_run()` del bucle de `_loose_count`), `route_sky.gd` (los `find_children` son de `_ready`; los grupos por frame devuelven 1 nodo) y `play_area.gd` (sus tramos mezclan ruta y caminos de casas: una ventana no daría lo mismo).
  - `bench_drive --headless --cpu-only --seconds=30 --seed=1234` (física por tick, scripts + Jolt): entrega 1,67 → 1,55 ms (media de 3); Endless 1,46 → 1,41 ms (dentro del ruido). Frame, p99 y tirones sin cambio: el resto es Jolt.
  - Aviso: `docs/avisos/2026-09-30-n223-menos-trabajo-por-frame.md`.

### N-315 · Cajas de 2048² triplicadas — B · `Opus 5.5 · medium` · Aviso: no
Cada textura de caja está tres veces (fuente en `art/cargo/`, volcado del importador en
`assets/models/cargo/` y embebida en el `.glb`): ~5 MB × 3 × 4. Regenerar a 512² con
`art/tools/make_cargo_textures.py` (`modelador-blender`), sacar los volcados del repo e ignorarlos.

### N-224 · Menos despacho dinámico — C · `Opus 5.5 · high` · Aviso: sí (varios)
251 `.call(&"…")`, 233 `.get(&"…")` y 112 rutas `/root/`: un renombre rompe en runtime. Por archivo,
empezando por `crew_progression.gd` y `route_event_manager.gd`: referencias tipadas (`class_name`) o
dependencias por `setup()`. Una PR por archivo; el conteo baja en cada una.

### N-225 · Partir los archivos que viven al borde del límite del lint — C · `Opus 5.5 · xhigh` · Aviso: sí
`synth_audio.gd` 1000, `package.gd` 999, `player.gd` 991, `run_manager.gd` 970, `reference_truck.gd`
932: están escritos contra `max-file-lines: 1000`, no partidos por responsabilidad. Orden:
`synth_audio` → `reference_truck` → `route.gd` → `package.gd`.

### N-316 · Capturas de tienda con gente y cajas — B · `Opus 5.5 · medium` · Aviso: no
Las 5 capturas de `art/marketing/capturas/` no muestran una persona ni un paquete. Rehacerlas con
tripulación, cajas en las manos y algo saliendo mal, después de N-117 (`trailer_shot`, `revisor-visual`).

### N-317 · Ruta de noche legible (calzada, luz y horizonte) — B · `Opus 5.5 · high` · Aviso: no · **[x] rama `arte/N-317-night-road`**
Origen: PC build 2026-09-30. Necesita PC (GPU real; la toma la sesión de arte). Capturas 1280×720 de
`render_route_dressing.gd` sobre 390ee37 (RTX 4060 Ti): en `render_route_sign.png`, `render_route_guardrail.png` y
`render_route_landmark.png` de noche la calzada es casi negra/azul marino, solo se leen las líneas del borde; el
corte entre lo iluminado y lo oscuro es duro (borde tipo foco); terreno y árboles oscuros y la torre de agua
apagada. `render_route_horizon.png` es casi ilegible: la cámara queda pegada a un cartel "CUIDA…" que tapa la parte
de arriba (puede ser el encuadre del script) y el contraste de la ruta es mínimo. Relacionada con N-304 (cerrada) y
con la nota de N-905 (camión casi negro de noche), que no cubren la ruta.
Hecho cuando, en capturas de noche de esos cuatro planos, la calzada tiene luminancia media ≥ un umbral medido
(anotar el valor antes/después con un script sobre el PNG), la transición de luz sin borde duro (caída suave) y el
plano `horizon` no tiene cartel tapando >10 % del cuadro; `revisor-visual` lo confirma y `tools/run-tests.sh route`
sigue en verde.
- [x] **N-317.1** ~~Revisar el encuadre del plano `horizon` de `render_route_dressing.gd` (cartel pegado a la cámara) y medir luminancia de la calzada. Con `revisor-visual`.~~
  **[x] Hecho (2026-09-30, sesión de arte)** — el script acepta `--seed=N` (7 por defecto: antes cada corrida era otra ruta
  y no se podía comparar) y el plano `horizon` sale de un punto de `route._path_points` a 70 m (o más) de ruta, descartando
  los que tienen techo o un cartel en los primeros 25 m: el cartel "CUIDA…" era el portón del depósito (61 % → 0 %).
  Medidor nuevo: `art/tools/measure_luminance.py`.
- [x] **N-317.2** ~~Subir luz ambiental/luna y suavizar el borde de los faros y `WorldMood` de noche; terreno, árboles y torre de agua con más valor. Con `artista-shaders` y `constructor-mundo`; tests `route`, `night_lights`.~~
  **[x] Hecho (2026-09-30, sesión de arte)** — el "borde tipo foco" no eran los faros (no hay en esas capturas) sino las
  lámparas del túnel, sin sombras y con 11 m de alcance a 6 m de la boca: derramaban un disco afuera (`tunnel_segment.gd`:
  7,5 m adentro y 9,5 m de alcance). Las sombras salían negras porque el ambiente del nivel viene del cielo (casi negro de
  noche): `world_mood.gd` baja `ambient_light_sky_contribution` a 0,4 de noche, ambiente (0,4, 0,45, 0,58) ×0,6 y luna ×0,55;
  `route_terrain.gdshader` aclara el asfalto ×1,4 con `night_road`; luz del porche más suave. Calzada de noche, seed 7
  (1280×720, RTX 4060 Ti): sign 0,038 → 0,136, guardrail 0,036 → 0,135, horizon 0,032 → 0,130; terreno del landmark 0,094 →
  0,188; cielo igual (0,050); 0 % quemados. Día y atardecer sin cambios (`night_road` = 0). Tests `world_mood` (nuevo
  `_check_night_light`) y `more_route_segments` (la boca del túnel queda fuera del alcance de las lámparas).
  Queda: la sombra dura de la loma frente al túnel es N-318.3; la lluvia de noche queda más oscura (calzada 0,07-0,12) a
  propósito.

### N-318 · Cartel A-3 quemado, granero negro y borde duro de la loma — C · `Opus 5.5 · medium` · Aviso: no
Origen: PC build 2026-09-30. Necesita PC (la toma la sesión de arte). Capturas de 390ee37: en `render_route_house.png` el
cartel amarillo "A-3" tiene un globo amarillo plano y sobreexpuesto, sin detalle, cortado por el borde de la imagen,
y el granero rojo queda negro. En `render_tunnel_from_road.png` y `render_tunnel_side.png` (día) la sombra de la
loma sobre la calzada es un borde diagonal muy duro; en `render_tunnel_side.png` se ve un hueco en la loma con
cielo/blanco sobre el portal (puede ser el hueco `_in_tunnel_bore()` de `route_terrain.gd`).
Hecho cuando (1) se verificó primero si el hueco es geometría rota: test en `test_route_terrain` que la loma no tiene
huecos sobre el portal fuera del túnel; (2) el globo del cartel tiene detalle (emisión bajada, sin píxeles
saturados en >5 % del globo, medido en la captura) y entra entero en el encuadre; (3) el granero recibe luz (luminancia
media medida); (4) la sombra de la loma con borde suave. Capturas antes/después con `revisor-visual`.
- [ ] **N-318.1** Diagnosticar el hueco de `render_tunnel_side.png` (geometría vs. luz) y corregirlo. Con `cazador-bugs`; tests `route_terrain`, `more_route_segments`.
- [ ] **N-318.2** Cartel y granero (emisivo, luz, encuadre del script). Con `artista-shaders`; captura `render_route_dressing.gd`.
- [ ] **N-318.3** Suavizar la sombra de la loma sobre la calzada. Con `constructor-mundo`.

### N-706 · Docs a dieta — C · `Opus 5.5 · low` · Aviso: sí (`colaboracion-equipo.md`) · **[x]**
- [x] Los 68 avisos de `colaboracion-equipo.md` a `docs/avisos/archivo-2026-09.md`; cada aviso nuevo es un
  archivo nuevo en `docs/avisos/` (`colaboracion-equipo.md` quedó en ~100 líneas de política).
- [x] Sin encabezado "Última actualización" en las listas (la fecha la tiene git; todos los PRs lo editaban).
- [x] Sin lista de tests en el README: cada test se describe en su encabezado y `tools/list-tests.sh`
  arma el índice; CI falla si uno no tiene descripción (`--missing`).

## 1. Game Design

### N-101 · Decidir el rol del depósito en Endless — A · `Opus 5.5 · medium` · Aviso: no · **[x] `30f94a3`**

Antes #127. En Endless la pizarra no asigna pedidos (`post_orders(0)`), así que hoy muestra una
pizarra vacía.

- [x] **N-101.1 Decisión (tomada acá para no depender de playtesting):** el depósito se mantiene
  completo en Endless (ya está construido y sirve de lobby: vestuario, taller, suministros), pero la
  pizarra cambia su contenido a "ENDLESS — Llevá todo lo que puedas lo más lejos posible" y muestra el
  récord de distancia (`RunManager.best_score(MODE_ENDLESS)`).
- [x] **N-101.2** En Endless el portón se abre apenas el camión arranca con carga, sin esperar pedidos.
  Ya pasaba: el portón arranca abierto en los dos modos y nada espera pedidos; el test lo fija.
- [x] **N-101.3** Documentarlo en `docs/plan-desarrollo.md` Fase 3 y en `docs/arquitectura.md` §5.1.
- [x] Test en `test_depot.gd`: en Endless la pizarra no queda vacía y no se publican pedidos.

### N-102 · Presupuesto de largo de ruta (regla de oro de 2-5 minutos) — A · `Opus 5.5 · high` · Aviso: no · **[x] `2dc63c8`**

`critica-diseno-abogado-del-diablo.md` §3: con tramos de 400-600 m (`route.gd` `LEG_MIN_LENGTH` /
`LEG_MAX_LENGTH`) y hasta 4 casas, una entrega puede tener ~3000 m, y nadie lo midió.

- [x] **N-102.1 Medir.** `tests/bench_route_duration.gd`: conductor automático (el de
  `test_vehicle_stress.gd` pero siguiendo el camino con `route.distance_from_path()`), a velocidad de
  crucero, frenando en cada casa 25 s (bajar, caminar, timbre, volver). Semillas 1-20, con 1, 2, 3 y 4
  casas. Imprimir minutos promedio y máximo.
- [x] **N-102.2 Regla.** Reemplazar el rango fijo por un presupuesto total: `ROUTE_TARGET_SECONDS := 240`
  (4 min). Largo de cada tramo = presupuesto de manejo ÷ (casas + 1), con piso de 250 m y techo de 600 m.
  Con 1 casa los tramos quedan largos (mini aventura); con 4, cortos. **Cambio:** el techo quedó en
  700 m, porque con 600 una casa sola daba 1,9 min (el test lo cazó).
- [x] **N-102.3** Volver a medir: ninguna combinación pasa de 5 minutos ni baja de 2. Tabla con los
  resultados en `docs/parametros-diseno.md` ("Duración de la entrega").
- [x] Test `test_route_duration_budget.gd` (rápido, sin manejar): el largo total calculado respeta el
  presupuesto para 1-4 casas.

### N-103 · Ritmo dentro de cada tramo — A · `Opus 5.5 · high` · Aviso: no · **[x] `90c2e9d`**

Un tramo largo sin nada que hacer es tedio; uno con todo difícil seguido es injusto.

- [x] **N-103.1** Regla de ritmo en `route.gd` al armar cada tramo: al menos un "momento" (tramo difícil,
  cruce de tren, cruce de animales o curva cerrada) cada 250 m; nunca dos tramos difíciles seguidos
  (misma regla que `RouteStreamer.hard_segments`, reutilizarla).
- [x] **N-103.2** Zona tranquila obligatoria: los últimos 80 m antes de cada casa son recta o curva suave
  (el conductor frena y los pasajeros bajan sin que un badén les tire la caja).
- [x] **N-103.3** Dificultad creciente dentro de la entrega: el peso de tramos difíciles sube de la primera
  a la última casa (misma curva que `hard_weight_at()` de Endless, escalada al largo de la entrega).
- [x] Test `test_route_pacing.gd`: 200 semillas, ninguna rompe las tres reglas.
- Hecho con `route.gd` `plan_spine()`: la ruta se planea entera antes de construirse; `test_route_pacing` revisa 200 semillas. El arranque seguro bajó de 150 a 100 m para que entre el primer "momento".

### N-104 · Balance del manejo medido — A · `Opus 5.5 · high` · Aviso: no · **[x] `2dc63c8`**

Hoy la sensación de manejo solo se juzga jugando. Medirla con números fijos permite ajustarla y que
no se rompa sin querer.

- [x] **N-104.1** `tests/test_vehicle_handling.gd`: para cada variante (`classic`, `agile`) medir en recta
  plana 0→50 km/h, distancia de frenado desde 50 km/h, radio de giro a 20 km/h, y la velocidad máxima a la
  que una curva de `CurveSegment` se toma sin volcar.
- [x] **N-104.2** Objetivos escritos en `docs/parametros-diseno.md` ("Manejo"). **Cambio (decidido con el
  usuario):** el camión real hace 0→50 en 2,4 s y frena en 6,4 m, lejos de lo propuesto (5-7 s, < 18 m);
  cambiar la sensación de manejo sin playtesting era apostar a ciegas, así que los objetivos son los
  valores medidos. Ninguna variante vuelca en la curva más cerrada a ninguna velocidad que alcance.
  Revisarlos es de lo primero para cuando haya playtesting.
- [x] El test falla si un cambio futuro saca los valores de rango (±10 %).

### N-105 · Ruta como fuente de riesgo para la carga, medida — B · `Opus 5.5 · high` · Aviso: no · **[x] `661bc19`**

Complementa el simulador de balance de Slatex (S-108) sin depender de él.

- [x] `tests/bench_route_shocks.gd`: grabar por tipo de tramo los impactos (delta de velocidad) y la
  inclinación que sufre un paquete montado a velocidad de crucero. Tabla en `docs/parametros-diseno.md`:
  qué tramo produce qué nivel de golpe comparado con los umbrales de Frágil (3,0 y 7,0 m/s).
- [x] Si un tramo supera siempre el umbral pesado a velocidad normal (golpe inevitable), bajarle la
  severidad: un obstáculo tiene que poder pasarse sin daño manejando con cuidado.
- Resultado: ningún tramo golpea siempre por encima del umbral pesado; los golpes pesados son choques contra bloques o el tren. Hallazgo para diseño: badén, ripio y loma casi no golpean la carga (tabla en `docs/parametros-diseno.md`).

### N-106 · Variedad de peligros sin tráfico — B · `Opus 5.5 · xhigh` · Aviso: no · **[x] `467361a`**

Decisión vigente (antes #76): no hay tráfico en movimiento. La variedad sale de peligros puntuales.

- [x] **N-106.1 Rebaño de ovejas** cruzando en zona de campo (reutilizar `wildlife_crossing.gd`: grupo de
  6-10 que se dispersa si el camión toca bocina; atropellar una multa como el ciervo).
- [x] **N-106.2 Perro que persigue al camión** en zona de pueblo durante 150 m, ladrando; no hace daño,
  distrae (y es un momento gracioso para clips).
- [x] **N-106.3 Piedras o ramas caídas** en el asfalto después de tormenta (solo con clima lluvia): obstáculo
  estático que obliga a esquivar.
- [x] Todo determinista desde la semilla y disparado por el host, como el cruce de tren (#63 viejo).
- [x] Tests por peligro, patrón `test_wildlife_crossing.gd`.
- Rebaño (arranca a cruzar con el camión a 110 m, no a 45: si no, a velocidad normal pasaba antes de que llegaran al asfalto), perro de pueblo y ramas/troncos con lluvia. Modelos nuevos de oveja y perro (`build_wildlife.py`). Tests: `test_flock_crossing`, `test_chasing_dog`, `test_road_hazards`. Solo en la ruta de entrega; Endless todavía no los tiene.

### N-107 · Bocina con función — C · `Opus 5.5 · medium` · Aviso: no · **[x] `eed9809`**

- [x] La bocina espanta animales (ciervo, ovejas, perro) dentro de 30 m hacia adelante. (El ciervo ya;
  ovejas y perro llegan con N-106 y usan lo mismo.) Hoy es solo
  comedia; así el conductor tiene una herramienta además del volante. Test en `test_horn.gd`.

---

## 2. Programación y arquitectura técnica

### N-201 · Objetos sueltos del camión que no alteren la física en red — A · `Opus 5.5 · high` · Aviso: no · **[x] `3d76e90`**

Pendiente desde el #18 viejo: `cargo_clutter.gd` crea la caja de herramientas y el termo como
`RigidBody3D` en **cada** peer, y su contacto puede empujar la simulación del camión de forma
distinta en cada máquina.

- [x] **Resuelto por la arquitectura de red, sin tocar el clutter:** desde #145/#146 el camión de los
  clientes está congelado y lo posiciona el host, así que el clutter de un cliente no puede empujarlo; el
  único camión simulado es el del host, y ahí el clutter (4,3 kg contra 950 kg) es el mismo para todos
  porque todos reciben esa pose. Ya estaban en capa 0 sin tocar paquetes ni jugadores. Separarlos de las
  paredes del camión no era posible sin que lo atraviesen. Regla documentada en
  `docs/convenciones-godot.md` §2.
- [x] Test nuevo `test_cargo_clutter`: capa 0 y máscara sin paquetes ni jugadores, menos del 1 % de la
  masa del camión, y camión congelado en la copia de un cliente (reemplaza la medición de trayectoria,
  que ya no aplica).

### N-202 · El ciervo no debería usar el canal de eventos de ruta — A · `Opus 5.5 · medium` · Aviso: no · **[x] `92db30b`**

`wildlife_crossing.gd` avisa el choque con `route_event_started(&"deer_hit", …)` y nunca lo cierra.
Slatex va a hacer que los eventos de ruta tengan cuenta regresiva y resolución (S-101 de su lista);
un "evento" sin fin va a quedar colgado en su banner.

- [x] Agregar `"incident": true` y `"duration": 0` al diccionario, y emitir `route_event_resolved(&"deer_hit",
  false, 0)` 4 s después. Así funciona con el HUD de hoy y con el de S-101 sin que ninguno de los dos
  tenga que esperar al otro.
- [x] Usar el mismo formato para los peligros nuevos de N-106: `WildlifeCrossing.report_incident()` ya
  lo arma (se cierra solo aunque el tramo se haya borrado). Se tilda con N-106.
- [x] Test en `test_wildlife_crossing.gd`: tras el choque se emite el resuelto.

### N-203 · Bocina por el bus correcto — A · `Opus 5.5 · medium` · Aviso: no · **[x] `31222cc`**

Pendiente del #81 viejo: motor, impacto y chirrido se rutean Interior/Exterior según la cámara
(`vehicle_presentation.gd`), la bocina (`vehicle.gd` `_horn_player`) va fija por `SFX`.

- [x] Mover la creación del reproductor de bocina a `vehicle_presentation.gd` o exponerlo para que se rutee
  igual que los demás. Test en `test_audio_bus_routing.gd`. (Se expuso: el nodo se llama `HornAudio` y
  la presentación lo rutea con los demás.)

### N-204 · FPS reales con GPU — A · `Opus 5.5 · medium` · Aviso: no · **[x] `90ecef4`**

El #93 viejo midió CPU/física en headless; el costo de dibujado nunca se midió.

- [x] Correr `tests/bench_drive.gd` **con ventana** (agente `revisor-visual`) en la PC de desarrollo, en las
  tres horas del día y con lluvia, en entrega y Endless. Anotar FPS promedio, 1 % más bajo y draw calls
  (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`).
- [ ] Meta: 60 FPS estables a 1080p en la PC de desarrollo y ≥ 45 FPS con el preset bajo (N-205).
- [x] Resultado en README → Rendimiento, con la PC usada.
- Medido el 2026-09-24 (tabla en README → Rendimiento): reparto 139-164 FPS, 1 % más bajo 85-104; Endless 312-393. Queda abierto medir el preset bajo en una PC modesta (no hay una a mano).

### N-205 · Presets de calidad gráfica — B · `Opus 5.5 · high` · Aviso: sí (`game_settings.gd` y `options_panel.gd` de Slatex, una fila) · **[x] `7151f84`**

- [x] `scripts/presentation/world_quality.gd` (estático): tres niveles que ajustan distancia de sombras,
  distancia de dibujado del decorado (`dressing_batcher.gd`), densidad de plantas, partículas de polvo y
  lluvia, y resolución de escala 3D.
- [x] Guardar la elección en `GameSettings` (clave nueva, sin cambiar las existentes) y una fila
  "Calidad gráfica" en `options_panel.gd`. Son 10-15 líneas en archivos de Slatex: aviso.
- [x] Test: cada nivel aplica sus valores y se puede cambiar en caliente.
- Sin densidad de plantas: el decorado sale del RNG compartido de la sesión y poner menos en una máquina movería el mundo de los demás. Aviso en `colaboracion-equipo.md`.

### N-206 · Endless con curvas reales — B · `Opus 5.5 · xhigh` · Aviso: no · **[x] `90ecef4`**

Antes #114: `RouteStreamer` sigue siendo recto en −Z.

- [x] **N-206.1** Pasar el streamer a un cursor `Transform3D` como `route.gd` (#110 viejo): cada tramo nuevo
  se arma en la pose de salida del anterior.
- [x] **N-206.2** Lookahead y borrado por distancia **a lo largo del camino** (acumulada), no por Z.
- [x] **N-206.3** Evitar que el camino se cruce consigo mismo: si el rumbo acumulado se aleja más de 120° del
  inicial, el próximo `CurveSegment` dobla hacia el otro lado.
- [x] **N-206.4** La red de "fuera de la ruta" de `level_endless.gd` pasa a medir distancia al camino.
- [x] Tests `test_route_streaming.gd` y `test_level_endless.gd` ampliados: 5 km simulados sin cruces, nodos
  acotados.
- El rumbo se limita a 80° de −Z (como `route.gd`) en lugar de "doblar al otro lado pasados 120°": así el camino siempre avanza y nunca puede cruzarse.

### N-207 · Prueba de red con 3 jugadores — A · `Opus 5.5 · xhigh` · Aviso: no · **[x] `2f5096a`**

`plan-desarrollo.md` Fase 4 lo marca como lo que falta para cerrarla.

- [x] `tests/net_trio.gd` sobre el patrón de `tests/net_smoke.gd`: un host y dos clientes ENet en localhost.
- [x] Chequear que los tres tienen el mismo `world_seed`, la misma cantidad de casas, la misma lista de
  pedidos, un hash igual de la ruta generada (posición de cada tramo y casa), y la misma fase del cruce de
  tren cuando el host lo dispara. Un cliente que entra tarde recibe todo igual.
- [x] `tools/run-net-trio.sh` que lanza los tres y junta los códigos de salida.
- Pasa con el segundo cliente entrando 6 s tarde; el host elige una semilla con cruce de tren. Un crash del motor al cerrar después de reportar cuenta como "cierre inestable", como en `run-tests.sh`.

### N-208 · Camión del host suave en los clientes — B · `Opus 5.5 · xhigh` · Aviso: no · **[x] `8c8aff2`**

- [x] Medir en un cliente el tirón de la posición replicada del camión con latencia artificial
  (opción de depuración `--fake-lag=150`): diferencia entre la pose mostrada y una interpolada ideal.
- [x] Si hay saltos visibles (> 10 cm por frame a velocidad de crucero), sumar interpolación con un buffer de
  100 ms para la pose replicada en clientes. Nunca predicción de física en el cliente (el host manda).
- [x] Test con el retraso: la pose mostrada no salta más que el umbral.
- **En espera (2026-09-24):** implica cambiar cómo se replica el camión y sobre qué viajan los pasajeros (`player.gd`), que estaba en obra en otra sesión. Retomar con ese archivo quieto.
- Medido (`test_vehicle_net_smoothing`, 150 ms de lag + hasta 50 ms de jitter, 60 km/h en curva, 144 fps): poniendo cada pose al llegar, el camión se apartaba hasta ~1 m por cuadro del movimiento parejo; con el buffer, menos de 10 cm. `vehicle_net_smoother.gd`: la pose viaja con el reloj del host (`net_time`, `net_position`, `net_rotation` en la replicación) y el cliente la dibuja 100 ms atrás, interpolada; nunca predice física. Un teletransporte (respawn) salta. `--fake-lag=<ms>` en un cliente retiene las poses para probarlo en red real.

### N-209 · Unificar lo común entre nivel de entrega y Endless — C · `Opus 5.5 · xhigh` · Aviso: sí (`level_base.gd`) · **[x] `abf72b8`**

`level_endless.gd` duplica a propósito partes de `level_base.gd` (#42 viejo). Los dos modos ya están estables.

- [x] Extraer a `scripts/gameplay/level_common.gd` (clase base) solo lo idéntico: spawn de jugadores
  (`_sync_players`), pausa, reinicio, chequeo de carga perdida. Cada nivel hereda y conserva lo propio.
- [x] Hacerlo en un solo commit chico, avisado, con toda la batería verde. Si Slatex está tocando
  `level_base.gd` esa semana (su S-203 / S-209), coordinar el orden en el chat; no es bloqueante: el que
  llega segundo hace merge.
- **En espera (2026-09-24):** refactor de `level_base.gd` (de Slatex), prioridad C; mejor en una semana sin cambios de Slatex en ese archivo.
- `level_common.gd` (clase `LevelCommon`) tiene lo idéntico: carga en el depósito, spawn de jugadores, pausa, reinicio, carga perdida, vista al caerse el host, arranque con conductor y carga. Cada nivel conserva `_prepare_mode()`, `start_delivery()`, `_physics_process()`. Sin cambios de firma; aviso en `colaboracion-equipo.md`. Test `test_level_common` (ninguno redefine lo compartido y los dos arrancan).

### N-210 · Builds de exportación automáticas — B · `Opus 5.5 · high` · Aviso: no · **[x] `8d71e30`**

- [x] Job de GitHub Actions que exporta Windows y Linux con `export_presets.cfg` en cada tag `v*` y adjunta
  los zip al release. Versión en `project.godot` (`config/version`) mostrada en el menú (texto chico, la
  pone el job; aviso si se toca `main_menu.gd`).
- `.github/workflows/release.yml`: en cada tag `v*` escribe la versión del tag en `config/version` (`tools/export/stamp_version.py`), exporta con `tools/export/export_presets.cfg` (el `export_presets.cfg` de `do-not-drop/` sigue siendo local), prueba que la build de Linux arranque sin errores de carga y sube `TakeMyPackage-<versión>-windows.zip` / `-linux.zip` al release. Probado localmente con las plantillas 4.7.2: las dos builds salen con las DLL de Steam. El menú muestra "Versión <config/version>" (una línea en `main_menu.gd`, aviso). Test `test_release_build`. Cómo usarlo: `CONTRIBUTING.md` → Builds de release.

---

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
- [ ] **Fase 7b · i18n del resto:** textos visibles en `core/` (eventos de ruta, desbloqueos, cartas,
  suministros, caras), `gameplay/` (contenidos de paquetes, avisos del depósito, historias) y los
  `display_name` de los `.tres` de trampas/contenidos. Ojo: `hud_prompts` y `ui_theme` indexan por
  nombre visible de trampa (`"FRÁGIL"`...); pasarlos a id antes de traducir esos nombres.
- [x] **Fase 8 · Responsividad:** capturas del HUD y el menú en 16:9, 16:10 (Steam Deck), 21:9 y 4:3.
  16:9/16:10/21:9 bien. Arreglado: en 4:3 todo el HUD se dibujaba al 75% (letra de 6-7 px) — ahora
  `Hud.layout_scale()` maqueta siempre en 720 de alto lógico (HUD y tarjeta); el aviso de interacción
  pisaba la barra de ruta (ahora va en el flujo del dashboard); el chip de plata dejaba un óvalo vacío
  (`Hud.set_economy_visible()`); "furgoneta" → "camión". Todo con aserciones en `test_hud_flow`.
  - [ ] A confirmar: en las capturas la escena 3D del depósito salió más fría en una tanda que en otra;
    probablemente el clima/`WorldMood` al azar de cada corrida (nada de iluminación cambió en esta rama).
- [ ] **Aparte:** faltan 14 `.uid` en `main` (Godot los genera en cada clon con valores distintos);
  commitearlos en un PR chico cuando nadie tenga copias sin trackear.
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
- [ ] Separar de `VehicleNetSmoother` un `NetSnapshotBuffer` genérico, con reloj del host, y usarlo en
  jugadores y cajas.
- [ ] Colchón adaptativo: 2 intervalos más 2 × el jitter medido, entre 50 y 200 ms.
- [ ] Recién con eso, bajar `replication_interval` de caja y jugador a 1/30 s. `test_net_bandwidth_budget`
  tiene que seguir pasando.
- [ ] Tolerancia de alcance proporcional al ping en los chequeos del host (agarrar y usar cajas).

### N-218 · Predicción del camión para el conductor cliente — A · `Opus 5.5 · xhigh` · Aviso: no

Fase 3 de `docs/investigacion-red.md`. Hoy el volante del conductor cliente tiene un ping más 100 ms de
atraso.
- [ ] El cliente que maneja descongela su copia del camión y la simula con sus inputs numerados.
- [ ] El host devuelve su pose con el último input procesado. El cliente compara contra su historial y
  corrige suave (posición en ~150 ms), sin re-simular.
- [ ] Las cajas siguen en el host y se dibujan en el espacio del camión del cliente (`net_in_vehicle`).
- [ ] Test con `--fake-lag`: el volante responde en el mismo tick, y la corrección no salta más de 10 cm
  por frame.
- Descartado: pasarle la autoridad del camión al conductor. El host terminaría simulando las cajas sobre
  un camión que llega atrasado, y volverían las cajas que atraviesan las paredes.

### N-219 · Pico de física al generar cada tramo de Endless — B · `Opus 5.5 · high` · Aviso: no

La auditoría del 2026-09-29 midió que, al generarse un tramo, `TIME_PHYSICS_PROCESS` sube de ~3 ms a
~24 ms durante decenas de frames (el límite a 60 Hz es 16,7 ms). Se midió antes del merge del PR #35, que
no toca la física.
- [ ] Reproducirlo con ventana real y ver quién gasta: los `StaticBody3D` y shapes del tramo, el terreno,
  los scripts con `_physics_process` o el CCD.
- [ ] Arreglar: armar el tramo repartido en varios frames, usar menos shapes o shapes más simples, o
  generarlo antes y más lejos.
- [ ] Test: el costo de física tras un spawn vuelve a la base en pocos frames.

### N-220 · Auditoría gráfica con ventana real y física con el camión lleno — B · `Opus 5.5 · high` · Aviso: no

Lo que la auditoría headless no pudo medir (`revisor-visual` o `perfilador-rendimiento` con pantalla).
- [ ] Draw calls, sombras, transparencias y partículas en Reparto y en Endless: comparar antes y después del
  PR #35.
- [ ] Física de Jolt con 5 jugadores y el camión lleno (objetos activos y pares de colisión).
- [ ] Tiempo de carga del menú y del nivel, y memoria.
- [ ] Opcional: vaciar los cachés `static` de mallas al volver al menú. No es un leak: el "1693 Mesh
  leaked at exit" son cachés acotados.

### N-221 · Red defensiva: validación de RPC y reconexión — B · `Opus 5.5 · xhigh` · Aviso: sí (zona compartida)

Fase 4 de `docs/investigacion-red.md`.
- [ ] Validador común para RPC `any_peer`: remitente, `NaN`/`inf` en poses, tamaño de diccionarios y un
  límite de pedidos por segundo por peer.
- [ ] Test que recorra todos los `@rpc("any_peer"` y exija el chequeo del remitente.
- [ ] Reconexión: el que se cae a mitad de una partida vuelve a su lugar.
- [ ] Regla en `convenciones-godot.md`: subir `PROTOCOL_VERSION` con cada cambio de RPC o de replicación.
- [ ] Antes de jugar con gente de afuera: AppID propio (N-901).

## 3. Arte y dirección visual

### N-301 · Líneas de paneles y juntas de puertas — B · `Opus 5.5 · high` · Aviso: no · **[x] `8c8aff2`**

Antes #4. Única pieza de modelado del camión que queda.

- [x] Hendiduras finas (bisel invertido o calcomanía oscura) en puertas de cabina, puertas traseras, capó y
  laterales del modelo de referencia, sin cambiar la colisión. Captura con `render_reference_truck.gd`.
- `reference_truck.gd` `_build_panel_lines()`: franjas oscuras de 20 mm (a 12 mm casi no se leían en la captura) apenas salidas de la cara exterior de cada panel, colgadas del panel (se mueven con la puerta): contorno de las puertas de cabina y de las traseras, línea del capó y juntas de chapa de los laterales de la caja. Sin colisión. Test en `test_reference_truck`; captura en `render_world_features.gd --part=truck`.

### N-302 · Timbre real en cada casa — A · `Opus 5.5 · high` · Aviso: no · **[x] `ad4c281`**

`inventario-assets.md` §5: hoy `doorbell_point.gd` es una caja.

- [x] Panel de timbre low-poly (placa, botón, número de casa) con script de Blender, que se ilumina cuando
  la casa espera un paquete y se apaga cuando se resolvió. Mismo punto de interacción.
- `assets/tools/build_doorbell.py` → `sm_env_prop_doorbell_panel.glb` (12×26 cm: número, rejilla, botón con
  aro, tarjeta, tornillos). `delivery_house.gd` lo cuelga en la pared de cada modelo (medida en los .glb),
  del lado del picaporte entre el marco y el postigo, con el botón a 1,2 m del porche; número y botón se
  encienden mientras la casa espera y se apagan con `house_delivery_recorded`, como la luz del porche. El
  `DoorbellPoint` es el mismo y se mueve con el panel. De paso: el panel viejo flotaba 13-43 cm delante de
  la pared, a la altura de la cadera. Test en `test_house_waiting_marker`; primeros planos en
  `render_house_waiting.gd`.

### N-303 · Lluvia en el parabrisas y limpiaparabrisas — B · `Opus 5.5 · high` · Aviso: no · **[x] `8c8aff2`**

- [x] Shader de gotas deslizándose en el vidrio de la cabina, solo con clima lluvia y solo visto desde
  adentro.
- [x] Limpiaparabrisas animados que barren las gotas (el shader lee el ángulo del limpiador).
- `presentation/windshield_rain.gd` + `shaders/windshield_rain.gdshader`: una copia de la malla del parabrisas apenas adentro de la cabina, con sus caras hacia adentro (desde afuera se descarta). Gotas en celdas con reloj propio que bajan despacio; se muestran solo con lluvia y con la cámara adentro del camión. Dos brazos en tándem que descansan paralelos y barren a la par sin cruzarse (la primera versión se cruzaba en X), y el shader borra exactamente donde pasa cada escobilla (misma fórmula y mismo reloj, `sweep_angle()`). Test `test_windshield_rain`.
- Revisión visual (2026-09-25, `render_world_features.gd`; `655c6f2`, `5cc1497`): las gotas eran oscuras como hollín: el shader mezclaba el color de cada gota con negro según su alfa y después volvía a aplicar el alfa (quedaba a un quinto del brillo). Ahora son agua pálida con borde fino y brillo, y se desvanecen en los bordes del vidrio. El modelo del camión traía dos escobillas fijas que quedaban debajo de las animadas (dos X): se ocultan.

### N-304 · Faros y noche con más carácter — C · `Opus 5.5 · medium` · Aviso: no · **[x] `94bed31`**

- [x] Destello (flare) suave de faros de autos estacionados y faroles de pueblo de noche, ventanas de las casas
  iluminadas de noche, porche encendido en la casa que espera entrega (se combina con N-501).
- De noche (y al 50 % al atardecer) brillan el vidrio de los faroles del pueblo, las luces de los autos estacionados y las ventanas de las casas (`LowpolyMaterials.light_up()`, `night_level` que fija `WorldMood.pick()`), con un halo aditivo en cada farol y faro (`presentation/night_flares.gd`, un MultiMesh por ruta). El porche de la casa que espera ya estaba (N-501). Test `test_night_lights`.
- Revisión visual (2026-09-25, `render_world_features.gd`; `655c6f2`, `5cc1497`): no se veía ningún halo. El rango de visibilidad del MultiMesh se medía desde el centro de toda la ruta (a kilómetros) y lo ocultaba entero: sacado, y cada halo conserva su tamaño al girar hacia la cámara. El test lo cubre. Los faros de un auto estacionado son una sola malla: el halo iba al medio del paragolpes; ahora uno por faro (`NightFlares.lamp_centres()`), solo los delanteros, en un tono más cálido.

### N-305 · Identidad visual por zona — B · `Opus 5.5 · high` · Aviso: no · **[x] `94bed31`**

Con entregas de varios minutos, bosque-campo-pueblo se repiten.

- [x] Una paleta de follaje por sesión (verano / otoño) elegida por semilla, como el clima: tinte de hojas y
  pasto en `lowpoly_materials.gd` y `route_terrain.gdshader`.
- [x] Cartel de nombre de pueblo al entrar a cada zona de pueblo (ver N-601).
- `WorldMood` sortea también la estación (verano 55 % / otoño 45 %) con su propio flujo de la semilla: `LowpolyMaterials` lleva hojas, helechos y pasto a ocres (`AUTUMN`), el batcher cachea por estación y el terreno seca el pasto (`route_terrain.gdshader` `autumn`). Forzable con `--mood=...otono`. Carteles de pueblo: ver N-601. Test en `test_world_mood`.
- Revisión visual (2026-09-25, `render_world_features.gd`; `655c6f2`, `5cc1497`): los pinos se ponían ocres; ahora quedan verdes (`LowpolyMaterials.EVERGREEN`, por nombre de modelo, porque comparten la paleta de hojas).

### N-306 · Vehículos del depósito también en la ruta — C · `Opus 5.5 · medium` · Aviso: no · **[x] `94bed31`**

`sm_vehicle_tractor.glb` y `sm_vehicle_competitor_van.glb` solo se usan en el depósito.

- [x] Tractor en zona de campo (regla nueva en `route_dresser.gd`, raro, lejos del asfalto) y la camioneta de la
  competencia estacionada en pueblo. Test en `test_route_placement_rules.gd`.
- Reglas `tractor` (campo, 17-28 m del eje, a 320 m de otro) y `competitor_van` (pueblo, estacionada a lo largo como los autos) en `route_dresser.gd`, agregadas al final de la tabla para no mover el RNG de las demás y ordenadas antes de los árboles con el campo `order`. Sólidos (`dressing_batcher.gd`). Test en `test_route_placement_rules`.

### N-307 · Inventario y dirección visual al día — A · `Opus 5.5 · low` · Aviso: no · **[x] `220e6e0`**

- [x] `docs/inventario-assets.md`: sacar el ⛔ de la furgoneta (ya está integrada), marcar ✅ los cables entre
  postes y los autos nuevos, revisar cada 🟡.
- [x] `docs/direccion-visual.md`: cerrar los `[ ]` que ya están resueltos (escala de personajes, LOD, motion
  blur descartado) y dejar abiertos solo los vigentes. Antes #100.

### N-308 · Decisión de renderer — A · `Opus 5.5 · medium` · Aviso: sí (`project.godot`, solo si se cambia) · **[x] `ae775d7`**

Antes #34: SSAO bloqueado por GL Compatibility, decisión nunca tomada.

- [x] **Decisión recomendada:** quedarse en GL Compatibility para el MVP (hardware modesto, 60 FPS, el estilo
  low-poly no depende de SSAO). Compensar con oclusión horneada en vértices de los modelos (script de Blender)
  y sombras de contacto falsas bajo autos y casas (decal oscuro).
  - [x] **N-308.1** Oclusión horneada en colores de vértice al exportar los modelos (script de Blender,
    agente `modelador-blender`). **Hecho** `8238840` (ajuste) + `ae775d7` (aplicado).
    - `assets/tools/bake_vertex_ao.py` corre con el módulo de Python de Blender (`pip install bpy`, sin
      abrir Blender): rayos propios con BVH, `STRENGTH` 0,5, `FLOOR` 0,62 (ninguna esquina más oscura),
      subdivide aristas de más de 1 m y deja sin tocar vidrios, marcos, faroles y gomas (se acabaron la X
      oscura en el vidrio y el hollín en las ventanas).
    - Aplicado a 14 modelos: las 5 casas y el granero, los 5 vehículos (estacionados y del depósito), la
      parada de colectivo, el molino y el tanque de agua. Nunca vegetación (se instancia de a miles).
    - `LowpolyMaterials.apply()` activa `vertex_color_use_as_albedo` cuando la malla trae color (también
      fuera de `DETAIL`) y separa esos materiales en su caché, así el batcher no mezcla superficies.
    - Revisado de día y de noche en captura (`revisor-visual`): suma volumen bajo aleros, porches y
      autos sin oscurecer las fachadas. Test `test_baked_ao`.
  - [x] **N-308.2** Sombras de contacto falsas (decal oscuro y difuso) bajo autos estacionados, casas y
    cajas apiladas. `presentation/contact_shadow.gd`: sin `Decal` en Compatibility, es una malla 4×4 sin luz
    con el desvanecido por vértice, en metros (sólida desde `margen` adentro de la huella, nada a `margen`
    afuera). Autos estacionados de la ruta (cada vértice sobre el terreno: el auto se hunde al asentarse y
    una mancha colgada de él quedaba enterrada), casas (una por bloque de paredes) y en el depósito autos,
    contenedor y pallets. Los fardos/cajones de campo no: el camión los voltea. Test `test_contact_shadows`.
- [x] Registrar la decisión y su por qué en `docs/requerimientos-tecnicos.md` §1. Cerrar la fila #60 de
  `especificaciones-visuales.md`. (`0c7f0f1`)

---


### N-309 · Personaje redondeado: animaciones y rostro con vida — A · `Opus 5.5 · xhigh` · Aviso: sí (`player.gd` de Slatex) · **[x] Hecho (2026-09-25)**

Pedido del usuario: refinar el personaje y sus animaciones al máximo, sin perder lo tierno.

- [x] ~~Rehacer los cinco clips~~ **[x] Hecho (2026-09-25)** — `art/rounded_character/animation_library.py`:
  poses paramétricas, brazos en FK, pies que ruedan sobre bola/taco; `Walk` como trote corto a
  3,6 m/s, `Stroll` nuevo, `Jump` con "Y" y aterrizaje con arrastre, `PickUpPackage` en
  sentadilla sincronizada con la caja, `Sit` con manos en la panza. Detalle en `REFINAMIENTO.md`.
- [x] ~~Arreglar deformaciones~~ **[x] Hecho (2026-09-25)** — `model_fixes.py`: zapato que se
  dobla en el metatarso, rodilla, línea dentada del bajo de la camiseta, dobladillo y cuello.
- [x] ~~Parpadeo~~ **[x] Hecho (2026-09-25)** — `character_face.gd` `blink()`, también al aterrizar.
- Pendiente (ver "Límites conocidos" en `REFINAMIENTO.md`):
  - [x] ~~Sentadilla según la altura de la caja~~ **[x] `58e0de4`** — clip nuevo
    `PickUpHigh` (caja a la cintura, sin sentadilla, mismos tiempos) y `player.gd` mezcla los
    dos por la altura del agarre (`pickup_high_weight`, blend horneado en 1/8). Test:
    `test_player_character`.
  - [x] ~~Pasos al girar en el lugar~~ **[x] `75fdae5`** — clip nuevo `TurnInPlace`
    (dos pasitos en loop, 0,8 s) y `player.gd` lo elige parado y girando a más de 1,5 rad/s
    (`movement_state()`, histéresis hasta 0,8 rad/s); viaja en `anim_state`. Tests:
    `test_player_character`, `test_character_motion`.
  - [x] ~~Pliegue del short sentado~~ **[x] `84b94fb`**. En `model_fixes.py`, el
    tiro del short reparte su peso entre los dos muslos (la parte compartida L+R crece hacia
    el fondo y la diferencia L−R se mantiene), así ya no cuelga en punta entre las rodillas
    en `Sit`. Métrica en `check_deformation.py` (`--crotch-only`); test: `test_player_character`.

### N-310 · Personaje cartoon gordito — A · `Opus 5.5 · xhigh` · Aviso: sí (`character_face.gd`, GLB) · **[x] Hecho (2026-09-27)**

Pedido del usuario: modelo cartoon cómico y tierno, más gordito, "nivel Pixar".

- [x] Modelo (`art/rounded_character/build_character.py`, `head_shape.py`): cabeza esculpida por
  fórmula (elipsoide con papada; los cachetes salientes se sacaron a pedido), nariz de botón, orejas, pelo corto con flequillo en
  mechones y rulo (material nuevo `Hair`), panza más grande y adelantada, brazos, piernas y
  zapatos más regordetes. Mismos huesos y articulaciones: el juego no cambia.
- [x] Oclusión suave y rubor horneados en color de vértice (`vertex_shading.py`); ~23.500 triángulos.
- [x] Animación (`animation_library.py`): brazos que cuelgan separados de la panza (`HANG`,
  `GAIT_ARMS`), caminos de las manos al agarrar por delante de la panza (`PICKUP_*`,
  `CARRY_HANDS`), manos sentado sobre la panza nueva, panza y cabeza con más rebote al
  trotar y al aterrizar, bamboleo más marcado. Medido con `check_clearance.py`.
- [x] Ojos ovalados con brillos redondos (`build_faces.py`); `character_face.gd` apoya la cara
  sobre la cabeza nueva. Test: `test_player_character` (cara sobre la piel, color de vértice).
- [x] Asientos remedidos para el cuerpo nuevo (`player_seat_pose.gd`, rulo más bajo para el conductor).
- [x] Ajustes tras verlo en el juego: sin cachetes salientes (el usuario no los quería), piernas sin
  decimar y oclusión horneada con rayos fijos y suavizado (el ruido se veía como rayas en las
  pantorrillas y ondas bajo el flequillo), rubor subido a los pómulos.
- Pendiente: la nuca del conductor roza el techo inclinado de la cabina y los pasajeros vecinos
  se superponen (asientos a 0,48 m); ver "Límites conocidos" en `REFINAMIENTO.md`.

### N-139 · Caja de herramientas y termo de la zona de carga con modelo — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-139-cargo-clutter`**

Hoy `scripts/presentation/cargo_clutter.gd` arma la caja de herramientas (BoxMesh 0,36×0,2×0,2 m roja + manija) y el
termo (CylinderMesh r 0,045 h 0,26 + tapa) con primitivas, y se ven de cerca en la zona de carga (`docs/inventario-assets.md`
§10.1). Colisiones (BoxShape y CylinderShape), masas y capas NO cambian: solo la malla visual pasa a un GLB del mismo tamaño y
centrado en el cuerpo, como la primitiva actual. **Necesita PC** (Blender). Origen: sesión de arte 2026-09-30.
Hecho cuando hay dos GLB low-poly (caja de herramientas metálica roja con manija, cierres y bisagra; termo con tapa/vaso y asa)
generados por script, dentro del presupuesto de props chicos de primer plano del inventario (~300-800 tris cada uno), cargados
por `cargo_clutter.gd` en vez de las primitivas, con `test_cargo_clutter` ampliado para exigir que la malla viene del GLB,
verificado con `revisor-visual` y `check_pivots.gd`, y con el inventario §10.1 actualizado.
- [x] **N-139.1** ~~Modelar las dos piezas por script en `do-not-drop/assets/tools/` con `lowpoly_kit.py`, exportar a
  `do-not-drop/assets/models/...` con las medidas y el origen de las primitivas. Con `modelador-blender`; tests `cargo_clutter`.~~
  **[x] Hecho (2026-09-30)** — `assets/tools/build_cargo_clutter.py` → `models/props/cargo/sm_prop_cargo_toolbox.glb` (756 tris,
  cuerpo exacto 0,36×0,20×0,20 + manija) y `sm_prop_cargo_thermos.glb` (600, r 0,045 × 0,26 + tapa-vaso y asa); origen en el
  centro de la base, como el resto del pipeline.
- [x] **N-139.2** ~~Cambiar `cargo_clutter.gd` para instanciar los GLB como malla visual, sin tocar formas de colisión, masas ni
  capas; ampliar `test_cargo_clutter` (malla del GLB, tamaño y colisión iguales). Con `constructor-mundo` y `escritor-tests`;
  tests `cargo_clutter`.~~ **[x] Hecho (2026-09-30)** — `cargo_clutter.gd` `_make_item()` instancia el GLB bajado −alto/2
  (`TOOLBOX_MODEL`, `THERMOS_MODEL`), sin primitivas; `test_cargo_clutter` `_check_looks()` exige la escena del GLB, ninguna
  `PrimitiveMesh`, las colisiones de siempre y que la malla quepa en ellas (salvo manija, tapa y asa).
- [x] **N-139.3** ~~Verificar de cerca con `revisor-visual` (capturas de la zona de carga y `check_pivots.gd`) y actualizar
  `docs/inventario-assets.md` §10.1. Con `revisor-visual` y `documentador`.~~ **[x] Hecho (2026-09-30)** — con GPU real: apoyan
  en el piso y el banco, se leen como caja y termo; pivotes en la base (los dos GLB sumados a `check_pivots.gd`); inventario
  §10.1 y `assets/README.md` al día.

## 4. Audio y diseño sonoro

### N-401 · Motor con más vida — B · `Opus 5.5 · high` · Aviso: sí (`synth_audio.gd`, solo funciones nuevas) · **[x] `8081c75`**

- [x] Capas por RPM (ralentí, medio, alto) mezcladas según velocidad y acelerador; cambio de marcha audible
  (bajón breve de RPM) en la clásica, más agudo y rápido en la ágil.
- [x] Test en `test_vehicle_audio.gd`: las capas cambian de volumen con la velocidad.
- Tres capas (ralentí, medio, acelerado) al mismo RMS, cruzadas por un cuentavueltas con caja en `vehicle_presentation.gd`; cada cambio corta el acelerador y baja las vueltas. Clásica: 4 marchas, corta a 3500 rpm, 0,38 s; ágil: 5 marchas, 5000 rpm, 0,16 s y 14 % más aguda. Detalle en `docs/audio-mundo.md`.

### N-402 · Eco en el túnel y bajo techo — B · `Opus 5.5 · high` · Aviso: no · **[x] `8081c75`**

Pendiente del #58 viejo.

- [x] `Area3D` en `TunnelSegment` que al entrar la cámara pasa el sonido del mundo a un bus `Tunnel` con reverb
  larga, y al salir vuelve. Mismo mecanismo para el depósito (`roofed_area`).
- [x] Revisar la lluvia con cámaras exteriores ancladas al camión (pendiente del #68 viejo).
- `AcousticZone` (Area3D) a lo largo de cada túnel y el depósito en el grupo `acoustic_space`; `AcousticSpace` prende una reverb (agregada en ejecución a SFX y Exterior) según dónde esté la cámara: túnel larga, depósito media, afuera nada. #68: una cámara anclada al camión desde afuera ya no cuenta como adentro para lluvia y ambiente (`VehiclePresentation.viewer_inside()`). Test `test_acoustic_space`.

### N-403 · Música del menú y del depósito — B · `Opus 5.5 · medium` · Aviso: sí (una línea en `main_menu.gd`) · **[x] `8081c75`**

Hoy hay una sola pista (`mus_ingame_loop.ogg`).

- [x] Una pista de menú y una "radio del depósito" (la radio ya existe como objeto en `depot.gd`). Origen:
  encargo, música libre con licencia compatible, o generada con registro en `art/ai-registro.md`. Anotar
  licencia al lado del archivo.
- [x] `scripts/presentation/menu_music.gd` autocontenido; `main_menu.gd` solo lo instancia (aviso).
- Compuestas por código (`tools/audio/compose_music.py`, sin samples ni terceros; licencia en `assets/audio/music/LICENCIA.md`): `mus_menu_loop.ogg` y `mus_depot_radio_loop.ogg`. `menu_music.gd` la agrega `main_menu.gd` (aviso); la radio del depósito pasa el programa. Niveles medidos (`loudness.json`). Test `test_music_tracks`.

### N-404 · Mezcla medida del dominio — A · `Opus 5.5 · high` · Aviso: no · **[x] `e9a89db`**

Cierra el #83 viejo sin depender del oído.

- [x] Mismo método que la S-404 de Slatex, sobre los sonidos de Nacho: script que genera cada sonido de
  `synth_audio.gd` del mundo y del camión, calcula RMS y pico en dBFS, y los lleva a objetivos (motor −20 dBFS
  RMS, impactos −14 pico, ambiente −28 RMS, lluvia −24).
- [x] Tabla antes/después en `docs/direccion-visual.md` (audio) o `docs/audio.md` si Slatex ya lo creó.
- Tabla en `docs/audio-mundo.md` (no existía ninguno de los dos). Todos los niveles pasan a
  `presentation/world_mix.gd`; `test_world_audio_levels` los mide (21 sonidos, 8 clases) y exige ±2 dB. Se
  sumaron tres clases: "señal" −18 (la misma escala que la S-404 de Slatex), "naturaleza" (pájaros y grillos,
  por sus 100 ms más fuertes: su RMS engaña) y "detalle" / "música". Cambio grande: motor +14 dB, lluvia +17,
  pájaros +19; golpes −8, vecino −11/−13. `synth_audio.gd` no se tocó.

### N-405 · Sonidos de los peligros nuevos — C · `Opus 5.5 · medium` · Aviso: no · **[x] `467361a`**

- [x] Balido de ovejas, ladrido, golpe de rama, sintetizados, para N-106.

---
- Ladrido y balido sintetizados (`dog_bark()`, `sheep_bleat()`); el golpe de rama es el golpe normal del camión. Aviso por `synth_audio.gd`.

## 5. UI / UX (en el mundo)

La UI de pantalla es de Slatex. Nacho se encarga de la guía **dentro del mundo**, que no necesita
tocar el HUD.

### N-501 · Saber de lejos qué casa espera entrega — A · `Opus 5.5 · high` · Aviso: no · **[x] `a4b6803`**

- [x] La casa que espera paquete tiene: porche encendido, buzón con su número grande, y un cartel en el jardín
  con el código de la caja que espera (el mismo de la pizarra del depósito, `A-3`). Al resolverse, se apaga.
- [x] Visible a 120 m de día y de noche. Captura con `revisor-visual`.
- Ajustado en cuatro pasadas de revisión visual: globo naranja sobre el techo (de día, a 120 m), halo de la luz del porche (de noche), cartel en V a 40°, número del buzón en los costados, líneas de visión despejadas en los últimos 120 m, 3 m de jardín delante de cada casa y ningún túnel justo después de una casa.

### N-502 · GPS en el tablero (UI diegética) — B · `Opus 5.5 · high` · Aviso: no · **[x] `67e8abc`**

- [x] Pantallita en el tablero del camión (`SubViewport` o `Label3D`) con distancia a la próxima casa, flecha
  de dirección y el código de la caja que espera. Solo lee datos de `route.gd` y de la asignación de casas.
- [x] En Endless muestra la distancia recorrida y el récord.
- Reemplaza a la radio en el centro del tablero, inclinado hacia el ojo del conductor; `check_driver_sightline` sigue pasando.

### N-503 · Señalización del depósito — A · `Opus 5.5 · medium` · Aviso: no · **[x] `29d9aca`**

- [x] Flechas pintadas en el piso y carteles colgantes: "ESTANTES", "PIZARRA", "VESTUARIO", "TALLER",
  "SUMINISTROS", "CAMIÓN → PORTÓN". Un jugador nuevo encuentra cada estación sin que nadie le diga.
- [x] Captura desde el punto donde aparece el jugador: al menos 4 carteles legibles.
- [x] Espejo de cuerpo entero en el vestuario que refleja de verdad, para verse el uniforme
  (`depot/depot_mirror.gd`, test `test_depot_mirror`). Pedido del usuario, 2026-09-24. Después: de lejos
  (fuera de los 9 m en que se actualiza) se veía negro; ahora saca una foto del salón al arrancar, con la
  cámara del reflejo sin interpolación física (si no, salía la ruta de afuera).
- Hecho en `depot.gd` `_build_wayfinding()`: desde el spawn se leen 6 carteles colgantes ("← ESTANTES" y
  "PIZARRA" sobre la pizarra, "CAMIÓN → PORTÓN" sobre el camión, "VESTUARIO →" y "SUMINISTROS →" a la
  derecha, y el "TALLER" que ya estaba). Las flechas de los carteles se dibujan como forma, solo en la cara de
  adelante. En el piso, alrededor del spawn, hay una flecha con su palabra hacia cada estación, del color de
  su cartel, y flechas a los costados del camión hacia el portón. Los estantes pasan a llamarse "ESTANTE A/B",
  como en la pizarra. De paso se arregló un panel de la oficina que medía 23 m en vez de 4 y tapaba el cartel
  de SUMINISTROS. `test_depot` cuenta los carteles legibles desde el spawn con proyección y rayos, sin render.

### N-504 · La cámara no atraviesa la cabina — B · `Opus 5.5 · xhigh` · Aviso: sí (`first_person_camera.gd`) · **[x] `8c8aff2`**

Antes #15 y #38.

- [x] Límite de pitch y giro por asiento (el conductor no puede mirar a través del techo ni de la
  mampara). Para no tocar `seat_point.gd` (de Slatex), los límites viven en `vehicle.tscn`: un `Marker3D`
  por asiento con metadatos `pitch_min`, `pitch_max`, `yaw_max`, y `first_person_camera.gd` los lee de la
  cámara del asiento activo. Aviso por el archivo compartido.
- [x] Si la cámara igual queda a menos de 10 cm de una pared, retroceder a lo largo de la línea de mirada.
- `LookLimits` (Marker3D con `pitch_min`/`pitch_max`/`yaw_max`) en los 11 puntos de ojos de `vehicle.tscn`; conductor −55°/+32°/110°, carga −60°/+55°/120°. `first_person_camera.gd` los lee y, con algo sólido a menos de 10 cm adelante, retrocede la vista por la línea de mirada. Test `test_seat_look_limits`.

---

## 6. Narrativa y guion (narrativa ambiental del mundo)

La premisa, los clientes y los textos de las cajas son de Slatex (su S-601 a S-605). Nacho cuenta la
historia **con el entorno**, sin esperar esos textos.

### N-601 · Pueblos con nombre y carteles — B · `Opus 5.5 · medium` · Aviso: no · **[x] `94bed31`**

- [x] Lista de 12 nombres de pueblo con tono de humor ("Villa Frágil", "Paso del Golpe", "Bajada Lenta")
  elegidos por semilla; cartel de entrada y salida de cada zona de pueblo.
- `route/town_sign.gd`: 12 nombres repartidos por semilla sin repetir, cartel verde "Bienvenidos a …" al entrar a cada zona de pueblo y el nombre tachado al salir, a la derecha y mirando al camión (`RouteDresser._dress_town_signs()`). Test `test_town_signs`.

### N-602 · Historias en la banquina — C · `Opus 5.5 · medium` · Aviso: no · **[x] `94bed31`**

- [x] Escenas estáticas raras (1 cada ~800 m como máximo): la camioneta de la competencia con cajas
  desparramadas y la puerta abierta; una gallina suelta al lado de una caja rota; un cartel "Take My Package:
  entregamos (casi) todo" en una valla publicitaria.
- `route/roadside_story.gd`: la camioneta de la competencia en la cuneta con la puerta trasera abierta y las cajas desparramadas, una gallina picoteando al lado de su caja rota, y el cartel "TAKE MY PACKAGE — entregamos (casi) todo". Como mucho una cada 800 m, desde los 250 m, sin repetir tipo hasta usar los tres. Test `test_roadside_stories`.
- Revisión visual (2026-09-25, `render_world_features.gd`; `655c6f2`, `5cc1497`): el texto del cartel se salía del panel (ahora se achica hasta entrar, también traducido) y la caja tapaba una letra (ahora está sobre el borde de arriba); la camioneta tenía la trompa para arriba y todo quedaba a la altura del origen de la escena, flotando o enterrado en la pendiente de la banquina. `RoadsideStory.fit_to_ground()` apoya cada pieza en el terreno y clava la trompa 45 cm con la cola 40 cm en el aire, sea cual sea la pendiente.

### N-603 · El depósito cuenta la campaña — C · `Opus 5.5 · high` · Aviso: no · **[x] `94bed31`**

- [x] Cartel "Días sin accidentes: N" que vuelve a 0 cuando una partida termina con carga arruinada (lee el
  resultado de `run_ended`), y una pared de fotos con las fotos de entrega de la campaña (miniaturas que ya
  captura `phone_camera.gd`).
- `depot/depot_campaign_board.gd`: el cartel junto al portón cuenta partidas sin cajas rotas (vuelve a 0 con una, guarda el récord) y la pared de fotos arriba del café muestra las últimas 8 fotos de entrega del celular, guardadas en `user://` al terminar cada partida. Test `test_depot_campaign_board`. Chinches de colores en cada foto; la pared se corrió para no pisar el pizarrón del equipo.

### N-604 · Reacciones en la puerta — B · `Opus 5.5 · high` · Aviso: no · **[x] `94bed31`**

- [x] En `delivery_house.gd`, animación y globo de texto del vecino según el resultado (contento, abre la caja
  y se agarra la cabeza, se lleva la caja equivocada de vuelta, no está y deja una nota). Pool de 5 frases por
  resultado en `delivery_house.gd`.
- `presentation/door_reaction.gd` + `DeliveryHouse.REACTION_LINES`: salta contento, revisa la caja, se agarra la cabeza con las dos manos (IK), devuelve la caja equivocada negando con la cabeza, o deja una nota en la puerta. Reacciona al registro que el host manda a todos (ahora los clientes también ven al vecino); 5 frases por resultado elegidas por semilla. Test `test_door_reactions`.
- Revisión visual (2026-09-25, `render_world_features.gd`; `655c6f2`, `5cc1497`): el vecino le daba la espalda a la calle (el modelo mira a −Z), el globo quedaba tapado por la lamparita del porche y la nota quedaba enterrada dentro de la puerta. Arreglados los tres, con test. Las manos que se agarran la cabeza quedaban adentro y detrás de ella (13 cm al costado, cabeza de 19 cm de radio): ahora van por fuera y adelante.

### N-605 · Textos del mundo traducibles — B · `Opus 5.5 · high` · Aviso: no · **[x] `94bed31`**

Complementa la S-509 de Slatex sin esperarla.

- [x] Pasar los textos de los archivos de Nacho (casas, depósito, ciervo, cruce, carteles de pueblo) a
  `do-not-drop/translations/strings_world.csv` (columnas `es,en`, claves `WORLD_*`) y usar `tr()`. Godot admite
  varios CSV, así que no choca con el de Slatex. Registrar el CSV en `project.godot` (aviso).
- [x] Traducción al inglés.
- 130 textos del mundo en `translations/strings_world.csv` (claves `WORLD_*`, columnas `es,en`) con `tr()`: depósito, casas y vecino, GPS, ciervo y ovejas, puertas del camión, carteles de pueblo, historias. Registrado en `project.godot`; hasta la S-509 el juego fuerza español (`game_settings.gd`, aviso). Los prompts de asiento de `vehicle.tscn` quedan para la S-509. Test `test_world_translations`.

---

## 7. Producción y gestión de proyecto

### N-701 · Cerrar formalmente lo que no se hace en el MVP — A · `Opus 5.5 · low` · Aviso: no · **[x] `b6d7439`**

- [x] Registrar como "fuera del MVP" en `docs/plan-desarrollo.md` (misma sección que la S-702 de Slatex; si ya
  existe, sumar filas): tráfico en movimiento (#76/#77/#79 viejos), puente con prioridad de paso (#59), curva
  peraltada (#65), motion blur (#14), rotonda (#60). Cualquier idea nueva va a "Después del lanzamiento".

### N-702 · Esta lista como tablero — A · `Opus 5.5 · low` · Aviso: no

Tarea permanente: no se cierra, se cumple en cada tanda.

- [x] `[x]` + hash al cerrar. Tarea que crece se parte acá antes de seguir. Revisión semanal de "Última
  actualización". (Tanda del 2026-09-25: cada tarea cerrada con su hash; la revisión visual y las
  capturas quedaron anotadas en su tarea.)
- [x] Verificar después de cada tarea grande `test_vehicle_presentation`, `test_vehicle_audio`,
  `test_route_streaming` y `check_driver_sightline` (antes #99). (2026-09-25: los tres primeros en la
  batería completa del `pre-push`, 115/116 con `test_look_controls` pasado aparte con pantalla;
  `check_driver_sightline` PASS, ahora ignora mallas ocultas y overlays con `ALPHA`.)

### N-703 · Hitos de lanzamiento con fecha — B · `Opus 5.5 · medium` · Aviso: no · **[x] `3e23947`**

- [x] En `docs/plan-desarrollo.md` Fase 7: fechas objetivo para "contenido cerrado", "página de Steam
  publicada", "build de demo", "Early Access". Una por mes como máximo de distancia entre hitos.
- Contenido cerrado 2026-10-30, página de Steam 2026-11-27, demo 2026-12-18, Early Access 2027-01-22, con qué significa "listo" y de qué depende cada uno (`plan-desarrollo.md` Fase 7).

---

## 8. QA (sin playtesting)

### N-801 · Fuzz de generación de ruta — A · `Opus 5.5 · high` · Aviso: no · **[x] `38ca576`**

- [x] `tests/test_route_fuzz.gd`: 500 semillas × 1-4 casas. Falla si: el camino se cruza consigo mismo,
  una casa o su jardín queda sobre el asfalto, un árbol sólido queda a menos de 2 m del carril, dos tramos se
  superponen, el terreno bajo el asfalto tiene un escalón de más de 0,3 m, o la meta queda inalcanzable.
- [x] Guardar las semillas que fallaron en el mensaje, para reproducir.
- Las 500 × 4 del cruce se revisan sobre el plan (rápido); las comprobaciones que necesitan geometría, sobre 20 rutas construidas.

### N-802 · Determinismo entre jugadores — A · `Opus 5.5 · high` · Aviso: no · **[x] `38ca576`**

- [x] Test de un solo proceso: armar la ruta, el decorado y el depósito dos veces con la misma semilla y
  comparar un hash de todas las posiciones. Cualquier `randf()` sin la semilla de sesión lo rompe (fue el bug
  del #122 viejo).

### N-803 · Estrés del camión en las rutas nuevas — B · `Opus 5.5 · high` · Aviso: no · **[x] `abf72b8`**

- [x] Ampliar `test_vehicle_stress.gd` a la ruta curva con casas (no solo Endless): 3 minutos de manejo agresivo
  sin NaN, sin salir del mundo y sin quedar atascado sin que salte la detección.
- `test_vehicle_stress.gd` maneja 3 minutos agresivos (a fondo, frenadas con freno de mano, zigzag) por la ruta curva con 4 casas en 4 semillas. Encontró un bloqueo real: el camión que rozaba el primer cono de una obra caía con el chasis sobre la valla o un cono (0,9/0,65 m, más que su despeje) y ninguna red de seguridad terminaba la partida. Arreglos: los conos de obra son cuerpos livianos que el camión voltea, la colisión de la valla y de los bloques de chicana y curva en S mide 1,6 m (se dibujan igual), y `level_base.gd` suma la regla de atascado (acelerador apretado y camión quieto 6 s, como Endless; test `test_stuck_detection`). El bot mira adelante y esquiva; "atascado" en el test es inmovilizado (menos de 3 m en 12 s), no dar vueltas.

### N-804 · Recorrido técnico del mundo — A · `Opus 5.5 · low` · Aviso: no · **[x] `ba67f84`**

Esto no es playtesting (no juzga diversión), busca errores.

- [x] Checklist en `docs/qa-recorrido.md` (sección de Nacho; si Slatex ya lo creó, sumarla): cada clima × hora
  del día una vez, túnel, cruce de tren, puente, ripio, ciervo, depósito completo y portón. Anotar errores de
  consola y capturas raras.

---

## 9. Negocio, marketing y distribución

> **⏸ Pospuesto (2026-09-28):** estamos en desarrollo y refinamiento, así que lo de publicar en Steam
> y promocionar el juego queda para una iteración de lanzamiento. Las tareas marcadas ⏸ no se trabajan
> ni cuentan como pendientes hasta que se reabra esta sección.

### N-901 · Steamworks y AppID propio — A (decisión) · `Opus 5.5 · medium` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

Hoy se usa el AppID 480 (Spacewar), que no se puede publicar.

- [ ] Crear la cuenta de Steamworks y pagar el Steam Direct (USD 100 por juego). Anotar el AppID en
  `steam_appid.txt` y en `network_manager.gd` (aviso).
- [ ] Volver a verificar el flujo de invitación de amigos con el AppID real (la crítica §7 avisa que nunca se
  probó con el juego real).

### N-902 · Herramienta de cámara para tráiler — B · `Opus 5.5 · high` · Aviso: no · **[x] `8ffbb2f`**

- [x] Cámara libre de depuración (solo build de debug) con rieles: grabar 3-4 puntos y que la cámara los
  recorra suave mientras el camión maneja solo. Reutilizar `results_orbit.gd` como base.
- [x] 6 planos guardados: salida del depósito con el portón, curva en el bosque, cruce de tren, puente angosto
  con lluvia, llegada a una casa de noche, vuelco con cajas volando.
- `scripts/tools/trailer_camera.gd` (sobre `results_orbit.gd`): en builds de debug F7 cámara libre, F5 graba un punto de riel relativo al camión, F6 lo reproduce, F8 lo imprime. `scenes/tools/trailer_shot.tscn` reproduce un plano de `data/trailer_shots.json` con el camión manejado por piloto automático: salida del depósito, curva en el bosque (otoño), cruce de tren, puente angosto con lluvia, llegada a una casa de noche vuelco (con 4 cajas que salen volando y el camión que queda tumbado) y el ciervo del devlog. `--still`/`--frames` sacan capturas; `--write-movie` graba. Nada de eso se exporta. Test `test_trailer_shots`. Cada plano arranca con el camión lejos del depósito (semilla con el tramo a más de `lead + 60 m`), puertas cerradas y sin HUD ni carteles flotantes; el test reproduce la casa de noche, el tren y el ciervo y verifica que el camión, el tren y el ciervo queden en cuadro. Arreglos tras revisar las capturas: `61d2b5f`, `e0fb236`, `08f62b0`, `77da5a8`.

### N-903 · Guion del tráiler — B · `Opus 5.5 · medium` · Aviso: no · **[x] `ee2cefd`**

- [x] `docs/marketing/trailer.md`: 60-90 s, plano por plano (qué se ve, qué suena, texto en pantalla), con los
  planos de N-902 y los momentos de falla de las cajas de Slatex (S-310). Primer gancho en los primeros 5 s.

### N-904 · Competidores de manejo cooperativo — B · `Opus 5.5 · medium` · Aviso: no · **[x] `e362f7f`**

- [x] `docs/marketing/competidores-manejo.md`: Drive Together, Co-Drive Chaos, Deliver Together, Totally
  Reliable Delivery Service: precio, reseñas de Steam (qué elogian y qué critican del manejo), cantidad de
  jugadores, cómo se ven sus páginas. Qué hacemos distinto (roles asimétricos) en una frase.

### N-905 · Capturas del mundo para la tienda — C · `Opus 5.5 · medium` · Aviso: no · **[x] `f74b26e`**

- [x] Con N-902: 5 capturas 1920×1080 sin HUD de paisaje, clima y camión. Se suman a las de Slatex (S-902).
- `art/marketing/capturas/2026-09-25_*.png` (`f74b26e`, `b28efa1`): salida del depósito por el portón,
  curva del bosque en otoño, cruce de tren con la barrera baja y la locomotora entrando, puente con lluvia y
  llegada a la casa de noche. Sacadas con `trailer_shot.tscn` (`--fixed-fps 10 --frames`, el mejor cuadro de
  cada plano). Las primeras tandas se descartaron: el camión fuera de cuadro, la cámara dentro de una pared
  y el cartel de "¡A REPARTIR!" en el primer cuadro; esos arreglos están en N-902.
- A mejorar en una próxima tanda: de noche el camión queda casi negro (solo se leen los faros) y el "puente"
  no tiene agua ni desnivel debajo, así que se lee como una ruta con barandas.

### N-906 · Devlog en GIF — C · `Opus 5.5 · low` · Aviso: no · **[x] `4363a0a`**

Tarea semanal: estos son los cuatro primeros; la costumbre sigue.

- [x] Un GIF corto por semana (ciervo, tren, vuelco, lluvia) desde la cámara de tráiler, para redes. Carpeta
  `art/devlog/` fuera de `do-not-drop/` para que no entre al build.
- `art/devlog/2026-09-25_{ciervo,tren,vuelco,lluvia}.gif` (`b28efa1`, `4363a0a`), 480 px de ancho y
  menos de 8 MiB cada uno: el ciervo cruza delante del camión, el tren pasa entre la cámara y el camión
  frenado en la barrera, el camión vuelca, se queda tumbado y las cajas salen volando por atrás, y la
  persecución bajo la lluvia. `tools/devlog/make_gif.py` arma una paleta con cuadros de todo el clip.

---

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

### N-704 · Corregir el diferencial y criticar las ideas grandes — A · `Opus 5.5 · low` · Aviso: no · **[x] `c0bfeb5`**

- [x] **N-704.1** `docs/definicion-proyecto.md`: quitar "no encontramos roles asimétricos replicados"
  (Backseat Drivers los tiene desde oct-2025). Diferencial nuevo: asimetría **entre pasajeros** (cada uno
  con su trampa) + la carga como protagonista, con revisión del cliente en la puerta.
- [x] **N-704.2** `docs/investigacion-mercado.md` y `docs/marketing/competidores-manejo.md` (N-904): sumar
  RV There Yet? (4,5 M copias, ~8 USD, game jam) y Backseat Drivers (Friend Pass, ≈78 % positivas).
- [x] **N-704.3** Pasar N-212, N-214 y N-112 por `critico-diseno` antes de empezarlas; anotar el
  veredicto en cada tarea.
- Hecho cuando: los tres docs dicen lo mismo sobre el diferencial y las tres tareas tienen veredicto.
- Hecho: `definicion-proyecto.md`, `investigacion-mercado.md` y `competidores-manejo.md` dicen el mismo
  diferencial (asimetría entre pasajeros + la carga protagonista, revisada en la puerta) y suman RV There Yet?
  y Backseat Drivers. `critico-diseno`: N-212 y N-214 a favor con cambios, N-112 en contra (veredictos abajo).

### N-505 · Indicaciones rápidas con voz de personaje — A · `Opus 5.5 · high` · Aviso: sí (UI y jugador de Slatex, `synth_audio.gd` solo funciones nuevas) · **[x] `c488838`**

Versión barata de la voz (N-212) que funciona sin micrófono y en solitario.

- [x] **N-505.1** Rueda radial (D-pad / rueda del mouse + tecla) con 6-8 frases: "¡Frená!", "¡Bache!",
  "¡Ayuda acá!", "¡Se cae!", "Tengo la cinta", "Esperá", "¡Dale, dale!". `ad3e2d9` — se reusó la rueda de
  pings que ya existía (mantener la tecla de ping, apuntar con mouse o stick derecho): `PingCatalog` pasa
  de seis a ocho frases ("¡Cuidado!" sigue siendo el toque corto) con clave `HUD_CALLOUT_*` en
  `strings_ui.csv`; lo que viaja por la red sigue siendo la frase en castellano. Salen "Acá", "Gracias"
  y "Sí/No".
- [x] **N-505.2** Cada frase: ícono sobre la cabeza del jugador, entrada en el HUD mínimo del conductor
  ("pedidos de freno" de `jugabilidad-paquetes-rescate.md`) y voz sintetizada en `SynthAudio` con tono
  por color de jugador. **Hecho (`ad3e2d9`):** el ícono ya lo ponía `HudNotices._mark_pinger()`; el conductor
  ve la frase de otro tripulante grande en el centro (`ping_indicator`, color de la frase).
  **Voz (`c488838`):** `SynthAudio.callout_voice(color, sílabas)` balbucea una sílaba por grupo de vocales
  de la frase (`PingCatalog.syllables()`), con tono base según el color del jugador (peer id módulo
  cinco, 150-310 Hz) y la boca que salta entre vocales como el ladrido del perro. `HudNotices._speak()`
  la hace sonar desde la cabeza del que avisa (la propia, plana); nivel `CALLOUT_VOICE_DB` medido
  como "signal" en `test_world_audio_levels`.
- [x] **N-505.3** RPC confiable al host y reenvío a todos; enfriamiento de 1,5 s por jugador. `ad3e2d9` — el
  RPC y el reenvío ya eran `EventBus.request_ping()`; el host ahora descarta la segunda frase del mismo
  jugador dentro de `ping_cooldown_seconds` (1,5 s).
- [x] Test `test_quick_callouts.gd`: la frase llega a todos, el enfriamiento corta el spam y el conductor
  la ve en su HUD. Textos en el CSV de traducciones. `ad3e2d9` (`test_ping` ajustado a las ocho frases).

### N-213 · Carga que sale del camión y rescate afuera — A · `Opus 5.5 · xhigh` · Aviso: sí (`DeliveryPackage`, `RunManager`) · **[x] `2ee38e1`**

Generaliza "la gallina se escapa afuera" a cualquier caja despedida del camión.

- [x] **N-213.1** Un paquete fuera del camión deja de ir directo a `RUINED`: queda en el suelo con marcador
  y una ventana de rescate (más larga que los 8-15 s de adentro; medirla con el bot). `d8a014b` —
  `LevelCommon._check_lost_cargo()` (host) abre una ventana de `overboard_rescue_seconds` (30 s) y
  relaya `EventBus.cargo_overboard` / `cargo_overboard_ended`; `presentation/overboard_marker.gd` pone en
  cada par un cartel "¡RESCATAR! N s" que sigue a la caja (rojo en los últimos 10 s). Al vencer, `mark_lost`.
  **Pendiente:** los 30 s no se midieron con el bot (valor tentativo; ajustarlo con `bench_route_duration`
  o playtesting).
- [x] **N-213.2** Bajar a buscarlo: levantarlo y volver a subirlo al estante o al regazo. `d8a014b` — ya
  se podía levantar y volver a montar; ahora levantarla cierra la ventana como rescatada (y la subida
  premia `rescued` como antes).
- [x] **N-213.3** Caña o gancho de rescate (mejora de tienda, rama Supervivencia): desde la puerta trasera,
  un pasajero engancha una caja cercana sin frenar. El cliente solo manda la intención; el host resuelve.
  `2ee38e1` — suministro `rescue_hook` del depósito ($30, se compra o se vota como el acolchado y el
  seguro; los suministros no tienen ramas, la de Supervivencia queda en el texto). `depot.begin_run()` arma
  `gameplay/vehicle/rescue_hook.gd`, un `Interactable` que `LevelCommon` cuelga del poste izquierdo de la
  puerta trasera (sin tocar `vehicle.gd`), con un palo amarillo visible solo en ese recorrido. Con la
  puerta abierta y las manos libres, "Enganchar la caja caída" le da al pasajero (`take_by()` en el host,
  vía `request_interact`) la caja caída más cercana a ≤ 7 m del gancho; eso cierra la ventana como
  rescatada. Enfriamiento de 3 s; se guarda al terminar la partida. **Pendiente:** el estado armado
  llega por RPC en `begin_run`, así que un cliente que recarga a mitad de reparto no lo ve; el alcance
  (7 m) es tentativo, sin medir con el bot.
- [x] **N-213.4** Abandonarlo cierra el pedido vacío (resultado "Perdido"), sin terminar la partida.
  `33f7702` — al vencer la ventana, `LevelCommon._check_lost_cargo()` llama a `Route.close_lost_order()`
  antes de `mark_lost`: la casa queda resuelta con el resultado nuevo `&"lost"` (`DeliveryHouse.close_lost()`,
  sin vecino en la puerta) y `RunManager` la saca de la carga, así que perder la última caja ya no corta la
  partida. `RunManager.handed_over()` reemplaza los `!= &"missed"` (foto, plazos, pago de rescate); en
  resultados, "PERDIDO ✕" y la línea "Paquetes perdidos en la ruta" con la multa de una casa sin entregar;
  la pizarra del depósito marca "PERDIDO". "Abandonar" es dejar vencer la ventana: no hay botón aparte.
- [x] Tests `test_cargo_overboard.gd` (ventana, recogida, abandono) y ampliar el de red con dos clientes
  que intentan agarrar la misma caja. **Parcial (`d8a014b`):** `test_cargo_overboard.gd` cubre ventana,
  cartel, recogida y pérdida al vencer; faltan el abandono (N-213.4) y el caso de red. `33f7702`: suma el
  abandono (pedido "Perdido", la partida sigue, sin foto, línea propia en resultados); falta el caso de red.
  `1e3c226`: el caso de red, en `tests/net_trio.gd`: los dos clientes piden a la vez la misma caja, el host
  se la da a uno solo y los tres pares nombran al mismo dueño (`grab=`). El host arma de entrada las casas
  de la tripulación completa, porque si no reinicia el nivel 3 s después del último en entrar
  (`level_base.gd`). También `play_area.gd` ya no castea un jugador liberado mientras el host recarga.
  La caja disputada está en el depósito, no caída en la ruta: el agarre pasa por el mismo `take_by()`.
  Queda solo N-213.3 (gancho). `2ee38e1`: el gancho, en `test_cargo_overboard.gd` (estante: nada que
  enganchar; lejos o con la puerta cerrada no; al alcance sí, cierra la ventana como rescatada).

### N-214 · Averías del camión reparables con el kit — A · `Opus 5.5 · xhigh` · Aviso: sí (camión congelado: componente aparte) · **[x] `dc0f925`**

> **Veredicto `critico-diseno` (N-704.3, 2026-09-28): a favor con cambios.** Reutiliza el kit y da
> historias para resultados, pero 2 de las 5 averías dependen de lluvia o noche, el asiento flojo no se ve y
> sumar avería a un choque agranda el error. Condiciones: primera versión con **2 averías** (puerta trasera
> que se abre sola, enganchada con N-213, y espejo reemplazado por el celular); cada avería se avisa con
> sonido y algo visible en el golpe; **como mucho 1 por entrega**, ninguna saca al conductor ni va directo a
> RUINED; el repuesto cuesta menos que lo que se pierde sin arreglarlo pero más que la cinta.
> Limpiaparabrisas, faro y asiento esperan a que haya lluvia y noche en las rutas.

- [x] **N-214.1** Componente `VehicleFaults` fuera de `vehicle.gd`: escucha los impactos y decide averías en
  el host (una por golpe fuerte como máximo, con tope por entrega). `03868fe`
  - `gameplay/vehicle/vehicle_faults.gd`: con `vehicle_impact` ≥ 9 el host tira por la semilla del mundo y
    rompe la puerta trasera o el espejo (las 2 del veredicto), una por entrega; señales relayadas
    `vehicle_fault_started`/`vehicle_fault_repaired` y `repair()` en el host. Sin efecto visible todavía.
    Test `test_vehicle_faults` (determinista por semilla, tope, arreglo que llega a cada par).
- [x] **N-214.2** Averías: puerta trasera que se abre sola, espejo caído, limpiaparabrisas roto (solo con
  lluvia), faro roto (solo de noche), asiento flojo. Cada una con efecto visible y leve. `cfccf54`
  - Las 2 del veredicto: con la puerta rota el host la abre en el golpe y otra vez con cada bache ≥ 4,5
    (se puede cerrar, no se queda cerrada); el espejo del conductor se cae a la ruta con ruido de vidrio
    (`vehicle_fault_effects.gd`, en cada par). Limpiaparabrisas, faro y asiento siguen esperando lluvia y
    noche en las rutas (veredicto). Duda: el camión no tiene vista de espejo funcional, así que el espejo
    caído es solo visual hasta N-214.3 (el celular que lo reemplaza).
- [x] **N-214.3** Arreglo oficial (repuesto de tienda) e improvisado con el kit existente (cinta, cincha,
  trapo; el espejo lo reemplaza un pasajero con `phone_camera.gd`). Sin herramientas nuevas.
  - [x] **N-214.3a** Puntos de arreglo (`fault_repair_spot.gd`, un `Interactable` por avería que
    `VehicleFaults` cuelga del camión) y el repuesto: `SUPPLIES` suma `spare_part` ($25), el depósito se
    lo pasa al recorrido y arregla la puerta o el espejo; la puerta rota se ata con una cincha del kit,
    que va antes que el repuesto para guardarlo para el espejo. Test `test_vehicle_faults` ampliado. `2c46ce4`
  - [x] **N-214.3b** Espejo improvisado: un pasajero sostiene el celular como espejo. `77452a6`
    - Sin repuesto, el punto del espejo ofrece "Sostener el celular como espejo" a cualquiera menos el
      conductor, uno a la vez; no es arreglo: la avería sigue activa, se ve un celular donde estaba el
      espejo en cada par y el host lo suelta si el que lo sostiene se aleja (> 5 m, alcanza desde
      cualquier asiento), agarra una caja o toma el volante. El repuesto va primero y lo reemplaza.
      Quien se une a mitad del recorrido recibe averías, repuestos y quién sostiene el celular.
    - Duda: el camión no tiene vista de espejo funcional, así que el celular es visual (no abre la
      cámara de `phone_camera.gd` ni muestra la vista de atrás). Queda para cuando haya espejo real.
  - [x] **N-214.3c** Confirmar con `revisor-visual` el punto del espejo (y el celular) en las variantes
    de camión que no son la clásica. `dc0f925`
    - Las variantes (`classic`, `agile`) son el mismo modelo con otro ajuste y otra pintura, así que el
      punto cae en el mismo lugar en todas. `tests/render_fault_mirror.gd` (vista de costado y desde
      arriba, por variante × pintura) lo confirmó con `revisor-visual`: espejo del conductor oculto,
      celular y punto afuera de la puerta, a la altura del marco de la ventanilla, pintura y detalles
      correctos. `test_vehicle_faults` ampliado sobre `vehicle.tscn` de verdad con cada variante y
      pintura. Dudas: desde afuera no se ve la pantalla del celular (mira al conductor), y el celular
      a veces sale inclinado ~20° en la captura (pedazo del espejo cayendo o pose sin fijar).
- [x] **N-214.4** La pantalla de resultados cuenta la avería ("Espejo reemplazado por un celular"). `29a24d5`
  - `VehicleFaults` guarda cómo terminó cada avería del recorrido (cincha, repuesto, celular o sin
    arreglar, la puerta con cuántas veces se abrió) y entra al grupo `run_stories`;
    `RunManager.world_stories()` suma esas líneas a `results["stories"]`, junto a los rescates. El
    celular cuenta aunque después lo suelten. Duda: las líneas se traducen en el host (como el resto
    de los resultados que manda), así que un cliente en otro idioma las vería en el del host.
- [x] Test `test_vehicle_faults.gd`: determinista por semilla, tope respetado, arreglo sincronizado
  (cubierto desde N-214.1 y ampliado en cada subtarea, N-214.4 incluida).

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
- [ ] **N-212.2** Reproducción en `AudioStreamPlayer3D` en la cabeza del jugador; dentro de la cabina se
  oyen todos, afuera se atenúa y pasa por el bus Exterior con filtro (se oye "a través de la chapa").
- [ ] **N-212.3** Pulsar para hablar (con tecla configurable) y detección de voz, silenciar y volumen por
  jugador, y un interruptor general en Opciones. Hecho en `649c7fa`: `GameSettings.voice_chat_enabled`
  (apagado hasta que exista N-212.2) y `voice_push_to_talk` (por defecto; apagado = micrófono abierto),
  la tecla reasignable y `ProximityVoice.set_peer_muted()` / `set_peer_volume()`. **Falta:** mostrarlos en
  Opciones y en una lista de jugadores (UI de Slatex, `options_panel.gd`).
- [x] **N-212.4** LAN/ENet: `AudioEffectCapture` o dejarlo fuera del MVP (decidir y anotar). `649c7fa`
  Decidido: **LAN sin voz** (condición de `critico-diseno`); la razón quedó en `proximity_voice.gd`.
- [ ] Medir con `auditor-red` el ancho de banda con 5 jugadores. Test de que el apagado general no
  captura el micrófono. El test ya está (`test_proximity_voice.gd`, `649c7fa`); falta medir el ancho de
  banda (con N-212.2).

### N-109 · Animales que se meten con la carga — B · `Opus 5.5 · xhigh` · Aviso: sí (estados del paquete)

Extiende N-106 y N-107: los animales ahora amenazan paquetes, no solo el camino.

- [ ] **N-109.1** Gaviota o carancho que baja a la caja del estante y trata de llevársela; se espanta con la
  bocina o sujetando la caja.
- [ ] **N-109.2** Perro que se sube a una caja abierta en una parada; se lo distrae tirándole algo.
- [ ] **N-109.3** Abejas atraídas por la torta (Equilibrio) en zona de campo.
- [ ] Cada uno anunciado con sonido o ícono antes de actuar (la queja principal de RV There Yet? es la
  fauna sin aviso). Determinista por semilla, disparado por el host. Tests con el patrón de
  `test_wildlife_crossing.gd`.

### N-406 · Radio del camión con función — B · `Opus 5.5 · high` · Aviso: sí (trampa Ruidoso)

- [ ] **N-406.1** Perilla en el tablero que cualquiera puede girar: tranquila / fuerte / noticiero /
  apagada. Estado en el host.
- [ ] **N-406.2** Música tranquila calma la trampa Ruidoso; la fuerte la altera.
- [ ] **N-406.3** El noticiero anuncia el próximo evento de ruta ("inspección más adelante").
- [ ] Test `test_truck_radio.gd`: el estado se sincroniza y modifica la agitación de Ruidoso.

### N-108 · Tramo de barro/pendiente con salida cooperativa — B · `Opus 5.5 · high` · Aviso: no

- [ ] Tramo nuevo, raro y anunciado con carteles, donde el camión se puede atascar. Salidas: pasajeros que
  bajan a empujar (mantener un botón en la zona correcta; el host aplica la fuerza) o eslinga de tienda.
- [ ] El dilema tiene que existir: mientras empujan, sus cajas quedan sin atender.
- [ ] Nunca bloquea para siempre: pasado un tiempo aparece una grúa cómica que lo saca, con multa.
- [ ] Con `constructor-tramos`; tests de pacing y fuzz (N-103, N-801) siguen pasando.

### N-110 · Paradas de servicio en la ruta — B · `Opus 5.5 · xhigh` · Aviso: sí (compra de suministros)

- [ ] En rutas largas y en Endless, una estación de servicio opcional: reponer consumibles del kit con
  dinero cooperativo, arreglar averías (N-214) y un cosmético escondido (N-311).
- [ ] Parar cuesta tiempo de plazo: es una decisión, no un respiro gratis.
- [ ] Test: aparece según las reglas de ritmo y la compra usa la misma votación que el depósito.

### N-311 · Cosméticos para encontrar en el mundo — B · `Opus 5.5 · medium` · Aviso: sí (cosméticos del jugador)

- [ ] Además de los que se desbloquean con mérito, algunos gorros aparecen en el depósito, en las paradas
  (N-110) o en el jardín de un cliente. Recogerlos exige bajarse o desviarse unos metros.
- [ ] Se guardan en la campaña por color de jugador, como el mérito. Test de guardado y carga.

### N-113 · Evento de visibilidad limitada para el conductor — C · `Opus 5.5 · high` · Aviso: no

- [ ] Evento de ruta de 10-20 s: niebla densa, parabrisas embarrado o una caja que tapa la vista. Un
  pasajero en la ventana guía (con N-505 o N-212). Solo como evento corto: la premisa completa es la de
  Backseat Drivers.
- [ ] Shader con `artista-shaders`; test de que dura lo previsto y no se repite seguido.

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

### N-114 · Caja de cambios manual como variante — C · `Opus 5.5 · xhigh` · Aviso: no

- [ ] Variante "clásico viejo" a elegir en el depósito, con marchas manuales opcionales y más paga o
  mérito como compensación.
- [ ] Los tests de manejo (N-104) de las variantes existentes no cambian.

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

### N-115 · Correr — A · `Opus 5.5 · high` · Aviso: sí (`player.gd`, `player_animator.gd`, `player_carry.gd`, daño de paquetes y controles de Slatex)

> Hoy el jugador tiene una sola velocidad (`Player.WALK_SPEED` = 3,6 m/s). Correr sirve sobre todo para
> llegar a tiempo a una caja caída (los 30 s de rescate de N-213) y para moverse por el depósito.

- [ ] **N-115.1** Mantener Correr (Shift en teclado, clic del stick izquierdo en gamepad; reasignable en
  Opciones como el resto) sube la velocidad a ~6 m/s. Sin estamina: el juego es cooperativo y casual.
- [ ] **N-115.2** **Se puede correr con una caja en brazos, con el riesgo que conlleva** (decisión del
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
- [ ] **N-115.3** Clip `Run` nuevo en `art/rounded_character/animation_library.py` (zancada con fase de
  vuelo, brazos más abiertos) y elegido por `PlayerAnimator` por velocidad, con la misma histéresis que
  Walk/Stroll. En primera persona: balanceo más marcado y el FOV se abre un poco (+4°, suavizado).
  Pasos más rápidos en el sonido.
- [ ] **N-115.4** Red: el estado de carrera viaja como `anim_state` (el dueño lo decide, los demás solo
  reproducen el clip).
- Test: `test_player_sprint.gd` (velocidad al correr con y sin caja, no corre sentado ni manejando, correr
  con caja daña más que caminar, el tropezón deja la caja en el suelo y es igual en host y cliente con la
  misma semilla, elige `Run`, el otro par ve el mismo clip). Captura del clip con `revisor-visual`.
- Hecho cuando: se corre a pie en la ruta y en el depósito, con animación propia, y correr con una caja
  la sacude y puede hacerte tropezar.

### N-116 · Parada final: estacionamiento de camiones de reparto — A · `Opus 5.5 · high` · Aviso: no

> Hoy la meta es un arco de hormigón con la palabra META, una barrera y un `GoalArea`
> (`route.gd::_build_goal()`): se termina al pasar por abajo. Pedido del usuario: una parada final de
> verdad, la base de la empresa en el pueblo, donde se deja el camión.

- [ ] **N-116.1** Playa de estacionamiento "Base Take My Package — {pueblo}" en lugar del arco (sacarlo de
  `route.gd` a `route/route_goal_lot.gd`): explanada plana de ~40 × 30 m al final de la ruta, asfalto con
  cordón, cerco perimetral, cartel grande de la empresa, garita con barrera que se levanta cuando llega el
  camión, faroles que se prenden de noche (`WorldMood`), 5-6 bahías pintadas con camiones de la empresa
  estacionados y **una bahía libre marcada** (número grande pintado, flecha y conos). Los camiones
  estacionados son sólidos: chocarlos es un golpe normal (`vehicle_impact`), la carga lo siente.
- [ ] **N-116.2** Terminar = estacionar: la partida termina cuando el camión queda **frenado dentro de la
  bahía libre** (misma regla que la zona de entrega: casi quieto durante ~1,5 s), no al cruzar un arco. El
  GPS y la guía apuntan a la bahía ("Estacioná en la bahía 7"). Estacionar derecho (menos de 10° de
  desvío) suma una línea chica en los resultados, "Estacionamiento prolijo" (toca `run_manager.gd`,
  zona compartida: aviso; si complica, queda para después).
- [ ] **N-116.3** Vida en la base: un par de repartidores NPC (`DepotWorker`) descargando otro camión, un
  carro con cajas, una manguera de lavado. Nada que se mueva por la bahía libre.
- [ ] **N-116.4** Es el último plano antes del diario (N-606): la órbita de resultados muestra el camión
  estacionado en la base.
- Endless no tiene meta: no cambia.
- Test: `test_route_goal_lot.gd` (la playa queda plana y sin árboles ni casas encima, la bahía libre es
  alcanzable desde la ruta, pasar sin frenar no termina, frenar en la bahía sí, igual en host y cliente);
  actualizar los tests que buscan `GoalArch*`/`GoalArea`. Capturas de día y de noche con `revisor-visual`.
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

- [ ] **N-606.1** Apodo del jugador: se escribe en la personalización (16 caracteres); si queda vacío, el
  juego asigna uno gracioso con la semilla del jugador; viaja con la apariencia.
- [ ] **N-606.2** Contenido: `RunChronicle` (hechos de la partida desde el `EventBus`), `NewsDesk`
  (redacción pura, determinista por semilla), catálogo `data/newspaper/stories.json` con 3+ variantes por
  hecho, relay del host `newspaper_ready` (ids y casillas, no texto) y la página 2D mostrada antes de la
  tarjeta de resultados. Tests `test_news_desk.gd` y `test_run_chronicle.gd`.
- [ ] **N-606.3** La escena: set propio en su `World3D`, el Jefe sentado, diario 3D con la página en un
  `SubViewport`, cámara por rieles (`data/newspaper/shots.json`, formato de `TrailerCamera`), bandas
  negras, saltar manteniendo el botón, opción en Opciones y la tarjeta de resultados esperando
  `newspaper_finished`. Test headless del director y captura con `revisor-visual`.
- [ ] **N-606.4** ⏸ personajes en pausa (S-311) · Pulido: clips del Jefe (`SitRead`, `OpenPaper`, `TurnPage`, `LowerPaper`, `SpitTake`,
  `CirclePen`, `SipMate`), diario giratorio, curva de página, expresiones, audio (gallo, "¡extra!",
  papel, escupida) y hechos nuevos (vuelco, perro, tren).
- [ ] **N-606.5** Fotos reales: captura chica en el momento de un hecho (ciervo, gallina que salta,
  puerta que se abre) que va al diario con trama de puntos.
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

### 1. Game Design

#### S-101 · Terminar los eventos de ruta (hoy se anuncian y nunca se resuelven) — A · `Opus 5.5 · xhigh` · Aviso: sí (`run_manager.gd`)

**Problema real**: `RunManager.start_run()` llama `RouteEventManager.begin_random()` y el
HUD muestra el banner, pero **nadie llama nunca `resolve_active()`**. El evento queda activo
para siempre y, como `begin_event()` rechaza uno nuevo mientras hay otro activo, en toda la
sesión hay a lo sumo un evento, y no se puede resolver. Además `_emit_event()` emite solo en
local: si el host lo resolviera, los clientes no se enterarían.

**Archivos**: `scripts/core/route_event_manager.gd`, `scripts/core/run_manager.gd` (zona
compartida), `scripts/gameplay/package/package.gd`, `scripts/gameplay/package/package_feedback.gd`,
`scripts/ui/prototype_hud.gd`, `scripts/core/event_bus.gd` (solo si hace falta una señal nueva).

- [x] **S-101.1 Recortar el sorteo.** (commit `2287979`) Constante `ROUTE_POOL: Array[StringName]` con
  `inspection`, `impatient_client`, `mixed_labels`, `mimetic_package`, `parasite_box`.
  `rear_door_jam` (necesita las puertas del camión, dominio de Nacho) y `confusing_shop`
  (necesita la tienda en ruta) quedan en `EVENTS` pero **fuera del sorteo**, con un
  comentario que explique por qué. `begin_random()` sortea solo del pool.
- [x] **S-101.2 Duración y vencimiento.** (commit `2287979`) Cada evento suma `"duration"` (segundos, entre 45 y
  90) y `"fine"` (multa en dinero del equipo, entre 15 y 30). En `_physics_process`, **solo en
  el host** y solo con `RunManager.is_running`, descontar el tiempo; al llegar a 0 resolver con
  `success = false` y cobrar la multa con `CrewProgression.spend(mini(fine, team_money))`
  (la plata nunca queda negativa). Al terminar la partida (`run_ended`) cualquier evento activo
  se cierra como fallido sin multa, y `reset_route()` corre en cada `start_run`.
- [x] **S-101.3 Resolver en red.** (commit `2287979`) Reemplazar `_emit_event` por `EventBus.relay(...)` para
  `route_event_started`, `route_event_updated` y `route_event_resolved`, así el host decide y
  todos lo ven. Revisar que `_remote_start_run` en `run_manager.gd` no dispare el evento dos
  veces en el cliente (hoy el cliente lo reinicia con `begin_event`; con relay alcanza con que
  el cliente copie el estado sin volver a emitirlo).
- [x] **S-101.4 Inspección sorpresa.** (commit `2287979`) A los `duration - 15` s el host evalúa: toda caja del grupo
  `cargo` que siga en carga está `is_loaded` y no `is_open`. Si se cumple, éxito: dinero al
  equipo y mérito (`award_action`) para cada jugador sentado en un asiento de pasajero. Si no,
  multa. Mientras tanto, `route_event_updated` manda `{"loose": n}` para que el HUD muestre
  "Faltan asegurar 2 cajas".
- [x] **S-101.5 Cliente impaciente.** (commit `2287979`) Al empezar, elegir una casa del pedido (escuchar
  `houses_assigned`, que ya existe). Éxito si llega `house_delivery_recorded` para esa casa con
  resultado intacto antes del vencimiento. Si falla, además de la multa, poner
  `RunManager.results["time_bonus"] = 0` al cerrar (agregar una bandera `lost_time_bonus`
  en `RunManager`, no tocar la fórmula).
- [x] **S-101.6 Etiquetas mezcladas.** (commit `2287979`) Se activa con el primer `vehicle_impact` fuerte después de
  sortear el evento. El host elige dos cajas en carga y **intercambia solo la etiqueta visible**
  (el `Label3D` del contenido declarado en `package_feedback.gd`, más una marca "?" en el HUD):
  la carga real y el pedido no cambian. Se resuelve cuando alguien abrió (T) **las dos** cajas
  (el contenido real se ve al abrir). Mérito para quien abrió la segunda. Propiedad nueva
  replicada en `package.gd`: `label_swapped_with: StringName`.
- [x] **S-101.7 Paquete mimético.** (commit `2287979`) El host elige una caja en carga y le pone
  `disguise_trap_id` (replicado): el HUD y la caja muestran el ícono y el nombre de otra trampa
  de igual o menor dificultad. El primer impacto por encima de `impact_threshold_light` la
  revela (partículas + sonido). Éxito si 20 s después de revelarse no está arruinada.
- [x] **S-101.8 Caja parásita.** (commit `2287979`) El host enlaza dos cajas montadas: cada punto de daño que recibe
  una se le aplica al 50 % a la otra. Para separarlas, dos jugadores distintos tienen que mantener
  la acción primaria (`steady`) sobre una caja cada uno durante 2 s a la vez (usar lo que ya llega
  por `submit_tender_input`). Solo, en solitario, este evento no se sortea (`NetworkManager.peer_ids.size() < 2`).
- [x] **S-101.9 HUD.** (commit `2287979`) El banner del evento (`event_label`) pasa a tener tres partes: título,
  objetivo y cuenta regresiva, y se actualiza con `route_event_updated`. Tiene su propia zona
  (ver S-501): no comparte línea con el aviso de interacción.
- [x] **S-101.10 Tests.** (commit `2287979`) `tests/test_route_events.gd`: cada uno de los 5 eventos del pool se
  resuelve bien y vence mal; un evento no queda activo después de `run_ended`; la multa nunca deja
  la plata negativa; en solitario no sale `parasite_box`. Actualizar `test_route_event_manager.gd`.

**Hecho cuando**: una partida con el nivel de entrega sortea un evento, lo muestra con cuenta
regresiva, y termina resuelto o vencido en todos los casos; tests verdes.

#### S-102 · Mérito individual por acciones reales — A · `Opus 5.5 · xhigh` · Aviso: sí (`run_manager.gd`)

**Problema real**: `CrewProgression.award_action()` solo lo llama el evento de ruta (que nunca se
resuelve, S-101). Hoy nadie gana mérito nunca, y `merit_changed` se emite en local, así que un
cliente tampoco vería el suyo.

**Archivos**: `scripts/core/crew_progression.gd`, `scripts/gameplay/package/package.gd`, las
trampas en `scripts/gameplay/traps/`, `scripts/ui/prototype_hud.gd`.

- [x] **S-102.1 Saber quién hizo qué.** (commit `e3928bb`) En `package.gd`, guardar en el host el último peer que
  mandó input útil (`_last_tender_peer`, con `multiplayer.get_remote_sender_id()` o el id local si
  es 0) y el último que la tuvo en la mano.
- [x] **S-102.2 Hitos desde las trampas.** (commit `e3928bb`) Agregar a `i_trap_behavior.gd` una función
  `take_milestones() -> Array[StringName]` (por defecto vacía) que cada trampa llena cuando pasa
  algo meritorio, y el paquete la consume cada frame en el host. Hitos: `defused` (Explosivo
  desactivado), `calmed` (Hostil o Ruidoso vuelve de riesgo a OK), `dried` (Líquido: charco en 0
  después de haber pasado 30), `leveled` (Equilibrio vuelve a OK desde riesgo),
  `sequence` (Peso creciente resuelto).
- [x] **S-102.3 Hitos desde el paquete.** (commit `e3928bb`) `rescued`: alguien levanta una caja que estaba en el piso
  fuera del camión durante la partida y la vuelve a montar. `handover`: traspaso mano a mano.
  `photo_saved`: la foto de entrega anuló un reclamo (escuchar `delivery_photo_taken`).
- [x] **S-102.4 Tabla de puntos** (commit `e3928bb`) en `crew_progression.gd`: `MERIT_POINTS := {&"defused": 25,
  &"rescued": 20, &"calmed": 10, &"dried": 10, &"leveled": 8, &"sequence": 8, &"handover": 5,
  &"photo_saved": 15}`. El `action_id` tiene que ser único por hecho:
  `"%s:%s:%d" % [package_id, milestone, contador]`, así un mismo hito no se cobra dos veces.
- [x] **S-102.5 Red.** (commit `e3928bb`) `merit_changed` y `card_changed` pasan por `EventBus.relay`.
- [x] **S-102.6 Test** (commit `e3928bb`) `tests/test_merit.gd`: cada hito suma lo de la tabla una sola vez; el mérito
  va al peer correcto; un hito repetido en el mismo frame no duplica.

**Hecho cuando**: jugando solo, desactivar un explosivo muestra "Mérito +25" y el total aparece en
resultados (S-508).

#### S-103 · Cartas: dejar solo las que se pueden usar y hacerlas usables — A · `Opus 5.5 · xhigh` · Aviso: sí (`project.godot`, acción nueva)

**Problema real**: `_grant_card_chance()` reparte cartas, el HUD dice "Carta obtenida", y no hay
ninguna forma de usarlas. Prioridad e Información dependen de una tienda en ruta que no existe.

**Decisión de alcance (control de scope, ya tomada)**: para el MVP quedan **Rescate**,
**Descuento** y **Re-voto**. Prioridad e Información salen del reparto (sus valores del enum se
conservan para no romper nada guardado).

- [x] **S-103.1** (commit `955e585`) `CrewProgression.DRAWABLE_CARDS := [Card.RESCUE, Card.DISCOUNT, Card.REVOTE]`;
  `_grant_card_chance` sortea solo de ahí. Borrar `priority_issued` si queda sin uso.
- [x] **S-103.2 Acción `use_card`** (commit `955e585`) en `project.godot` (G / D-pad izquierda) y reasignable en
  `GameSettings` como las demás. Aviso por `project.godot`.
- [x] **S-103.3 Rescate en partida** (commit `955e585`): con un evento de ruta activo, `use_card` manda una RPC al host
  (`CrewProgression.request_use_card`, `@rpc("any_peer")`), que llama
  `RouteEventManager.use_rescue(peer)`. Sin evento activo, el HUD dice "No hay nada que rescatar".
- [x] **S-103.4 Descuento y Re-voto en el depósito** (commit `955e585`): botones en la sección de suministros de
  `depot_panel.gd`, visibles solo si el jugador tiene esa carta (ver S-104).
- [x] **S-103.5 HUD** (commit `955e585`): ficha con el nombre de la carta en la esquina de dinero y la tecla para usarla
  (`UiTheme.keycaps`). El toast "Carta obtenida" pasa a decir cuál.
- [x] **S-103.6 Test** (commit `955e585`) `tests/test_cards.gd`: nunca sale Prioridad ni Información; Rescate resuelve el
  evento activo y se consume; sin evento no se consume.

#### S-104 · Votación de suministros en el depósito — A · `Opus 5.5 · xhigh` · Aviso: no

**Problema real**: `ShopVoteManager` está completo pero `open_shop()` no se llama nunca. En el
mostrador de suministros compra el que llega primero.

**Archivos**: `scripts/core/shop_vote_manager.gd`, `scripts/ui/depot_panel.gd`. **No hace falta
tocar `depot.gd`**: la compra final se sigue haciendo con `depot.buy_supply(id)` en el host.

- [x] **S-104.1** (commit `c05ed44`) En `shop_vote_manager.gd`: `request_vote(offer_id)` con `@rpc("any_peer")` que en el
  host valida y llama `vote(sender, offer_id)`; `resolve_winner(peers) -> StringName` que decide
  **sin gastar** (la plata la descuenta `depot.buy_supply`, para no cobrar dos veces). Empate: gana la
  oferta más barata. Nadie votó: no se compra nada.
- [x] **S-104.2** (commit `c05ed44`) El host abre la votación (`open_shop(CrewProgression.SUPPLIES)`) la primera vez que
  alguien abre el mostrador en el depósito, y la cierra cuando votaron todos los conectados o a los
  20 s del primer voto. Al cerrar: `depot.buy_supply(ganador)`.
- [x] **S-104.3** (commit `c05ed44`) En solitario no hay votación: el botón compra directo como hoy.
- [x] **S-104.4** (commit `c05ed44`) UI: cada oferta muestra quién la votó (círculos con el color de cada jugador) y la
  cuenta regresiva; Descuento (S-103) aparece como botón "Usar Descuento (−50 %)" sobre la oferta
  ganadora; Re-voto borra los votos.
- [x] **S-104.5 Test** (commit `c05ed44`) `tests/test_supply_vote.gd` (con `ShopVoteManager` y `CrewProgression`
  instanciados sin red, como `test_shop_vote_manager.gd`): gana la mayoría, empate a la más barata,
  el dinero se descuenta una sola vez.

#### S-105 · Guardar la campaña cooperativa — A · `Opus 5.5 · high` · Aviso: no

**Problema real**: el dinero, las cartas y el mérito viven en memoria: al cerrar el juego se
pierden y la economía no significa nada entre sesiones.

- [x] **S-105.1** (commit `c694bdf`) `CrewProgression.save_campaign()` / `load_campaign()` en `user://crew_campaign.json`
  (dinero, suministros pendientes, cartas y mérito **por color de jugador**, no por peer id, porque el
  id cambia en cada conexión). Mismo patrón que `unlock_manager.gd`, con `version: 1`.
- [x] **S-105.2** (commit `c694bdf`) Guarda el host al terminar cada partida y al comprar. En línea manda la campaña del
  host; los clientes no escriben la suya.
- [x] **S-105.3** (commit `c694bdf`) Botón "Empezar campaña nueva" en `progress_panel.gd`, con confirmación.
- [x] **S-105.4** (commit `c694bdf`) Escritura segura (ver S-210).
- [x] **S-105.5 Test** (commit `c694bdf`) `tests/test_crew_campaign_save.gd`: guarda, recarga, conserva; archivo corrupto
  no rompe y arranca con $100.

#### S-106 · Introducción gradual de trampas desde el perfil — A · `Opus 5.5 · high` · Aviso: no

`docs/economia-y-contramedidas.md` dice que las primeras entregas presentan solo Frágil y
Equilibrio. Hoy las 4 básicas salen desde la primera partida.

- [x] **S-106.1** (commit `2a2ad10`) Sumar a `UnlockManager.UNLOCKS`: `growing_weight_trap` (1 entrega, 0 pts) y
  `noisy_trap` (2 entregas, 100 pts); agregarlas a `TRAP_UNLOCKS`. Correr los umbrales siguientes para
  que la curva quede: Frágil+Equilibrio → Peso creciente (1) → Ruidoso (2) → Líquido (4) → Explosivo (8)
  → Hostil (13).
- [x] **S-106.2** (commit `2a2ad10`) `PROFILE_VERSION` 3: un perfil que ya supera los umbrales nuevos los recibe
  desbloqueados al cargar (no quitarle nada a nadie).
- [x] **S-106.3** (commit `2a2ad10`) Verificar que con solo 2 trampas (4 cajas) siempre alcanzan para las casas
  (`max(jugadores - 1, 1)`, máximo 4). Si no alcanza, `locked_traps()` libera la trampa de menor
  dificultad que falte. Test en `test_locked_traps.gd`.
- [x] **S-106.4** (commit `2a2ad10`) Actualizar `docs/plan-desarrollo.md` Fase 5 con la curva nueva.

#### S-107 · Reglas de dificultad para armar el pedido — B · `Opus 5.5 · high` · Aviso: sí (una línea en `depot.gd`)

Pendiente de `docs/controles-y-ui.md` ("la selección semi-aleatoria y sus reglas de balance
siguen pendientes").

- [x] **S-107.1** (commit `1fb41b9`) Módulo puro `scripts/gameplay/traps/order_balancer.gd` (`class_name OrderBalancer`,
  funciones `static`): recibe trampas disponibles (`TrapDefinition`), cantidad de casas, partidas
  completadas del perfil y un `RandomNumberGenerator` con la semilla de la sesión; devuelve la lista de
  ids de trampa por casa.
- [x] **S-107.2** (commit `1fb41b9`) Reglas: suma de `difficulty` del pedido ≤ `4 + casas + min(completed_runs, 6)`;
  nunca dos de dificultad 4 juntas antes de 10 partidas; no repetir trampa mientras haya distintas
  disponibles; siempre al menos una de dificultad ≤ 2.
- [x] **S-107.3** (commit `1fb41b9`) Integración: `depot.gd` `post_orders()` usa el resultado para elegir la caja de cada
  casa. Es un cambio de 3-5 líneas en un archivo de Nacho: aviso en `colaboracion-equipo.md`.
- [x] **S-107.4** (commit `1fb41b9`) Test `tests/test_order_balancer.gd`: 1000 semillas por cantidad de casas, ninguna
  rompe las reglas; la misma semilla da el mismo pedido (todos los peers calculan igual).

#### S-108 · Simulador de balance de trampas (reemplaza al playtesting de balance) — A · `Opus 5.5 · xhigh` para diseñarlo, `Opus 5.5 · high` para implementarlo · Aviso: no · **[x] `8d04262`**

Cierra lo que antes era "#41/#51/#59/#67: falta playtesting". No mide diversión: mide si cada
trampa es **perdible, ganable y con momentos de casi-perder**, que es lo que `parametros-diseno.md`
pide de los números.

- [x] **S-108.1 Grabar manejo real.** (commit `8d04262`) `tests/sim_record_drive.gd`: maneja el camión de verdad por una
  ruta (mismo conductor automático que `test_vehicle_stress.gd`, pero respetando curvas) y guarda por
  frame de física lo que las trampas reciben: aceleración, inclinación de la caja, impactos (delta de
  velocidad). Salida: `tests/sim_data/drive_<semilla>.json`. 5 semillas.
- [x] **S-108.2 Pasajeros bot.** (commit `8d04262`) Tres perfiles: *ausente* (no toca nada), *torpe* (reacciona con
  0,8 s de retraso, acierta 60 % de las secuencias, suelta el botón 20 % del tiempo) y *experto*
  (0,25 s, 95 %). Cada perfil también con +150 ms de latencia de red simulada.
- [x] **S-108.3 Simulador.** (commit `8d04262`) `tests/sim_trap_balance.gd` (no va en la batería, como `bench_drive.gd`):
  para cada `data/traps/*.tres` × perfil × manejo grabado, corre el `ITrapBehavior` real 50 veces y
  anota % arruinadas, segundos en riesgo, y *casi-pérdidas* (integridad mínima entre 5 y 25 sin llegar a
  0). Imprime una tabla y la guarda en `tests/sim_data/balance_report.md`.
- [x] **S-108.4 Objetivos** (commit `8d04262`; escritos antes del ajuste) en `docs/parametros-diseno.md`:
  ausente arruina 80-100 %; torpe 30-55 % con al menos 1 casi-pérdida por viaje; experto < 12 %.
  La latencia de 150 ms no puede subir el % del experto más de 8 puntos.
- [x] **S-108.5 Ajustar** (commit `8d04262`) los `params` de los `.tres` hasta cumplir los objetivos (sin tocar scripts de
  trampa) y documentar valor viejo → nuevo y por qué en `parametros-diseno.md`.

**Hecho**: el reporte muestra las 6 trampas interactivas dentro de los objetivos y documenta
`Frágil` como excepción dependiente del conductor (sus perfiles son idénticos porque no consume input).

#### S-109 · Algo que hacer cuando tu paquete ya se arruinó — A · `Opus 5.5 · xhigh` · Aviso: no

`docs/critica-diseno-abogado-del-diablo.md` §6: quien pierde su caja pasa el resto del viaje sin
hacer nada. El modo espectador ayuda a mirar, no a jugar.

- [x] (commit `251b082`) **S-109.1 Ayudante.** Un paquete acepta input de hasta **dos** peers: el que lo atiende y un
  ayudante (otro jugador sentado en un asiento contiguo o a pie a menos de 1,5 m). En `package.gd`,
  `submit_tender_input` guarda el input por peer y combina: `steady`/`calm` del ayudante suman 50 % de
  la fuerza; las secuencias (Explosivo, Peso creciente) las puede completar cualquiera de los dos.
- [x] (commit `251b082`) **S-109.2** El aviso de interacción muestra "Ayudar con la caja de <color>" y el ayudante gana el
  hito `assist` (5 de mérito cada 10 s ayudando con la caja en riesgo).
- [x] (commit `251b082`) **S-109.3** Hostil pasa a pedir dos personas en su fase difícil: CALMÁ necesita la suma de dos
  inputs para bajar rápido (dato en `hostile.tres`, no código especial).
- [x] (commit `251b082`) **S-109.4** Test `tests/test_assist.gd`: dos peers simulados atienden la misma caja; la corrección
  combinada es la esperada; un tercer peer es ignorado.

#### S-110 · Medir cuánto dura una entrega (regla de oro de 2-5 min) — B · `Opus 5.5 · high` · Aviso: no (solo informa a Nacho)

- [x] (commit `35787d6`) **S-110.1** `tests/bench_delivery_time.gd`: con el conductor automático de S-108.1 y un bot que
  baja, camina y toca el timbre, medir el tiempo total de una entrega con 1, 2, 3 y 4 casas, a
  velocidad de crucero.
- [x] (commit `35787d6`) **S-110.2** Escribir el resultado en `docs/parametros-diseno.md` ("Duración medida") y dejar aviso
  a Nacho en `colaboracion-equipo.md` con los números. Ajustar el largo de la ruta es de Nacho: esta
  tarea termina al entregar la medición, no espera su respuesta.

#### S-111 · Congelado breve al arruinarse una caja (el "slow-mo" pendiente) — C · `Opus 5.5 · high` · Aviso: no

`requerimientos-tecnicos.md` §3.4 lo deja pendiente porque `Engine.time_scale` rompe la física
del host. Hacerlo **solo visual y local**:

- [x] (commit `5fa9277`) 0,35 s en los que las partículas de ruina (`package_feedback.gd`) corren a `speed_scale = 0.15`,
  un destello blanco suave en la viñeta del HUD y un golpe de sonido grave. La física no cambia.
- [x] (commit `5fa9277`) Opción "Efectos de impacto" en opciones para apagarlo (accesibilidad, ver S-502).
- [x] (commit `5fa9277`) Test: tras `package_ruined` el `Engine.time_scale` sigue en 1.0 y las partículas vuelven a 1.0.

---

#### S-112 · Rescate de carga (`docs/jugabilidad-paquetes-rescate.md`) — A · Aviso: sí (`run_manager.gd`, `event_bus.gd`)

**Hecho por Nacho (2026-09-27, pedido del usuario), corte vertical 1:**
- [x] Estado de cuidado en el host (`package_care.gd`) separado de la barra de la trampa: rescate de
  15 s, piezas para juntar (`package_salvage.gd`), cinta / recomponer / gallina de juguete con el
  minijuego de flechas, equilibrio con stick (`player_cargo_care.gd`) y tope de calidad.
- [x] Kit compartido en `RunManager` (3 cintas, 2 reparaciones, 1 juguete), sincronizado a clientes.
- [x] La puerta lee la categoría (reparado / poco convincente / sustituto) y reacciona con su línea; el
  pago no depende del azar; los resultados cuentan los rescates.
- [x] Derramar ya no pierde la caja: abre un rescate. Una gallina perdida no corta la partida mientras
  quede un juguete. Test: `tests/test_package_rescue.gd`.

**Hecho después (2026-09-28), resto del diseño:**
- [x] Plazos de entrega calculados sobre la distancia real de cada casa (`RunManager.plan_deadlines`,
  hasta 3), cuenta regresiva en el HUD, +40 por plazo cumplido y −15 por vencido.
- [x] Relleno, trapo y cincha; "recomponer" cambia según el contenido (pegar, rearmar, desactivar,
  reparar jaula, reubicar entre dos); el líquido solo se rescata con trapo y llega parcial.
- [x] Regazo o soporte: sentado, Q mueve la caja entre las dos. El regazo amortigua pero ocupa las
  manos; el soporte libera las manos y pide cincha. La herramienta cambia con X (antes V, que era el ping).
- [x] Líneas de la puerta en `strings_world.csv`.
- [x] Si se desconecta quien atendía una caja en rescate, su ventana se mantiene (`peer_left`).

**Pendiente:** prueba real en red con dos o tres PCs (desconexión en medio de un rescate) y ajustar
cifras de plazos con `bench_route_duration` cuando se juegue.

### 2. Programación y arquitectura técnica

#### S-201 · Partir `prototype_hud.gd` (1176 líneas) en componentes — A · `Opus 5.5 · xhigh` · Aviso: no

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

#### S-202 · Partir `player.gd` (1131 líneas) — B · `Opus 5.5 · xhigh` · Aviso: no

- [x] (commits `bb4a862`, `f168819`, `42d5aa2`) Separar en nodos hijos con script propio: `player_interaction.gd` (alcance, avisos, E),
  `player_carry.gd` (caja en mano), `player_seat_pose.gd` (pose sentado, manos que atienden).
- [x] (commits `f168819`, `42d5aa2`) **Las funciones `@rpc` se quedan en `player.gd`** (Godot resuelve la RPC por la ruta del nodo; si
  se mueven, se rompe la red). Esas funciones solo delegan.
- [x] (commits `bb4a862`, `f168819`, `42d5aa2`) Tests verdes: `interaction`, `seat`, `carry`, `player`, `driver` y `look`.

#### S-203 · Detectar camión atascado también en el modo entrega — A · `Opus 5.5 · high` · Aviso: sí (`level_base.gd`)

Nacho encontró (su #97) que el camión puede quedar encajado sin volcar ni salir de la ruta;
`level_endless.gd` ya lo detecta, `level_base.gd` no.

- [x] (commit `204cfdc`) Copiar la misma regla (6 s casi quieto con el motor pedido → termina la partida con "La
  camioneta quedó atascada"), **sin** contar el tiempo parado en el depósito, en una casa, o con el
  conductor fuera del asiento.
- [x] (commit `204cfdc`) Test en `test_stuck_detection.gd`: parado en depósito, casa o sin conductor no dispara;
  encajado contra un obstáculo con el acelerador pedido sí.

#### S-204 · Test automático de dos procesos (reemplaza "requiere playtest de red") — A · `Opus 5.5 · xhigh` · Aviso: no

Cierra lo que quedaba de #79 (cosméticos en dos clientes) y #96 (dos jugadores con el mismo objeto).

- [x] (commit `200cb1b`) **S-204.1** `tests/net_pair.gd`, sobre el patrón de `tests/net_smoke.gd` (ENet en localhost,
  `--host` / `--client`): el host carga `level_base.tscn`; el cliente se une con un uniforme elegido.
- [x] (commit `200cb1b`) **S-204.2** Chequeos: el host ve el `cosmetic_id` del cliente; los dos intentan agarrar la misma
  caja en el mismo frame y solo uno la tiene; el cliente se sienta en un asiento ocupado y es rechazado;
  el cliente suelta una caja a mitad de traspaso y queda en el piso en los dos procesos.
- [x] (commit `200cb1b`) **S-204.3** `tools/run-net-pair.sh` que lanza los dos procesos y junta los códigos de salida.
  Agregado a CI como job aparte: 15-16 s en dos ejecuciones locales.

#### S-205 · Respuesta inmediata al mantener, aunque haya lag — B · `Opus 5.5 · xhigh` · Aviso: no

- [ ] Verificar si en un cliente la barra, el aviso de la trampa y las manos del asiento reaccionan al
  presionar o recién cuando vuelve el estado del host. Probarlo con latencia artificial: opción de
  depuración `--fake-lag=150` que retrasa `submit_tender_input` en `package.gd` (solo en build de debug).
- [ ] Si esperan al host: mostrar localmente el "estoy sosteniendo" (manos, brillo del botón, sonido)
  al instante y dejar que la integridad siga viniendo del host.
- [ ] Test con el retraso activado: la pose de manos cambia el mismo frame del input.

#### S-206 · Errores de conexión que un jugador entienda — A · `Opus 5.5 · high` · Aviso: sí (`network_manager.gd`)

- [x] (commit `03bd4e1`) **S-206.1** `NetworkManager.PROTOCOL_VERSION := 1` y enviarla en el handshake. Si no coincide, el
  host rechaza con motivo `version`. (El handshake ya cambió dos veces y hoy un cliente viejo solo ve un
  timeout.)
- [x] (commit `03bd4e1`) **S-206.2** En `main_menu.gd`, `_on_session_failed(reason)` traduce cada motivo a un texto con
  qué hacer: "El anfitrión tiene otra versión del juego: actualicen los dos", "No hubo respuesta en 8 s:
  revisá la IP y que el firewall de Windows permita Take My Package (ver README)", "La sala está llena".
- [x] (commit `03bd4e1`) **S-206.3** Test `tests/test_connection_errors.gd`: cada motivo muestra su texto.

#### S-207 · Unirse por código corto en LAN — C · `Opus 5.5 · high` · Aviso: sí (`main_menu.gd`, `hud.gd`)

- [x] (rama `nacho/S-207-room-code`) `scripts/ui/room_code.gd` (estático, `RoomCode`): IPv4 + puerto ↔ código sin O/0/I/1.
  Decisión: el puerto por defecto es implícito (8 caracteres, `K7QM-4TXA`); otro puerto suma 4 (12). Último
  carácter de control (suma ponderada mod 32). El HUD del anfitrión LAN muestra el código en vez de la IP;
  "Unirse" acepta código o IP (`RoomCode.resolve`). Steam no aplica. Aviso `docs/avisos/2026-09-30-s207-room-code.md`.
- [x] (rama `nacho/S-207-room-code`) Test `tests/test_room_code.gd`: ida y vuelta para 1000 direcciones, todo símbolo mal
  tipeado rechazado con mensaje, menú y HUD.

#### S-208 · Rendimiento del jugador, paquetes y UI — B · `Opus 5.5 · high` · Aviso: no

- [ ] `tests/bench_depot.gd`: depósito con 14 cajas y 5 jugadores simulados, 600 frames; medir
  `Performance.TIME_PROCESS` y el tiempo de `package_feedback.gd` y del HUD.
- [ ] Meta: < 1,5 ms por frame entre paquetes + HUD. Candidatos típicos: labels que reescriben
  `text` cada frame aunque no cambió (causa relayout), `find_child` en `_process`, materiales duplicados.
- [ ] Resultado anotado en el README → Rendimiento.

#### S-209 · Jugador que se desconecta en medio de la partida — A · `Opus 5.5 · xhigh` · Aviso: sí (`level_base.gd`)

- [x] (commits `c77194f`, `d20df06`) Cuando un peer se va: su caja en mano queda en el piso donde estaba; si estaba sentado, el
  asiento se libera; si conducía, el camión frena solo; su casa asignada sigue esperando.
- [x] (commit `5dd2771`) Probarlo con `tests/net_pair.gd` (S-204): el cliente se cierra con caja en mano y el host sigue sin
  errores.

#### S-210 · Guardados que no se corrompen — A · `Opus 5.5 · high` · Aviso: sí (`run_manager.gd` para el leaderboard)

- [x] (commit `c694bdf`) Función común `scripts/core/safe_json.gd`: escribe en `<archivo>.tmp` y renombra
  (`DirAccess.rename`), así un corte de luz no deja el archivo a medias; al leer, si el JSON es
  inválido, lo renombra a `<archivo>.bad` y devuelve el valor por defecto.
- [x] (commit `11328c1`) Usarla en `unlock_manager.gd`, en la campaña (S-105) y en el leaderboard de `run_manager.gd`.
- [x] (commit `11328c1`) Test `tests/test_safe_json.gd`: archivo truncado → no crashea, crea `.bad`, perfil por defecto.

---

### 3. Arte y dirección visual

#### S-301 · Íconos de Líquido, Explosivo y Hostil — A · `Opus 5.5 · medium` para el prompt, generación de imagen aparte · Aviso: no

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

#### S-302 · Contenidos propios para cada trampa — B · `Opus 5.5 · high` (Blender Python) · Aviso: no

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

#### S-303 · Íconos de acción del HUD — B · generación de imagen + `Opus 5.5 · high` para integrar · Aviso: no

- [x] (commit `d14cc56`) Agarrar, soltar, sentarse, timbre, foto, bocina, ping, abrir caja, usar carta. 128×128, mismo
  estilo que los de trampa. `assets/ui/icons/tx_ui_action_<acción>_128.png`.
- [x] (commit `d14cc56`) `UiTheme.action_icon(id)`; los avisos de interacción muestran ícono + tecla + texto corto.

#### S-304 · Celular en la mano y marco de la cámara — B · `Opus 5.5 · high` · Aviso: sí (`presentation/phone_camera.gd` no tiene dueño en el reparto)

- [ ] Mostrar `models/props/handheld/sm_prop_phone.glb` en la mano derecha del viewmodel mientras la
  cámara del celular está abierta (hoy el GLB está sin usar, `inventario-assets.md` §2). **Ojo
  (2026-09-24):** ya no hay manos de primera persona (pedido del usuario: nada de manos que no sean
  del personaje), así que el celular no puede colgar de una; ver aviso en `colaboracion-equipo.md`.
- [ ] Marco de UI del celular (bordes redondeados, hora, batería, botón de obturador) como `Control`
  en `scripts/ui/phone_frame.gd`.

#### S-305 · Accesorios cosméticos 3D — C · `Opus 5.5 · high` · Aviso: no

- [ ] 4 accesorios low-poly con script de Blender: gorra, chaleco reflectivo, casco de obra, mochila
  térmica. `models/characters/accessories/`.
- [ ] Engancharlos con `BoneAttachment3D` (cabeza / columna) en `player.tscn`, uno por categoría.
- [ ] Desbloqueos en `UnlockManager.COSMETICS` y columna nueva en `cosmetics_panel.gd`; replicar
  `accessory_id` como `cosmetic_id`.

#### S-306 · Logo como imagen — B · generación de imagen + `Opus 5.5 · medium` · Aviso: no

- [x] (commit `004bb8b`) Wordmark "TAKE MY PACKAGE" en PNG transparente 2048 px de ancho, a partir de `UiTheme.logo()`
  (Lilita One + cinta amarilla), más una versión apilada cuadrada. `assets/ui/logo/`.
- [x] (commit `004bb8b`) Usarlo en el menú en lugar del logo armado con tipografía. Es la base de las cápsulas (S-903).

#### S-307 · Ilustración de fondo de resultados — C · generación de imagen · Aviso: no

- [ ] La tripulación frente a la furgoneta al terminar la ruta, 1920×1080, con zona libre a la
  izquierda para el puntaje. Registrar en `art/ai-registro.md`.

#### S-308 · Animaciones de emote — C · `Opus 5.5 · high` (Blender Python) · Aviso: no

- [ ] Saludar, señalar, pulgar arriba, agarrarse la cabeza: 4 animaciones cortas agregadas al GLB del
  jugador. Desde el 2026-09-24 el jugador es el personaje redondeado de Astra: se suman como
  poses nuevas en `art/rounded_character/build_game_export.py` (ver `assets/README.md`,
  "Personajes"). Las dispara la rueda de pings (S-505).

#### S-309 · Mantener al día la dirección visual del dominio — A · `Opus 5.5 · medium` · Aviso: sí (`especificaciones-visuales.md`, filas propias)

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

### 4. Audio y diseño sonoro

#### S-401 · Sonidos de interfaz — A · `Opus 5.5 · high` · Aviso: no

- [x] (commit `60c4dc4`) `scripts/ui/ui_sounds.gd` (autocontenido, **sin tocar `synth_audio.gd`**, que es zona
  compartida): pasar el mouse, clic, abrir y cerrar panel, toast, desbloqueo, voto, error. Sintetizados
  igual que `SynthAudio` (generar `AudioStreamWAV` en código), por el bus `SFX`.
- [x] (commit `60c4dc4`) `UiTheme.button()` conecta hover/press automáticamente, así todos los botones suenan.
- [x] (commit `60c4dc4`) Test: cada botón de `main_menu.gd` tiene el sonido conectado; el volumen de efectos lo afecta.

#### S-402 · Voces sin palabras ("gibberish") — B · `Opus 5.5 · xhigh` · Aviso: no · **[x] PR #62**

**Actuación de voz (decisión)**: el MVP no tiene voces grabadas (costo, localización). En su
lugar, balbuceo sintetizado estilo Animal Crossing, con tono propio por color de jugador.

- [x] Síntesis de sílabas con formantes (3-4 vocales, 60-120 ms cada una), tono base por
  `PLAYER_COLORS`, por el bus `Voice`. En `scripts/gameplay/player/player_voice.gd`.
- [x] Disparadores: ping (según la opción de la rueda), golpe fuerte (el flinch de la vieja #12), ragdoll, entrega
  intacta, caja arruinada propia.
- [x] Opción de volumen "Voces" ya existe: verificar que lo respeta.

#### S-403 · Stingers de resultado y desbloqueo — B · `Opus 5.5 · high` · Aviso: no · **[x] `180765c`**

- [x] (commit `180765c`) Frases musicales cortas sintetizadas (2-4 s): entrega perfecta, entrega con pérdidas, récord,
  desbloqueo, evento resuelto, evento fallido. Por el bus `Music`. En `ui_sounds.gd`.

#### S-404 · Mezcla medida de los sonidos de trampa — A · `Opus 5.5 · high` · Aviso: no

Balance de volumen sin depender del oído (Nacho dejó registrado en su #83 que editar valores a ciegas
no sirve).

- [x] (commit `2dc4769`) `tests/audio_loudness_report.gd`: genera cada sonido de trampa y de UI, calcula RMS y pico
  en dBFS, y lista la diferencia contra un objetivo (−18 dBFS RMS para efectos de trampa, −24 para UI).
- [x] (commit `2dc4769`) Ajustar el `volume_db` de cada reproductor del dominio de Slatex para quedar a ±2 dB del objetivo.
  Tabla antes/después en `docs/direccion-visual.md` (sección de audio) o un `docs/audio.md` nuevo.

---

### 5. UI / UX

#### S-501 · HUD con jerarquía: una cosa urgente a la vez — A · `Opus 5.5 · xhigh` (después de S-201) · Aviso: no

Resuelve `critica-diseno-abogado-del-diablo.md` §5.

- [x] **S-501.1** Definir en `docs/controles-y-ui.md` tres capas con zona fija de pantalla:
  **crítico** (tu caja en riesgo, evento con cuenta regresiva, cuenta del explosivo) arriba al centro,
  grande, con pulso; **contexto** (aviso de interacción, tapa de la caja) abajo al centro; **información**
  (velocidad, dinero, distancia, carga de los demás) en las esquinas, chico y quieto.
- [x] **S-501.2** Nunca dos textos en la misma zona: cola con prioridad en `hud_notices.gd`.
- [x] **S-501.3** Barra de atajos: se oculta sola después de 3 partidas completadas o 60 s sin usar
  ayuda; opción "Ayudas de controles: siempre / al principio / nunca".
- [x] **S-501.4** El dinero del equipo solo se ve en el depósito, en la pausa y en resultados.
- [x] **S-501.5** Test en `test_hud_flow.gd`: con evento + aviso + toast a la vez, cada uno en su zona y
  ninguno tapado. Captura antes/después con `render_hud.gd`.

#### S-502 · Accesibilidad: daltonismo, texto y efectos — A · `Opus 5.5 · high` · Aviso: no

- [x] Estados de caja con forma además de color: OK ✓, En riesgo ! (con pulso), Arruinada ✕, en las filas
  de carga y sobre la caja.
- [x] Opción "Paleta para daltonismo" que cambia verde/amarillo/rojo por la paleta Okabe-Ito
  (azul/naranja/bermellón) en `UiTheme`.
- [x] Opción "Tamaño de texto de menús" (100 / 125 / 150 %), aparte de la escala del HUD que ya existe.
- [x] Opción "Subtítulos de sonidos": "[tictac acelerando]", "[gruñido]", "[vidrio que cruje]" en la
  zona de contexto, para los sonidos de trampa en riesgo.
- [x] Todas persistidas en `GameSettings`; `test_settings.gd` ampliado.

#### S-503 · Tipografía legible a distancia de sillón — C · `Opus 5.5 · medium` · Aviso: no

- [x] (commit `10218d0`) Revisar que ningún texto del HUD al 60 % de escala quede por debajo de 14 px efectivos a 1080p;
  subir los que no cumplan. Tabla de tamaños en `docs/direccion-visual.md` §3.

#### S-504 · Todo el menú con gamepad — A · `Opus 5.5 · high` · Aviso: no

- [x] (commit `67cf588`) Cada panel (`options`, `progress`, `tutorial`, `cosmetics`, `leaderboard`, `depot_panel`, pausa y
  resultados) da foco a su primer botón al abrir y devuelve el foco al botón que lo abrió al cerrar.
- [x] (commit `67cf588`) Vecinos de foco en grillas (cosméticos) para que el stick no salte de columna.
- [x] (commit `67cf588`) B / Círculo cierra cualquier panel (hoy lo hacen algunos).
- [x] (commit `67cf588`) Test `tests/test_gamepad_focus.gd`: al abrir cada panel hay un `Control` con foco.

#### S-505 · Rueda de pings — B · `Opus 5.5 · xhigh` · Aviso: no

Hoy hay un único ping "¡Cuidado!" (`player.gd` `_send_ping`).

- [x] (commit `638b9a4`) Tocar ping = ping rápido como hoy. Mantener = rueda de 6: ¡Cuidado!, ¡Ayuda!, ¡Frená!, Acá, Gracias,
  Sí/No. Selección con el mouse o el stick derecho.
- [x] (commit `638b9a4`) Sin cambios de red: `EventBus.request_ping(position, label)` ya lleva el texto.
- [x] (commit `638b9a4`) Color e ícono por tipo en el marcador (`_mark_pinger`); "¡Ayuda!" dispara el emote (S-308) y la
  voz (S-402) si existen.
- [x] (commit `638b9a4`) Test en `test_ping.gd`: cada opción llega con su etiqueta.

#### S-506 · Onboarding: tutorial en fichas y consejos de primera vez — A · `Opus 5.5 · high`, textos con `Opus 5.5 · medium` · Aviso: no

La decisión de pantalla estática sigue (sin mini-nivel), pero hoy es un solo párrafo largo.

- [x] **S-506.1** (commit `cffdbfc`) `tutorial_panel.gd` en páginas: 1) el objetivo (entregar a cada casa la caja de la
  pizarra), 2) conductor, 3) pasajero, 4) una ficha por trampa **desbloqueada** (ícono, qué la rompe, qué
  hacer, tecla del dispositivo en uso con `UiTheme.keycaps`), 5) dinero, mérito y cartas en dos líneas.
  Navegable con gamepad.
- [x] **S-506.2** (commit `cffdbfc`) Consejos de primera vez en partida: la primera vez que un perfil tiene una trampa en la
  mano o en su asiento, aparece su ficha resumida 6 s en la zona de contexto. Se guarda `seen_tips` en el
  perfil de `UnlockManager`.
- [x] **S-506.3** (commit `cffdbfc`) Al abrir el juego por primera vez (perfil sin partidas), el menú ofrece "Cómo jugar"
  resaltado.
- [x] **S-506.4** (commit `cffdbfc`) Test: cada trampa tiene su ficha; un consejo visto no vuelve a salir.

#### S-507 · Panel de tripulación en el depósito — B · `Opus 5.5 · high` · Aviso: sí (`hud.gd`, `hud_pause.gd`, `hud_prompts.gd`, `project.godot`)

- [x] (rama `nacho/S-507-crew-panel`) Con Tab (Back en gamepad) mantenido en el depósito: `scripts/ui/hud/crew_panel.gd` lista a los
  conectados con el color de su uniforme y su nombre, quién está al volante y quién tiene caja (ícono + texto, no solo
  color). No pausa ni toma foco. Acción nueva `crew_panel`: Tab ya era de `spectate_toggle` (solo en ruta), así que
  comparte Tab/Back con él porque nunca coinciden; documentado en `convenciones-godot.md` §1 y `controles-y-ui.md`.
  La barra de atajos lo enseña solo en el depósito. Sin RPC nuevos.
- [x] (rama `nacho/S-507-crew-panel`) Para el anfitrión LAN: código de sala (`RoomCode`) e IP; en Steam "invitá desde la lista de amigos";
  el cliente ve por qué no hay código. Test `tests/test_crew_panel.gd`. Aviso: `docs/avisos/2026-09-30-s507-crew-panel.md`.

#### S-508 · Pantalla de resultados completa — A · `Opus 5.5 · high` · Aviso: no

- [x] (commit `909a662`) Una fila por casa con ícono de la trampa, resultado y si tuvo foto.
- [x] (commit `909a662`) Premios de la entrega a partir del mérito (S-102): "MVP" (más mérito), "Rescatista", "Desactivador",
  "Mano firme". Con el color de cada jugador.
- [x] (commit `909a662`) Barra de progreso hacia el próximo desbloqueo: "Te faltan 2 entregas y 120 pts para Explosivo".
- [x] (commit `909a662`) Evento de ruta de la partida y cómo terminó.
- [x] (commit `909a662`) Test en `test_score_breakdown.gd` / `test_hud_flow.gd`.

#### S-509 · Idioma inglés — A (para lanzar) · `Opus 5.5 · high` para extraer, `Opus 5.5 · medium` para traducir · Aviso: sí (`project.godot`)

Los textos de Slatex quedaron centralizados en el catálogo bilingüe de UI.

- [x] (commit `8d66f72`) **S-509.1** Extraer los textos de **los archivos de Slatex** (`scripts/ui/`, avisos de
  `player.gd`/`package.gd`/`interaction/`, `get_hint()` de cada trampa, `UnlockManager`, `CrewProgression`,
  `RouteEventManager`) a `do-not-drop/translations/strings_ui.csv` con claves (`HUD_CARGO_TITLE`…) y columnas
  `es,en`. Usar `tr("CLAVE")`.
- [x] (commit `bf85e4b`) **S-509.2** Registrar el CSV en `project.godot` (internationalization) y opción "Idioma" en opciones.
- [x] (commit `8d66f72`) **S-509.3** Traducir al inglés con tono de juego (no literal).
- [x] (commit `8d66f72`) **S-509.4** Test `tests/test_ui_translations.gd`: toda clave usada existe en las dos columnas; ningún
  texto de la UI de Slatex queda sin pasar por `tr()` (buscar comillas con letras acentuadas en
  `scripts/ui/`).
- [x] (commit `8d66f72`) Los textos de archivos de Nacho (casas, depósito) los extrae él: dejar el aviso con la lista de
  archivos y la convención de claves. No es bloqueante para esta tarea.

#### S-510 · Progreso y récords que se entiendan — B · `Opus 5.5 · high` · Aviso: no

- [x] (commit `c2dad6d`) `progress_panel.gd`: barra por desbloqueo (entregas y puntos por separado), ícono del contenido y
  qué da ("Nueva trampa: Explosivo").
- [x] (commit `c2dad6d`) `leaderboard_panel.gd`: pestañas Entrega / Endless, tamaño de tripulación y fecha legible.
- [x] (commit `c2dad6d`) Test `test_progress_ui.gd` ampliado.

---

### 6. Narrativa y guion

#### S-601 · Premisa y tono en una página — B · `Opus 5.5 · medium` · Aviso: no · **[x] `01e81d2`**

- [x] (commit `01e81d2`) `docs/narrativa.md`: qué es la empresa Take My Package, quién manda (una jefa que solo habla por
  la radio del depósito y por notas), por qué los paquetes son tan raros (clientes excéntricos del
  pueblo), tono (humor absurdo, nunca cruel ni con sangre). Lista de 10 clientes recurrentes con nombre
  y manía. Es la referencia para S-602 a S-604.

#### S-602 · Remitentes, notas y etiquetas escritas a mano — B · `Opus 5.5 · medium` para textos, `Opus 5.5 · high` para código · Aviso: no · **[x] PR #74**

- [x] Campos nuevos en `package_content.gd`: `sender`, `recipient`, `notes: PackedStringArray` (3-5 por
  contenido). La etiqueta de envío muestra remitente y destinatario; al abrir la caja (T), la línea de
  "adentro" suma la nota ("Es la torta de mi boda. No la miren.").
- [x] Una garabateada a mano por caja ("NO AGITAR!!!", "ESTE LADO ARRIBA (EN SERIO)") como `Label3D` con
  tipografía de marcador. Narrativa ambiental sin cinemáticas.

#### S-603 · La jefa habla en el depósito — C · `Opus 5.5 · medium` · Aviso: sí (`depot_panel.gd`, `network_manager.gd`) · **[x] rama `nacho/S-603-boss-lines`**

- [x] Pool de 20 líneas de inicio de jornada según el pedido y la campaña ("Tres entregas. Una es una
  gallina. No pregunten.") mostradas en la pizarra del `depot_panel.gd` y como toast al entrar. Hecho
  (2026-09-30): `boss_lines.gd` (`BossLines`, módulo puro, determinista por semilla + partidas + casas) con 20
  líneas de inicio por pedido (trampas, cantidad de casas) y campaña (partidas, plata) más 4 propias de Endless;
  las decide el host y viajan como `LocText` (RPC `_receive_boss_lines` del depósito, `PROTOCOL_VERSION` 5). Se
  ven en la pizarra (`OrderBoard/Boss0`), en la hoja de pedidos de `depot_panel.gd` y como toast una vez. 34
  claves `WORLD_BOSS_*` en `strings_world.csv` + `UI_DEPOT_BOSS_TAG`.
- [x] Reacción según la última partida ("Ayer rompieron dos cosas. Hoy no."). Hecho: 8 reacciones (primera
  jornada, nada llegó, roto y perdido, rotas, una rota, perdidas, racha sin accidentes, entrega perfecta) desde
  el resumen que `depot_campaign_board.gd` guarda en `depot_log.json`; van en `OrderBoard/Boss1` y en el panel.
  Decisión Endless: líneas propias de inicio, sin reacción. Test `test_boss_lines.gd`.

#### S-604 · Reclamos de clientes con voz propia — B · `Opus 5.5 · medium` · Aviso: no

- [ ] Los reclamos de la pantalla de resultados salen de un pool por cliente y resultado (roto, en
  riesgo, abierta, equivocada) en vez de un texto genérico. Pool en `data/text/complaints.json` o dentro
  de la tabla de traducciones (S-509).

#### S-605 · Textos de trampas y eventos con tono — C · `Opus 5.5 · medium` · Aviso: no

- [x] Reescribir `get_hint()` de las 7 trampas y los `prompt` de los eventos de ruta con el tono de
  S-601, máximo 6 palabras por aviso (se leen manejando). Hecho el 2026-09-30: 24 textos `HUD_HINT_*` y 10 de
  prompts de evento reescritos en `strings_ui.csv` (es y en, mismas claves, verbos de N-117 intactos); ampliado
  `test_ui_translations` con la aserción de <= 6 palabras; aviso `docs/avisos/2026-09-30-s605-trap-event-tone.md`;
  rama `nacho/S-605-trap-event-tone`.

---

### 7. Producción y gestión de proyecto

#### S-701 · Esta lista como tablero — A · `Opus 5.5 · low` · Aviso: no

- [ ] Cada tarea cerrada: `[x]` + hash del commit en la misma línea. Si una tarea resulta más grande de lo
  pensado, partirla acá en subtareas antes de seguir.
- [ ] Una vez por semana, actualizar "Última actualización" y mover a "Hecho" lo cerrado del hito.

#### S-702 · Qué queda fuera del MVP (control de alcance) — A · `Opus 5.5 · medium` · Aviso: no

- [x] (commit `dbe3e48`) Sección nueva en `docs/plan-desarrollo.md` con la lista cerrada de lo que **no** se hace antes de
  Early Access: chat de voz propio, matchmaking público, cartas Prioridad e Información, tienda en ruta,
  tutorial jugable, más de 7 trampas, servidores dedicados, microtransacciones. Cualquier idea nueva se
  anota en una sección "Después del lanzamiento", no en esta lista.

#### S-703 · Avisos al día — A · `Opus 5.5 · low` · Aviso: sí

- [ ] Cada tarea con Aviso `sí` deja su entrada en `docs/colaboracion-equipo.md` en el mismo commit.
- [ ] Borrar de ese documento los avisos de más de un mes que ya no afectan a nadie (dejar solo los vigentes).

---

### 8. QA (sin playtesting)

#### S-801 · Recorrido técnico de 10 minutos antes de cada push grande — A · — · Aviso: no

Esto **no es playtesting** (no evalúa si es divertido): busca errores.

- [x] (commit `ce7370b`) Checklist en `docs/qa-recorrido.md`: abrir el juego, cambiar opciones, jugar solo una entrega
  completa (agarrar, montar, manejar, bajar, timbre, foto), pausa, volver al menú, Endless 2 minutos,
  cerrar. Anotar cualquier error de la consola de Godot.

#### S-802 · Tests de contrato para todo lo que se agrega por datos — A · `Opus 5.5 · high` · Aviso: no

- [x] (commit `7abb1a3`) `tests/test_trap_contract.gd`: recorre `data/traps/*.tres` y verifica para cada una: crea su
  comportamiento, la integridad queda en [0, max] con input vacío y con input aleatorio durante 30 s
  simulados, `get_hint()` nunca vacío, tiene ícono (S-301), contenido propio (S-302), sonido de riesgo, y
  un desbloqueo o está en el set inicial. Una trampa nueva que no cumpla falla este test.
- [x] (commit `7abb1a3`) Mismo criterio para `data/contents/*.tres` (nodos `Filler`/`Intact`/`Damage`/`Ruined`).

#### S-803 · Bot de caos — B · `Opus 5.5 · xhigh` · Aviso: no

- [x] `tests/test_chaos_bot.gd`: un jugador bot hace acciones al azar (con semilla fija) durante 5 minutos
  simulados en el nivel de entrega: agarrar, soltar, abrir, montar, sentarse, pararse, pingear, sacar foto.
  Falla si aparece un `push_error`, un NaN en posiciones o una caja fuera del mundo.
  Hecho: 300 s simulados (18000 ticks a 1/60 s) en ~35 s de pared, acelerando con `physics_ticks_per_second` x
  `time_scale` (solo `time_scale` alarga el paso, no acelera); errores capturados con un `Logger`. No entra en
  los 20 s de S-806. Rama `nacho/S-803-chaos-bot`.

#### S-804 · Nada anunciado queda colgado — A · `Opus 5.5 · high` · Aviso: no

- [x] (commit `6175d6e`) Test `tests/test_no_dangling_state.gd`: al terminar una partida, `RouteEventManager` no tiene evento
  activo, `ShopVoteManager.active` es falso fuera del depósito, ninguna caja queda con `occupied_by` de un
  jugador que ya no existe. Es el test que hubiera detectado S-101.

#### S-805 · Telemetría local para cuando haya playtesting — B · `Opus 5.5 · high` · Aviso: sí (`game_settings.gd`, `options_panel.gd`, `project.godot`)

- [x] Opción "Guardar registro de partidas" (apagada por defecto). Si está activa, al terminar cada partida
  escribe `user://telemetry/<fecha>.json` con: duración, trampas del pedido, tiempo en riesgo por trampa,
  qué rompió cada caja, evento de ruta, puntaje. Nada se manda por red. Hecho: autoload `RunTelemetry`
  (`scripts/core/run_telemetry.gd` + `run_telemetry_format.gd`) que solo escucha `EventBus` y escribe con `safe_json.gd`
  `AAAA-MM-DD_HH-MM-SS.json` (sin `:`; tope de 300 archivos); `GameSettings.save_run_log` persistida y en el panel
  de opciones (`UI_OPT_RUN_LOG`). La causa de ruina es el texto ya traducido que reporta la caja: agrupar por `trap`.
  Test `test_run_telemetry`; aviso `docs/avisos/2026-09-30-s805-run-log.md`; rama `nacho/S-805-local-telemetry`.
- [x] Script `tools/telemetry-summary.py` que resume una carpeta de registros en una tabla. Así el primer
  playtesting ya produce datos sin preparar nada. Hecho: solo librería estándar; tablas general, por trampa
  (partidas, cajas, % arruinadas, segundos en riesgo), causas y eventos de ruta; `--roles host,solo` evita contar dos
  veces la misma partida jugada en red; salta archivos rotos. Rama `nacho/S-805-local-telemetry`.

#### S-806 · Batería verde y rápida — A · — · Aviso: no

- [x] (commits `3c4ac88`, `37581a2`) Después de cada tarea: `tools/run-tests.sh` con filtro de lo tocado. Antes de push, el hook corre todo.
- [ ] Si un test propio tarda más de 20 s, revisar si se puede acortar sin perder lo que verifica.

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

- [ ] Con el logo (S-306): 460×215, 616×353, 231×87, 1232×706, 600×900, 3840×1240. `assets/store/`.
  Registrar en `art/ai-registro.md`.

#### S-904 · Press kit — C · `Opus 5.5 · medium` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

- [ ] `docs/marketing/presskit.md`: ficha (nombre, equipo, plataforma, precio objetivo $8-15, fecha
  tentativa de Early Access), descripción, características, logo, capturas (S-902), contacto.

#### S-905 · Cómo enseñan los competidores — B · `Opus 5.5 · medium` con búsqueda web · Aviso: no

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

### Modelado pendiente (101-106) — relevamiento 2026-09-23

> Anotado por Nacho al relevar el modelado pendiente de todo el juego; detalle en
> `docs/inventario-assets.md` §10. Son sugerencias para tu dominio: reordenalas o descartalas.

| # | Tarea | Prio | Estado |
|---|---|---|---|
| 101 | Ragdoll con el modelo del jugador (huesos del rig) en vez de cápsulas sueltas (`player_ragdoll.gd`). | B | Pendiente |
| 102 | Maniquí del panel de cosméticos con el modelo del jugador en vez de cápsula + esfera (`cosmetics_panel.gd`), para que la vista previa muestre lo que se va a ver en juego. | A | Pendiente |
| 103 | Accesorios cosméticos con geometría (gorras, chalecos), cuando se retome la decisión del #76. | C | Pendiente |
| — | ~~Cuerpo del jugador con el personaje redondeado de Astra.~~ **[x] Hecho por Nacho (2026-09-24, pedido del usuario)** — `sm_char_player_rounded.glb` con clips Idle/Walk/Jump/PickUpPackage/Sit, camiseta con el color del equipo, IK de manejo continuo sin cilindros; aviso en `colaboracion-equipo.md`. Los NPC siguen con el modelo viejo. El #101 (ragdoll) ahora tendría que usar este rig. | A | Hecho |
| — | ~~Manos flotantes en primera persona.~~ **[x] Hecho por Nacho (2026-09-24, pedido del usuario)** — sin guantes/cápsulas en las cámaras ni en el volante; las manos que atendían la trampa desde el asiento (#10) se fueron con ellos. Aviso en `colaboracion-equipo.md`. | A | Hecho |
| 104 | Rehacer el celular (`sm_prop_phone.glb`, 92 triángulos) e integrarlo en `phone_camera.gd`, que hoy no carga ningún modelo. | B | Pendiente |
| 105 | Borrar las cajas viejas `models/cargo/sm_cargo_package_*.glb`: sin uso desde las cajas por trampa. | A | Pendiente |
| 106 | Revisar los ojos/tentáculos del paquete Hostil (esferas y barras en `package_feedback.gd`): ¿alcanzan como chiste o merecen un modelo? | C | Pendiente |

---

## Para cuando haya playtesting (no se hace ahora)

| Ítem viejo | Qué hay que observar |
|---|---|
| #55 | Si la variedad del Endless se siente bien o hace falta más curaduría. |
| #98 | Si los tramos se sienten repetitivos después de varias partidas. |
| #83 (parte) | Mezcla de audio con oído, después de la medida de N-404. |
| — | Si el largo medido en N-102 se siente corto o largo jugando de verdad. |

---

## Qué pasó con la lista anterior (1-127)

- **Cerradas**: modelado, comportamiento y sonido del camión; ruta procedural con curvas; 11 tipos de tramo;
  clima y hora del día; casas de entrega con timbre y pizarra; depósito; Endless con dificultad creciente;
  segundo vehículo y pinturas; optimización con decorado horneado; red con semilla y casas desde el host. El
  detalle está en el historial de git (`git log -p docs/tareas-nacho.md`).
- **Reubicadas en esta lista**: #4 → N-301 · #15 y #38 → N-504 · #18 (clutter en red) → N-201 · #34 (SSAO) →
  N-308 · #58/#68 (eco del túnel, lluvia con cámara exterior) → N-402 · #81 (bocina) → N-203 · #83 (mezcla) →
  N-404 · #93 (FPS con GPU) → N-204 · #99 → N-702 · #100 → N-307 · #114 (Endless curvo) → N-206 · #127
  (depósito en Endless) → N-101.
- **Cerradas como "fuera del MVP"** (N-701): #14, #59, #60, #65, #76, #77, #79.
- **Movidas a "Para cuando haya playtesting"**: #55, #98.
- **Encontradas en el relevamiento del 2026-09-24**: el ciervo abre un evento de ruta que nunca se cierra
  (N-202), el largo de la entrega nunca se midió contra la regla de 2-5 minutos (N-102), el tractor y la
  camioneta de la competencia solo aparecen en el depósito (N-306), el inventario de assets está
  desactualizado (N-307).

## Bugs de multijugador del playtest (143-149) — reporte directo del usuario, 2026-09-24

| # | Tarea | Prio |
|---|---|---|
| 143 | ~~Con 3+ jugadores los demás se ven flotando / al cargar una caja se ve la caja sola.~~ **[x] Hecho** — en Steam el cliente no tenía `server_relay`: lo que un cliente mandaba a otro (su posición) se perdía y lo veían quieto en su punto de aparición, a 1 m del piso (`network_manager.gd`). Falta confirmarlo jugando por Steam. | A |
| 144 | ~~Un cliente no puede manejar (velocímetro 0-1-0-1).~~ **[x] Hecho** — `controls_enabled` arrancaba en `false` en `vehicle.tscn` y solo se prendía en el host; ahora se replica. | A |
| 145 | ~~Las cajas rebotan atrás al avanzar (en clientes).~~ **[x] Hecho** — cajas y jugadores que van en la caja de carga se replican en coordenadas del camión (`net_transform` / `net_position` + `net_in_vehicle`, `vehicle.carries()`); cada peer los pone sobre su propia copia. Si en el host también rebotan, es otro problema: revisar jugando. | A |
| 146 | ~~Cajas y personajes que se salen del camión / atraviesan las puertas cerradas.~~ **[x] Hecho** — lo de #145, más: el jugador parado atrás se mueve y gira con el camión a mano (`player.gd` `_ride_with_vehicle`; en el cliente el camión es una copia teletransportada que no arrastra nada), y los objetos sueltos del cliente también (`cargo_clutter.gd`). | A |
| 147 | ~~Foto del celular en un cliente: "no hay ninguna entrega que probar".~~ **[x] Hecho** — el celular miraba `delivered` de la casa, que solo cambia en el host; ahora también el registro de `RunManager`, y la foto de un cliente se archiva en el host (`RunManager.submit_delivery_photo`). | A |
| 148 | ~~Cajas pegadas a la pared la atraviesan.~~ **[x] Hecho** — en clientes era el mismo desfase de #145; además la caja plana (0,95 m) en el estante se metía en la pared lateral y ahora se corre hacia adentro (`vehicle.gd` `_on_package_placed`). | A |
| 150 | ~~Los amigos tenían que tocar "Crear sala con amigos" para que Steam detectara el juego.~~ **[x] Hecho** — Steam se inicializaba recién al crear o unirse; ahora arranca con el juego (`NetworkManager._ready`, salvo headless). Aceptar una invitación o "Unirse a la partida" funciona desde el menú, jugando solo o con el juego cerrado (`+connect_lobby`); el menú entra con `join_steam_lobby()`. | A |
| 149 | Probar con 3+ jugadores por Steam: jugadores quietos, carga, manejo de un cliente, caja de carga en movimiento y foto desde un cliente. | A |

## Segunda tanda de multijugador (151-166) — cacería de `cazador-bugs`, 2026-09-24

| # | Tarea | Prio |
|---|---|---|
| 151 | ~~Caja cargada o soltada dentro del camión en marcha, 1 m atrás o afuera.~~ **[x] Hecho** — la pose de carga y la de soltar viajan en coordenadas del camión (`submit_carry_transform`/`request_drop` con `in_vehicle`); el host la reaplica cada tick sobre su camión, y la caja soltada arranca con la velocidad del camión (`vehicle.point_velocity()`). | A |
| 152 | ~~El host reinicia y los clientes quedan en resultados, encerrados, sin poder manejar.~~ **[x] Hecho** — `NetworkManager.begin_restart()`: el nivel nuevo del host manda `_remote_restart` y cada cliente recarga; los jugadores solo se crean para peers con el nivel cargado (`is_peer_ready`, filtro de visibilidad del sincronizador del jugador). | A |
| 153 | ~~El que entra tarde no ve la partida, ve cajas entregadas y el portón al revés.~~ **[x] Hecho** — `RunManager.send_session_state()` al peer que tiene el nivel listo: partida, evento, reloj, entregas, carga (con tarjetas del HUD), cajas entregadas y portón. Si llega con la partida terminada, espera el reinicio. | A |
| 154 | ~~La caja entregada queda congelada en la puerta en los clientes.~~ **[x] Hecho** — `consume()` se replica (`_remote_consume`) y queda anotada en `RunManager.consumed_packages`. | A |
| 155 | ~~En un cliente, el que va parado atrás "rebota" contra el camión.~~ **[x] Hecho** — sigue al camión en cada frame y sin interpolación mientras el camión no se interpola (`_ride_frame_by_frame`); igual los objetos sueltos. El camión ahora se replica a ~60 Hz (antes 20). | A |
| 156 | ~~Pasajero sentado (cliente) no puede abrir la caja.~~ **[x] Hecho** — el alcance se mide desde el asiento (`Player.reach_origin()`), también en pasar cajas, fotos y el ping. | A |
| 157 | ~~Entrada de "atender caja" pegada.~~ **[x] Hecho** — solo la acepta del que está sentado ahí (`tender_peer_id`, `set_tender`), vence a los 0,25 s y se limpia al levantarse. | B |
| 158 | ~~Si se cae el host, el cliente sigue con el mundo de la sala.~~ **[x] Hecho** — `_end_session()` limpia semilla, casas, trampas y lobby; el menú muestra el motivo. | B |
| 159 | ~~Casas según la cantidad de jugadores: falta decidir si conviene reconstruir la ruta sola.~~ **[x] Decidido (2026-09-25): no.** La ruta, sus casas, los pedidos de la pizarra, el decorado y el ciervo salen de la semilla y del número de casas en el momento de construir el nivel, en cada peer. Reconstruirla sola en el depósito obligaría a reconstruir y re-sincronizar todo eso en vivo (casas asignadas, pedidos, cajas en los estantes, quien ya entró tarde) y abre la puerta a mundos distintos entre peers, el bug que más cuesta encontrar. El reinicio ya lo hace bien y en un solo lugar (`NetworkManager.begin_restart()`), y el depósito avisa al host (`level_base.gd` `_on_peer_level_ready()`). Si en playtesting el aviso no alcanza, lo siguiente es un botón "Rehacer la ruta" en el depósito que dispare ese mismo reinicio, no una reconstrucción parcial. | B |
| 160 | ~~Handshake: timeout de 60 s, el que entra con el host entre escenas, código muerto.~~ **[x] Hecho** — timeout de 20 s, el cliente siempre espera a tener el nivel, el host recuerda su nivel (`session_scene`); se borró `_accept_joiner`. | B |
| 161 | ~~Invitación aceptada mientras el menú conecta se pierde.~~ **[x] Hecho** | C |
| 162 | ~~Al desconectarse desaparecen los jugadores y hay spam de errores.~~ **[x] Hecho** — `OfflineMultiplayerPeer` en vez de null y sin anunciar el roster vacío. | C |
| 163 | ~~Salto al cruzar el borde de la caja de carga.~~ **[x] Hecho** — histéresis de 0,4 m (`carries(point, margin)`). | C |
| 164 | ~~Ragdoll dentro del camión sale volando.~~ **[x] Hecho** — hereda la velocidad del camión. | C |
| 165 | ~~RPCs sin validar.~~ **[x] Hecho** — golpe de caja solo del host, interacción remota con chequeo de alcance, foto solo cerca de la casa. | C |
| 166 | ~~Bonus de foto en casas salteadas.~~ **[x] Hecho** | C |
| 167 | ~~Verificación con probes (2 y 3 procesos): los sincronizadores del jugador y de las cajas se limitaban a peers listos recién en `_ready`, y tras un reinicio el host dejaba de verse moverse.~~ **[x] Hecho** — el filtro va en `_enter_tree` (jugador y caja); el jugador remoto sobre el camión del host se ubica en el tick de física. | A |
| 168 | ~~En el host, el jugador que viaja atrás golpeaba las cajas sueltas en cada paso (se mueve entre pasos, no durante).~~ **[x] Hecho** — con el camión en marcha no choca con las cajas (`_on_foot_mask`); estacionado, sí. | A |
| 169 | ~~Se cae el host: la cámara saltaba a un asiento.~~ **[x] Hecho** — Godot borra igual a los jugadores creados por el host; el nivel conserva la vista con una cámara quieta (`_keep_view`). | C |
| 170 | ~~El borde de la explanada del depósito hace cabecear el camión a ~15 m/s y tira la carga suelta (visto en los probes).~~ **[x] Hecho** `abf72b8` — medido con `cazador-bugs`: no era el borde de la explanada sino una loma (`HillSegment`) o un túnel como primer tramo, apretados en la salida del depósito (rampa de ~27 %), más el CCD del camión, que frenaba su posición y dejaba que la carga lo atravesara. `route.gd` `_plan_pick` ya no pone loma ni túnel primero, y el camión no usa `continuous_cd` (los paquetes sí). Test `test_start_yard`: saliendo a fondo no cabecea más de 20 °/s y una caja suelta sigue atrás. | B |
| 171 | ~~Guantes sueltos sobre el volante aunque no maneje nadie, y manos flotantes en las cámaras.~~ **[x] Hecho** (pedido del usuario, 2026-09-24) — fuera los guantes de `vehicle_presentation.gd`; la bocina mueve el punto de IK de la mano derecha del conductor (`test_driver_ik`). | A |


## Playtest del 2026-09-25 (172-177) — reporte directo del usuario, jugando solo de noche

| # | Tarea | Prio |
|---|---|---|
| 172 | ~~Ruido "como de interferencia" que obligaba a bajar los efectos.~~ **[x] Hecho** — el crujido de Peso creciente (diente de sierra con la frecuencia sorteada en cada muestra, bus de efectos) pasó a stick-slip; el viento y la ruta lejana dejaron de ser retumbo sub-grave (banda de ruido, loop con fundido cruzado). Detalle en `docs/audio-mundo.md`. Falta oírlo jugando. | A |
| 173 | ~~El camión anda a tirones y una caja atravesó el camión hacia adelante.~~ **[x] Hecho** — cajas, jugadores, objetos sueltos y ragdoll chocan con una cáscara cinemática que sigue al camión (`vehicle.gd` `_build_cargo_shell`, capa 7 `vehicle_shell`); el camión solo con el mundo. El tope trasero del estante es más grueso. Los conos de la obra eran postes estáticos: ahora se derriban (#176). `test_cargo_shell`. Queda: los derribables grandes (fardos, hasta 90 kg) todavía empujan al camión. | A |
| 174 | ~~Los grillos, molestos en bucle.~~ **[x] Hecho** — tres grillos con frases cortas y silencios de 3-7 s, 1,5 dB más bajos. | B |
| 175 | ~~Las montañas de noche, un negro sólido.~~ **[x] Hecho** — `shaders/horizon_mountains.gdshader`: facetas con luz fija, crestas más claras y pie fundido en el horizonte del cielo; de noche con luz de luna (0,32 en vez de 0,16). | B |
| 176 | ~~Conos y vallas raros y "sin texturas".~~ **[x] Hecho** — la causa de "sin texturas": `route_terrain.gd` `conform_geometry()` reconstruía cada malla con su primera superficie y sin materiales, así que la valla (y cualquier modelo importado de un tramo) salía en el gris por defecto; ahora conserva todas las superficies con su material (`test_route_terrain`). Además, de noche los faros iban a ×4 de energía y quemaban lo cercano (el tonemap lo lavaba a beige): ahora la energía tiene tope y el alcance sale de una caída más plana. La obra es un cierre de carril: diagonal de conos, vallas tabla con tabla con la lámpara encendida, diagonal de salida; los conos se derriban. | B |
| 177 | ~~El perro feo, con un ladrido raro y corriendo en el lugar.~~ **[x] Hecho** — Shiba Inu con esqueleto de Quaternius (CC0); marcha (quieto / paso / galope) y ritmo del clip según la velocidad real; ladrido "guau" con formantes, a intervalos al azar y a veces doble. Al rendirse vuelve hasta su casa (antes se quedaba en la banquina). | B |
| 178 | ~~El ruido sigue, más fuerte en la zona de carga del depósito: poner todos los sonidos en Opciones para encontrarlo.~~ **[x] Hecho** — "Sonidos del juego" en Opciones: cada sonido por quién lo toca, si suena, silenciar / solo, sonando con el juego en pausa (`sound_audit.gd`, `sound_check_panel.gd`, `test_sound_check`). Con eso el usuario lo encontró: **Depósito · Zumbido**. Era un sonido 3D con `unit_size` 30 colgado a 4 m sobre la zona de carga: debajo sonaba ~7 veces (+17 dB) más fuerte que el nivel medido, y el loop tenía un hueco cada 3 s. Ahora es un tono de sala parejo en todo el depósito (sin caída por distancia, `depot.gd`), rehecho sin hueco (`warehouse_hum`), a −42 dBFS. Igual molestaba: por pedido del usuario **se sacó** (`depot.gd` ya no tiene tono de sala; `test_depot` lo cuida). | A |
| 179 | ~~Menú principal saturado: diez botones iguales y el campo de IP a la vista.~~ **[x] Hecho** (pedido del usuario, 2026-09-25) — `main_menu.gd` en páginas dentro de la tarjeta: inicio con "¡JUGAR!", "Garaje" (Apariencia, Progreso, Récords) y una fila chica Opciones / Cómo jugar / Salir; "¡JUGAR!" lleva a Jugar solo, Endless, Crear sala y Unirse a una sala (la IP, con la ayuda de Steam). "Volver" y Esc suben un nivel. Tarjeta esmerilada: el arte desenfocado una vez al abrir (sin blur por cuadro) y recortado a la tarjeta por shader. `ui_theme.gd`: los botones se levantan 2 px al pasar el mouse y hacen el bip de escáner (`SynthAudio.scanner_beep`) al presionarlos. Descartado de la propuesta: fondo 3D animado, cambiar tipografías (Lilita One/Nunito ya son las redondeadas que pedía) y avatares de sala en el menú. `test_main_menu`. | B |
| 180 | ~~Los paquetes se salen del camión aunque las puertas traseras estén cerradas (playtest 2026-09-27, jugando solo: la caja quedó en la ruta y se arruinó toda la carga).~~ **[x] Hecho (2026-09-27)** — era el CCD de Jolt: viajando a bordo, la caja se barría desde el lugar del tick anterior contra la cáscara ya movida, o sea desde detrás del tope trasero del estante y de las puertas, y quedaba afuera (sonda por la ruta real: 23 escapes en 6 rutas antes, 0 después). Ahora `package.gd` y `cargo_clutter.gd` prenden `continuous_cd` solo cuando la caja está suelta o la tira un choque (`vehicle.gd` `needs_sweep()`). Las puertas abiertas siguen siendo la mecánica de olvidarse de cerrarlas. `test_cargo_shell`. Queda: el termo (8 cm) todavía puede atravesar una pared lateral en un choque violento con el camión girando. | A |
