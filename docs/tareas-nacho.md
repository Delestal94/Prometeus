# Tareas de Nacho — Vehículo, Ruta, Ambientación y Depósito

> Reescrita entera con el mismo formato que `docs/tareas-slatex.md`: las tareas 1-127 de la
> versión anterior están cerradas o reubicadas (ver "Qué pasó con la lista anterior" al final).
> Esta lista sigue los 9 pilares de producción y **solo tiene trabajo que Nacho puede terminar
> sin esperar a Slatex y sin playtesting**.
>
> División de dominios y zona compartida: `docs/colaboracion-equipo.md`.

## QA — bugs abiertos

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

### N-918 · `test_level_endless` falla a veces: "SegmentN's static boxes are merged as it spawns (1 left loose)" — C · `Opus 5.5 · medium` · Aviso: sí (`modules/render_budget/`, zona compartida) · **[x] rama `nacho/fix-main-endless-merged-name`**
Origen: construcción 2026-10-02 (CI rojo del PR #212, que no tocaba nada de esto; ~1 de cada 24 corridas en `main`
con la CPU cargada). Con `cazador-bugs`: dos causas juntas. (1) `streamer.set(&"segment_scripts", [Straight…])`
pasaba un `Array` sin tipo a la propiedad `Array[Script]`; Godot lo descarta sin avisar y la ruta salía con los 11
tipos (por eso la camioneta terminaba OFF_ROAD o STUCK tan seguido). Pasaba igual en `test_endless_multi_cargo.gd` y
`test_mud_segment.gd`. (2) Con un `MudSegment` en la ruta, `DressingBatcher.merge_segment_geometry()` crea dos
`MergedGeometry` (sombra prendida y apagada), y el segundo quedaba con el nombre `@MeshInstance3D@N`, que el test
contaba como pieza suelta. Ahora se agrega con `add_child(instance, true)` (queda `MergedGeometry2`), y los tres
tests pasan la lista tipada. `tests/data/route_golden.txt` regenerado: cambian solo 22 `hash=` de tramos (el nombre del nodo), ni posiciones ni conteos. El módulo prueba el caso en `test_render_budget` (`_test_segment_merge`). Aviso
`docs/avisos/2026-10-02-merged-geometry-name.md`.
  **[x] Hecho (2026-10-02, rama `nacho/fix-main-endless-merged-name`)**.

