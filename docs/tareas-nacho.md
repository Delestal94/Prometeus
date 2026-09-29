# Tareas de Nacho — Vehículo, Ruta, Ambientación y Depósito

> Última actualización: 2026-09-29 (N-214.4: la pantalla de resultados cuenta cómo terminó cada avería
> del camión, "Espejo reemplazado por un celular"; de N-214 solo falta N-214.3c). Antes, el mismo día: (N-214.3b: un pasajero sostiene el celular como espejo mientras no
> haya repuesto; quien se une a mitad del recorrido recibe las averías; faltan los resultados, N-214.4).
> Antes, el mismo día: (N-214.3 parcial: puntos de arreglo en el camión; la puerta se ata
> con la cincha del kit y el repuesto nuevo del depósito arregla puerta o espejo; falta el celular como
> espejo y los resultados). Antes, el mismo día: (túneles de tren en las dos puntas de la vía del paso a
> nivel; repaso de las cascadas). Antes, el mismo día: (N-214.2: la puerta trasera rota se abre sola con los baches y el
> espejo del conductor se cae a la ruta; faltan arreglos y resultados). Antes, el mismo día: (N-213.3: gancho de rescate como suministro del depósito; N-213 queda
> cerrada). Antes, el mismo día: (N-213: test de red con dos clientes que agarran la misma caja; queda el
> gancho N-213.3). Antes, el 2026-09-28: (cascadas con rocas en las dos puntas del río de cada
> puente angosto). Antes, el mismo día: (N-214.1: componente `VehicleFaults` que decide en el host las averías
> del camión por golpe fuerte, una por entrega; faltan efectos, arreglos y resultados). Antes, el mismo día: (N-213.4: abandonar la caja caída cierra su pedido como
> "Perdido" sin terminar la partida; falta el gancho). Antes, el mismo día: (N-213 parcial: la caja que sale del camión tiene 30 s de rescate
> con cartel encima y se puede volver a subir; faltan el gancho y el pedido "Perdido"). Antes, el mismo día: (N-505 cerrada: la voz sintetizada de cada frase, con tono por
> color de jugador). Antes, el mismo día: (N-505 parcial: rueda de ocho frases, enfriamiento de 1,5 s en el
> host y la frase en el HUD del conductor; falta la voz sintetizada). Antes, el mismo día: (N-704 cerrada: diferencial corregido en los docs y veredictos de
> `critico-diseno` en N-212, N-214 y N-112 — esta última en contra). Antes, el mismo día: (hito M6: 15 tareas tomadas de `analisis-competencia-backseat-rv.md`,
> asignadas a Nacho aunque varias tocan el dominio de Slatex; N-907 nace pospuesta ⏸). Antes, el mismo día:
> N-901 y todo lo de publicar/promocionar pospuesto a la iteración de lanzamiento. Antes: 2026-09-27 (repaso del depósito tras playtest; #180 cajas que se salían del camión; N-310, personaje cartoon gordito). Antes: 2026-09-25 (tanda sobre `claude/nacho-pending-tasks-qhxmmj`). M1, M2 y M3 cerrados;
> M4 completo; de M5, N-210, N-703 y N-902 a N-906. Quedan abiertas solo las que no dependen de código:
> N-901 (pagar Steam Direct y el AppID real), la meta de N-204 con el preset bajo en una PC modesta (no hay
> una a mano; la nube renderiza por software) y #149 (probar con 3+ personas por Steam). N-702 es permanente.
> Reescrita entera con el mismo formato que `docs/tareas-slatex.md`: las tareas 1-127 de la
> versión anterior están cerradas o reubicadas (ver "Qué pasó con la lista anterior" al final).
> Esta lista sigue los 9 pilares de producción y **solo tiene trabajo que Nacho puede terminar
> sin esperar a Slatex y sin playtesting**.
>
> División de dominios y zona compartida: `docs/colaboracion-equipo.md`.

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

Dentro de un hito, el orden de la tabla es el recomendado.

---

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
empezarlas, conviene pasar el plan por `guardian-dominios`. `vehicle.tscn` / `vehicle.gd` siguen
congelados: nada de esta sección los edita; lo que necesita el camión se cuelga desde afuera.

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

### N-214 · Averías del camión reparables con el kit — A · `Opus 5.5 · xhigh` · Aviso: sí (camión congelado: componente aparte)

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
- [ ] **N-214.3** Arreglo oficial (repuesto de tienda) e improvisado con el kit existente (cinta, cincha,
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
  - [ ] **N-214.3c** Confirmar con `revisor-visual` el punto del espejo (y el celular) en las variantes
    de camión que no son la clásica.
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

- [ ] **N-212.1** Steam: captura y envío con la voz de GodotSteam (`startVoiceRecording` / `getVoice` /
  `decompressVoice`) por un canal no confiable, fuera de la simulación autoritativa.
- [ ] **N-212.2** Reproducción en `AudioStreamPlayer3D` en la cabeza del jugador; dentro de la cabina se
  oyen todos, afuera se atenúa y pasa por el bus Exterior con filtro (se oye "a través de la chapa").
- [ ] **N-212.3** Pulsar para hablar (con tecla configurable) y detección de voz, silenciar y volumen por
  jugador, y un interruptor general en Opciones.
- [ ] **N-212.4** LAN/ENet: `AudioEffectCapture` o dejarlo fuera del MVP (decidir y anotar).
- [ ] Medir con `auditor-red` el ancho de banda con 5 jugadores. Test de que el apagado general no
  captura el micrófono.

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

### N-114 · Caja de cambios manual como variante — C · `Opus 5.5 · xhigh` · Aviso: sí (camión congelado)

- [ ] Variante "clásico viejo" a elegir en el depósito, con marchas manuales opcionales y más paga o
  mérito como compensación. Requiere acuerdo previo para tocar el manejo; si no, queda descartada.
- [ ] Los tests de manejo (N-104) de las variantes existentes no cambian.

### N-907 · Friend Pass y demo separada — C · `Opus 5.5 · medium` · Aviso: no · **⏸ Pospuesta (iteración de lanzamiento)**

Es de publicación en Steam: queda pospuesta como el resto del pilar 9 (ver la nota de esa sección).

- [ ] Averiguar en Steamworks cómo funciona el Friend Pass (Backseat Drivers lo usa) y si se puede
  combinar con nuestro lobby de Steam. Decisión anotada en `docs/plan-desarrollo.md` Fase 7.
- [ ] Evaluar publicar la demo (hito del 2026-12-18) como app aparte para acumular deseados.
- Depende de N-901 (AppID propio).

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
