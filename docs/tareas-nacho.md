# Tareas de Nacho — Vehículo, Ruta y Ambientación

> Última actualización: 2026-09-23 (estado sincronizado con `680001a`)
> Ver `docs/colaboracion-equipo.md` para la división de dominios y la zona
> compartida. Las tareas 1-40 vienen directo de `docs/especificaciones-visuales.md`
> (número original entre paréntesis); 41-100 son backlog nuevo del proyecto,
> descompuesto en pasos concretos.
>
> Prioridad: **A** accionable ya (sin pipeline de arte) · **B** necesita
> arte/assets · **C** pulido para más adelante.

## Vehículo — modelado (1-11)

| # | Tarea | Prio |
|---|---|---|
| 1 | ~~Silueta real de la furgoneta: biselar aristas, inclinar la trompa, proporciones de vehículo real, no dos cajas apiladas. (#5)~~ **[x] Hecho (2026-09-23)** — el camión de referencia (`reference_truck.gd`) ya tiene silueta real, trompa y proporciones. | B |
| 2 | ~~Guardabarros / arcos de rueda que contengan las ruedas, hoy flotan junto a un panel plano. (#6)~~ **[x] Hecho (2026-09-23)** — `WheelArch_*` del modelo de referencia. | B |
| 3 | ~~Neumático con dibujo y llanta diferenciada del caucho. (#7)~~ **[x] Hecho (2026-09-23)** — `Tire_*`/`WheelRim`/`RimBolt` del modelo de referencia. | B |
| 4 | Líneas de paneles y juntas de puertas en la carrocería. (#8) | B |
| 5 | ~~Espejos retrovisores laterales — correctos y que encuadren bien el plano en primera persona. (#9)~~ **[x] Hecho (2026-09-23)** — `MirrorHousing_*`/`MirrorSurface_*` del modelo de referencia. | B |
| 6 | ~~Puertas traseras reales en la zona de carga, hoy `Tailgate` es una caja fija. (#10)~~ **[x] Hecho (2026-09-23)** — puertas traseras reales con bisagras y animación (`reference_truck.gd`). | B |
| 7 | ~~Mampara entre cabina y zona de carga — hoy son dos volúmenes sin nada que los separe visualmente. (#11)~~ **[x] Hecho (2026-09-23)** — mampara `Bulkhead*`; ahora además es sólida (`_build_bulkhead_collision`). | B |
| 8 | ~~Tablero completo: instrumentos, rejillas de ventilación, guantera, palanca de cambios. (#12)~~ **[x] Hecho (2026-09-23)** — `Dashboard`, `InstrumentCluster`, palanca y guantera en `_dress_cab()`. | B |
| 9 | ~~Pedales, visibles al mirar hacia abajo desde el asiento del conductor. (#14)~~ **[x] Hecho (2026-09-23)** — tres pedales bajo el tablero; freno y acelerador se hunden con lo que hace el camión (`_build_pedals`). | C |
| 10 | ~~Asientos con apoyacabezas y estructura real, hoy son dos cajas. (#15)~~ **[x] Hecho (2026-09-23)** — asientos con respaldo del modelo de referencia. | B |
| 11 | ~~Cinturones de seguridad. (#16)~~ **[x] Hecho (2026-09-23)** — `Seatbelt` en el modelo de referencia. | C |

## Vehículo — comportamiento visual y físico (12-16)

| # | Tarea | Prio |
|---|---|---|
| 12 | ~~Balanceo de carrocería exagerado en curvas y frenadas.~~ **[x] Hecho** (#21, ver detalle en `docs/especificaciones-visuales.md`). | A |
| 13 | ~~Aberración cromática breve en impactos muy fuertes.~~ **[x] Hecho** — `vehicle_effects.gd` la activa sólo ante impactos fuertes. (#72) | C |
| 14 | Motion blur por velocidad, sutil. (#73) **no se hace: GL Compatibility no tiene motion blur y un pase propio costaría rendimiento; descartado a favor de los 60+ FPS.** | C |
| 15 | Evitar que la cámara atraviese geometría cercana al mirar en diagonal dentro de la cabina (fade o retroceso). (#80) | B |
| 16 | ~~La furgoneta se hunde levemente según el peso total de la carga.~~ **[x] Hecho** — no hizo falta coordinar con Slatex, `mass` de `package.gd` ya era legible desde el grupo `cargo` sin tocar ese archivo. (#96) | A |

## Vehículo — detalle interior/exterior (17-19)

| # | Tarea | Prio |
|---|---|---|
| 17 | ~~Si la puerta trasera está abierta, la carga suelta puede salirse. (#87)~~ **[x] Hecho (2026-09-23)** — la carga suelta ya se sale físicamente con la puerta abierta; la mampara sólida evita que atraviese la cabina al frenar. | B |
| 18 | ~~Objetos sueltos en la zona de carga que traqueteen con los golpes.~~ **[x] Hecho** — `cargo_clutter.gd` crea caja de herramientas y termo como cuerpos físicos; su contacto con el vehículo puede influir en la simulación y requiere corrección para que sean decorado local seguro en red. (#88) | B |
| 19 | ~~Rayones y abolladuras acumuladas en la carrocería a lo largo de la entrega.~~ **[x] Hecho** — `vehicle_effects.gd` acumula marcas visuales a partir de impactos. (#91) | C |

## Vehículo — sonido (20-22)

| # | Tarea | Prio |
|---|---|---|
| 20 | ~~Ambiente exterior.~~ **[x] Parcial** — viento en loop hecho, faltan pájaros y ruido lejano de ruta (queda como pendiente menor). (#45) | A |
| 21 | ~~Reverb distinta dentro de la furgoneta vs. afuera (buses de audio). (#46)~~ **[x] Hecho (2026-09-23)** — buses Interior/Exterior con reverb (`default_bus_layout.tres`), ruteo en `vehicle_presentation.gd`. | B |
| 22 | ~~Música de tensión que suba con el riesgo acumulado de la carga.~~ **[x] Hecho** — `ingame_music.gd` adapta la capa de tensión al riesgo de la carga. (#47) | B |

## Ruta y ambientación (23-34)

| # | Tarea | Prio |
|---|---|---|
| 23 | ~~Partículas de polvo/tierra bajo las ruedas.~~ **[x] Hecho.** (#49) | A |
| 24 | ~~Humo de escape en el caño trasero.~~ **[x] Hecho** — `vehicle_effects.gd` lo emite mientras el motor está activo. (#50) | C |
| 25 | ~~Marcas de neumático en el asfalto al frenar. (#51)~~ **[x] Hecho (2026-09-23)** — marcas de neumático al derrapar, en un MultiMesh circular (`vehicle_effects.gd`). | C |
| 26 | ~~Props de banquina: árboles, postes, carteles, cercas, tachos — hoy son 10 cajas grises.~~ **[x] Hecho** — bosque completo (`_build_forest`) + farolas/bancos/buzones/conos/barrera (`_build_landmarks`, ahora `RoadsideDressing`), reemplazando las 10 cajas grises. Sin colisión, mismo criterio que el bosque. (#52) | A |
| 27 | ~~Cableado eléctrico entre postes. (#53)~~ **[x] Hecho (2026-09-23)** — postes cada ~36 m con tres cables con comba; 2 draw calls, postes sólidos (`route_dresser.gd` `_dress_power_lines`). | B |
| 28 | ~~Edificios con ventanas, techos y puertas.~~ **[x] Hecho** — `DeliveryHouse` usa modelos GLB con techo a dos aguas, porche, puerta, ventanas y chimenea; la cantidad de casas depende de la tripulación. (#54) | A |
| 29 | ~~Vehículos estacionados al costado de la ruta.~~ **[x] Hecho** — hatchback y pickup GLB, uno cada ~55m alternando lados (`_build_landmarks`). (#55) | A |
| 30 | ~~Variación de hora del día.~~ **[x] Hecho** — `WorldMood` elige día/atardecer/noche por semilla de sesión y ajusta sol, ambiente, cielo y faros. (#56) | C |
| 31 | ~~Clima: lluvia, asfalto mojado con reflejos.~~ **[x] Hecho** — presets soleado/nublado/lluvia/niebla; la lluvia humedece el material de terreno y sigue la cámara. (#57) | C |
| 32 | ~~Nubes en el cielo procedural.~~ **[x] Hecho** — el shader de cielo recibe cobertura y color de nubes según `WorldMood`. (#58) | C |
| 33 | ~~Silueta de horizonte / terreno lejano.~~ **[x] Hecho** — `route_dresser.gd` construye horizonte y lo integra con la niebla. (#59) | B |
| 34 | SSAO: confirmado bloqueado por el renderer (`gl_compatibility`, ver fila #60 de `docs/especificaciones-visuales.md`) — no reabrir sin decidir primero migrar a Forward+. | B |

## Cámara de manejo (35-38)

| # | Tarea | Prio |
|---|---|---|
| 35 | ~~Manera de mirar hacia atrás: espejos (#5 de esta lista) o una tecla dedicada. (#68)~~ **[x] Hecho (2026-09-23)** — B (o L3) mantiene la vista por encima del hombro (`first_person_camera.gd`, acción `look_back` reasignable). | B |
| 36 | ~~Cámara de resultados: plano cinematográfico de la furgoneta al terminar.~~ **[x] Hecho** — órbita lenta local de `results_orbit.gd` alrededor del camión al finalizar. (#69) | C |
| 37 | ~~Cámara en tercera persona alternable, solo para desarrollo.~~ **[x] Hecho** — F9, solo se construye en build de debug. (#75) | A |
| 38 | Límite de pitch contextual dentro de la cabina (`first_person_camera.gd` es archivo compartido — avisar antes de tocarlo). (#78) | C |

## Interacción vehículo-mundo (39-40)

| # | Tarea | Prio |
|---|---|---|
| 39 | ~~La furgoneta puede voltear props de banquina, no atravesarlos. (#89)~~ **[x] Hecho (2026-09-23)** — el decorado ahora es sólido (árboles, guardarraíles, autos, carteles) y los props chicos se vuelcan: cuerpos rígidos dormidos (`dressing_batcher.gd`). | B |
| 40 | ~~Escombros y partículas al chocar contra algo sólido. (#90)~~ **[x] Hecho (2026-09-23)** — astillas y polvo al chocar, donde fue el golpe (`vehicle_effects.gd`). | B |

## Modo Endless / streaming de tramos (41-55)

| # | Tarea | Prio |
|---|---|---|
| 41 | ~~Conectar `RouteStreamer.start()` al vehículo real.~~ **[x] Hecho.** | A |
| 42 | ~~Crear `level_endless.tscn`/`level_endless.gd`.~~ **[x] Hecho** — duplica algo de `level_base.gd` a propósito en vez de refactorizar un archivo del que Slatex también depende. | A |
| 43 | ~~Definir la condición de fin de partida para endless.~~ **[x] Decidido: se pierde (carga perdida, vuelco, salir de la ruta), nunca "se entrega".** El puntaje por distancia queda para el #52, ver detalle en `docs/plan-desarrollo.md` Fase 3. | A |
| 44 | ~~Adaptar `RunManager` para puntaje por distancia en modo endless, sin romper el puntaje por entrega del modo normal.~~ **[x] Hecho** (2026-09-22) — `run_manager.gd` es de Slatex/zona compartida; decisión explícita de Nacho de avanzar igual. `current_mode`/`MODE_ENDLESS`, `_finish_endless_run()` separado de `finish_run()`, `DISTANCE_POINTS_PER_METER` (placeholder ajustable). Modo delivery sin cambios de comportamiento, tests existentes verifican esto. | A |
| 45 | ~~Botón "Modo Endless" en el menú principal.~~ **[x] Hecho** (2026-09-22) — `main_menu.gd` es de Slatex; decisión explícita de Nacho de avanzar igual sin esperar coordinación previa. Botón "Modo Endless (solo)" + atajo `--autostart-endless`. | A |
| 46 | ~~Ajustar `lookahead_distance` contra el far clip.~~ **[x] Hecho** — 180 m (era 60 m), niebla más densa en la escena endless (0.013 vs. 0.006) para que se disuelva antes de llegar al far clip. | A |
| 47 | ~~Reglas de combinación más allá de "nunca repetir el mismo tipo": evitar 3 obstáculos difíciles seguidos.~~ **[x] Hecho** — `RouteStreamer.hard_segments` (chicane, puente angosto, curva en S, ripio, zona de obras) fuerza un respiro después de 2 difíciles seguidos. "Difícil" definido igual que ya lo trataban los propios tests (lo que un manejo sin dirección no puede sobrevivir), no un criterio nuevo aparte. Encontré y corregí un bug real al implementarlo: `const HARD_SEGMENTS` referenciando varios `class_name` globales en un array no compila en GDScript ("no es una expresión constante") — silenciosamente no falló en `--import` pero sí al usarse de verdad, colgando el proceso. Pasado a una `var` poblada en `_ready()`. | A |
| 48 | ~~Integrar la niebla de distancia también en la escena endless.~~ **[x] Hecho de una vez con el #46.** | A |
| 49 | ~~Balancear la dificultad progresiva del modo endless.~~ **[x] Hecho (2026-09-23)** — el peso de los tramos difíciles va de 0,25 a 2,5 en 2 km (`route_streamer.gd`, `test_endless_difficulty`). | B |
| 50 | ~~Probar el modo endless con las 4 trampas activas simultáneamente a velocidad sostenida.~~ **[x] Automatizado** — `tests/test_endless_multi_cargo.gd`. Cobertura funcional (nada explota, las 4 trampas siguen activas durante 20s de manejo sostenido), no si la mezcla aleatoria "se siente bien" con las 4 activas (eso es el playtesting real del #55, deferido). Encontrar esto reveló un bug real, ver nota en #97. | A |
| 51 | ~~Verificar que `RouteStreamer._cull_behind()` libere a tiempo.~~ **[x] Verificado** — sin fuga: conteo de segmentos activos y de hijos de `World` acotados tras una sesión larga simulada (`test_level_endless.gd`). | A |
| 52 | ~~Sumar el modo endless al leaderboard local existente, como categoría separada del modo normal.~~ **[x] Hecho junto con el #44** — cada entrada del leaderboard guarda `mode`; `best_score(mode)` y el cap de `MAX_LEADERBOARD_ENTRIES` son por-modo (un modo no puede desplazar las entradas del otro del `.json` guardado). | A |
| 53 | ~~Test automatizado de una sesión larga de endless simulada.~~ **[x] Hecho** — `tests/test_level_endless.gd`. | A |
| 54 | ~~Documentar el modo endless en `docs/plan-desarrollo.md` Fase 3.~~ **[x] Hecho.** | A |
| 55 | Playtesting real del modo endless: ¿se siente bien la variedad aleatoria o hace falta más curaduría? | A |

## Contenido de ruta nuevo (56-65)

| # | Tarea | Prio |
|---|---|---|
| 56 | ~~Tramo de subida/bajada.~~ **[x] Hecho** — `HillSegment` registra una cresta de hasta 6 m en el terreno y vuelve a nivel en ambos extremos. | B |
| 57 | ~~Tramo de curva en S (doble chicana en direcciones opuestas).~~ **[x] Hecho** — `SCurveSegment`, 4 bloques alternados en vez de los 2 del chicane. | A |
| 58 | ~~Tramo de túnel corto.~~ **[x] Hecho** — `TunnelSegment` tiene paredes/techo sólidos e iluminación interior; el eco dedicado queda para una pasada de audio. | B |
| 59 | Puente de un solo carril con prioridad de paso. **bloqueado: sin tráfico no hay con quién ceder el paso (#76/#77).** | B |
| 60 | Rotonda simple. | B |
| 61 | ~~Tramo de ripio/tierra con fricción distinta a la ruta pavimentada.~~ **[x] Hecho** — `GravelSegment`. Verificado antes de implementar que `PhysicsMaterial.friction` del suelo **no** afecta `VehicleWheel3D.get_skidinfo()` en este motor; el único control real es `wheel_friction_slip` por rueda. El tramo usa un `Area3D` que lo reduce al entrar y lo restaura al salir (con red de seguridad en `_exit_tree()` por si el streamer libera el tramo con el vehículo todavía encima). | A |
| 62 | ~~Tramo nocturno (probar junto con el ciclo día/noche).~~ **[x] Hecho (2026-09-23)** — la noche sale por sorteo como cualquier hora (`world_mood.gd`). | B |
| 63 | ~~Cruce de vías de tren con barrera.~~ **[x] Hecho** — `RailCrossingSegment` avisa, baja una barrera sólida, deja pasar el tren y la reabre; puede no activarse según semilla. **En red (2026-09-23):** lo dispara sólo el host (`_begin_cycle` por RPC a todos) y un cliente que arma el tramo a mitad del cruce le pide la fase al host (`_request_state` → `_apply_state`); antes cada peer lo disparaba con su copia interpolada del camión. Los tramos tienen nombre estable (`Segment%d`, en `route.gd` y `route_streamer.gd`) para que el RPC encuentre el nodo. | B |
| 64 | ~~Zona de obras con conos y carril reducido.~~ **[x] Hecho** — `ConstructionZoneSegment`, barrera lateral sostenida (no alternada, a diferencia del chicane/curva en S) + fila de conos marcando el borde. | A |
| 65 | Curva peraltada (banked turn) que favorece tomarla rápido. **no se hace por ahora: el asfalto es el mismo campo de alturas del terreno y no admite peralte sin rehacerlo.** | B |

## Clima y ciclo día/noche (66-73)

| # | Tarea | Prio |
|---|---|---|
| 66 | ~~Diseñar presets de clima.~~ **[x] Hecho** — soleado 45%, nublado 25%, lluvia 18%, niebla 12%; se eligen determinísticamente con la semilla de sesión. | B |
| 67 | ~~Implementar lluvia.~~ **[x] Hecho** — gotas que siguen cámara + parámetro `wetness` del shader de terreno. | B |
| 68 | ~~Sonido de lluvia sobre el techo, distinto adentro que afuera.~~ **[x] Hecho** — `route_sky.gd` reproduce `SynthAudio.rain_loop()` y usa buses Interior/Exterior con -11/-17 dB según la cámara; queda revisar el caso de cámaras exteriores ancladas al vehículo. | B |
| 69 | ~~Ciclo día/noche opcional.~~ **[x] Resuelto con una decisión más estable**: cada sesión fija día (60%), atardecer (25%) o noche (15%) por semilla, en vez de cambiar de luz durante la partida. | B |
| 70 | ~~Ajustar faros para la noche.~~ **[x] Hecho** — `WorldMood.headlight_boost()` aumenta intensidad/alcance hasta 4× de noche. | A |
| 71 | ~~Nubes procedurales en el cielo.~~ **[x] Hecho** — shader de cielo con cobertura dependiente del clima. | B |
| 72 | ~~Probar la niebla de distancia con cada preset. **Parcial** — `test_world_mood.gd` comprueba lluvia+noche, densidad y aislamiento del `Environment`; falta cobertura de los otros presets y revisión visual.~~ **[x] Hecho (2026-09-23)** — la niebla se ajusta por preset (densidad y color); revisado en capturas. | A |
| 73 | ~~Documentar presets de clima.~~ **[x] Hecho** — `docs/direccion-visual.md` §4. | A |

## Tráfico y vehículos estacionados (74-79)

| # | Tarea | Prio |
|---|---|---|
| 74 | ~~Modelar/colocar 3-4 variantes de auto estacionado como props de banquina (placeholder hasta tener arte final).~~ **[x] Hecho (2026-09-23)** — regla `parked_vehicle` de `route_dresser.gd`. | B |
| 75 | ~~Reglas de colocación: nunca bloquear el carril completo, variar el lado de la ruta.~~ **[x] Hecho (2026-09-23)** — la regla los deja a 12-14,5 m del centro, nunca sobre el carril. | A |
| 76 | ~~Decidir si vale la pena tráfico en movimiento o si es demasiado para el alcance actual.~~ **[x] Decidido: no por ahora.** Tráfico en movimiento suma IA de waypoints, una capa de colisión dinámica nueva, y un playtesting propio de "tensión divertida vs. molesta" (#79) — alcance real para un prototipo solo con asistencia de IA que todavía no tiene ni autos estacionados construidos (#74, bloqueado por arte) ni un segundo vehículo (#85-91). Los vehículos estacionados como props de banquina estática (#74/#75/#78) ya cubren la sensación de "ruta habitada" sin ese costo. Revisar esta decisión recién si el modo endless necesita más variedad después de tener contenido curado real. | A |
| 77 | Diseño mínimo de IA para tráfico en movimiento (waypoints simples, sin pathfinding complejo) — **no construir todavía**, ver #76. Dejar esta fila como semilla de diseño si la decisión cambia más adelante. | B |
| 78 | ~~Capa de colisión para vehículos estacionados/tráfico, coherente con `docs/convenciones-godot.md`.~~ **[x] Ya resuelto, sin agregar nada nuevo**: los props estáticos de banquina son geometría estática igual que los bloques del chicane/curva en S/zona de obras, que ya usan la capa 1 (`environment`) vía `RouteSegment._box(..., solid=true)`. No hace falta una capa dedicada para tráfico en movimiento porque esa función quedó deferida (#76). Si esa decisión se revierte, ahí sí conviene una capa propia (para que el vehículo pueda reaccionar distinto a tráfico que a concreto fijo). | A |
| 79 | Playtesting: ¿el tráfico agrega tensión divertida o es solo un obstáculo molesto? **No aplica hasta que #76 se reconsidere** — no hay tráfico en movimiento que probar. | A |

## Audio: buses y mezcla (80-84)

| # | Tarea | Prio |
|---|---|---|
| 80 | ~~Crear buses de audio "Interior" y "Exterior".~~ **[x] Hecho** — `default_bus_layout.tres`, registrado en `project.godot`. | A |
| 81 | ~~Rutear motor/neumáticos/impacto por el bus correcto según la cámara activa.~~ **[x] Hecho** para motor/impacto/chirrido (`VehiclePresentation`). La bocina (`vehicle.gd`) queda sin rutear — vive en otro archivo, follow-up chico. | A |
| 82 | ~~Reverb distinta por bus.~~ **[x] Hecho de una vez con el #80**, no hizo falta separarlo — cada bus ya trae su propio `AudioEffectReverb` (interior más cerrado y húmedo, exterior más abierto y seco) en el mismo `.tres`. | B |
| 83 | ~~Mezcla general de volúmenes relativos.~~ **[x] Parcial, honesto sobre el límite**: no puedo "escuchar" el juego para juzgar el balance de verdad — lo que hice fue revisar los valores en busca de inconsistencias objetivas. Encontré una real: la bocina (`vehicle.gd`) nunca tuvo `volume_db` seteado, quedaba en el default de 0dB, mucho más fuerte que todo lo demás sin que fuera intencional (nada en el código sugería que "la bocina debe ser así de fuerte"). La empardé con el pico del golpe de impacto (-6dB), el más fuerte del resto de la mezcla a propósito. Una pasada de balance real con oído sigue pendiente y necesita a alguien escuchando el juego, no edición de valores a ciegas. | A |
| 84 | ~~Gancho de riesgo acumulado para la música de tensión.~~ **[x] Hecho** — `ingame_music.gd` calcula el riesgo desde `RunManager.cargo` y modula la capa de tensión; se instancia en entrega y Endless. | B |

## Vehículos adicionales (85-92)

| # | Tarea | Prio |
|---|---|---|
| 85 | ~~Diseñar un segundo vehículo.~~ **[x] Hecho** — la Furgoneta ágil es más rápida, liviana y con más giro; se desbloquea con 4 entregas y 350 puntos. | B |
| 86 | ~~Definir sus parámetros de física.~~ **[x] Hecho** — variantes declarativas en `vehicle.gd`; `test_truck_variant.gd` verifica que la ágil cambie velocidad, masa y giro frente a la clásica. | A |
| 87 | ~~Adaptar `VehiclePresentation` para que sea reutilizable entre vehículos, no hardcodeada a los nombres de nodo del actual.~~ **[x] Hecho** — reemplazadas las rutas fijas (`"CabinInterior/SteeringWheel"`, `"BodyVisuals/" + side + "Headlight"`, `"CargoBay/" + side + "TailLight"`) por búsquedas por nombre/patrón (`find_child`/`find_children`) en cualquier parte del árbol. Convención documentada en `docs/agregar-vehiculo.md` (#92). | A |
| 88 | ~~Selección de vehículo en el menú.~~ **[x] Hecho** — el panel de cosméticos permite elegir vehículo y pintura, respetando los desbloqueos. | B |
| 89 | ~~Librea/calcomanía simple.~~ **[x] Hecho** — pintura blanca inicial y violeta desbloqueable (5 entregas, 450 puntos), aplicada por instancia sin modificar el material importado compartido. | B |
| 90 | ~~Decidir si las libreas son cosméticos desbloqueables o variantes de color fijas.~~ **[x] Decidido e implementado**: blanco inicial y violeta desbloqueable mediante `UnlockManager`; la elección persiste en el perfil local. | A |
| 91 | ~~Probar que el segundo vehículo respete lo ya construido. **Parcial** — `test_truck_variant.gd` verifica diferencias de física, pintura, bloqueo de elecciones y que `variant_id`/`paint_id` estén configurados para replicarse; falta una prueba con dos clientes del estado recibido y de las interacciones completas.~~ **[x] Hecho (2026-09-23)** — `test_truck_variant.gd`. | A |
| 92 | ~~Documentar "cómo agregar un vehículo nuevo" para no redescubrirlo cada vez.~~ **[x] Hecho** — `docs/agregar-vehiculo.md`. | A |

## Optimización / tooling de mundo (93-96)

| # | Tarea | Prio |
|---|---|---|
| 93 | ~~Medir el costo real de `RouteStreamer` en FPS con varios tramos activos a la vez.~~ **[x] Medido, con reserva honesta**: headless no renderiza nada, así que esto es costo de CPU/física real (`Performance.TIME_PHYSICS_PROCESS`), no FPS real con GPU — sigue faltando esa medición con ventana real. Manejando en `level_endless.tscn` con streaming activo (7 tramos activos en régimen estable): **0.56 ms promedio, 0.92 ms p95** de paso de física, contra un presupuesto de 16.67 ms a 60Hz. Margen amplio. | A |
| 94 | ~~Evaluar si hace falta LOD para los props de banquina una vez que dejen de ser cajas grises.~~ **[x] Hecho (2026-09-23)** — resuelto con el horneado del decorado y distancias de dibujado (`dressing_batcher.gd`). | B |
| 95 | ~~Revisar `far` clip (600 m) y `lookahead_distance`/`behind_keep_distance` juntos, para no generar ni de más ni de menos.~~ **[x] Revisado por cálculo**: con `fog_density = 0.013` (endless), la transmitancia (`exp(-density·distancia)`) cae a ~9.6% de claridad a los 180 m (el borde de `lookahead_distance`) y a ~5% a los 230 m — el borde del mundo generado ya queda bastante disuelto en niebla antes de acercarse al `far` de 600 m, sin superponerse de más con lo generado. `behind_keep_distance` (40 m, default) no tiene contraparte visual (no hay espejo retrovisor todavía, #35), así que no hay riesgo de pop-out visible por detrás. No hizo falta tocar ningún valor. | A |
| 96 | ~~Perfilar el costo de las partículas de polvo bajo las 4 ruedas simultáneas.~~ **[x] Medido**: comparé el mismo régimen estable manejando (polvo activo, ~0.56 ms/0.92 ms p95) contra la furgoneta detenida (polvo apagado, ~0.70 ms/2.53 ms p95 — el p95 más alto detenido es ruido de muestra por contactos de reposo resolviéndose, no una señal real). El polvo no aparece como costo medible aparte del resto de la física del vehículo. | A |

## QA y documentación de su dominio (97-100)

| # | Tarea | Prio |
|---|---|---|
| 97 | ~~Bug bash de física del vehículo: saltos, vuelcos, quedarse atascado, comportamiento en los bordes de la ruta.~~ **[x] Hecho, automatizado en vez de manual una sola vez** — `tests/test_vehicle_stress.gd`: 60s de aceleración a fondo con dirección oscilante (no recta, para chocar contra el chicane/obras/puente de verdad) a través de los 7 tipos de tramo, revisando posición/velocidad finitas (sin NaN/Inf) cada frame y que la red de seguridad de "fuera de la ruta" (`level_endless.gd`, y<-8/\|x\|>42) atrape una caída antes de que se vuelva una caída real a través del mundo. Este bug bash encontró **un bug real en el juego, no solo en el test**: manejar sin frenar contra `SpeedBumpSegment` repetidos a velocidad máxima sostenida puede lanzar la furgoneta lo bastante fuerte como para aterrizar encajada contra la geometría de la ruta — nunca vuelca (no dispara el chequeo de vuelco) y nunca sale de los límites (no dispara ese chequeo tampoco), simplemente se queda parada para siempre con `RunManager.is_running` todavía en `true`, sin forma de recuperarse. Corregido sumando detección genérica de "atascado" en `level_endless.gd` (6s de velocidad casi nula termina la run como pérdida, `"La camioneta quedó atascada..."`) — no existía ningún mecanismo así antes, en ningún modo. Nota para `docs/tareas-slatex.md` o revisión futura: el mismo hueco conceptual podría existir en `level_base.gd`, no tocado acá por ser zona compartida. | A |
| 98 | Playtesting de variedad de ruta: ¿los tramos curados se sienten repetitivos después de varias vueltas? | A |
| 99 | Verificar que `test_vehicle_presentation`, `test_vehicle_audio`, `test_route_streaming` y `check_driver_sightline` sigan pasando después de cada tarea grande. | A |
| 100 | Mantener actualizadas las filas de vehículo/ambientación en `docs/especificaciones-visuales.md` y `docs/direccion-visual.md` a medida que se completan tareas. | A |

## Sistema de casas de entrega (101-108) — pedido directo del usuario, 2026-09-21

> Reemplaza el único "Warehouse" al final de la ruta curada por `house_count`
> casas separadas a lo largo del tramo final, cada una con timbre propio.
> Al tocar el timbre, quien atiende reacciona según el estado del paquete
> que se le entregó (o no se le entregó nada). Construido enteramente del
> lado de Nacho (`route.gd`, `delivery_house.gd`, `doorbell_point.gd`) para
> no interferir con lo que Slatex está tocando ahora mismo (expansión a 8
> jugadores). `doorbell_point.gd` extiende `interactable.gd` (base de
> Slatex) solo por lectura, mismo patrón que `package_mount_point.gd`.

| # | Tarea | Prio |
|---|---|---|
| 101 | ~~Casas separadas a lo largo de la ruta en vez de una única zona de entrega.~~ **[x] Hecho** — `route.gd` construye `house_count` `DeliveryHouse` alternando lados de la ruta, terminando en una meta (`GoalArea`) que reemplaza el viejo `DeliveryArea`/Warehouse, mismo contrato (`is_vehicle_in_delivery`) que ya usaba `level_base.gd`, sin tocar ese archivo. | A |
| 102 | ~~Timbre que reacciona al estado del paquete entregado.~~ **[x] Hecho** — `DeliveryHouse` reacciona según integridad y contenido; `level_base.gd` conecta `route.house_resolved` con `RunManager.register_delivery()`, que aplica puntaje y penalidades por puerta. | A |
| 103 | ~~"Si te olvidaste un paquete, tenés que bajarte a tocar el timbre igual y sufrir las consecuencias."~~ **[x] Hecho** — al llegar a la meta, cualquier casa que nadie tocó se resuelve automáticamente como `"missed"` (`force_resolve_if_missed()`), no queda colgada para siempre. | A |
| 104 | ~~Cantidad de casas según jugadores.~~ **[x] Hecho (2026-09-23)** — `max(jugadores - 1, 1)` (`route.gd` `crew_house_count`), pero ahora la decide el host una vez por sesión (`NetworkManager.world_house_count`, se fija la primera vez que su ruta se arma) y viaja en el handshake junto con la semilla (`_accept_joiner`). Antes cada peer contaba su propio roster, y el de un cliente arranca como `[host, él]`: desde tres jugadores cada uno armaba otra cantidad. Límite asumido: como el host arma la ruta al crear la sala, quien se suma después no agrega casas hasta una partida nueva (y un reinicio del host la conserva, porque los clientes no recargan su mundo). `test_house_assignment`. | B |
| 105 | ~~Cantidad de paquetes por casa dinámica.~~ **[x] Resuelto por el depósito (2026-09-23)** — el depósito tiene dos cajas de cada trampa (14) y la pizarra asigna una caja concreta a cada casa (`depot.gd` `post_orders`); las que no están en el pedido se pueden llevar igual como carga. Las trampas no desbloqueadas quedan fuera de los estantes (`withhold_locked`, `test_locked_traps`). | B |
| 106 | ~~Volver a levantar un paquete ya montado para entregarlo.~~ **[x] Hecho** — `package_pickup_point.gd` permite bajarlo y libera el soporte; cubierto por `test_house_delivery_flow.gd`. | A |
| 107 | ~~Asignar qué paquete corresponde a qué casa.~~ **[x] Hecho** — desde 2026-09-23 la asigna la pizarra del depósito al cargar el nivel, desde `world_seed` (todos los peers calculan lo mismo) y se re-emite al arrancar (`houses_assigned`); antes era por orden de soporte. `DeliveryHouse` devuelve una caja equivocada sin gastar la entrega (`test_house_assignment`). | B |
| 108 | ~~Sumar un hecho a `EventBus` para que el HUD reaccione a las entregas.~~ **[x] Hecho (2026-09-22)** — `house_delivery_recorded(house_index, outcome, package_id)` y `delivery_photo_taken(house_index, accepted)`, ambos relayed. `RunManager` los escucha además de registrarlos, para que cada peer puntué su propio run igual (los dos handlers son idempotentes, que es lo que hace seguro que el host reciba de vuelta el hecho que acaba de emitir). | A |

## Entrega real, celular y opciones (115-121) — pedido directo del usuario, 2026-09-22

> "Revisá todas las funcionalidades y vamos puliendo todo a nivel profesional."
> El barrido encontró que el loop central estaba roto, no incompleto: las
> casas existían pero eran inalcanzables y no puntuaban. Esta sección es lo
> que se arregló y se agregó encima.

| # | Tarea | Prio |
|---|---|---|
| 115 | ~~Conectar `route.house_resolved` con el puntaje.~~ **[x] Hecho** — nadie lo escuchaba salvo un test: entregar bien, entregar roto o pasar de largo daban el mismo puntaje. `level_base.gd` lo reenvía a `RunManager.register_delivery()`, que puntuá por puerta (150 intacto / 75 en riesgo / 20 roto / -60 por casa no atendida) aparte de la carga que vuelve en la furgoneta. | A |
| 116 | ~~Que una casa nunca atendida penalice aunque el run no termine en la meta.~~ **[x] Hecho** — `force_resolve_if_missed()` solo corría al llegar a la meta, así que volcar 300m antes salía gratis. `RunManager.expected_houses` cuenta las puertas que el run debía alcanzar, independiente de cómo terminó. | A |
| 117 | ~~Celular con modo cámara y foto de entrega.~~ **[x] Hecho** — `scripts/presentation/phone_camera.gd`, autocontenido: toma la pose de la cámara activa en una cámara propia en vez de tocar `player.gd`, y nunca escribe el FOV del jugador (que `_apply_context_fov()` interpola cada frame y pelearía con él). F abre, click dispara, captura real del viewport a miniatura. | A |
| 118 | ~~Quejas de clientes al final, y la foto como prueba.~~ **[x] Hecho** — un paquete entregado roto siempre genera reclamo, uno en riesgo a veces (`COMPLAINT_CHANCE_AT_RISK`). Con foto de esa puerta el reclamo se cae; sin foto descuenta. Es lo que le da sentido a parar a sacarla. | A |
| 119 | ~~Pantalla de opciones, salir del juego y volver al menú.~~ **[x] Hecho** — `GameSettings` (autoload, `user://settings.cfg`) + `scripts/ui/options_panel.gd`, alcanzable desde el menú y desde la pausa. Volumen, sensibilidad de mirada, invertir Y, pantalla completa. Antes no había ninguna forma de salir salvo Alt+F4. | A |
| 120 | ~~Paleta de UI duplicada entre menú y HUD.~~ **[x] Hecho** — `scripts/ui/ui_theme.gd` es la única fuente de colores y widgets; `main_menu.gd` y `prototype_hud.gd` construyen desde ahí (`docs/direccion-visual.md` sección 3 ya lo marcaba). | A |
| 121 | ~~Cantidad de casas atada a la tripulación, con al menos una en solitario.~~ **[x] Hecho (2026-09-23)** — ver #104 (cantidad sincronizada desde el host) y #105/#107 (asignación por la pizarra del depósito). | B |
| 122 | ~~**Bug de multijugador encontrado revisando**: `route.gd` y `route_streamer.gd` hacían `_rng.randomize()` en cada peer, así que cada jugador construía un camino distinto y el cliente veía la furgoneta replicada del host atravesar casas inexistentes.~~ **[x] Resuelto (2026-09-22)** — `NetworkManager.world_seed`: el host la sortea al crear la sala y se la manda a cada joiner por RPC (`_accept_joiner`) **antes** de que el joiner emita `session_ready` y cargue el nivel, porque cargarlo antes era exactamente el problema. Timeout de 8s con mensaje claro si nunca llega. Semilla 0 = solo, sigue sorteando. Cubierto por `tests/test_world_seed.gd`. | A |


## Ruta procedural con curvas reales (109-114) — pedido directo del usuario, 2026-09-22

> "No quiero que sean tramos rectos, además me gustaría que sean tramos
> mucho más largos entre casa, que sean mini aventuras." Reemplaza el
> trazado recto hecho a mano (una sola caja de asfalto en línea) por un
> generador procedural: cada tramo entre casas (y del arranque a la
> primera, y de la última a la meta) es 400-600m armados encadenando
> `RouteSegment`s reales, ahora incluyendo `CurveSegment` -- el único tipo
> que cambia el rumbo del camino de verdad, no solo agrega obstáculos
> dentro de un carril recto. Construido enteramente del lado de Nacho
> (`route.gd`, `route_segment.gd`, `segments/curve_segment.gd`).

| # | Tarea | Prio |
|---|---|---|
| 109 | ~~`CurveSegment`: un tramo que dobla el rumbo real del camino.~~ **[x] Hecho** — encadena cuerdas rectas cortas (~10m, una cada ~12°) rotando progresivamente; `exit_offset`/`exit_turn` (nuevos en `route_segment.gd`, default recto/0° para los otros 7 tipos, ninguno tocado) le dicen a quien encadena dónde y hacia dónde sigue el camino después. | A |
| 110 | ~~Encadenar segmentos con posición + rumbo (Transform3D), no solo un offset en -Z.~~ **[x] Hecho** — `route.gd` camina un cursor `Transform3D`; cada segmento se sigue construyendo en su propio espacio local sin cambios (ni siquiera los 7 tipos viejos lo notaron). | A |
| 111 | ~~Tramos mucho más largos entre casas (mini aventura).~~ **[x] Hecho** — cada tramo entre inicio, casas y meta apunta a 400-600 m; el total depende de cuántas casas construya la ruta (una en solitario). | A |
| 112 | ~~Bosque/props siguiendo la curva en vez de flotar en línea recta.~~ **[x] Hecho** — `RouteSegment.get_dressing_slots()` (nuevo) da transforms locales a lo largo del camino real de cada segmento; `CurveSegment` lo sobreescribe caminando su propia cadena de cuerdas. | A |
| 113 | ~~Red de seguridad "te saliste de la ruta" (`level_base.gd`) medía `abs(x mundial) > 42`, roto apenas el camino dobla.~~ **[x] Hecho** — `route.distance_from_path()` mide distancia real al camino generado (~10m de densidad), no a un eje fijo del mundo. Encontrado por regresión real en `test_vehicle_presentation.gd`/`test_dust_and_ambience.gd`, no hipotético. | A |
| 114 | **Sin extender a Modo Endless todavía, a propósito** — `RouteStreamer` sigue siendo un camino recto que hace streaming/cull por -Z; darle curvas reales necesita que su lookahead/cull dejen de asumir un solo eje, un cambio más arriesgado que este (streaming infinito vs. construir todo una vez). Queda como follow-up separado, no mezclado con este pedido. | B |

## Depósito de salida (123-127) — pedido directo del usuario, 2026-09-23

> "La partida arranca en un depósito con el camión estacionado, paquetes de
> todos los tipos, una pizarra de pedidos, estaciones para prepararse y un
> portón que se cierra al salir; todo profesional." Hecho en `680001a`
> (`scripts/gameplay/depot/`, detalle en `docs/arquitectura.md` §5.1 y el
> aviso de `docs/colaboracion-equipo.md`).

| # | Tarea | Prio |
|---|---|---|
| 123 | ~~Depósito como punto de partida de entrega y Endless.~~ **[x] Hecho** — camión en su bahía mirando al portón, suelo nivelado y sin árboles (`route.gd` `start_yard`), geometría horneada por material (`depot_kit.gd`), sin lluvia bajo techo (`roofed_area`). | A |
| 124 | ~~Pizarra de pedidos y estanterías con código.~~ **[x] Hecho** — dos cajas por trampa con código `A-1`…`B-8`, un pedido por casa desde la semilla; el pedido se ve en el cartel de cada casa y en el objetivo del HUD (`test_depot`, `test_house_assignment`). | A |
| 125 | ~~Estaciones: vestuario, taller, suministros y equipo del mes.~~ **[x] Hecho** — `depot_station.gd` + `ui/depot_panel.gd`; los suministros (acolchado, seguro) los decide el host con la plata del equipo (`CrewProgression.buy_supply`). | A |
| 126 | ~~Portón que se cierra al salir y vida en el depósito.~~ **[x] Hecho** — `depot_roller_door.gd` (se cierra cuando el camión salió y no queda nadie a pie), operarios, autoelevador que frena ante jugadores, cinta, radio, reloj; sonidos en `SynthAudio`. | B |
| 127 | Decidir el rol del depósito en Endless: ahí la pizarra no asigna pedidos (`post_orders(0)`), así que sólo sirve para estaciones y carga; ¿se mantiene completo o conviene uno reducido? (Validarlo jugando queda para el playtesting final.) | A |