### N-917 · Aviso de Jolt "exceeded the maximum number of jobs" al cargar la entrega — C · `Opus 5.5 · medium` · Aviso: sí (`modules/route_gen/`, zona compartida) · **[x] rama `nacho/N-917-jolt-jobs`**
Origen: QA 2026-10-01. Escenario: `godot --path do-not-drop -- --autostart --mood=nublado_dia` (o cualquier clima), o
entrar a la entrega desde el menú; la consola muestra una vez `WARNING: Jolt Physics job system exceeded the maximum
number of jobs. This should not happen. Please report this.` No se repite cada frame ni rompe nada; no aparecía en la
corrida de la mañana (e033559), así que probablemente lo trajo el depósito que se arma por frames (#195, N-408b) o el
precalentado de shaders (#205, N-409), que agregan muchos cuerpos o colisiones en pocos frames. Con `cazador-bugs`
(confirmar qué PR y qué paso de la carga) y `constructor-mundo`. Hecho cuando: el escenario de QA pasa sin el aviso
(repartir la creación de cuerpos en más frames, o ajustar los límites de Jolt en `project.godot` si corresponde) y hay
un test que carga la entrega y falla con ese aviso (un `Logger` que cuente warnings de Jolt).
  **[x] Hecho (2026-10-01, rama `nacho/N-917-jolt-jobs`)** — con `cazador-bugs`: no era #195 ni #205 sino #191
  (`4140b19`, N-408): `TerrainField.build_async()` y `conform_all()` (`modules/route_gen/terrain_field.gd`) lanzaban
  su `add_group_task` con `tasks_needed = -1` y prioridad alta, que ocupa todo el `WorkerThreadPool` 1,5–3 s. Jolt
  corre sus jobs en ese pool y solo los libera cuando un hilo los ejecuta: se acumulaban ~24 por paso hasta agotar
  los 2048 fijos, y el paso de física esperaba en el hilo principal (cuadros de 0,4–1,8 s bajo la pantalla de
  carga; aparecía ~3 de cada 4 corridas). Los límites de Jolt de `project.godot` no influyen (el tope es de
  compilación). Arreglo: los dos grupos usan `TerrainField.worker_tasks()` = núcleos − 1 (mínimo 1). Test
  `test_jolt_job_budget` (un `Logger` cuenta el aviso durante una ruta por rebanadas con un cuerpo despierto, y
  `worker_tasks()` deja un hilo libre). Aviso `docs/avisos/2026-10-01-n917-terreno-deja-hilo-a-jolt.md`.


### S-908 · Nodos huérfanos de `package_salvage.gd` al liberar el nivel (heredada de Slatex) — B · `Opus 5.5 · medium` · Aviso: sí (`scripts/gameplay/package/package_salvage.gd`) · **[x] rama `nacho/S-908-salvage-orphans`**
Origen: QA 2026-10-01. Escenario: instanciar `level_endless.tscn`, `start_debug_delivery`, `reset_run` y
`level.free()`, repetido; `Node.print_orphan_nodes`. Cada nivel liberado deja ~50 huérfanos (`Stray Node:
RepairTape (MeshInstance3D)` y `Stray Node: ReplacementHen (Node3D)` con sus mallas hijas; 63 reinicios → 3150).
Causa probable (sin confirmar): `package_salvage.gd:25-59`, `_ready()` crea `tape_mesh` y `toy_mesh` y los cuelga con
`package.add_child.call_deferred(...)`; si el paquete se libera antes de que corra el diferido (nivel liberado en el
mismo frame) esos nodos nunca tienen padre y nadie los libera. Arreglo sugerido: liberarlos en `_exit_tree` /
`NOTIFICATION_PREDELETE` si no tienen padre, o crearlos sin dejarlos sueltos. Hecho cuando el escenario de QA pasa
sin el error y hay un test que lo fija: instanciar un nivel con paquetes, liberarlo y afirmar que
`Performance.OBJECT_ORPHAN_NODE_COUNT` vuelve al valor inicial.
- [x] ~~**S-908.1** Confirmar la causa y arreglar `package_salvage.gd`. Con `cazador-bugs` (confirmar) y
  `constructor-jugador`; tests `package`, `salvage`.~~
- [x] ~~**S-908.2** Test de huérfanos (conteo inicial = final tras liberar el nivel con paquetes, también liberando en el
  mismo frame). Con `escritor-tests`; tests `package`.~~
  **[x] Hecho (2026-10-01, rama `nacho/S-908-salvage-orphans`, #164)** — causa confirmada: `package.gd:207-209` crea el
  `PackageSalvage` y su `_ready()` (`package_salvage.gd:35` y `:62`) cuelga cinta y gallina con `call_deferred`; si el
  paquete se libera antes, quedan 5 nodos sin padre por paquete. El diferido pasa a ser un método propio
  (`_attach_meshes`, muere con el salvage) y `_notification(NOTIFICATION_PREDELETE)` libera los que sigan sin padre. `_build_point` no tenía el problema (agrega sincrónico). Test
  `test_package_salvage_orphans` (paquete liberado en su primer frame, después del diferido y diez a la vez; sin el
  arreglo da 5 huérfanos; además exige cero errores del motor con un `Logger`). Aviso
  `docs/avisos/2026-10-01-salvage-orphans.md`.

### N-238 · `request_gear_shift` sin `RpcGuard` y un test que se deja engañar por comentarios — A · `Opus 5.5 · xhigh` · Aviso: no · **[x] rama `nacho/N-238-gear-shift-guard`**
Origen: auditoría integral 2026-10-01, A-D.1 (P1). `request_gear_shift` en
`do-not-drop/scripts/gameplay/vehicle/vehicle.gd:558-568` no llama `RpcGuard.allow_request(self)`: solo
tiene un comentario TODO. `tests/test_rpc_guard.gd` busca el token como texto con los comentarios incluidos,
así que el TODO lo hace pasar. El comentario "protocol version 12" de `vehicle.gd:557` es falso (el 12 es
N-109; A-D.3). Hecho cuando `request_gear_shift` llama al guard, `test_rpc_guard` quita lo que sigue a `#`
antes de buscar el token y tiene un caso negativo (token solo en un comentario => falla), y el comentario
de versión dice la verdad. Si el cambio no toca firmas RPC no hace falta subir `PROTOCOL_VERSION` (solo se
agrega una llamada interna; subirla solo si cambia alguna firma o el orden de los RPC). Dominio: nacho
(`vehicle.gd`) y libre (`tests/`).
- [x] ~~**N-238.1** Sumar `RpcGuard.allow_request(self)` a `request_gear_shift` y corregir el comentario de
  `vehicle.gd:557`. Con `constructor-red`; tests `rpc_guard`, `vehicle`.~~
- [x] ~~**N-238.2** `test_rpc_guard.gd` quita los comentarios `#…` antes de buscar el token y suma el caso
  negativo (token solo en un comentario). Con `escritor-tests`, y después `auditor-red` sobre todo el diff;
  tests `rpc_guard`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-238-gear-shift-guard`, #159)** — `request_gear_shift` gasta el presupuesto
  del que lo manda (`RpcGuard.allow_request`, después de autoridad y dirección; el host conduciendo es llamada
  local y no gasta) y el comentario dice "Added with N-114" en vez de la versión 12. `test_rpc_guard` corta
  cada línea en su `#` (salvo dentro de un string) antes de buscar tokens, también en los helpers expandidos,
  con caso negativo y uno de `"#"` en un string (`_check_comments_ignored`). `PROTOCOL_VERSION` sin cambio
  (ni firma ni orden). `auditor-red`: sin BUG ni riesgo alto; ningún otro RPC pasaba por un comentario. Riesgos
  bajos que quedan: el presupuesto es compartido con bocina y demás (un cambio perdido se ve en el HUD y se
  reintenta; la marcha la replica el host) y los `"""` multilínea no llevan estado de comilla entre líneas.

### N-239 · ⏸ decide el usuario: CI sin run en los commits del auto-merge — A · `Opus 5.5 · xhigh` · Aviso: no
Origen: auditoría integral 2026-10-01, A-D.2 (P1). El auto-merge (`dependabot-auto-merge.yml` con
`GITHUB_TOKEN`) no dispara CI: 19 de 49 commits de `main` no tienen run. `construccion.md:14` y
`pc-build.md:13` miran `gh run list --branch main --limit 1` (el último run, no el de HEAD), así que una
rutina puede dar por verde un `main` que nadie probó. Opciones: (a) GitHub App o PAT como secret para el
auto-merge (los merges sí disparan CI; pide un secret); (b) workflow `schedule`/`workflow_run` que pruebe
HEAD de `main` cuando no tenga run; (c) solo cambiar las rutinas para consultar el run del SHA de HEAD
(`gh run list --commit <sha>`). Recomendación: (b)+(c), sin secretos; (a) si el usuario prefiere. Cambia CI y
rutinas, por eso espera decisión (issue `decide-usuario`). Hecho cuando (según la opción) un commit de
`main` hecho por el auto-merge termina con un run de CI verde o rojo, y las rutinas miran el run del SHA de
HEAD y tratan "sin run" como "no verificado".
- [ ] **N-239.0** ⏸ Decisión del usuario entre (a), (b)+(c) o (c) sola.
- [ ] **N-239.1** Implementar la opción elegida en `.github/workflows/` y `.claude/rutinas/construccion.md`
  / `pc-build.md`. Con la conversación principal; verificar con `gh run list --commit <sha>` sobre un commit
  de auto-merge.

### N-240 · Intermitente sin nombre en CI: anotar cada falla y cazarlo — A · `Opus 5.5 · high` · Aviso: no · **[x] rama `nacho/N-240-ci-fail-annotation`**
Origen: auditoría integral 2026-10-01, A-5.1 (P1). `main` quedó rojo en `8a51334` (run 36815889169, shard
2/4) y el mismo árbol salió verde en #143; el sospechoso es `test_mud_segment`, pero el log no dice cuál
falló. Hecho cuando `tools/run-tests.sh` emite, con `GITHUB_ACTIONS` definido, una línea
`::error title=FAIL <test>::<primera línea ERROR>` por cada falla (el resultado pase/falla no cambia, con un
test que lo comprueba) y el intermitente identificado por esa anotación tiene causa y arreglo con un test
que lo reproduce o 50 corridas seguidas en verde. El reintento automático en CI queda fuera (pregunta al
usuario). Dominio libre (`tools/`, `tests/`).
- [x] ~~**N-240.1** Anotación `::error` por falla en `tools/run-tests.sh`. Con la conversación principal;
  tests `run_tests` (o chequeo con un test de mentira) y `ejecutor-tests`.~~
- [x] ~~**N-240.2** Con el nombre que dé la anotación (primero `mud_segment`), identificar y arreglar el
  intermitente. Con `cazador-bugs`; tests `mud_segment` repetido.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-240-ci-fail-annotation`, #160)** — con `GITHUB_ACTIONS` definido,
  `run-tests.sh` emite `::error title=FAIL <test> (<motivo>)::<primera línea ERROR>` por falla (un cuelgue
  lleva su timeout como motivo; `%` escapado); pase/falla igual. `tools/test-run-tests.sh` lo comprueba con un
  Godot de mentira (falla, cuelgue, todo verde y sin `GITHUB_ACTIONS`) y CI lo corre en el job de lint. El
  intermitente no era `mud_segment`: el log del run 36815889169 dice `FAIL test_route_lookup_cache (timeout
  120s)`, después de terminar las 8 rutas y el streamer. Causa: el test tarda ~105 s (medido acá, solo o con
  otro test pesado al lado) contra el límite de 120 s de CI y no estaba en `SLOW_TESTS`. Arreglo: va a
  `SLOW_TESTS` (240 s y arranca primero). Juntar sus dos barridos completos en uno no ahorró tiempo (106 s) y
  cambiaba cómo se desempatan puntos equidistantes (float64 contra `Vector2` float32): se descartó.
### N-227 · El equipo cobra por las cajas que no entrega; el bono de tiempo nunca se paga — A · `Opus 5.5 · high` · Aviso: sí (`run_manager.gd`, zona compartida) · **[x] PR #108**
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
- [x] ~~**N-227.1** Test con una entrega real (no un diccionario inventado) que compruebe que `team_money` sube; arreglar los mocks de `render_hud.gd` y `render_store_shots.gd`. Con `constructor-progresion` y después `escritor-tests`; tests `crew_progression`.~~ **[x] Hecho (2026-09-30)** — rama `nacho/N-227-payout-test`: `test_crew_progression.gd` corre una entrega real por `RunManager` (una casa + una caja intacta a bordo, 130 s) y exige que `team_money` suba lo que paga `award_delivery`; mocks de `render_hud.gd` y `render_store_shots.gd` con valores alcanzables (`time_bonus` 0, score = (carga + puerta) × 1.2). Quedan `time_bonus: 20` inalcanzables en `test_run_relay.gd:55` y `test_host_gone_tally.gd:135`: barrerlos con N-227.2.
- [x] ~~**N-227.2** Implementar la fórmula decidida en `docs/decisiones/2026-09-30-preguntas-auditoria.md` (preguntas 2 y 3): billetera compartida; pago = `delivery_points` + `cargo_points`, sin multiplicador de caos; se borra el bono de tiempo (`PAR_SECONDS`, `time_bonus`, `lost_time_bonus`, la fila `HUD_SCORE_SPEED`) y "Cliente impaciente" acorta el plazo de la casa siguiente; reclamo por caja abollada determinista; precios de tienda ajustados para que una entrega completa promedio compre un ítem de precio medio. Barrer los `time_bonus: 20` de `test_run_relay.gd:55` y `test_host_gone_tally.gd:135`. Actualizar `cartas-y-eventos-de-ruta.md`, `economia-y-contramedidas.md` y `parametros-diseno.md` (incluida la fórmula real de Endless). Con `constructor-progresion`; tests `crew_progression`, `run_manager`, `route_event`.~~ **[x] Hecho (2026-09-30)** — rama `nacho/N-227-payout-formula`: pago = `delivery_points + cargo_points` (resultado `payout`, línea "Pago del equipo"); sin bono de tiempo; Cliente impaciente acorta un 15 % el plazo de la casa siguiente (`deadline_cut.gd`); reclamo abollado siempre; tienda x4 (160/140/120/100) y seguro 50; docs al día con la fórmula de Endless (no paga dinero). Aviso: `docs/avisos/2026-09-30-n227-pago-por-entrega.md`. Pendiente aparte: multas y premios de eventos/fauna (10..30) quedaron iguales.

### N-228 · El tope es 8 jugadores en todos lados — B · `Opus 5.5 · low` · Aviso: no
Origen: decisión del usuario 2026-09-30 (`docs/decisiones/2026-09-30-preguntas-auditoria.md`, pregunta 1). El
código ya dice 8 (`network_manager.gd:27`). Los prompts de los agentes, `definicion-proyecto.md`,
`requerimientos-tecnicos.md` y la descripción del repo ya se corrigieron el 2026-09-30.
- [x] ~~**N-228.1** Barrer el resto de `docs/` (y `docs/marketing/`) buscando "5 jugadores", "cinco", "4 pasajeros", "hasta 4" y equivalentes en inglés, y corregirlos a 8 (1 conduce, hasta 7 cargan). Con `documentador`.~~
  **[x] Hecho (2026-09-30, rama `nacho/N-228-eight-players`, )** — a 8 jugadores / 7 pasajeros: `README.md`, `requerimientos-tecnicos.md` (encabezado y asientos), `narrativa.md`, `parametros-diseno.md`, `direccion-visual.md` (escala y oclusión), `marketing/trailer.md` ("1-8 jugadores") y `analisis-competencia-backseat-rv.md`. Se dejaron como están las mediciones con un número fijo de jugadores (`investigacion-red.md` "4 jugadores", `bench_depot` "5 jugadores" del README, "Solo, 2 y 5 jugadores" de `jugabilidad-paquetes-rescate.md`), los datos de competidores y los registros fechados (auditorías, avisos, decisiones).
  Para N-228.2: `vehicle.tscn` tiene 10 puntos de ojo de asiento (3 por lado, centro y 3 en el portaequipaje) pero solo 4 `*PackageMount` (Left/RightSeat1-2): con 7 pasajeros, tres se quedan sin soporte de caja enfrente.
- [x] ~~**N-228.2** Verificar que el juego aguanta 8: asientos o lugares de carga para 7 pasajeros, filas del tablero de pedidos, colores del roster (se cruza con N-226) y el presupuesto de ancho de banda. Lo que falte, subtareas acá. Con `auditor-red` y `constructor-camion`.~~
  **[x] Hecho (2026-09-30, rama `nacho/N-228-eight-seats`, `ff635c0`)** — auditoría de código con `auditor-red`. Aguantan 8: transportes (ENet `max_players-1`, lobby de Steam, el 9º recibe "full"), slots de color del host (8), tablero de pedidos (`ROWS = 7`, `test_depot`), puntos de aparición del depósito (8), estantes (16 lugares), votación, espectador y asientos (conductor + 10 de pasajero; `seat_point.gd` no limita). Arreglado acá: `UnlockManager.MAX_DELIVERY_HOUSES` pasa de 4 a 7; con 4, ocho jugadores con perfil nuevo tenían 7 casas y solo 4 pedidos (3 casas "missed" seguras). Ahora un equipo completo libera Peso Creciente y Líquido para tener 8 cajas; `test_locked_traps` lo exige con `MAX_PLAYERS`. Lo que falta, abajo.
- [x] **N-228.3** Paleta de 8 colores: hoy hay 5 (`player.gd:43-45`, `hud_results.gd:8-10`, `crew_progression.gd:15-18`, 5 tonos de voz en `synth_audio_scenes.gd:318`, `strings_ui.csv:661-665`), así que los slots 5-7 repiten color. 8 colores distinguibles (también con daltonismo), claves y nombres traducidos y 8 tonos; va junto con N-226.2 (leer `color_slot()` en vez del `peer_id`). Test: `PLAYER_COLORS.size() >= NetworkManager.MAX_PLAYERS` y colores distintos. Con `constructor-progresion` y `constructor-ui`. Aviso: sí (`player.gd`, `scripts/ui/` de Slatex).
  **[x] Hecho (2026-10-01, rama `nacho/N-228-eight-colors`, #148)** — `Player.PLAYER_COLORS` con 8 (blanco hielo, cobalto, turquesa en 5-7; los 5 primeros intactos), claves/nombres `UI_COLOR_*` y 8 tonos de voz; `hud_results.gd` lee la misma paleta. Test: `test_player_colors` (tamaño, distancia Lab también con deuteranopía/protanopía, nombres es/en, tonos). Aviso: `avisos/2026-10-01-n228-paleta-ocho.md`.
- [x] ~~**N-228.4** Séptimo anclaje de caja: `vehicle.tscn` tiene 6 `PackageMount` (4 de asiento + 2 de estante) para hasta 7 cajas, y `LeftSeat3`, `CenterSeat` y `RightSeat3` no cuidan ninguna (sin `required_mount_path` ni `tend_mount_paths`). Sumar un anclaje (frente a un asiento 3 o en el piso central) y un test que cuente `package_mount >= MAX_PLAYERS - 1`. Con `constructor-camion`, después `auditor-red`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-228-seventh-mount`, #139)** — anclaje `RightSeat3PackageMount` en el piso contra la pared derecha (0.5, 0.58, 1.82); `RightSeat3` es su dueño y `LeftSeat3`/`CenterSeat` lo cuidan: los 10 asientos de pasajero cuidan algún anclaje. `PROTOCOL_VERSION` 17. Con `auditor-red`: arreglado que el último en sentarse frente a un anclaje compartido le sacaba el cuidado al anterior (`seat_tending.gd`: el que cuida se queda la caja salvo que llegue el dueño; al levantarse o caerse, la hereda otro sentado frente al anclaje), el conductor fuera del reparto, la caja en brazos al sentarse, `tend_package` tardío estando de pie y dos regazos reservando el mismo anclaje. El evento parásito elige cajas en anclajes con asiento dueño. Tests `test_multi_cargo`, `test_reference_truck`, `test_seat_tending` (nuevo), `test_route_events`. Aviso `docs/avisos/2026-10-01-n228-septimo-anclaje.md`.
- [x] ~~**N-228.8** Restos de bajo riesgo de N-228.4 (`auditor-red`): (a) si alguien parado saca la caja del anclaje de un tender sentado y la guarda en otro, el sentado la sigue cuidando desde un asiento que no la mira: en `store()` del mount, si el tender no `looks_at_mount`, `set_tender(0)` + `SeatTending.hand_over` (no se limpia en `take_by` porque rompe devolverla al mismo anclaje); (b) `_reserved` (`seat_point.gd`) decide "sentado" con `seat_node_path` replicado: usar el `occupant` de los asientos en el host; (c) una caja en el regazo de un vecino deja a `RightSeat3` sin poder sentarse con las manos vacías. Origen: construcción 2026-10-01. Con `constructor-jugador`, después `auditor-red`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-228-tending-leftovers`, #142)** — `SeatTending.on_stored()` (lo llama `store()` del anclaje, host): si el que cuida no está sentado frente al anclaje nuevo, deja de cuidarla (se le avisa con `tend_package` vacío) y la hereda otro sentado frente a ese anclaje; `_reserved` decide "sentado" con el `occupant` de los asientos en el host (en el cliente, el `seat_node_path` replicado); un asiento dueño con su anclaje vacío pero reservado por el regazo de un vecino deja sentarse con las manos vacías (sin sacarle la caja al vecino) y rechaza a quien trae otra caja. Con `auditor-red`: `lap_mount_path` replicado en el paquete (el cliente también ve la reserva del regazo), `request_lap_toggle` decide "sentado" con `SeatTending.is_seated`, y una caja guardada sin cuidador la toma quien esté sentado frente al anclaje. `PROTOCOL_VERSION` 18. Test `test_seat_tending`. Aviso `docs/avisos/2026-10-01-n228-cuidado-restos.md`.
- [x] ~~**N-228.5** Ancho de banda con 8: `test_net_bandwidth_budget.gd:11,22` calcula con `CREW = 4`; con 8 y 14 cajas da ~124 KB/s por cliente (97 % del tope de 128, sin encabezados) y ~7 Mbit/s de subida del host. Pasar `CREW` a `MAX_PLAYERS`, contar encabezados y la subida total del host; para bajar: cajas quietas o en estante sin envío, cajas a 30 Hz (`investigacion-red.md:27`), ruedas reconstruidas en el cliente en vez de 4 `Transform3D`. Con `constructor-red`, después `auditor-red`. Aviso: sí si toca `network_manager.gd`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-228-bandwidth-eight`, #144)** — `test_net_bandwidth_budget` usa `MAX_PLAYERS` y cuenta el encuadre de `SceneMultiplayer` (3 B por paquete, 8 por sincronizador, MTU 1350, 6 B de relay por pose de otro cliente) y 80 B de encabezado por datagrama; también la subida del host y la de cada cliente. Antes, con 8 y 14 cajas: 165 KB/s por cliente y 9,5 Mbit/s de subida del host. Arreglado (las dos hacían falta): el camión manda `net_wheel_heights` en vez de 4 `Transform3D` de rueda y el cliente reconstruye las ruedas (`vehicle.gd _pose_remote_wheels`, `PROTOCOL_VERSION` 19), y las cajas quietas mandan a 2 Hz (`NetRestThrottle`, módulo `net_pose_smoother`, nodo en `package.tscn`). Después: 117,7 KB/s estable (8 cajas moviéndose), 154 con todas moviéndose, 6,8 Mbit/s de subida (tope 8). Números en `investigacion-red.md` §4.2. Lo que más pesa ahora son las poses relayadas de los jugadores (N-217). Aviso: `docs/avisos/2026-10-01-n228-ancho-de-banda-ocho.md`.
- [x] ~~**N-228.6** UI con 8: captura del panel de pedidos del depósito con 7 pedidos (`depot_panel.gd:96`, 620 px sin scroll; si no entra, `ScrollContainer` o filas compactas) y un caso de 8 entradas en `test_crew_panel.gd` (hoy prueba 4). Con `constructor-ui` y `revisor-visual`. Aviso: sí (`scripts/ui/` de Slatex).~~
  **[x] Hecho (2026-10-01, rama `nacho/N-228-ui-eight`, #143)** — con 7 pedidos y las notas del Jefe la hoja medía ~799 px en 720: las filas van en un `ScrollContainer` "OrdersScroll" (`_fit_orders_scroll()`, alto hasta lo que deja la pantalla; Volver siempre visible); si no entra, el scroll es una parada de foco con su anillo (`draw_focus_border`) y arriba/abajo lo desplazan. Queda sin probar con mando real: el stick analógico puede desplazar varios pasos por empujón (igual que la navegación de foco del resto de los menús). El panel de tripulación con 8 entradas ya entraba (511 px). Tests `test_depot_panel.gd` (nuevo, 1280x720) y `test_crew_panel.gd` (8 entradas). Aviso `docs/avisos/2026-10-01-depot-orders-scroll-8-jugadores.md`.
- [x] ~~**N-228.7** Quien entra con la partida en curso aparece en el depósito aunque el camión esté en la ruta (`level_common.gd:181`): aparecer en un asiento libre del camión. También: al reconectarse, el slot de color puede cambiar (`network_manager.gd:162-164`), y la campaña se guarda por color. Con `constructor-jugador` y `constructor-red`.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-228-late-join-seat`, #149)** — `LateJoinSeating` (`scripts/gameplay/late_join_seating.gd`, host): con la partida en curso el que entra aparece en el `ExitPoint` de un asiento de pasajero libre y se sienta con `seat.interact()` tras el `spawn()` (prefiere el asiento con más cajas sin cuidador y nunca uno que le saque la caja a quien la cuida, `would_displace()`); sin asiento, de pie en el pasillo de la caja de carga. Antes del arranque y con resultados, en el depósito como siempre. Con `auditor-red`: sin reintentos (el orden spawn → `board_seat` lo garantiza Godot; un reintento por plazo desincronizaba al cliente lento). El punto de aparición viaja en espacio del camión (`vehicle_position` en los datos de spawn, `player_spawner.gd`), así el cliente que entra lo resuelve contra su propia copia del camión aunque su primera pose llegue después; el host le escribe `seat_node_path` a la copia en el acto. El slot de color al reconectarse ya lo conservaba N-221 (`test_network_rejoin`). `PROTOCOL_VERSION` 21 (el 20 es del PR #145). Test `test_late_join_seating` (nuevo). Aviso `docs/avisos/2026-10-01-n228-entrada-tardia-en-camion.md`. Falta probar el orden en red real con dos procesos (etapa de `net_pair`).

### ~~N-229 · El jugador torpe vuelve a tener casi-pérdidas~~ **[x] Hecho (2026-09-30)** — C · `Opus 5.5 · medium` · Aviso: no
Origen: decisión 2026-09-30 (`docs/decisiones/2026-09-30-preguntas-auditoria.md`, pregunta 9).
`tests/sim_data/balance_report.md:103` sigue en "REQUIERE AJUSTE": el objetivo de al menos una casi-pérdida
por entrega para el perfil torpe se mantiene.
- [x] ~~**N-229.1** Ajustar las trampas que no llegan al objetivo con `sim_trap_balance` hasta que el informe diga OK, sin romper los demás perfiles. Con `pulidor-jugabilidad`.~~ **[x] Hecho (2026-09-30)** — rama `nacho/N-229-clumsy-near-misses` (#117): Frágil `impact_damage_heavy` 35 → 36 (dos baches sin amortiguar y uno amortiguado dejan 24,4 en vez de 26,5); casi-pérdidas del torpe en Frágil 0,8 → 37,6 %, por viaje 0,73 → 1,10, reporte **CUMPLE**; pérdidas de todos los perfiles sin cambio. Ruidoso: una caja rescatada tras tocar el máximo de agitación cuenta como casi-pérdida en el arnés (decisión delegada, pregunta 9); torpe 0 → 51,2 %, por viaje → **1,61**. Test `test_sim_near_miss.gd`.

### N-237 · El tutorial de cuidado se dibuja encima de Opciones — B · `Opus 5.5 · low` · Aviso: sí (`player_cargo_care.gd`, archivos de Slatex) · **[x] rama `nacho/fix-tutorial-over-options` (#128)**
Origen: captura con GPU 2026-09-30. Con Opciones abierta, la tarjeta "Cómo cuidar la carga" (`care_practice.gd`) se
veía entera, sin oscurecer, a la derecha del panel. Causa: la tarjeta de cuidado y la de práctica viven en un
`CanvasLayer` propio (`player_cargo_care.gd`) con `layer = 7`, y el HUD (Opciones, pausa, resultados, depósito,
tripulación) es el `CanvasLayer` 1: todo lo del HUD quedaba por debajo. La guarda del mouse capturado lo tapaba
casi siempre, pero no la práctica en el cuadro en que el jugador recaptura el mouse.
- [x] ~~**N-237.1** Bajar la capa de las tarjetas de cuidado/práctica a `CARD_LAYER = 0` (debajo del HUD) y cubrirlo con `test_modal_layers.gd`. Tests `modal_layers`, `options`, `tutorial`, `hud`.~~ **[x] Hecho (2026-09-30)**.

### N-235 · Una caída sucia se nota a los 45 s — C · `Opus 5.5 · high` · Aviso: sí (`network_manager.gd`, zona compartida)
Origen: construcción 2026-09-30 (arreglo del trío de red en main, `auditor-red`). Para que el que se une no
se corte mientras carga el nivel (bloquea el poll de ENet 18-34 s en CI), el timeout de ENet quedó fijo en
45 s toda la sesión: si un jugador crashea, su caja sigue "sostenida", el volante ocupado y su voz activa
hasta 45 s; si crashea el anfitrión, los demás ven "anfitrión perdido" a los 45 s.
- [x] ~~**N-235.1** Bajar el timeout de ENet (MIN = MAX ≈ 20 s) una vez admitido el peer (host en
  `_on_peer_connected`, cliente tras `complete_auth`) y volver a 45 s en `begin_restart` / `_remote_restart`
  antes de recargar. `test_connection_errors` ya exige MIN == MAX y MAX ≥ handshake. Con `constructor-red`
  y después `auditor-red`; va después de N-231 (kit de red), que mueve `network_manager.gd`.~~
  **[x] Hecho (2026-09-30)** — rama `ccr-7ed3ad6f-aszdmn`: en `NetSession` (módulo), 20 s
  (`ENET_PEER_TIMEOUT_SESSION_MSEC`, MIN = MAX) desde que el host admite al que se une y 45 s mientras
  alguien puede estar cargando. Como la recarga del host bloquea su poll, los clientes se enteran antes:
  RPC nuevo `_host_load_timeout(bool)` (reliable, host → clientes, con `flush`), que manda
  `announce_restart()` (nuevo; `restart_delivery()` lo llama antes del fundido, así ENet puede reenviarlo;
  `begin_restart()` anuncia solo si nadie lo hizo). El host baja a cada cliente a 20 s con su último
  `_report_level_ready` pendiente, pasados `settle_delay_seconds` (3 s) y revalidando al vencer
  (`_reloads_owed`: un reporte viejo no baja nada ni cuenta al cliente listo). `_auth_failed` olvida el
  timeout del joiner. Hallazgos de `auditor-red` resueltos. `PROTOCOL_VERSION` 13 (el 12 es de N-109). Tests:
  `test_net_session` (host y cliente reales por ENet en un proceso: 45 → 20 al admitir con margen, 20 → 45
  al reiniciar con o sin anuncio, reinicios seguidos, joiner de otra versión), `test_connection_errors`
  (valores; `restart_delivery()` anuncia antes del fundido con dos `NetworkManager` reales) y `net_pair`
  (20 s en las dos puntas). Aviso `docs/avisos/2026-09-30-n235-timeout-enet.md`.
- [x] ~~**N-235.2** `net_pair` / `net_trio` avisan si la carga del joiner pasa de 35 s (margen sobre los 45 s).~~
  **[x] Hecho (2026-09-30)** — rama `ccr-7ed3ad6f-aszdmn`: `NETLOG ... WARNING slow level load` en
  `net_pair.gd` / `net_trio.gd` (umbral = presupuesto de carga de `NetworkManager` − 10 s) y línea
  `WARNING:` (más `::warning::` en GitHub Actions) en `tools/run-net-pair.sh` / `run-net-trio.sh`; sigue
  siendo PASS.

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

### N-911 · ⏸ decide el usuario: origen y licencia de `mus_ingame_loop.ogg` — C · `Opus 5.5 · low` · Aviso: no
Origen: mantenimiento 2026-10-01. `do-not-drop/assets/audio/music/mus_ingame_loop.ogg` (la música de cada partida) no
está en `assets/audio/music/LICENCIA.md`; entró con la importación inicial del repo (cc12c0e, 2026-09-25), no sale de
`tools/audio/compose_music.py`; quizá derive de `art/audio/music1.m4a` (sin referencias ni procedencia). Ya lo marcó
la auditoría 2026-09-29 §5.10 sin tarea. Bloquea la declaración de IA y las licencias de Steam. Opciones: (a) el
usuario documenta origen y licencia en `LICENCIA.md` y en `art/ai-registro.md` si es IA; (b) reemplazarla por una pista
compuesta con `compose_music.py` (sesión de arte en la PC) y borrar `music1.m4a`. Recomendación: (b) si el origen no
es 100 % propio. Hecho cuando la pista figura en `LICENCIA.md` con origen y licencia (o fue reemplazada y
`music1.m4a` borrado).
- [ ] **N-911.1** Decidir (a) o (b). Lo decide el usuario.
- [ ] **N-911.2** Ejecutar la opción elegida. Con `disenador-audio` (b) o `documentador` (a).
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

### N-916 · ⏸ decide el usuario: fecha, Steam Direct, precio, idiomas y promesa de la página — A (decisión) · `Opus 5.5 · low` · Aviso: no · ⏸ M5
Origen: lanzamiento 2026-10 (`docs/marketing/estado-steam.md` §2 y §6). Cinco decisiones juntas porque se condicionan:
(1) fecha: Early Access 2027-01-22 sin Next Fest (A) o correrlo a 2027-03-12 para entrar al Next Fest 22-feb a 1-mar,
inscripción hasta 2027-01-10 (B; recomendado, verificar que Next Fest exige juego sin lanzar); (2) pagar Steam Direct
(USD 100, 30 días de espera) antes del 2026-10-16; (3) precio, objetivo $8-15, propuesta ≈9,99; (4) idiomas: no sumar
ninguno hasta cerrar N-211 fase 7b; (5) qué promete la página: sin voz hasta N-212.2 y "hasta 8 jugadores" solo tras
probarlo con gente real por Steam. Hecho cuando las cinco quedan escritas en `docs/decisiones/` y las fechas de
`docs/plan-desarrollo.md` coinciden.
- [ ] **N-916.1** Decidir las cinco. Lo decide el usuario (issue `decide-usuario`).
- [ ] **N-916.2** Aplicar: fechas en el plan, precio en S-904 y S-901. Con `documentador`.

## Orden de ataque (hitos)

| Hito | Objetivo | Tareas |
|---|---|---|
| **M1 — Cerrar lo que está a medias** | Nada del mundo que se comporte distinto en cada jugador ni que quede sin usar. | N-201, N-202, N-203, N-101, N-102, N-701, N-702 |
| **M2 — Ritmo y guía del jugador** | Una entrega de 2-5 minutos donde siempre se sabe adónde ir. | N-103, N-104, N-105, N-501, N-502, N-503 |
| **M3 — Base técnica** | Rendimiento medido en ventana real, red de 3+ jugadores probada, Endless con curvas. | N-204, N-205, N-206, N-207, N-208, N-209, N-801, N-802 |
| **M4 — Vida y variedad** | IA ambiental, audio del mundo, narrativa ambiental, detalles del camión. | N-106, N-107, N-301 a N-308, N-401 a N-405, N-601 a N-604 |
| **M5 — Preparación de lanzamiento** ⏸ | Builds, tienda, tráiler. N-901 pospuesta a la iteración de lanzamiento. | N-210, N-703, N-901 a N-906, N-911 ⏸, N-916 ⏸, N-912 ⏸, N-913 ⏸, N-914 ⏸, N-915 ⏸ (+ S-903 y S-907). Orden: N-916 y N-911 (decisiones), N-901, N-912, N-914, N-913, N-915 |
| **M6 — Mecánicas de la competencia** | Lo que Backseat Drivers y RV There Yet? hacen bien, adaptado a la carga. | N-704, N-505, N-213, N-214, N-212, N-109, N-406, N-108, N-110, N-311, N-113, N-111, N-112, N-114 (N-907 ⏸) |
| **M7 — Pedidos del usuario** | Correr, una meta que sea un lugar, un segundo cuerpo y el diario del día siguiente. | N-115, N-116, N-312, N-606 |
| **M8 — Auditoría 2026-09-29** | Lo que la auditoría encontró roto o flojo: cada pasajero con su propia acción, puntaje y red honestos, textos traducibles, menos trabajo por frame, repo liviano. Va **antes** que lo que quede de M6/M7. | N-919, N-705, N-117, N-805, N-118, N-119, N-222, N-313 ⏸, N-314, N-223, N-315, N-224, N-225, N-316, N-317, N-318, N-319, N-706, N-226, N-227, N-228, N-229, N-238, N-240, N-239 ⏸, N-321, N-908, N-909, N-910, N-320, N-922, N-920, N-921 |
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

### N-230 · Fases 0 y 1: reglas, chequeos y los siete módulos que ya eran genéricos — A · `Opus 5.5 · high` · Aviso: sí (`player_ragdoll.gd` de Slatex; `modules/` compartida) · **[x] rama `nacho/N-230-modulos-portables`**
Origen: análisis de acoplamiento del 2026-09-30 (191 scripts; 83 sin autoloads ni clases de otras
carpetas). Hecho: `do-not-drop/modules/{persistence,loc_text,synth_audio,net_pose_smoother,render_budget,
acoustics,ragdoll}` con `module.cfg` y test propio; `tools/check_modules.py` (job `lint`) y
`tools/portability-check.sh` (job `modules`: cada módulo solo en un proyecto vacío); `run-tests.sh`,
`lint.sh` y `list-tests.sh` incluyen `modules/`; adaptadores `LowpolyMaterials` → `DetailMaterials` y
`LegacyUserData` → `UserDataMigration`; `NetPoseSmoother` (ex `VehicleNetSmoother`) y `PlayerRagdoll`
reciben lo que antes buscaban solos. Docs: `docs/modulos.md`, `arquitectura.md` 1.1, `convenciones-godot.md`,
`CLAUDE.md`, aviso `docs/avisos/2026-09-30-modulos-portables.md`.

### N-231 · Fase 2: kit de red portable — A · `Opus 5.5 · xhigh` · Aviso: sí (`network_manager.gd`, `event_bus.gd`, zona compartida) · **[x] rama `nacho/N-231-net-session`**
Módulo `net_session` (`docs/modulos.md`): `NetSession` (Steam + ENet, lobby e invitaciones, handshake con
versión, peers listos, tolerancia a cargas de nivel, reinicio, `--net-sim`) con el estado del juego en hooks
virtuales (`_session_state()`, `_apply_session_state()`, `_failure_text()`...); `NetEventBus` (`relay()` y
`request()` cliente→host→todos con `request_cooldowns`); `SteamVoice`; `NetStats` + `NetStatsOverlay` base.
`NetworkManager`, `EventBus`, `ProximityVoice` y el overlay del juego **extienden** esas clases y conservan
su API (tests intactos). `PROTOCOL_VERSION` 11. Verificado con los tests de red, el par de red y
`portability-check`. Pendiente de una pasada de `auditor-red` en la rutina de revisión (regla: todo PR de
red la lleva).

### N-232 · Fase 3: interacción, cámara de asiento y ajustes — B · `Opus 5.5 · high` · Aviso: sí (`interaction/`, `game_settings.gd` de Slatex) · **[x] rama `nacho/N-232-interaction-camera-settings`**
`interaction` (`Interactable` con capa y grupo configurables; `SeatPoint` genérico con hooks para lo de
carga/rol, el asiento del juego lo extiende), `seat_camera` (`SeatCamera` con `add_shake()`/`kick_fov()`;
`first_person_camera.gd` lo extiende y conecta `EventBus`), `settings_store` (`SettingsStore` con
`saved_keys`, idioma, pantalla, buses, teclas, gamepad y hooks de migración; `GameSettings` lo extiende).
**`UiTheme` se queda en el juego** (es la marca: paleta, fuentes e íconos; se lleva copiando el archivo),
decisión en `docs/modulos.md`. Los tres módulos pasan `portability-check`; los tests del juego no cambian.

### N-233 · Fase 4: generación de ruta y clima — B · `Opus 5.5 · xhigh` · Aviso: sí (`game_settings.gd` de Slatex, una línea) · **[x] rama `nacho/N-233-route-gen`**
`route_gen` (`RouteSegment`, `SegmentStreamer` → `RouteStreamer` del juego lo extiende con su pool, la semilla, el cielo
y los cruces; `TerrainField` → `route_terrain.gd` lo extiende con el shader, las texturas y las cascadas; los seis tramos
construidos por código) y `world_mood` (`WorldMood` con la estación y la noche en `DetailMaterials`). `RoutePlanner`, los
tramos con assets, `RouteDresser`, `RouteSky` y `WindshieldRain` se quedan en el juego (decisión en `docs/modulos.md`).
Los dos módulos pasan `portability-check`; `test_route*`, `test_world_mood`, `test_level_endless` y `route_smoke_check`
sin cambios.

### N-234 · Fase 5: contrato de peligros, votación, perfil y registro — C · `Opus 5.5 · high` · Aviso: sí (`traps/` de Slatex) · **[x] rama `nacho/N-234-game-systems`**
`hazards` (`ITrapBehavior` + `TrapDefinition` con `translation_key` por `@export` en cada `.tres`, sin tabla fija),
`coop_vote` (`CoopVote`; `ShopVoteManager` lo extiende con las cartas y la billetera), `unlock_profile`
(`UnlockProfile` con reglas por umbral de estadísticas y migraciones; `UnlockManager` lo extiende), `run_log`
(`RunLog`; `RunTelemetry` lo extiende). Los cuatro pasan `portability-check`; `test_traps`, `test_shop_vote_manager`,
`test_unlock_manager`, `test_run_telemetry` sin cambios de comportamiento.

## M8 — Auditoría 2026-09-29

Pedido del usuario: arreglar todo lo que marcó la auditoría (`docs/auditorias/2026-09-29.md`), salvo
revisión humana de PRs ni agente revisor (no se quieren: la puerta son los checks obligatorios). Varias tocan
archivos de Slatex: aviso en `colaboracion-equipo.md` en el mismo PR, como siempre.

### N-705 · Puertas automáticas y repo limpio — A · `Opus 5.5 · medium` · Aviso: no · **[x]**
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

### N-117 · Una acción propia por trampa, en el mundo y no en la tarjeta — A · `Opus 5.5 · xhigh` · Aviso: sí (trampas, `player_seat_pose.gd`, `player_cargo_care.gd`, HUD de Slatex) · **[x]**
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

### N-226 · Color estable del jugador asignado por el anfitrión — B · `Opus 5.5 · xhigh` · Aviso: sí (`network_manager.gd` compartida; `player.gd` y `scripts/ui` de Slatex) · **[x] N-226.2 en la rama `nacho/N-221-rpc-guard-rejoin`**
Origen: auditoría integral 2026-09-30, A-4.3 (P1). Esfuerzo M. Mérito y cartas se identifican por un "color
estable" (`cartas-y-eventos-de-ruta.md:12-14`), pero el color sale de `PLAYER_COLOR_KEYS[posmod(peer_id, 5)]`
(`crew_progression.gd:134-135`, `player.gd:41-43`, `hud_results.gd:151`, `depot_panel.gd:274`). ENet da ids
aleatorios: el color cambia entre sesiones y con 5 jugadores ~96 % de las veces dos comparten color, así que
alguien que vuelve a la campaña puede heredar el mérito o la carta de otro. Hecho cuando el anfitrión asigna un
índice de color por orden de llegada, lo replica en el roster, la campaña se guarda por ese índice y un test con
ids aleatorios grandes verifica colores distintos y estables.
- [x] **N-226.1** ~~Índice de color asignado por el anfitrión y replicado en el roster. Con `constructor-red`; después `auditor-red`; tests `network_roster`.~~
  **[x] Hecho (2026-09-30)** — rama `nacho/N-226-host-color-index`: `ColorSlots` (`scripts/core/color_slots.gd`, lógica pura) y
  `NetworkManager.color_slot(peer_id)` (host 0, cada joiner el libre más bajo desde que empieza a autenticarse; fuera de
  sesión, el `posmod` de siempre). Viaja en el handshake (`"colors"`) y por el RPC `_sync_color_slots` en cada join, salida
  o auth fallida; señal `color_slots_changed`. `PROTOCOL_VERSION` 9 → 10. `auditor-red`: sin bugs; par y trío en verde.
- [x] **N-226.2** ~~Leer el color desde ese índice en `crew_progression.gd`, `player.gd`, `hud_results.gd` y `depot_panel.gd` (también `crew_panel.gd:152` y `hud_notices.gd:97`); guardar la campaña por índice. Con `constructor-progresion`; tests `crew_progression`.~~
  **[x] Hecho (2026-09-30)** — rama `ccr-7ed3ad6f-aszdmn`: helper único `PlayerColorSlot.slot(peer_id, tamaño_paleta)`
  (`scripts/core/player_color_slot.gd`) = `posmod(color_slot(id), paleta)` con el host fijo en 0 (solo y en sala el mismo
  color); lo usan `crew_progression.gd`, `player.gd`, `player_voice.gd`, `hud_results.gd`, `depot_panel.gd`,
  `crew_panel.gd` y `hud_notices.gd`, y los que dibujan escuchan `color_slots_changed`. Campaña `CAMPAIGN_VERSION` 2
  por slot (`"0"`..`"4"`), con migración del 1 (host "yellow" → slot 0) y sin crashear con archivos corruptos o de
  otra versión; quien se va se guarda con el slot que tenía. Slot liberado: lo hereda el siguiente, salvo que
  N-221 lo tenga reservado para el que se fue y puede volver. Test: `test_crew_progression.gd`. Aviso `2026-09-30-n226-color-por-indice.md`. Lo que quedaba (`_fail` sin emitir
  `color_slots_changed`, `net_trio.gd` con `slots=`) lo cerró N-221 (PR #125).
  Notas de `auditor-red` (N-226.1): `MAX_PLAYERS` es 8 y la paleta 5, así que se lee `posmod(color_slot(id), paleta.size())`;
  jugando solo el host da 1 y en sala 0 (decidir si solo se lee como 0); un índice liberado lo hereda el próximo que entra
  (mérito/carta por color dentro de la sesión: reservarlo mientras dure o documentarlo); los lectores escuchan también
  `color_slots_changed` y recorren el roster, no el mapa; `_fail` limpia el mapa sin emitir la señal. Falta una prueba
  multiproceso: `net_trio.gd` con `slots=0,1,2` iguales en los tres procesos.
- [x] **N-226.3** ~~Test con ids de peer aleatorios grandes. Con `escritor-tests`; tests `network_roster`.~~ **[x] Hecho (2026-09-30)** junto con N-226.1: `test_network_roster.gd` (ids > 1,8e9, 200 tripulaciones al azar, reutilizar el libre más bajo, mapas inválidos rechazados).

### N-313 · El ragdoll con el cuerpo real — B · `Opus 5.5 · high` · Aviso: sí (`player_ragdoll.gd`) · ⏸ personajes en pausa (S-311)
Origen de la pausa: auditoría integral 2026-09-30, A-102 (mismo trabajo que S-311.48; `constructor-jugador.md:43`: personajes y ragdoll no se tocan).
Hoy esconde al personaje y dibuja seis cápsulas turquesa (`player_ragdoll.gd:20,56-62`). Hecho cuando
el modelo real del jugador (con su color) es el que vuela y cae; lo mínimo, el modelo entero pegado al
torso físico; lo ideal, `PhysicalBoneSimulator3D`. Captura con `revisor-visual`.

### N-314 · Antialiasing y texturas 3D con mipmaps — B · `Opus 5.5 · medium` · Aviso: sí (`project.godot`) · **[x] PR #110** (la comparación MSAA en captura queda para `revisor-visual` con GPU en la sesión de arte)
- [x] MSAA por preset: Baja sin MSAA, Media 2×, Alta 4× (`WorldQuality`, PR #45). Falta compararlo en
  captura con `revisor-visual`.
- [x] ~~Las 35 texturas 3D sin compresión ni mipmaps (`compress/mode=0`, `mipmaps/generate=false`)
  se reimportan con VRAM + mipmaps desde el editor (el hook bloquea editar `.import` a mano).
  Necesita PC (editor de Godot con ventana; la toma la sesión de arte).~~
  **[x] Hecho (2026-09-30, sesión de arte, b0a16d1)** — `scripts/tools/texture_import_3d.gd` pone `compress/mode=2`
  (VRAM, S3TC/BPTC), mipmaps y `detect_3d` apagado en todo `assets/textures/{detail,terrain,cargo}` y
  `Godot --headless --import` reescribe los `.import` (decisión 7 de `docs/decisiones/2026-09-30-preguntas-auditoria.md`):
  14 texturas (10 de detalle, 3 de terreno, la etiqueta del courier). Las otras de la cuenta de 35 no eran 3D o no
  van: íconos y fondos de UI y el ícono de la app son 2D; los volcados de las cajas ya no se versionan (N-315); las 14
  caras (`textures/characters/faces/`) quedan como están por la pausa de personajes. Test nuevo `test_texture_import_3d`
  (toda textura de esas carpetas importada como VRAM con mipmaps). `revisor-visual` con GPU, antes/después en
  terreno, depósito, ruta de noche y cajas: sin artefactos de compresión, luminancia igual (±1), desaparece el grano
  parpadeante de tejados, estuco y pasto de lejos; el suelo a ángulo rasante queda algo más suave.

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

### N-315 · Cajas de 2048² triplicadas — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-315-cargo-textures-512`**
- [x] ~~Cada textura de caja está tres veces (fuente en `art/cargo/`, volcado del importador en
  `assets/models/cargo/` y embebida en el `.glb`): ~5 MB × 3 × 4. Regenerar a 512² con
  `art/tools/make_cargo_textures.py` (`modelador-blender`), sacar los volcados del repo e ignorarlos.
  Necesita PC (Blender; la toma la sesión de arte).~~
  **[x] Hecho (2026-09-30, sesión de arte)** — `make_cargo_textures.py` sigue dibujando a 2048 y guarda
  `art/cargo/tx_cargo_box_<v>_512.png` con LANCZOS (`cargo_layout.json`: mismos rectángulos UV); los 4 GLB
  reexportados con `build_cargo_packages.py -- boxes` (84 tris, nodos y bisagras iguales): 5,7/5,7/4,2/4,2 MB →
  316/319/243/241 KB. Los volcados `*_tx_*.png` del importador salen del repo y van a `.gitignore`: ~57 MB menos,
  VRAM de las cajas de ~10,7 a ~0,7 MiB. Test nuevo `test_cargo_box_textures` (atlas ≤ 512², 84 tris, solapas).
  `revisor-visual` con GPU: se leen logo, FRÁGIL, VIVO, PESADO y MANTENER VERTICAL de cerca y en el depósito;
  solo el texto chico secundario (sello, "RECICLABLE", "LEVANTAR ENTRE DOS" en la plana) queda como textura.
  Quien tenga el proyecto abierto: al bajar, Godot reimporta los GLB solo (si no, `--import`).

### N-224 · Menos despacho dinámico — C · `Opus 5.5 · high` · Aviso: sí (varios)
251 `.call(&"…")`, 233 `.get(&"…")` y 112 rutas `/root/`: un renombre rompe en runtime. Por archivo,
empezando por `crew_progression.gd` y `route_event_manager.gd`: referencias tipadas (`class_name`) o
dependencias por `setup()`. Una PR por archivo; el conteo baja en cada una.
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
- [ ] **N-224.4** El resto por conteo (`grep -c` de los patrones de `PATTERNS` en `scripts/`), un archivo por PR. Sumar
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

### N-225 · Partir los archivos que viven al borde del límite del lint — C · `Opus 5.5 · xhigh` · Aviso: sí
`synth_audio.gd` 1000, `package.gd` 999, `player.gd` 991, `run_manager.gd` 970, `reference_truck.gd`
932: están escritos contra `max-file-lines: 1000`, no partidos por responsabilidad. Orden:
`synth_audio` → `reference_truck` → `route.gd` → `package.gd`.
- [x] **N-225.1** `synth_audio.gd` **[x] Hecho (2026-09-30)** — rama `ccr-7ed3ad6f-aszdmn`: 999 → 249 líneas. Los
  generadores pasan a `synth_audio_vehicle.gd` (160), `synth_audio_world.gd` (253), `synth_audio_handling.gd` (107),
  `synth_audio_animals.gd` (82), `synth_audio_dsp.gd` (80: costura, normalizado, `Resonator`) y a
  `synth_audio_traps.gd` (32 → 187); `SynthAudio` queda como puerta con el caché y los mismos accesores y claves
  (los 43 streams salen byte por byte iguales). Sin `max-line-length` en el módulo (la baseline bajó 3).
  `test_synth_audio_golden.gd` compara los 43 con lo que daba el archivo único. Aviso:
  `docs/avisos/2026-09-30-n225-synth-audio-partido.md`.
- [x] **N-225.2** `reference_truck.gd` **[x] Hecho (2026-10-01)** — rama `nacho/N-225-reference-truck-split`: 976 → 394
  líneas. `ReferenceTruck` queda como orquestador (mismo orden en `_ready()`, API pública y `panel_lines`/`_paint_materials`);
  la cabina pasa a `reference_truck_cab.gd` (367: ventanas, volante, vestido, pedales), la carga a `reference_truck_cargo.gd`
  (162: herrajes, asientos rebatibles, rampa), las juntas a `reference_truck_panel_lines.gd` (133) y los helpers de malla y
  material a `reference_truck_props.gd` (72), todos tipados (sin `.call`/`.get` nuevos). `test_reference_truck_golden.gd`
  firma cada nodo que arma el camión (y los cambios tras puertas, rampa, pintura, retro y pedales) contra
  `tests/data/reference_truck_golden.txt`, generado con el archivo único. La baseline del lint bajó 1.
- [x] **N-225.3** `route.gd` **[x] Hecho (2026-10-01)** — rama `nacho/N-225-route-split`: 948 → 499 líneas. `route.gd`
  queda como cara pública (señales, exports, API de consultas, `_ready`, encadenado de tramos, meta, terreno, ambiente,
  callbacks de entrega y los arrays de estado que leen los tests); las casas y patios pasan a `route_houses.gd` (289),
  las consultas sobre el camino (punto más cercano, distancias acumuladas, hueco más ancho) a `route_path.gd` (170) y
  lo que se le dice al terreno (tramos, crestas, ríos, recorte del alcance del río, patio de salida) a
  `route_ground.gd` (159). Helpers por `preload`, que comparten los arrays de `route.gd` por referencia. Se borró
  `_mesh_base_offset` (sin llamadas). `test_route_golden.gd` firma tres rutas (nodos, casas, camino, terreno y ~600
  consultas cada una) contra `tests/data/route_golden.txt`, generado con el archivo único (`-- --write-golden`).
  La baseline del lint bajó. Aviso `docs/avisos/2026-10-01-n225-route-partido.md` (comentarios de `terrain_field.gd`).
- [x] **N-225.4** `package.gd` **[x] Hecho (2026-10-01)** — rama `nacho/N-225-package-split`: 995 → 661 líneas.
  Helpers estáticos sobre el estado del paquete, como `PackageRescue`: llevar, pasar, soltar, anclar y entregar a
  `package_handling.gd` (`PackageHandling`), la entrada del que cuida, el ayudante y el mérito a
  `package_tending.gd` (`PackageTending`), y los golpes (`_integrate_forces`, impactos, choques entre cajas y con
  jugadores, `_report_change`) a `package_impacts.gd` (`PackageImpacts`). Los 10 `@rpc` quedan en el paquete, con
  sus guardas y en el mismo orden; los métodos que usan otros archivos o los tests quedan como envoltorios. Usos
  por nombre: los mismos 9/0/3/1, repartidos entre los cuatro archivos (`test_dynamic_dispatch_budget.gd`).
  `test_package_split.gd` fija la tabla de RPC del original, los métodos que usa el resto y ≤ 700 líneas. Aviso
  `docs/avisos/2026-10-01-n225-package-partido.md`.
- [x] **N-225.5** Quedan `player.gd` (1000), `run_manager.gd` (1000) y `package_feedback.gd` (1000) en el borde.
  Origen: construcción 2026-10-01.
  **[x] `package_feedback.gd` (2026-10-01, rama `nacho/N-225-package-feedback-split`)** — 1000 → 444 líneas.
  Helpers estáticos que reciben el nodo (ahora `class_name PackageFeedback`): lo propio de cada trampa, las correas
  y el disfraz de evento a `package_trap_visuals.gd` (`PackageTrapVisuals`), cartón, contorno, material por
  paquete, abolladuras y etiqueta a `package_box_dressing.gd` (`PackageBoxDressing`), y rebote, temblor,
  deformación, etiqueta que se desprende y confeti a `package_box_motion.gd` (`PackageBoxMotion`). Todas las `var`,
  las constantes que leen otros archivos, `_ready`/`_process` (mismo orden) y los métodos usados afuera quedan en el
  nodo. `test_package_feedback_split.gd` fija ≤ 700 líneas, la API usada afuera, los nodos de cada trampa y el orden
  de hijos de `Box`. La baseline del lint bajó 1. Aviso `docs/avisos/2026-10-01-n225-package-feedback-partido.md`.
  **[x] `run_manager.gd` (2026-10-01, rama `nacho/N-225-run-manager-split`)** — 1000 → 669 líneas. Helpers estáticos
  sin `class_name`, cargados solo por `run_manager.gd` y sin nombrar autoloads: puntaje (`run_scoring.gd`), filas e
  historias del resultado (`run_results.gd`), plazos (`run_deadlines.gd`), registros de entrega y fotos
  (`run_deliveries.gd`), tabla local (`run_leaderboard.gd`) y la parte de escena del ingreso tardío
  (`run_session.gd`). Variables, señales, los cinco `@rpc` (mismo orden) y la API usada afuera quedan en el nodo;
  las constantes movidas se reexportan con el mismo nombre. `test_run_manager_split.gd` fija ≤ 700 líneas, la tabla
  de RPC, la API y tres corridas doradas por `finish_run` (entrega, fallida, infinito) calculadas con el original.
  Aviso `docs/avisos/2026-10-01-n225-run-manager-partido.md`. Queda `player.gd`.
  **[x] `player.gd` (2026-10-01, rama `nacho/N-225-player-split`)** — 1000 → 695 líneas. Helpers estáticos sin
  `class_name` que reciben al jugador: viaje con el camión y estado de red (`player_ride.gd`), movimiento a pie,
  mirada, balanceo, FOV y red de seguridad del piso (`player_movement.gd`), entrada (`player_input.gd`) y filtro de
  visibilidad para peers listos (`player_net_visibility.gd`). Los siete `@rpc` quedan en el nodo, mismo orden y
  guardas; constantes movidas reexportadas; 15 envoltorios privados sin usos de afuera se quitaron. Sin tocar cuerpo,
  ragdoll ni apariencia (S-311). `test_player_split.gd` fija ≤ 700 líneas, la tabla de RPC, la API usada afuera y
  corridas chicas doradas. La baseline del lint bajó 4. Aviso `docs/avisos/2026-10-01-n225-player-partido.md`.
  **N-225 completa.**

### N-316 · Capturas de tienda con gente y cajas — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-316-store-shots-crew`**
Las 5 capturas de `art/marketing/capturas/` no muestran una persona ni un paquete. Rehacerlas con
tripulación, cajas en las manos y algo saliendo mal, después de N-117 (`trailer_shot`, `revisor-visual`).
Necesita PC (capturas de tienda con luz real; la toma la sesión de arte).

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

### N-318 · Cartel A-3 quemado, granero negro y borde duro de la loma — C · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-318-hill-shadow`**
Origen: PC build 2026-09-30. Necesita PC (la toma la sesión de arte). Capturas de 390ee37: en `render_route_house.png` el
cartel amarillo "A-3" tiene un globo amarillo plano y sobreexpuesto, sin detalle, cortado por el borde de la imagen,
y el granero rojo queda negro. En `render_tunnel_from_road.png` y `render_tunnel_side.png` (día) la sombra de la
loma sobre la calzada es un borde diagonal muy duro; en `render_tunnel_side.png` se ve un hueco en la loma con
cielo/blanco sobre el portal (puede ser el hueco `_in_tunnel_bore()` de `route_terrain.gd`).
Hecho cuando (1) se verificó primero si el hueco es geometría rota: test en `test_route_terrain` que la loma no tiene
huecos sobre el portal fuera del túnel; (2) el globo del cartel tiene detalle (emisión bajada, sin píxeles
saturados en >5 % del globo, medido en la captura) y entra entero en el encuadre; (3) el granero recibe luz (luminancia
media medida); (4) la sombra de la loma con borde suave. Capturas antes/después con `revisor-visual`.
- [x] **N-318.1** ~~Diagnosticar el hueco de `render_tunnel_side.png` (geometría vs. luz) y corregirlo. Con `cazador-bugs`; tests `route_terrain`, `more_route_segments`.~~
  **[x] Hecho (2026-09-30, sesión de arte)** — era geometría: la loma sube 11,4 m en ~3 m detrás de la fachada y
  `_in_tunnel_bore()` sacaba la celda de 2 m entera, con su borde trasero por encima del Backfill del modelo (tapa 9,3 →
  6,95 m): una ventana de ~3,7 × 8 m bajo el terreno por la que se veía el cielo. `route_terrain.gd` `_tunnel_shelf()`
  deja la loma en un escalón a `crown + 0,75` justo detrás del portal (medidas del Backfill nombradas en
  `RailCrossingSegment.BACKFILL_*`). `test_route_terrain` `_check_tunnel_hill_gaps()` (0° y 33°): el borde del hueco
  daba 11,40 m y ahora 6,84 / 6,91 m (límite 6,95).
- [x] **N-318.2** ~~Cartel y granero (emisivo, luz, encuadre del script). Con `artista-shaders`; captura `render_route_dressing.gd`.~~
  **[x] Hecho (2026-09-30, sesión de arte)** — el globo pasa de unshaded a `shaders/house_balloon.gdshader` (lo iluminan
  sol y luna, brillo propio más fuerte arriba y de noche, borde fresnel, sin niebla) con nudo, y el plano de la casa lo
  encuadra entero; saturados < 5 % (noche 0,7-1,8 %, día 0,3-3,4 %). El granero salía negro de noche a contraluz porque
  su rojo puro no devuelve la luz fría: `LowpolyMaterials.LIFTED` lo aclara con el mismo tono (pared a contraluz de noche
  0,042 → 0,056, aplastados 25 % → 3 %; con luna 0,125 → 0,163; de día en sombra 0,290 → 0,313). Plano nuevo
  `render_route_barn.png` (seed 12 de día, `--seed=4` de noche). Tests `test_house_waiting_marker`, `test_baked_ao`.
- [x] **N-318.3** ~~Suavizar la sombra de la loma sobre la calzada. Con `constructor-mundo`.~~
  **[x] Hecho (2026-09-30, sesión de arte)** — el "borde diagonal duro" de `render_tunnel_from_road` no era sombra sino el
  borde asfalto/banquina (0,8 m de `smoothstep` en `route_terrain.gdshader`; el asfalto ahí está al sol, 0,40 como en
  `tunnel_side`), y la captura usaba un sol propio, no el del juego. `render_rail_tunnel.gd` ahora toma `Sun` y
  `WorldEnvironment` de `level_base.tscn` más `WorldMood`/`RouteSky`, y suma el plano `render_tunnel_shadow_edge.png`
  (sol bajo, asfalto al sol contra asfalto a la sombra de la loma, mide el ancho del borde; `--quality`, `--shadow-filter`,
  `--shadow-atlas`, `--shadow-opacity`). En Compatibility `shadow_blur` y `light_angular_distance` no hacen nada: el borde
  lo dan el filtro PCF y el atlas, que ahora fija `WorldQuality.apply_shadow_softness()` por nivel (Bajo/Medio/Alto: filtro
  2/3/4 y atlas 2048; antes 2 y 4096 en todos; a 1024 el borde salía escalonado). `Sun` de los dos niveles con
  `shadow_opacity` 0,85. Borde de la loma (vieja → Alto): cociente sombra/sol 0,82 → 0,95-0,99, sin escalones ni acné;
  sombras de contacto de casa, granero y carteles sin cambio visible. Test `test_world_quality` `_check_shadow_softness()`.
  Aviso: `docs/avisos/2026-09-30-n318-3-sun-shadows.md`.
  Intento 2026-09-30 (sesión de arte): no se llegó a hacer (el agente se cortó). Pista: `render_rail_tunnel.gd` arma
  un `DirectionalLight3D` pelado; el sol del juego (`level_base.tscn`) ya tiene `shadow_blur = 1,6` y
  `directional_shadow_blend_splits`. Primero comprobar si el borde duro es solo de la captura.

### N-319 · Depósito de nivel profesional (rediseño en iteraciones) — A · `Opus 5.5 · xhigh` · Aviso: sí (`level_base.tscn` compartida si tocás la niebla) · **[x] ramas `nacho/N-319-depot-redesign` y `nacho/N-319-depot-finish` (#145 y el cierre)**
Origen: pedido del usuario 2026-09-30 ("el galpón es muy genérico; que quede como el lobby de un juego profesional:
distribución de espacios, áreas importantes, modelos genéricos"). El plan, el diagnóstico de la línea de base, la planta
objetivo y el registro de cada iteración están en `docs/deposito-rediseno.md`; capturas de cada iteración en
`D:/tmp/depot_review/iterN/` (fuera del repo). Necesita PC con GPU para las capturas y para los modelos (iteración 2).
Restricciones (no se rompen): el juego no cambia (8 spawns, `TRUCK_BAY`, `TRUCK_CLEAR_Z`, portón, códigos y slots de
estante, `DepotStation` con sus `station_id`, espejo, radio, pizarra de campaña); todo lo estático por `DepotKit`;
`bench_depot` no empeora más de ~10 %; los cuerpos de los operarios son de Slatex (solo se mueven).
Hecho cuando (1) adentro no hay velo lechoso: la luz marca el foco (camión, pizarra, estantes) y hay zonas en penumbra;
(2) cada zona se lee por forma, luz y color antes que por carteles (pañol en jaula, taller en box, vestuario en cuarto,
oficina en entrepiso con escalera), con un cartel chico por zona sobre la zona; (3) el recorrido spawn → pizarra →
estantes → camión se sigue por las sendas verdes y el carril amarillo, con cruces cebra; (4) el espacio tiene capa de
oficio (matafuegos, tableros, jaulas, bolardos, carteles chicos) y modelos propios en vez de primitivas; (5) `test_depot`,
`test_start_yard`, `test_depot_campaign_board`, `test_depot_mirror`, `test_depot_zones` y `bench_depot` verdes; (6) la
crítica de `director-arte` sobre las capturas finales ya no dice "genérico".
- [x] **N-319.1** ~~Iteración 1 — luz y atmósfera, planta por zonas, sendas y señalética (con `constructor-mundo`).~~
  **[x] Hecho (2026-09-30, rama `nacho/N-319-depot-redesign`)** — sin niebla adentro (`DepotAtmosphere`: el `Environment`
  del nivel se mezcla bajo el techo y vuelve al salir), ambiente más bajo, spots con sombra sobre camión, estantes y empaque
  (presupuesto por nivel en `WorldQuality`: Baja 0, Media 1, Alta 3), spot cálido sobre la pizarra, pozos de luz bajo
  las campanas, haces por los tragaluces, piso gris medio con juntas y desgaste, paredes en capas. Planta: isla de control
  con la pizarra de 4,4 m, bahía oscura, pañol en jaula al frente a la izquierda, taller con media pared, vestuario con
  tabiques, oficina en entrepiso con escalera que se sube (`depot_zones.gd`); sendas verdes, carril del autoelevador y
  cuatro cruces cebra (`depot_circulation.gd`); carteles de zona un 15 % más chicos sobre su zona. `bench_depot` sin
  cambio; GPU con sombras apagadas +2-11 % de llamadas de dibujo, con las de Alta +40-90 % adentro. Tests `test_depot_zones`
  (nuevo), `test_depot` (umbrales de carteles/flechas a propósito), `test_render_budget`. Qué queda para la 2 en el
  registro de `docs/deposito-rediseno.md`; aviso `docs/avisos/2026-09-30-n319-deposito.md`.
- [x] **N-319.2** Iteración 2 — kit de modelos nuevos en Blender (`assets/tools/build_depot_props.py`) y reemplazo de las
  primitivas de `DepotKit` (`modelador-blender`, después `constructor-mundo`). Necesita PC.
  **[x] Modelos hechos (2026-09-30, rama `nacho/N-319-depot-props`)** — 40 GLB `sm_env_depot_*` nuevos en
  `models/environment/depot/` (grupos `ceiling dispatch bay logistics office cage safety breakroom workshop` del script),
  más el atlas de 12 pictogramas y la malla de rombos en `assets/textures/depot/`. Lista, tris y pivotes en
  `docs/inventario-assets.md` y `assets/README.md`.
  **[x] Pasada de luz y pintura + kit conectado (2026-10-01, rama `nacho/N-319-depot-finish`)** — el interior con luz propia
  casi fija (`DepotAtmosphere`: ambiente fijo 0,25 al 80 %, sin aporte del cielo, sombras del sol a 1,0 bajo el techo;
  `SunShield` de losas solo-sombra), haces de tragaluz en dos ejes por clima, vidrio celeste con emisión por clima, ventanas
  con marcos del kit, techo gris y cerchas INK, sendas 1 m verde apagado con bordes gastados, contorno discontinuo con
  estarcido para la reunión, carteles "etiqueta de envío" con pictograma del atlas. Kit conectado: campanas de la bahía,
  tubos lineales, conductos y bandeja, protecciones de columna, bolardos, topes y calzas, mesa del despachante, escalera,
  barandas, persianas, malla y ventanilla del pañol, semáforo del portón (sigue al portón), compresor, banco con morsa,
  elevador de tijera, cocinita, heladera, dispensador, reciclaje; el centro del galpón (jaulas rodantes, pallet filmado,
  mesa de clasificación, flat-packs, escalera de ruedas) y la pared izquierda z 9-12 (`depot_props.gd`). Lotes de
  `DepotKit` 170 → 184 (tope ~190); `bench_depot` sin cambio. Detalle en `docs/deposito-rediseno.md`.
- [x] **N-319.3** Iteración 3 — estaciones a fondo (pañol, taller, vestuario/descanso, isla de control, oficina) y capa de
  oficio (`constructor-mundo`).
- [x] **N-319.4** ~~Iteración 4 — pulido con la crítica de `director-arte`: color, desgaste, detalle, lo que falte.~~
  **[x] Hecho junto con la 3 (2026-10-01, rama `nacho/N-319-depot-finish`)** — color neutro cálido, oficina del Jefe con
  ventanal cálido, pictogramas de zona (celdas 12-15 del atlas), taller con media pared opaca y tableros del kit, isla con
  lámpara y corcho, pañol sin violeta, descanso con lockers entreabiertos, sombras de contacto en un lote, desgaste en un lote,
  polvo en los haces, portón de recepción y mural del fondo, flechas solo en bifurcaciones, nube y línea de salida de afuera,
  tubo parpadeante bajo 3 Hz. Lotes 182, 7 luces. Mezclado en el #145.
- [x] **N-319.5** ~~Cierre: crítica final sobre las capturas y los textos que el arte dejó vacíos.~~
  **[x] Hecho (2026-10-01, rama `nacho/N-319-depot-finish`)** — la crítica sobre `D:/tmp/depot_review/iter5/` ya no dice
  "genérico" (cada zona se lee por forma, luz y color; ver "Cierre" en `docs/deposito-rediseno.md`). Textos: "COLORES DEL CAMIÓN"
  en claro sobre la franja oscura del tablero de muestras (antes INK sobre INK, invisible), palabra bajo los cinco pictogramas de
  seguridad (`WORLD_DEPOT_SAFETY_*`), título de "NUESTRAS ENTREGAS" sobre su franja. `test_depot_zones` ampliado; `bench_depot` sin
  cambio. Detalles menores que quedan, sin tarea, en el registro.

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

### N-219 · Pico de física al generar cada tramo de Endless — B · `Opus 5.5 · high` · Aviso: no

La auditoría del 2026-09-29 midió que, al generarse un tramo, `TIME_PHYSICS_PROCESS` sube de ~3 ms a
~24 ms durante decenas de frames (el límite a 60 Hz es 16,7 ms). Se midió antes del merge del PR #35, que
no toca la física.
- [x] Reproducirlo con ventana real y ver quién gasta: los `StaticBody3D` y shapes del tramo, el terreno,
  los scripts con `_physics_process` o el CCD. **[x] Hecho (2026-09-30, rama `nacho/N-219-endless-physics-spike`)** —
  reproducido headless (`bench_drive.gd --endless --cpu-only`, semilla 4242, 90 s): pico de 103 ms por tick. No eran
  los shapes ni el terreno (Endless no tiene terreno; un tramo son 7-105 nodos y pocas cajas): era el propio
  `RouteStreamer._physics_process` armando el tramo. Puente 35-93 ms, túnel 22-28 ms, obras 18 ms, resto < 3 ms.
  Causas: `RouteSegment._model()` hacía `load()` del `.glb` por cada riel, poste y módulo (~40 lecturas de disco por
  puente; el `PackedScene` se liberaba al salir de `_model`), el primer puente sintetizaba el loop del río
  (`SynthAudio.river_flow_loop()`, ~55 ms) y el `DressingBatcher` (5-11 ms) corría en el mismo tick que la
  construcción. Con ventana real / GPU sin medir: lo que queda es la subida de mallas al renderer.
- [x] Arreglar: armar el tramo repartido en varios frames, usar menos shapes o shapes más simples, o
  generarlo antes y más lejos. **[x] Hecho** — `RouteSegment._scene()` guarda cada `PackedScene`;
  `RouteStreamer.WARM_MODELS` y el loop del río se cargan al armar el nivel; `SegmentStreamer` une la geometría un
  tick después de construir el tramo (uno por tick, `flush_batches()` en `start()`). Pico por tick 103 -> 10-13 ms
  (1 corrida de 5 llegó a 21 ms y 1 a 127 ms por PC ocupada, sin relación con un spawn); tick promedio sin cambio
  (1,0 ms). Detalle en `docs/rendimiento-pc.md`.
- [x] Test: el costo de física tras un spawn vuelve a la base en pocos frames. **[x] Hecho** —
  `tests/test_endless_physics_spike.gd` (modelos y loop calientes, tramo pesado < 30 ms, construir y unir nunca en el
  mismo tick, cola vacía a los 3 ticks) y ampliación de `modules/route_gen/tests/test_route_gen.gd`.

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
### N-920 · Endless: parar no debe terminar la partida si no hay conductor acelerando — A · `Opus 5.5 · high` · Aviso: no · M8
Origen: auditoría integral 2026-10-02, A-1.1 (P1). `level_endless.gd:86-97` cuenta como atascado cualquier velocidad
< 0,3 m/s durante más de 6 s y solo exceptúa el barro y la bahía de servicio. La regla de la entrega
(`level_base.gd:262-282`, S-203) exige además conductor sentado y acelerador apretado, y excluye el depósito y las
casas. El comentario de `level_endless.gd:28-30` ("no hay razón para parar en endless") ya no es cierto. Casos que hoy
cortan la partida: el arranque en el depósito con el camión quieto (`level_common.gd:404-408`), el rescate de una caja
caída (ventana de 30 s), la reparación que exige detenerse y el relevo de conductor (si se baja, el camión se congela,
`vehicle.gd:499`). Los bots de QA y `pc-build` no paran nunca, así que no lo ven.
**Supuesto (conservador):** parar sin acelerar no termina la partida (como S-203); encajado con el acelerador apretado
sí. Pregunta de diseño abierta, para el usuario: ¿parar para rescatar o reparar debe costar algo (distancia o tiempo)?
No se implementa ningún costo hasta que responda.
Hecho cuando un test de Endless prueba que 6+ s quieto sin acelerar (depósito, rescate, relevo de conductor) no termina
la partida y que 6+ s encajado con acelerador sí, y `test_level_endless` / `test_stuck_detection` pasan sin dar por
buena una partida cortada por "atascado" sin acelerador.
- [ ] **N-920.1** Llevar `_should_count_as_stuck()` de `level_base.gd` a `level_common.gd` con un gancho por modo; Endless
  la usa sumando el depósito y actualiza el comentario de `level_endless.gd:28-30`. Con `constructor-tramos`; tests
  `stuck_detection`, `level_endless`.
- [ ] **N-920.2** Casos Endless en `test_stuck_detection.gd` y corregir `test_level_endless.gd:49-61`. Con
  `escritor-tests`; tests `stuck_detection`, `level_endless`.

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

### N-922 · Auditar la red de N-218 (#239) y arreglar el número de protocolo — A · `Opus 5.5 · xhigh` · Aviso: sí (`network_manager.gd`, zona compartida) · M8
Origen: auditoría integral 2026-10-02, A-D.1 y A-D.2 (P1) y los dos puntos "para auditor-red" de los P3. #239 (N-218,
commit `c760998`) cambia la autoridad del camión, la firma de `submit_driver_input` (`vehicle.gd:610`) y 6 propiedades
del sincronizador de `vehicle.tscn`, y entró sin pasar por `auditor-red`; su cuerpo lista "Riesgos para auditor-red" que
nadie corrió (`construccion.md:98,106`). Además, `ff31ad5e` subía el protocolo a 25, pero el merge `27390a2c` se quedó
con el lado de main: hoy es 26 (`network_manager.gd:61`) y la línea 55 sigue diciendo "25: reserved for N-218". Las
builds de `b68207e`..`7496de3` llevan 26 sin N-218 y pueden desincronizarse en silencio.
Fuera de alcance: hacer de `auditor-red` una compuerta dura del auto-merge (cambia CI y rutinas; decide el usuario).
Hecho cuando hay un informe de `auditor-red` sobre `c760998` que cubre los riesgos del PR, `ServiceCounter._open_locally`
(`service_counter.gd:46-51`, RPC en un nodo creado en tiempo de ejecución) y `mud_segment._hold_predicted_truck` con la
predicción de #239, con cada hallazgo corregido o convertido en tarea; `PROTOCOL_VERSION` es 27 con la entrada de N-218,
no queda ninguna línea "reserved", y `test_protocol_version` falla si hay una entrada "reserved".
- [x] **N-922.1** Correr `auditor-red` sobre `c760998` con los riesgos del cuerpo del PR y los dos puntos sin
  diagnosticar; devolver hallazgos. Con `auditor-red`; tests `network`, `rpc_guard`, `net_pair` (por la orquestadora).
  **[x] Hecho (2026-10-02, rama `nacho/N-922-n218-net-audit`)** — sin BUG ni RIESGO alto. OK: autoridad (el cliente
  solo decide la pose de su copia), validación de `submit_driver_input` (remitente = conductor, `finite_float`, clamp,
  buffer de 64), joins tardíos (`net_input_seq` ALWAYS, `net_simulating` ON_CHANGE con el mismo valor inicial), ancho
  de banda (+~0,5 KB/s por cliente), `ServiceCounter._open_locally` (ruta determinista, RPC `authority`, solo al que
  interactuó) y `mud_segment._hold_predicted_truck` (sin fuerza duplicada). Los riesgos medios y bajos, en N-922.2 a
  N-922.7.
- [x] **N-922.2** Subir `PROTOCOL_VERSION` a 27 con la entrada de N-218, borrar la línea "25: reserved" y que
  `test_protocol_version` rechace entradas "reserved"; corregir lo que salga de N-922.1. Con `constructor-red`, seguido
  de `auditor-red`; tests `protocol_version`, `network`.
  **[x] Hecho (2026-10-02, rama `nacho/N-922-n218-net-audit`)** — 27 con la entrada de N-218; la 25 queda como
  "skipped" y explica qué builds llevan 26 con y sin N-218. `test_protocol_version` falla si una entrada dice
  "reserved". De la auditoría, arreglados acá: el host deja de repetir un input del conductor de más de 30 ticks
  (suelta el pedal; volante y freno de mano quedan; hitch o Wi-Fi sin desconexión), `driver_changed()` reinicia `applied_seq` (el conductor
  nuevo no se corrige contra el `seq` del anterior) y `_stop_orphaned_run` congela el camión si el host se va mientras
  el cliente predice.
- [ ] **N-922.3** Colisionadores que existen distinto en cada peer frenan a la copia predicha y terminan en salto de 3 m:
  barreras y vagones del paso a nivel (`rail_crossing_segment.gd:213,281`, llegan RTT/2 tarde al cliente) y operarios y
  autoelevador del depósito (`depot_worker.gd:42-44`, `depot_forklift.gd:32-34`, cada peer en su fase; hoy también
  frenan al camión del host). Arreglo: `add_collision_exception_with` del camión en los peers que no son host (paso a
  nivel) y en todos (depósito), o capa propia fuera de la máscara del camión. Test: muro solo en el mundo del cliente en
  `test_vehicle_prediction` y las excepciones en `get_collision_exceptions()`. Origen: construcción 2026-10-02
  (`auditor-red`, N-922.1). Con `constructor-red` (y `constructor-mundo` para el depósito), después `auditor-red`.
- [ ] **N-922.4** Predecir sin suelo: quien vuelve (N-221) o entra tarde en Endless al volante arranca la predicción
  antes de que el streamer arme el terreno (60 m por tick) y la copia cae. Arreglo: en `vehicle_prediction.gd`
  `_start`/`wanted`, un rayo de 4 m hacia abajo desde `latest_pose` (máscara 1, sin el camión); sin impacto no se
  predice. Test: mundo del cliente sin piso en `test_vehicle_prediction`. Origen: construcción 2026-10-02. Con
  `constructor-red`.
- [ ] **N-922.5** `--net-sim` en LAN no retrasa ni los inputs del conductor ni el `host_state` del reconciliador
  (`vehicle.gd:674`, `vehicle_prediction.gd:129`): con LAN la predicción se ve perfecta. Arreglo: cola de retraso chica
  en `modules/net_prediction` con el perfil de `pose_net_sim()`; test del módulo y etapa de `net_pair` con `--net-sim`.
  Origen: construcción 2026-10-02. Con `constructor-red`.
- [ ] **N-922.6** Barro: la copia predicha no recibe el empuje de la cuadrilla (BOGGED) ni el arrastre (HAULING, 3-5
  m/s) (`mud_segment.gd:453-462` vs `:525,609`): efecto goma durante el arrastre, sin salto. Pasar las dos a
  `_drag_truck` con `pushers` y `haul_method` (ya replicados). Origen: construcción 2026-10-02. Con `constructor-tramos`.
- [ ] **N-922.7** Presentación al dejar o tomar la predicción: al soltar el volante en movimiento el hueco de ~7 m se
  cierra en 0,3 s y el camión dibujado retrocede (`vehicle_prediction.gd:186-197`; usar
  `maxf(EXIT_BLEND_SECONDS, 1.5 * gap / speed)`); al empezar, la cámara salta 1-2 m. Opcional: la caja manual no modela
  el embrague en la copia (`vehicle_gearbox.gd`, ~0,5 m/s, sin salto). Origen: construcción 2026-10-02. Con
  `constructor-camion`.

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

### N-321 · Grúa del tramo de barro con modelo — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-321-mud-crane`**

Hoy `scripts/gameplay/route/mud_crane.gd` (la grúa cómica del tramo de barro, N-108) se arma con ~12 BoxMesh: chasis amarillo
2,6×0,7×6 m, cabina blanca, parabrisas, paragolpes rojo, pluma inclinada −16°, gancho, 4 ruedas cuadradas y una baliza que gira
y late. Aparece pegada al camión del jugador cuando se atasca, así que se ve de cerca. Pasarla a un GLB low-poly generado por
script de Blender (`do-not-drop/assets/tools/` con `lowpoly_kit.py`, ampliando `build_street_props.py` o con un script nuevo)
en `do-not-drop/assets/models/vehicles/` (p. ej. `sm_vehicle_tow_crane.glb`), del mismo tamaño y orientación (frente a −Z,
gancho atrás +Z en `HOOK_LOCAL` (0, 2.1, 3.6)), con presupuesto como los autos refinados (~1.500-2.500 tris) y nodos con nombre
para lo que anima el script (`Beacon`, que gira y late, y el gancho). `mud_crane.gd` lo instancia en vez de las primitivas, sin
cambiar `hook_position()`, los carteles `Board`/`BoardLeft`, el traqueteo ni nada de la lógica de `mud_segment.gd`.
**Necesita PC** (Blender; la toma la sesión de arte). Origen: sesión de arte 2026-10-01.
Hecho cuando hay un GLB de grúa de remolque dentro del presupuesto, cargado por `mud_crane.gd` sin ninguna `PrimitiveMesh`,
con `test_mud_segment` ampliado (la grúa usa el GLB, `Beacon` existe, el gancho queda donde estaba), verificado con
`revisor-visual` (`tests/render_mud_segment.gd`) y `check_pivots.gd`, y con el inventario §10.1 actualizado.
- [x] **N-321.1** ~~Modelar la grúa por script y exportar el GLB con las medidas y la orientación de la versión de
  primitivas. Con `modelador-blender`.~~ **[x] Hecho (2026-10-01, sesión de arte)** — `build_street_props.py -- crane`
  (`tow_crane()`) → `models/vehicles/sm_vehicle_tow_crane.glb`, 2.028 tris (2.393 con el AO de `bake_vertex_ao.py`):
  `Chassis`, `Cab` (faros-ojos y parrilla-sonrisa), `Boom` (dos tramos, cilindro hidráulico, malacate, cable fijo),
  `Wheels`, `Light` (`lamp`), `TailLights` (`danger`), `Beacon` (origen en (0; 2,55; −1,9), emisivo `beacon`) y `Hook`
  (origen en el ojo, (0; 2,05; 3,6)); lados del chasis planos en |x| = 1,30 para los carteles; patito de goma en la cola.
- [x] **N-321.2** ~~Cambiar `mud_crane.gd` para instanciar el GLB y ampliar `test_mud_segment`. Con `constructor-tramos`.~~
  **[x] Hecho (2026-10-01)** — `mud_crane.gd` `_build_model()` instancia el GLB bajo `Body` (sigue traqueteando), lo pasa
  por `LowpolyMaterials.apply()` y `light_up(["lamp"])` como los autos estacionados y toma `Beacon` del modelo; sin
  primitivas. `HOOK_LOCAL`, `hook_position()`, `Board`/`BoardLeft` y `mud_segment.gd` sin cambios. `test_mud_segment`
  `_check_crane_model()`/`_expect_crane_model()` (escena del GLB, ninguna `PrimitiveMesh`, nodos con nombre, `Beacon`
  emisivo que gira, gancho a < 0,6 m de `hook_position()`, carteles afuera del chasis); GLB sumado a `check_pivots.gd` y
  `test_baked_ao`.
- [x] **N-321.3** ~~Verificar de cerca con `revisor-visual` y `check_pivots.gd`, y actualizar el inventario.~~
  **[x] Hecho (2026-10-01)** — con GPU real: pivote en el suelo (centro XZ (0; 0,19) por la pluma), "GRÚA" legible en los
  dos lados, cable del gancho al camión sin cortes, baliza visible, sin z-fighting ni caras invertidas. Inventario §7 y
  §10.1. Queda (menor): el patito no se reconoce a distancia, la cabina crema sale fría con la luz del cielo, y los planos
  `crane`/`crane_cable` de `render_mud_segment.gd` la encuadran chica detrás del camión de cajas; no hay plano de noche.

### N-322 · Barro con la calidad del resto del suelo — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `nacho/N-322-mud-look`**

Pedido del usuario 2026-10-01 ("el barro no tiene ni cerca la calidad ni textura que los demás suelos"): el barro de
`MudSegment` (N-108) eran cajas planas de un color naranja (`MudSurface`, `MudPit`, `MudRut`), discos grises de charco y
montículos cúbicos, sin textura; al lado del terreno con mapas de grano se veía de otro juego.
~~Hecho cuando el barro es una superficie con textura y relieve que sigue el suelo, sin cajas ni discos.~~
**[x] Hecho (2026-10-01)** — `shaders/mud_ground.gdshader`: una sola `PlaneMesh` `MudSurface` (subdividida a ~1 m, la
acomoda `conform_geometry()`) con el grano de tierra (`tx_detail_earth_512.png`), barro marrón con costra seca y zonas
mojadas, el pozo más húmedo donde está la física (`pit_start`/`pit_end`), dos huellas con dibujo que se cortan por tramos,
agua turbia con brillo suave en lo bajo, relieve por normal y borde irregular (discard) con anillo de costra que lo funde con
la ruta. Montículos: semiesferas low-poly con el mismo shader (`lump`). `mud_segment.gd` `_build()`/`_mud_material()`.
`test_mud_segment` ampliado (shader y parámetros del pozo, sin cajas ni discos, montículos); revisado en 4 iteraciones con
`revisor-visual` (`tests/render_mud_segment.gd`). Queda: el contorno se ve algo ruidoso a mucha distancia.

### N-320 · Polvo de las ruedas legible y según el suelo — B · `Opus 5.5 · medium` · Aviso: no · **[x] rama `arte/N-320-wheel-dust`**

Hoy `scripts/presentation/vehicle_presentation.gd:453-488` (`_apply_dust` y el emisor) echa cubos `BoxMesh` de 0,05 m, 14 por
rueda, vida 0,55 s, color fijo `9c8060`, opacos: son subpíxel a pocos metros desde la caja o el espejo, y el polvo es el mismo
en asfalto, grava y con lluvia. Rehacer el efecto, no el sistema, con la receta del humo de escape (`vehicle_effects.gd:95`:
esfera low-poly de 6 lados, sin sombra): bolas que crecen (curva 0,5→2,5) y se desvanecen (gradiente alfa ~0,35→0), color de
la tierra de `route_terrain` (no naranja), intensidad según el suelo (grava/tierra 1, asfalto 0), apagado con `wetness` alto
(lluvia), vida 0,9-1,2 s, emisor en las ruedas traseras hacia +Z y sin invadir ~1,5 m alrededor de la cámara de la caja.
**Intento 2026-10-01 (02:30): corrida caída, capturas en `D:/tmp/wheel_dust/`; quedó demasiado opaco, anaranjado, con borde
octogonal duro y con bolas que tapaban la cámara de la caja. No repetir: alfa bajo y con degradé, color de `route_terrain`,
más lados o mezcla suave del borde, y corte duro de emisión cerca de la cámara de la caja.**
**Necesita PC** (GPU real para las capturas; la toma la sesión de arte). Origen: sesión de arte 2026-10-01.
Hecho cuando en grava se ve una nube suave y clara desde el espejo, la caja y atrás, de día y de noche; en asfalto no hay
polvo; con lluvia se apaga; no hay bolas a menos de 1,5 m de la cámara de la caja; `test_dust_and_ambience.gd` ampliado (en
asfalto no emite, en grava sí, con `wetness` alto no, material sin sombra y con alfa); hay capturas antes/después con
`revisor-visual` desde un script reproducible en `tests/render_*.gd`; y el inventario de assets está al día.
- [x] **N-320.1** ~~Rehacer el emisor y el material del polvo según la receta de arriba y ampliar
  `test_dust_and_ambience.gd`. Con `artista-vfx` y `escritor-tests`; tests `dust`.~~ **[x] Hecho (2026-10-01, sesión de arte)** —
  componente nuevo `scripts/presentation/wheel_dust.gd` (`WheelDust`, lo crea `vehicle_presentation.gd`, que pierde
  `_build_dust_emitters`/`_apply_dust`): 2 emisores en la carrocería, uno por rueda trasera (la rueda gira y arrastraba la
  dirección), quad billboard de 1,3 m con degradé radial por código (la esfera low-poly dejaba el octógono del intento
  anterior), unshaded, sin sombra, color `e0d4b8` (más claro que la grava, no naranja), alfa 0,8 → 0,7 → 0, escala 0,5 → 2,5
  (`Curve.max_value` 3), 32 partículas × 1,2 s, `inherit_velocity_ratio` 0,35. Intensidad = máx(velocidad, derrape) ×
  suelo (`Route.ground_roughness()` × 1,6: asfalto 0, banquina 0,4, grava 1; sin ruta, 0) × (1 − wetness de `WorldMood`:
  lluvia 1, niebla 0,35), muestreada cada 0,2 s; de noche color ×0,35 y alfa ×0,75. No emite con la cámara activa a
  < 1,5 m. `test_dust_and_ambience.gd` con ruta falsa y mood fijo: asfalto no, grava sí, banquina más rala, lluvia no,
  niebla menos, noche más oscuro, corte de cámara, material.
- [x] **N-320.2** ~~Script de captura reproducible y verificación visual antes/después. Con `revisor-visual`; tests
  `dust`.~~ **[x] Hecho (2026-10-01, sesión de arte)** — `tests/render_wheel_dust.gd` (`--mood`, `--seed`, `--out`,
  `--ground`, `--dry`): el camión real a ~42 km/h en grava y asfalto, planos `mirror`, `cargo` y `rear`. Con GPU real
  (RTX 4060 Ti, 1280×720): antes (cubos de 0,05 m) no se veía nada; después, estela clara en grava, luminancia sobre la
  estela vs. grava limpia en `rear` 189 vs. 150 de día y 69 vs. 49 de noche; asfalto y lluvia, 0 de 2 emisores; tapa
  ~10-15 % de la puerta trasera abierta en `rear`. En `mirror` la caja tapa la estela (pose de la cámara, no del efecto).
- [x] **N-320.3** ~~Actualizar el inventario/spec; corregir de paso los ítems 51 y 90.~~ **[x] Hecho (2026-10-01)** —
  `docs/inventario-assets.md` §7 y `docs/especificaciones-visuales.md` #49 (polvo nuevo), #51 (marcas de frenada) y #90
  (escombros), que ya existían en `vehicle_effects.gd`.
- Queda (fuera de N-320): el humo de escape de `vehicle_effects.gd` → N-324.

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

### N-702 · Esta lista como tablero — A · `Opus 5.5 · low` · Aviso: no · **[x]**

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

### N-323 · Que nada visible se cierre con cajas de color plano — A · `Opus 5.5 · low` · Aviso: no · **[x] rama `nacho/N-323-art-quality-gate`**

Pregunta del usuario 2026-10-01 tras N-322 ("¿por qué no se hizo así desde un principio, quién es el encargado?"): el barro de
N-108 salió con cajas naranjas porque el "hecho cuando" solo pedía la mecánica, `constructor-tramos` arma con `_box()`,
`revisor-visual` miró que estuviera y no si estaba a la altura, y `director-arte` audita el inventario, donde la geometría
por código no figura. Nadie tenía a cargo la calidad visual de lo que arma un constructor.
~~Hecho cuando la cadena de agentes marca y deriva los placeholders visibles.~~
**[x] Hecho (2026-10-01)** — `planificador-tareas`: toda tarea visible lleva en el "hecho cuando" la revisión de
`director-arte` contra lo que la rodea y, si se arma con primitivas, una subtarea de arte desde el principio.
`director-arte` (punto 8): busca la geometría por código con color plano a la vista. `auditor-integral` (pilar 2): marca
los placeholders sin subtarea de arte. `constructor-tramos` y `constructor-mundo`: un placeholder visible sale como
subtarea, nunca como hecho. Rutina de construcción (paso 7): `revisor-visual` compara contra el entorno y un suelo o
material plano pasa por `artista-shaders` en la misma sesión.

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
  probó con el juego real). Se hace junto con N-215 y N-912.3.
- Nota lanzamiento 2026-10: Steam Direct tiene 30 días de espera entre el pago y poder lanzar; fecha de pago en N-916.
  Sin AppID no hay logros (S-907), nube (N-914) ni prueba real.

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

### N-506 · Pantalla "Hacé tu personaje" profesional, caras rubber hose y vestuario del depósito — A · `Opus 5.5 · xhigh` · Aviso: sí (`cosmetics_panel.gd`, `depot_panel.gd`, `scripts/ui/customize/` de Slatex, `docs/avisos/2026-10-01-n506-pantalla-personaje.md`) · **[x] rama `nacho/N-506-character-customization`**

Pedido del usuario (2026-10-01): la pantalla de personaje se veía fea, las caras poco profesionales y
tenían que ser más caricatura (referencia: hojas de caras rubber hose de los años 30), y cambiarlas también en
el vestuario del depósito.

- [x] **N-506.1** Caras rubber hose originales (`art/rounded_character/build_faces.py`): ojos altos y juntos,
  pupila en cuña, cejas cortas, paréntesis en las comisuras, bocas oscuras con lengua; ojos un 15 % y
  bocas un 22 % más grandes. 8 ojos (+ "Decididos") y 8 bocas (+ "Pícara"); los IDs viejos siguen valiendo.
- [x] **N-506.2** Cejas en capa propia (`brows_*.svg`, `CharacterFace` "Brows"): el parpadeo ya no las baja
  (antes "Preocupados" las aplastaba contra los ojos). `EYE_LINE_V` y los recortes de tarjeta medidos sobre
  los SVG.
- [x] **N-506.3** Pantalla nueva (`cosmetics_panel.gd`): personaje 3D real en estudio con luz propia
  (`customize/character_preview.gd`), cara en primer plano o cuerpo entero según la pestaña, giro con mouse
  o stick derecho, rebote al cambiar; apodo y "Sorprendeme" debajo; pestañas con subrayado y tarjetas con
  dibujo (`customize/customize_swatch.gd`): ocho caras armadas (`FaceCatalog.PRESETS`), los 8 ojos y las 8
  bocas a la vista sin scroll, remeras altas como en un perchero y furgonetas; tilde en la elegida y candado
  con "se gana con…" en las bloqueadas. Se actualiza en el lugar, sin reconstruirse.
- [x] **N-506.4** El vestuario del depósito abre la misma pantalla en modo depósito (Rostro + Uniforme): lo
  elegido llega en vivo al jugador y al resto por la réplica que ya había. Con "Color de equipo" la vista
  previa muestra el color del slot propio.
- [x] **N-506.5** Tests: `test_customization_screen` (nuevo); `test_character_faces`, `test_nickname` y
  `test_gamepad_focus` adaptados. Capturas en `tests/render_character_faces.gd` (pestañas, modo depósito y
  las 16 caras sobre cabezas reales a 5 y 9 m).

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

### N-109 · Animales que se meten con la carga — B · `Opus 5.5 · xhigh` · Aviso: sí (estados del paquete)

Extiende N-106 y N-107: los animales ahora amenazan paquetes, no solo el camino.

- [x] **N-109.1** Gaviota que baja a la caja del estante y trata de llevársela; se espanta con la bocina o
  sujetando la caja. Rama `nacho/N-109-cargo-animals`. Entra por la puerta trasera abierta; anunciada 3 s antes
  (graznido + ícono con cuenta regresiva sobre la caja + cartel en el HUD); después tiene 6 s: si la caja no
  está sujeta (el primario de quien la atiende, o alguien que la levanta; 1 s en total) ni suena la bocina,
  la saca por la puerta con velocidad hacia atrás y sigue cargada, así que cae en la ventana de rescate de
  N-213 (no la arruina de entrada). Modelo: el pájaro de la ruta (`sm_env_animal_bird.glb`) a escala ×2,2.
- [x] **N-109.2** Perro que se sube a una caja abierta en una parada; se lo distrae tirándole algo. Rama
  `nacho/N-109-cargo-animals`. En una parada a menos de 18 m de una casa, con una caja abierta a menos de 10 m
  del camión: ladrido y carrera 3 s antes, y después la desgasta de a poco (2,5 de 100 por segundo, hasta 30 s:
  nunca la arruina sola). Se va con la bocina, cerrando la tapa, levantando la caja o con **"Tirarle un palo al
  perro"** (`dog_distract_point.gd`, un `Interactable` que va sobre el perro: apuntarle y apretar interactuar
  con las manos libres; el palo vuela y el perro lo persigue).
- [x] **N-109.3** Abejas atraídas por la torta (Equilibrio) en zona de campo. Rama `nacho/N-109-cargo-animals`.
  Campaña, tramo de campo abierto (`RouteDresser.Zone.COUNTRYSIDE`), torta abierta a bordo: zumbido y nube
  3 s antes; después desgastan la torta (3 por segundo, hasta 14 s) y le dan empujones que la inclinan (lo que
  Equilibrio hace contrarrestar con el peso). Se van al cerrar la tapa, con la bocina o al salir del campo.
- [x] Cada uno anunciado con sonido o ícono antes de actuar (la queja principal de RV There Yet? es la
  fauna sin aviso). Determinista por semilla, disparado por el host. Tests con el patrón de
  `test_wildlife_crossing.gd`. Rama `nacho/N-109-cargo-animals`.
  - `CargoAnimalPlan` (semilla → tramo): ninguno en el primer tramo, uno por tramo como mucho y nunca en dos
    seguidos, ~55 % de los demás; el host (`CargoAnimals`) mira si puede actuar (caja en el estante / caja
    abierta), tope de 3 por partida, y lo cuenta a todos con `cargo_animal_alert` / `cargo_animal_ended`
    (`EventBus.relay`); tras irse uno no se anuncia otro en 3,5 s (el tiempo de su salida); quien entra tarde
    recibe el aviso otra vez sin reiniciar al bicho. Cada cliente lo
    dibuja (`CargoAnimalView`). El daño lo hace solo el host (`DeliveryPackage.apply_external_damage`).
  - Revisión visual (2026-09-30): la gaviota tiene modelo propio de primitivas (`cargo_gull.gd`: cuerpo blanco,
    alas grises con puntas oscuras abiertas al volar y plegadas al posarse, pico amarillo); el perro (Shiba) sale
    1,3 veces más grande, de pie en el pasillo junto a la caja; las abejas son 64 bichos de una sola malla (amarillos con franjas
    negras y alitas blancas) que orbitan la torta; el ícono sobre la caja es más chico, con flecha y cuenta regresiva; y el palo sale como
    prompt aunque el control de puertas esté más cerca (`aim_bonus`).
  - Test `test_cargo_animals.gd` (plan, sonidos, modelos, gaviota, perro, abejas, cliente vs host, ritmo). Capturas:
    `tests/render_cargo_animals.gd` (para `revisor-visual`).
  - Aviso: `docs/avisos/2026-09-30-n109-cargo-animals.md`. `PROTOCOL_VERSION` 11 → 12.
  - En Endless solo viene la gaviota (no hay casas ni campo). El perro y las abejas piden la caja **abierta**:
    con la tapa cerrada no vienen (es lo que hace que cerrarla sea una salida). **Decidido** (Claude, con delegación del usuario,
    2026-09-30): el perro y las abejas van solo por cajas abiertas y cerrar la tapa es la contramedida que el
    jugador aprende (`docs/decisiones/2026-09-30-preguntas-auditoria.md`).
  - Revisión visual hecha (2026-09-30, con GPU): gaviota propia, perro más grande y abejas de una sola malla
    (`cargo_bee_mesh.gd`: cuerpo amarillo con dos franjas negras, cabeza y aguijón negros y dos alitas blancas
    translúcidas; la abeja entera vibra). Falta: medir el ancho de banda de red (`auditor-red`) y dar mérito a
    quien espanta (`CrewProgression.award_milestone`).

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

### N-108 · Tramo de barro/pendiente con salida cooperativa — B · `Opus 5.5 · high` · Aviso: no

- [x] Tramo nuevo, raro y anunciado con carteles, donde el camión se puede atascar. Salidas: pasajeros que
  bajan a empujar (mantener un botón en la zona correcta; el host aplica la fuerza) o eslinga de tienda.
- [x] El dilema tiene que existir: mientras empujan, sus cajas quedan sin atender.
- [x] Nunca bloquea para siempre: pasado un tiempo aparece una grúa cómica que lo saca, con multa.
- [x] Con `constructor-tramos`; tests de pacing y fuzz (N-103, N-801) siguen pasando.

> **Hecho (2026-09-30), rama `nacho/N-108-mud-segment`.** `MudSegment` (`segments/mud_segment.gd`): una entrada con
> cartel "¡BARRO!" y el cartel de peligro de la ruta, un pozo de 12 m donde el camión se atasca si baja de 5 m/s; atascado
> lo sostiene el host. Salidas: pasajeros a pie detrás del camión mantienen el botón primario (1/20 del avance por segundo
> cada uno, el motor solo 1/90: no pueden empujar sentados ni con una caja en la mano, ahí está el dilema), la eslinga de
> la tienda (`tow_strap`, $30) o la grúa cómica (`mud_crane.gd`) a los 45 s con multa de $40 que nunca deja el saldo en
> negativo. Rara (`RoutePlanner.MUD_WEIGHT`, una por entrega, no en la llegada a una casa ni antes de los 100 m; en Endless
> no antes de 300 m ni dos a menos de 600 m). `SegmentStreamer` ganó los ganchos `_pick_weight` y `_limit_candidates`.
> `vehicle.gd`: un camión sin conductor se congelaba ("parking") bajo la grúa, ahora respeta el meta `keep_awake`.
> `PROTOCOL_VERSION` 15. Tras la auditoría de red: fin de partida atascado cancela sin multa, agarre compartido con la grava (`GripZones`), unión tardía, una sola salida por tramo, grúa gratis en Endless. Test `test_mud_segment.gd` (generación, física con la camioneta real, empuje de 1 y 2, eslinga,
> grúa con saldo 100 y 15, ambos niveles no cuentan "atascado" en el barro); captura con `tests/render_mud_segment.gd`.
> Pendiente con la PC: modelo propio del cartel de barro (hoy el de ripio más el cartel del tramo) y el sonido.
> Aviso: `docs/avisos/2026-09-30-n108-barro.md`.

### N-110 · Paradas de servicio en la ruta — B · `Opus 5.5 · xhigh` · Aviso: sí (compra de suministros) · **[x] rama `nacho/N-110-service-stops`**

- [x] En rutas largas y en Endless, una estación de servicio opcional: reponer consumibles del kit con
  dinero cooperativo, arreglar averías (N-214) y un cosmético escondido (N-311).
- [x] Parar cuesta tiempo de plazo: es una decisión, no un respiro gratis.
- [x] Test: aparece según las reglas de ritmo y la compra usa la misma votación que el depósito.
- [x] **N-110.2** Arreglos de la auditoría de red (`auditor-red`): usar el mostrador otra vez ya no borra los votos,
  la votación solo sigue abierta con el equipo en la estación (el host la cierra cuando se van), una carta de
  Prioridad o Descuento cobra una vez, el panel se cierra al alejarse o si Endless borra la estación, aviso sin
  plata, estado solo a peers con el nivel cargado. Aviso: `docs/avisos/2026-10-01-service-stop-vote-fixes.md`.
- [x] **N-110.1 (necesita PC)** Modelo propio de la estación con `modelador-blender` (techo de surtidores, surtidores,
  kiosco con mostrador, poste de precios, carteles de "estación de servicio"): hoy son cajas `DepotKit` con tres props
  del depósito (timbre, pallet envuelto, matafuego). Después, captura con `revisor-visual` en entrega y en Endless.
  **Hecho (2026-10-01), rama `arte/N-110.1-service-station`:** 6 GLB `sm_env_service_*` (`tools/build_service_station.py`,
  ~5.900 tris en total) conectados en `service_stop.gd` con `DepotKit.model()`; colisiones, mostrador, textos y brillos
  siguen en código, el cartel "KIOSCO" pasó a una marquesina sobre el frente y el pallet de cajones quedó al lado (no
  encima) del punto del cosmético. Captura `tests/render_service_stop.gd` (entrega y Endless, 5 vistas cada uno).

> **Hecho (2026-10-01), rama `nacho/N-110-service-stops`.** `ServiceStopRules` (`service_stop_rules.gd`, puro y
> estático): una ruta de 3+ casas o 2000+ m lleva una estación (en la práctica todas las de 3-4 casas), en el borde
> de tramos más cercano a la mitad que deje 150 m desde la salida, 40 m después de una casa, 110 m antes de la
> próxima (más que la llegada tranquila) y 60 m antes de la meta, nunca al lado de puente, túnel, paso a nivel o
> loma; `RoutePlanner.plan_spine()` la inserta como un tramo más (`ServiceStopSegment`, 110 m) y corre las
> distancias de lo que sigue, así el plazo cuenta ese camino y parar es tiempo gastado (el reloj nunca se frena).
> En Endless `RouteStreamer` la pone a 450-800 m y luego cada 900-1500 m, sorteado de la semilla y su número,
> nunca justo después de un tramo difícil. El tramo trae dársena a la derecha, dos carteles y la estación
> (`ServiceStop`: techo, surtidores, kiosco, poste de precios, punto `hidden_cosmetic_spot` para N-311); en la
> entrega el terreno se nivela bajo ella con dos `pads` y no crecen árboles ni postes. El mostrador
> (`ServiceCounter`) abre la tienda (`ServiceStopShop`): repone lo que falta del kit (cinta, pegamento, relleno,
> trapos, cinchas, gallina) y vende el repuesto, que arregla en el acto la puerta o el espejo, un 40 % más caro
> que el depósito. Online la compra pasa por la misma votación del depósito (`ShopVoteManager`, ofertas con
> `venue`), solo se compra al toque; `DepotPanel` ganó la cara `service`. Parado en la dársena no cuenta como
> trabado. `PROTOCOL_VERSION` 22. Test `test_service_stop.gd`; `tests/data/route_golden.txt` regenerado (las
> rutas de 3 y 4 casas del golden ahora tienen estación). De paso: un cartel de pueblo cuyo lugar está ocupado se
> corre al siguiente paso libre (`route_signage.gd`, antes quedaba un pueblo sin salida) y el chaos bot ya no se cae
> leyendo una caja entregada (liberada). Aviso: `docs/avisos/2026-10-01-service-stops.md`.

### N-311 · Cosméticos para encontrar en el mundo — B · `Opus 5.5 · medium` · Aviso: sí (cosméticos del jugador)

- [ ] Además de los que se desbloquean con mérito, algunos gorros aparecen en el depósito, en las paradas
  (N-110) o en el jardín de un cliente. Recogerlos exige bajarse o desviarse unos metros.
- [ ] Se guardan en la campaña por color de jugador, como el mérito. Test de guardado y carga.

### N-113 · Evento de visibilidad limitada para el conductor — C · `Opus 5.5 · high` · Aviso: sí (`event_bus.gd`, `network_manager.gd` y `hud_notices.gd`) · **[x] rama `nacho/N-113-low-visibility-event`**

- [x] Evento de ruta de 10-20 s: niebla densa, parabrisas embarrado o una caja que tapa la vista. Un
  pasajero en la ventana guía (con N-505 o N-212). Solo como evento corto: la premisa completa es la de
  Backseat Drivers.
- [x] Shader con `artista-shaders`; test de que dura lo previsto y no se repite seguido.

> **Hecho (2026-09-30), rama `nacho/N-113-low-visibility-event`.** Variante **parabrisas embarrado** (la niebla local y la
> caja que tapa la vista quedan sin hacer: `LowVisibilityPlan.KINDS` y el overlay ya trabajan por tipo, sumar uno es
> agregar su valor y su efecto). `low_visibility_event.gd` (nodo de `level_common.gd`): el host sortea cada 5 s de
> partida con `low_visibility_plan.gd` (función pura de semilla + número de sorteo, azar 1,5 %), dura 10-20 s, no antes de
> los 45 s, con conductor y camión en marcha, enfriamiento de 2 min tras terminar, uno por entrega (Endless: solo el
> enfriamiento), nunca si termina dentro de la zona tranquila (`RoutePlanner.QUIET_ZONE`) antes de una casa o la meta
> (si el camión entra igual, se corta) ni con un evento de ruta abierto. `EventBus.low_visibility_changed` lo replica y
> quien entra tarde recibe lo que queda (`_receive_state`, `PROTOCOL_VERSION` 5). `windshield_rain.gd` suma el overlay
> `shaders/windshield_mud.gdshader` (manchones con chorreras, GL Compatibility, 9 vueltas de bucle) que solo ve quien
> conduce desde el asiento; el pasajero ve la ruta y guía. Los limpiaparabrisas corren mientras dura y adelgazan el barro
> (20 % por pasada, hasta 70 %) con la misma fórmula de barrido que la lluvia. HUD: aviso al conductor y toast a los
> demás que sugiere la rueda de frases. Tests: `test_low_visibility_event` (nuevo). **Falta (necesita revisión de ojos):**
> captura del parabrisas con barro (`revisor-visual`).

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

### N-114 · Caja de cambios manual como variante — C · `Opus 5.5 · xhigh` · Aviso: sí (archivos de Slatex y zona compartida, `docs/avisos/2026-09-30-n114-manual-gearbox.md`) · **[x] rama `nacho/N-114-manual-gearbox-v2`**

- [x] Variante "clásico viejo" a elegir en el depósito, con marchas manuales opcionales y más paga o
  mérito como compensación.
- [x] Los tests de manejo (N-104) de las variantes existentes no cambian.

> **Hecho (2026-09-30), rama `nacho/N-114-manual-gearbox-v2`.** Variante `vintage` ("Furgón clásico viejo", 68 km/h,
> 1000 kg) que se desbloquea con 6 entregas y 550 puntos (`vintage_van`) y se elige en el taller como las otras. Caja
> manual de 5 marchas en un componente aparte, `vehicle_gearbox.gd` (nodo `Gearbox` del camión): cada marcha tira hasta su
> tope (30/50/70/88/100 % de la velocidad máxima) y ahí corta, las bajas tiran más fuerte, una marcha alta a paso de hombre
> "arrastra" (nunca se cala), cambiar toma 0,3 s con el embrague adentro (sin tracción) y una reducción a destiempo frena con
> el motor. La marcha de atrás no es una marcha (frenar parado retrocede). El host manda: el conductor pide subir o bajar con
> el RPC confiable `request_gear_shift` (solo cuenta el conductor actual) y `Gearbox:gear` se replica; `PROTOCOL_VERSION`
> 12. Acciones `drive_shift_up/down` (flechas arriba/abajo, bumpers del mando), reasignables en Opciones. Se ve: "MARCHA n" bajo
> la velocidad del HUD (rojo con "¡SUBÍ!" en el tope de la marcha) y el motor suena distinto por marcha (el contador de
> revoluciones de `vehicle_presentation.gd` sigue la marcha elegida, con el embrague al cambiar). Compensación: el pago del equipo x1,25
> (`pay_multiplier` en `results`, línea "(incluye +$N del furgón viejo)"), el puntaje no cambia. El clásico y el ágil no
> cambian (caja automática, `drive_multiplier` 1.0). Tests: `test_manual_gearbox` (nuevo).
> Tras la auditoría de red y la revisión visual: un cambio que llega con el embrague adentro espera en una cola de un lugar
> (no se pierde); el RPC exige dirección +1/-1 y deja el lugar para `RpcGuard` (N-221); la marcha se dibuja al instante
> (`gear_changed`); el multiplicador de pago sale solo de `Vehicle.VARIANTS`; el furgón viejo tiene carrocería crema,
> cromados (paragolpes y ópticas) y "¡SUBÍ!" grande y titilante; las flechas se muestran como "↑ ↓".

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

### 1. Game Design

#### S-101 · Terminar los eventos de ruta (hoy se anuncian y nunca se resuelven) — A · `Opus 5.5 · xhigh` · Aviso: sí (`run_manager.gd`) · **[x]**

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

#### S-102 · Mérito individual por acciones reales — A · `Opus 5.5 · xhigh` · Aviso: sí (`run_manager.gd`) · **[x]**

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

#### S-103 · Cartas: dejar solo las que se pueden usar y hacerlas usables — A · `Opus 5.5 · xhigh` · Aviso: sí (`project.godot`, acción nueva) · **[x]**

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

#### S-104 · Votación de suministros en el depósito — A · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

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

#### S-105 · Guardar la campaña cooperativa — A · `Opus 5.5 · high` · Aviso: no · **[x]**

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

#### S-106 · Introducción gradual de trampas desde el perfil — A · `Opus 5.5 · high` · Aviso: no · **[x]**

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

#### S-107 · Reglas de dificultad para armar el pedido — B · `Opus 5.5 · high` · Aviso: sí (una línea en `depot.gd`) · **[x]**

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

#### S-109 · Algo que hacer cuando tu paquete ya se arruinó — A · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

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

#### S-110 · Medir cuánto dura una entrega (regla de oro de 2-5 min) — B · `Opus 5.5 · high` · Aviso: no (solo informa a Nacho) · **[x]**

- [x] (commit `35787d6`) **S-110.1** `tests/bench_delivery_time.gd`: con el conductor automático de S-108.1 y un bot que
  baja, camina y toca el timbre, medir el tiempo total de una entrega con 1, 2, 3 y 4 casas, a
  velocidad de crucero.
- [x] (commit `35787d6`) **S-110.2** Escribir el resultado en `docs/parametros-diseno.md` ("Duración medida") y dejar aviso
  a Nacho en `colaboracion-equipo.md` con los números. Ajustar el largo de la ruta es de Nacho: esta
  tarea termina al entregar la medición, no espera su respuesta.

#### S-111 · Congelado breve al arruinarse una caja (el "slow-mo" pendiente) — C · `Opus 5.5 · high` · Aviso: no · **[x]**

`requerimientos-tecnicos.md` §3.4 lo deja pendiente porque `Engine.time_scale` rompe la física
del host. Hacerlo **solo visual y local**:

- [x] (commit `5fa9277`) 0,35 s en los que las partículas de ruina (`package_feedback.gd`) corren a `speed_scale = 0.15`,
  un destello blanco suave en la viñeta del HUD y un golpe de sonido grave. La física no cambia.
- [x] (commit `5fa9277`) Opción "Efectos de impacto" en opciones para apagarlo (accesibilidad, ver S-502).
- [x] (commit `5fa9277`) Test: tras `package_ruined` el `Engine.time_scale` sigue en 1.0 y las partículas vuelven a 1.0.

---

#### S-112 · Rescate de carga (`docs/jugabilidad-paquetes-rescate.md`) — A · Aviso: sí (`run_manager.gd`, `event_bus.gd`) · **[x]**

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

### 4. Audio y diseño sonoro

#### S-401 · Sonidos de interfaz — A · `Opus 5.5 · high` · Aviso: no · **[x]**

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

#### S-404 · Mezcla medida de los sonidos de trampa — A · `Opus 5.5 · high` · Aviso: no · **[x]**

Balance de volumen sin depender del oído (Nacho dejó registrado en su #83 que editar valores a ciegas
no sirve).

- [x] (commit `2dc4769`) `tests/audio_loudness_report.gd`: genera cada sonido de trampa y de UI, calcula RMS y pico
  en dBFS, y lista la diferencia contra un objetivo (−18 dBFS RMS para efectos de trampa, −24 para UI).
- [x] (commit `2dc4769`) Ajustar el `volume_db` de cada reproductor del dominio de Slatex para quedar a ±2 dB del objetivo.
  Tabla antes/después en `docs/direccion-visual.md` (sección de audio) o un `docs/audio.md` nuevo.

---

### 5. UI / UX

#### S-501 · HUD con jerarquía: una cosa urgente a la vez — A · `Opus 5.5 · xhigh` (después de S-201) · Aviso: no · **[x]**

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

#### S-502 · Accesibilidad: daltonismo, texto y efectos — A · `Opus 5.5 · high` · Aviso: no · **[x]**

- [x] Estados de caja con forma además de color: OK ✓, En riesgo ! (con pulso), Arruinada ✕, en las filas
  de carga y sobre la caja.
- [x] Opción "Paleta para daltonismo" que cambia verde/amarillo/rojo por la paleta Okabe-Ito
  (azul/naranja/bermellón) en `UiTheme`.
- [x] Opción "Tamaño de texto de menús" (100 / 125 / 150 %), aparte de la escala del HUD que ya existe.
- [x] Opción "Subtítulos de sonidos": "[tictac acelerando]", "[gruñido]", "[vidrio que cruje]" en la
  zona de contexto, para los sonidos de trampa en riesgo.
- [x] Todas persistidas en `GameSettings`; `test_settings.gd` ampliado.

#### S-503 · Tipografía legible a distancia de sillón — C · `Opus 5.5 · medium` · Aviso: no · **[x]**

- [x] (commit `10218d0`) Revisar que ningún texto del HUD al 60 % de escala quede por debajo de 14 px efectivos a 1080p;
  subir los que no cumplan. Tabla de tamaños en `docs/direccion-visual.md` §3.

#### S-504 · Todo el menú con gamepad — A · `Opus 5.5 · high` · Aviso: no · **[x]**

- [x] (commit `67cf588`) Cada panel (`options`, `progress`, `tutorial`, `cosmetics`, `leaderboard`, `depot_panel`, pausa y
  resultados) da foco a su primer botón al abrir y devuelve el foco al botón que lo abrió al cerrar.
- [x] (commit `67cf588`) Vecinos de foco en grillas (cosméticos) para que el stick no salte de columna.
- [x] (commit `67cf588`) B / Círculo cierra cualquier panel (hoy lo hacen algunos).
- [x] (commit `67cf588`) Test `tests/test_gamepad_focus.gd`: al abrir cada panel hay un `Control` con foco.

#### S-505 · Rueda de pings — B · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

Hoy hay un único ping "¡Cuidado!" (`player.gd` `_send_ping`).

- [x] (commit `638b9a4`) Tocar ping = ping rápido como hoy. Mantener = rueda de 6: ¡Cuidado!, ¡Ayuda!, ¡Frená!, Acá, Gracias,
  Sí/No. Selección con el mouse o el stick derecho.
- [x] (commit `638b9a4`) Sin cambios de red: `EventBus.request_ping(position, label)` ya lleva el texto.
- [x] (commit `638b9a4`) Color e ícono por tipo en el marcador (`_mark_pinger`); "¡Ayuda!" dispara el emote (S-308) y la
  voz (S-402) si existen.
- [x] (commit `638b9a4`) Test en `test_ping.gd`: cada opción llega con su etiqueta.

#### S-506 · Onboarding: tutorial en fichas y consejos de primera vez — A · `Opus 5.5 · high`, textos con `Opus 5.5 · medium` · Aviso: no · **[x]**

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

#### S-507 · Panel de tripulación en el depósito — B · `Opus 5.5 · high` · Aviso: sí (`hud.gd`, `hud_pause.gd`, `hud_prompts.gd`, `project.godot`) · **[x]**

- [x] (rama `nacho/S-507-crew-panel`) Con Tab (Back en gamepad) mantenido en el depósito: `scripts/ui/hud/crew_panel.gd` lista a los
  conectados con el color de su uniforme y su nombre, quién está al volante y quién tiene caja (ícono + texto, no solo
  color). No pausa ni toma foco. Acción nueva `crew_panel`: Tab ya era de `spectate_toggle` (solo en ruta), así que
  comparte Tab/Back con él porque nunca coinciden; documentado en `convenciones-godot.md` §1 y `controles-y-ui.md`.
  La barra de atajos lo enseña solo en el depósito. Sin RPC nuevos.
- [x] (rama `nacho/S-507-crew-panel`) Para el anfitrión LAN: código de sala (`RoomCode`) e IP; en Steam "invitá desde la lista de amigos";
  el cliente ve por qué no hay código. Test `tests/test_crew_panel.gd`. Aviso: `docs/avisos/2026-09-30-s507-crew-panel.md`.

#### S-508 · Pantalla de resultados completa — A · `Opus 5.5 · high` · Aviso: no · **[x]**

- [x] (commit `909a662`) Una fila por casa con ícono de la trampa, resultado y si tuvo foto.
- [x] (commit `909a662`) Premios de la entrega a partir del mérito (S-102): "MVP" (más mérito), "Rescatista", "Desactivador",
  "Mano firme". Con el color de cada jugador.
- [x] (commit `909a662`) Barra de progreso hacia el próximo desbloqueo: "Te faltan 2 entregas y 120 pts para Explosivo".
- [x] (commit `909a662`) Evento de ruta de la partida y cómo terminó.
- [x] (commit `909a662`) Test en `test_score_breakdown.gd` / `test_hud_flow.gd`.

#### S-509 · Idioma inglés — A (para lanzar) · `Opus 5.5 · high` para extraer, `Opus 5.5 · medium` para traducir · Aviso: sí (`project.godot`) · **[x]**

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

#### S-510 · Progreso y récords que se entiendan — B · `Opus 5.5 · high` · Aviso: no · **[x]**

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

#### S-604 · Reclamos de clientes con voz propia — B · `Opus 5.5 · medium` · Aviso: sí (`docs/avisos/2026-09-30-s604-client-complaints.md`) · **[x] rama `nacho/S-604-client-complaints`**

- [x] Los reclamos de la pantalla de resultados salen de un pool por cliente y resultado (roto, en
  riesgo, abierta, equivocada) en vez de un texto genérico. Pool en `data/text/complaints.json` o dentro
  de la tabla de traducciones (S-509). Hecho: 90 líneas `WORLD_COMPLAINT_<CLIENTE>_<RESULTADO>_<n>` en
  `strings_world.csv` (10 clientes de `docs/narrativa.md` x roto 3 / en riesgo 2 / abierta 2 / equivocada 2, es + en);
  módulo puro `scripts/gameplay/route/client_complaints.gd` (`ClientComplaints`: cliente de la casa = `sender` del
  contenido del pedido, que ahora viaja como 4.º elemento de `Depot.assignments()`; línea elegida por
  semilla + casa + cliente + resultado; viaja la clave, cada par la traduce). `RunManager` guarda `client`,
  `result` y `line` en cada reclamo, marca `opened` (caja intacta entregada abierta) y suma una nota gratis
  ("equivocada") por puerta que rechazó una caja ajena; `hud_results.gd::complaint_line` muestra "Casa N · Cliente: «línea»"
  + qué pasó (sin foto / caso cerrado / sin descuento). `PROTOCOL_VERSION` 4 -> 5. Test nuevo
  `test_client_complaints.gd`; corridos `results score hud ui_translations world_translations house delivery depot
  route_events host_gone phone_camera connection_errors`. Sin capturar: recomiendo captura de la pantalla de resultados
  con `revisor-visual`. Queda abierto: la burbuja de la puerta (`REACTION_LINES`) sigue con frases genéricas.

#### S-605 · Textos de trampas y eventos con tono — C · `Opus 5.5 · medium` · Aviso: no · **[x]**

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

#### S-702 · Qué queda fuera del MVP (control de alcance) — A · `Opus 5.5 · medium` · Aviso: no · **[x]**

- [x] (commit `dbe3e48`) Sección nueva en `docs/plan-desarrollo.md` con la lista cerrada de lo que **no** se hace antes de
  Early Access: chat de voz propio, matchmaking público, cartas Prioridad e Información, tienda en ruta,
  tutorial jugable, más de 7 trampas, servidores dedicados, microtransacciones. Cualquier idea nueva se
  anota en una sección "Después del lanzamiento", no en esta lista.

#### S-703 · Avisos al día — A · `Opus 5.5 · low` · Aviso: sí

- [ ] Cada tarea con Aviso `sí` deja su entrada en `docs/colaboracion-equipo.md` en el mismo commit.
- [ ] Borrar de ese documento los avisos de más de un mes que ya no afectan a nadie (dejar solo los vigentes).

---

### 8. QA (sin playtesting)

#### S-801 · Recorrido técnico de 10 minutos antes de cada push grande — A · — · Aviso: no · **[x]**

Esto **no es playtesting** (no evalúa si es divertido): busca errores.

- [x] (commit `ce7370b`) Checklist en `docs/qa-recorrido.md`: abrir el juego, cambiar opciones, jugar solo una entrega
  completa (agarrar, montar, manejar, bajar, timbre, foto), pausa, volver al menú, Endless 2 minutos,
  cerrar. Anotar cualquier error de la consola de Godot.

#### S-802 · Tests de contrato para todo lo que se agrega por datos — A · `Opus 5.5 · high` · Aviso: no · **[x]**

- [x] (commit `7abb1a3`) `tests/test_trap_contract.gd`: recorre `data/traps/*.tres` y verifica para cada una: crea su
  comportamiento, la integridad queda en [0, max] con input vacío y con input aleatorio durante 30 s
  simulados, `get_hint()` nunca vacío, tiene ícono (S-301), contenido propio (S-302), sonido de riesgo, y
  un desbloqueo o está en el set inicial. Una trampa nueva que no cumpla falla este test.
- [x] (commit `7abb1a3`) Mismo criterio para `data/contents/*.tres` (nodos `Filler`/`Intact`/`Damage`/`Ruined`).

#### S-803 · Bot de caos — B · `Opus 5.5 · xhigh` · Aviso: no · **[x]**

- [x] `tests/test_chaos_bot.gd`: un jugador bot hace acciones al azar (con semilla fija) durante 5 minutos
  simulados en el nivel de entrega: agarrar, soltar, abrir, montar, sentarse, pararse, pingear, sacar foto.
  Falla si aparece un `push_error`, un NaN en posiciones o una caja fuera del mundo.
  Hecho: 300 s simulados (18000 ticks a 1/60 s) en ~35 s de pared, acelerando con `physics_ticks_per_second` x
  `time_scale` (solo `time_scale` alarga el paso, no acelera); errores capturados con un `Logger`. No entra en
  los 20 s de S-806. Rama `nacho/S-803-chaos-bot`.

#### S-804 · Nada anunciado queda colgado — A · `Opus 5.5 · high` · Aviso: no · **[x]**

- [x] (commit `6175d6e`) Test `tests/test_no_dangling_state.gd`: al terminar una partida, `RouteEventManager` no tiene evento
  activo, `ShopVoteManager.active` es falso fuera del depósito, ninguna caja queda con `occupied_by` de un
  jugador que ya no existe. Es el test que hubiera detectado S-101.

#### S-805 · Telemetría local para cuando haya playtesting — B · `Opus 5.5 · high` · Aviso: sí (`game_settings.gd`, `options_panel.gd`, `project.godot`) · **[x]**

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

#### S-806 · Batería verde y rápida — A · — · Aviso: no · **[x]**

- [x] (commits `3c4ac88`, `37581a2`) Después de cada tarea: `tools/run-tests.sh` con filtro de lo tocado. Antes de push, el hook corre todo.
- [x] (rama `nacho/S-806-faster-tests`) Si un test propio tarda más de 20 s, revisar si se puede acortar sin perder lo que verifica.
  Revisados los de jugador/paquete/trampas/UI/progresión que pasaban de 20 s en CI (main, 2026-09-30). Casi todo el
  tiempo es cargar `level_base` (~12-15 s cada vez), así que la única palanca es cargarlo menos veces:
  `test_package_handling` 6 → 3 cargas (~89 s → ~45-51 s local), `test_host_gone_tally` 2 → 1 (~35 s → ~20-30 s);
  ningún `_expect` cambió. Quedan igual: `test_locked_traps` (cada carga es un estado distinto del perfil que el
  `_ready` del depósito tiene que leer), `test_boss_lines` (dos escenas distintas), `test_ruin_effects` (mide
  segundos reales de vida del efecto) y `test_chaos_bot` (excepción de S-803). Los lentos de ruta, camión y mundo
  (`test_route_fuzz` 196 s, `test_roadside_stories` 132 s, `test_route_duration_budget` 122 s,
  `test_route_lookup_cache` 106 s, `test_world_seed` 101 s…) no son de esta tarea. Visto de paso: si una caja del
  depósito se libera (entregada) antes de `Depot.begin_run`, `depot.gd:325` tira "freed instance"; en juego no
  pasa hoy (cada partida recarga el nivel), el test lo esquiva corriendo el arranque vacío primero.

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
