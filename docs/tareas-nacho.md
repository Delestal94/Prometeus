# Tareas de Nacho — Vehículo, Ruta y Ambientación

> Última actualización: 2026-09-21 (curva en S, ripio y zona de obras sumadas)
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
| 1 | Silueta real de la furgoneta: biselar aristas, inclinar la trompa, proporciones de vehículo real, no dos cajas apiladas. (#5) | B |
| 2 | Guardabarros / arcos de rueda que contengan las ruedas, hoy flotan junto a un panel plano. (#6) | B |
| 3 | Neumático con dibujo y llanta diferenciada del caucho. (#7) | B |
| 4 | Líneas de paneles y juntas de puertas en la carrocería. (#8) | B |
| 5 | Espejos retrovisores laterales — correctos y que encuadren bien el plano en primera persona. (#9) | B |
| 6 | Puertas traseras reales en la zona de carga, hoy `Tailgate` es una caja fija. (#10) | B |
| 7 | Mampara entre cabina y zona de carga — hoy son dos volúmenes sin nada que los separe visualmente. (#11) | B |
| 8 | Tablero completo: instrumentos, rejillas de ventilación, guantera, palanca de cambios. (#12) | B |
| 9 | Pedales, visibles al mirar hacia abajo desde el asiento del conductor. (#14) | C |
| 10 | Asientos con apoyacabezas y estructura real, hoy son dos cajas. (#15) | B |
| 11 | Cinturones de seguridad. (#16) | C |

## Vehículo — comportamiento visual y físico (12-16)

| # | Tarea | Prio |
|---|---|---|
| 12 | ~~Balanceo de carrocería exagerado en curvas y frenadas.~~ **[x] Hecho** (#21, ver detalle en `docs/especificaciones-visuales.md`). | A |
| 13 | Aberración cromática breve en impactos muy fuertes. (#72) | C |
| 14 | Motion blur por velocidad, sutil. (#73) | C |
| 15 | Evitar que la cámara atraviese geometría cercana al mirar en diagonal dentro de la cabina (fade o retroceso). (#80) | B |
| 16 | ~~La furgoneta se hunde levemente según el peso total de la carga.~~ **[x] Hecho** — no hizo falta coordinar con Slatex, `mass` de `package.gd` ya era legible desde el grupo `cargo` sin tocar ese archivo. (#96) | A |

## Vehículo — detalle interior/exterior (17-19)

| # | Tarea | Prio |
|---|---|---|
| 17 | Si la puerta trasera está abierta, la carga suelta puede salirse. (#87) | B |
| 18 | Objetos sueltos en la zona de carga que traqueteen con los golpes (herramientas, un termo). (#88) | B |
| 19 | Rayones y abolladuras acumuladas en la carrocería a lo largo de la entrega. (#91) | C |

## Vehículo — sonido (20-22)

| # | Tarea | Prio |
|---|---|---|
| 20 | ~~Ambiente exterior.~~ **[x] Parcial** — viento en loop hecho, faltan pájaros y ruido lejano de ruta (queda como pendiente menor). (#45) | A |
| 21 | Reverb distinta dentro de la furgoneta vs. afuera (buses de audio). (#46) | B |
| 22 | Música de tensión que suba con el riesgo acumulado de la carga. (#47) | B |

## Ruta y ambientación (23-34)

| # | Tarea | Prio |
|---|---|---|
| 23 | ~~Partículas de polvo/tierra bajo las ruedas.~~ **[x] Hecho.** (#49) | A |
| 24 | Humo de escape en el caño trasero. (#50) | C |
| 25 | Marcas de neumático en el asfalto al frenar. (#51) | C |
| 26 | Props de banquina: árboles, postes, carteles, cercas, tachos — hoy son 10 cajas grises. (#52) | B |
| 27 | Cableado eléctrico entre postes. (#53) | B |
| 28 | Edificios con ventanas, techos y puertas — hoy son cajas grises lisas. (#54) | B |
| 29 | Vehículos estacionados al costado de la ruta. (#55) | B |
| 30 | Variación de hora del día — el sol está fijo en un solo ángulo. (#56) | C |
| 31 | Clima: lluvia, asfalto mojado con reflejos. (#57) | C |
| 32 | Nubes en el cielo procedural — hoy es un degradé liso. (#58) | C |
| 33 | Silueta de horizonte / terreno lejano. (#59) | B |
| 34 | SSAO: confirmado bloqueado por el renderer (`gl_compatibility`, ver fila #60 de `docs/especificaciones-visuales.md`) — no reabrir sin decidir primero migrar a Forward+. | B |

## Cámara de manejo (35-38)

| # | Tarea | Prio |
|---|---|---|
| 35 | Manera de mirar hacia atrás: espejos (#5 de esta lista) o una tecla dedicada. (#68) | B |
| 36 | Cámara de resultados: plano cinematográfico de la furgoneta al terminar. (#69) | C |
| 37 | ~~Cámara en tercera persona alternable, solo para desarrollo.~~ **[x] Hecho** — F9, solo se construye en build de debug. (#75) | A |
| 38 | Límite de pitch contextual dentro de la cabina (`first_person_camera.gd` es archivo compartido — avisar antes de tocarlo). (#78) | C |

## Interacción vehículo-mundo (39-40)

| # | Tarea | Prio |
|---|---|---|
| 39 | La furgoneta puede voltear props de banquina, no atravesarlos. (#89) | B |
| 40 | Escombros y partículas al chocar contra algo sólido. (#90) | B |

## Modo Endless / streaming de tramos (41-55)

| # | Tarea | Prio |
|---|---|---|
| 41 | ~~Conectar `RouteStreamer.start()` al vehículo real.~~ **[x] Hecho.** | A |
| 42 | ~~Crear `level_endless.tscn`/`level_endless.gd`.~~ **[x] Hecho** — duplica algo de `level_base.gd` a propósito en vez de refactorizar un archivo del que Slatex también depende. | A |
| 43 | ~~Definir la condición de fin de partida para endless.~~ **[x] Decidido: se pierde (carga perdida, vuelco, salir de la ruta), nunca "se entrega".** El puntaje por distancia queda para el #52, ver detalle en `docs/plan-desarrollo.md` Fase 3. | A |
| 44 | Adaptar `RunManager` para puntaje por distancia en modo endless, sin romper el puntaje por entrega del modo normal (coordinar con Slatex, que es dueño de la UI de resultados). | B |
| 45 | Botón "Modo Endless" en el menú principal — `main_menu.gd` es de Slatex, coordinar antes de tocarlo. | A |
| 46 | ~~Ajustar `lookahead_distance` contra el far clip.~~ **[x] Hecho** — 180 m (era 60 m), niebla más densa en la escena endless (0.013 vs. 0.006) para que se disuelva antes de llegar al far clip. | A |
| 47 | Reglas de combinación más allá de "nunca repetir el mismo tipo": evitar 3 obstáculos difíciles seguidos. Más urgente ahora que el pool default de `RouteStreamer` creció a 7 tipos (#57, #61, #64 sumados). | B |
| 48 | ~~Integrar la niebla de distancia también en la escena endless.~~ **[x] Hecho de una vez con el #46.** | A |
| 49 | Balancear la dificultad progresiva del modo endless. | B |
| 50 | ~~Probar el modo endless con las 4 trampas activas simultáneamente a velocidad sostenida.~~ **[x] Automatizado** — `tests/test_endless_multi_cargo.gd`. Cobertura funcional (nada explota, las 4 trampas siguen activas durante 20s de manejo sostenido), no si la mezcla aleatoria "se siente bien" con las 4 activas (eso es el playtesting real del #55, deferido). Encontrar esto reveló un bug real, ver nota en #97. | A |
| 51 | ~~Verificar que `RouteStreamer._cull_behind()` libere a tiempo.~~ **[x] Verificado** — sin fuga: conteo de segmentos activos y de hijos de `World` acotados tras una sesión larga simulada (`test_level_endless.gd`). | A |
| 52 | Sumar el modo endless al leaderboard local existente, como categoría separada del modo normal (coordinar con Slatex, dueño de `run_manager.gd` en la zona compartida). | B |
| 53 | ~~Test automatizado de una sesión larga de endless simulada.~~ **[x] Hecho** — `tests/test_level_endless.gd`. | A |
| 54 | ~~Documentar el modo endless en `docs/plan-desarrollo.md` Fase 3.~~ **[x] Hecho.** | A |
| 55 | Playtesting real del modo endless: ¿se siente bien la variedad aleatoria o hace falta más curaduría? | A |

## Contenido de ruta nuevo (56-65)

| # | Tarea | Prio |
|---|---|---|
| 56 | Tramo de subida/bajada (pendiente) — afecta el manejo y la trampa de Peso Creciente distinto que uno plano. | B |
| 57 | ~~Tramo de curva en S (doble chicana en direcciones opuestas).~~ **[x] Hecho** — `SCurveSegment`, 4 bloques alternados en vez de los 2 del chicane. | A |
| 58 | Tramo de túnel corto (oscuridad parcial, eco de audio distinto). | B |
| 59 | Puente de un solo carril con prioridad de paso. | B |
| 60 | Rotonda simple. | B |
| 61 | ~~Tramo de ripio/tierra con fricción distinta a la ruta pavimentada.~~ **[x] Hecho** — `GravelSegment`. Verificado antes de implementar que `PhysicsMaterial.friction` del suelo **no** afecta `VehicleWheel3D.get_skidinfo()` en este motor; el único control real es `wheel_friction_slip` por rueda. El tramo usa un `Area3D` que lo reduce al entrar y lo restaura al salir (con red de seguridad en `_exit_tree()` por si el streamer libera el tramo con el vehículo todavía encima). | A |
| 62 | Tramo nocturno (probar junto con el ciclo día/noche). | B |
| 63 | Cruce de vías de tren con barrera (parada forzada ocasional). | B |
| 64 | ~~Zona de obras con conos y carril reducido.~~ **[x] Hecho** — `ConstructionZoneSegment`, barrera lateral sostenida (no alternada, a diferencia del chicane/curva en S) + fila de conos marcando el borde. | A |
| 65 | Curva peraltada (banked turn) que favorece tomarla rápido. | B |

## Clima y ciclo día/noche (66-73)

| # | Tarea | Prio |
|---|---|---|
| 66 | Diseñar 3-4 presets de clima (soleado, nublado, lluvia leve, niebla densa) como variaciones del `Environment` actual. | B |
| 67 | Implementar lluvia: partículas simples + asfalto mojado con más reflejo especular. | B |
| 68 | Sonido de lluvia sobre el techo, distinto adentro que afuera (coordinar con la sección de audio). | B |
| 69 | Ciclo día/noche opcional, interpolando `DirectionalLight3D` y los colores del cielo a lo largo de una partida larga (relevante para endless). | B |
| 70 | Ajustar los faros ya implementados para que se sientan necesarios de noche, no solo decorativos. | A |
| 71 | Nubes procedurales en el cielo. | B |
| 72 | Probar la niebla de distancia combinada con cada preset de clima. | A |
| 73 | Documentar los presets de clima en `docs/direccion-visual.md`. | A |

## Tráfico y vehículos estacionados (74-79)

| # | Tarea | Prio |
|---|---|---|
| 74 | Modelar/colocar 3-4 variantes de auto estacionado como props de banquina (placeholder hasta tener arte final). | B |
| 75 | Reglas de colocación: nunca bloquear el carril completo, variar el lado de la ruta. | A |
| 76 | ~~Decidir si vale la pena tráfico en movimiento o si es demasiado para el alcance actual.~~ **[x] Decidido: no por ahora.** Tráfico en movimiento suma IA de waypoints, una capa de colisión dinámica nueva, y un playtesting propio de "tensión divertida vs. molesta" (#79) — alcance real para un prototipo solo con asistencia de IA que todavía no tiene ni autos estacionados construidos (#74, bloqueado por arte) ni un segundo vehículo (#85-91). Los vehículos estacionados como props de banquina estática (#74/#75/#78) ya cubren la sensación de "ruta habitada" sin ese costo. Revisar esta decisión recién si el modo endless necesita más variedad después de tener contenido curado real. | A |
| 77 | Diseño mínimo de IA para tráfico en movimiento (waypoints simples, sin pathfinding complejo) — **no construir todavía**, ver #76. Dejar esta fila como semilla de diseño si la decisión cambia más adelante. | B |
| 78 | Capa de colisión para vehículos estacionados/tráfico, coherente con `docs/convenciones-godot.md`. Aplica igual a los props estáticos de #74 aunque el tráfico en movimiento (#76) esté deferido. | A |
| 79 | Playtesting: ¿el tráfico agrega tensión divertida o es solo un obstáculo molesto? **No aplica hasta que #76 se reconsidere** — no hay tráfico en movimiento que probar. | A |

## Audio: buses y mezcla (80-84)

| # | Tarea | Prio |
|---|---|---|
| 80 | ~~Crear buses de audio "Interior" y "Exterior".~~ **[x] Hecho** — `default_bus_layout.tres`, registrado en `project.godot`. | A |
| 81 | ~~Rutear motor/neumáticos/impacto por el bus correcto según la cámara activa.~~ **[x] Hecho** para motor/impacto/chirrido (`VehiclePresentation`). La bocina (`vehicle.gd`) queda sin rutear — vive en otro archivo, follow-up chico. | A |
| 82 | ~~Reverb distinta por bus.~~ **[x] Hecho de una vez con el #80**, no hizo falta separarlo — cada bus ya trae su propio `AudioEffectReverb` (interior más cerrado y húmedo, exterior más abierto y seco) en el mismo `.tres`. | B |
| 83 | ~~Mezcla general de volúmenes relativos.~~ **[x] Parcial, honesto sobre el límite**: no puedo "escuchar" el juego para juzgar el balance de verdad — lo que hice fue revisar los valores en busca de inconsistencias objetivas. Encontré una real: la bocina (`vehicle.gd`) nunca tuvo `volume_db` seteado, quedaba en el default de 0dB, mucho más fuerte que todo lo demás sin que fuera intencional (nada en el código sugería que "la bocina debe ser así de fuerte"). La empardé con el pico del golpe de impacto (-6dB), el más fuerte del resto de la mezcla a propósito. Una pasada de balance real con oído sigue pendiente y necesita a alguien escuchando el juego, no edición de valores a ciegas. | A |
| 84 | Gancho de "riesgo acumulado" para la música de tensión — coordinar con Slatex, que vive del lado de paquetes/`RunManager`. | B |

## Vehículos adicionales (85-92)

| # | Tarea | Prio |
|---|---|---|
| 85 | Diseñar un segundo vehículo (manejo distinto: más lento y estable, o más rápido y nervioso) como contenido de desbloqueo — coordinar con el sistema de desbloqueos de Slatex. | B |
| 86 | Definir sus parámetros de física sin romper el balance ya afinado del vehículo actual. | A |
| 87 | ~~Adaptar `VehiclePresentation` para que sea reutilizable entre vehículos, no hardcodeada a los nombres de nodo del actual.~~ **[x] Hecho** — reemplazadas las rutas fijas (`"CabinInterior/SteeringWheel"`, `"BodyVisuals/" + side + "Headlight"`, `"CargoBay/" + side + "TailLight"`) por búsquedas por nombre/patrón (`find_child`/`find_children`) en cualquier parte del árbol. Convención documentada en `docs/agregar-vehiculo.md` (#92). | A |
| 88 | Selección de vehículo en el menú, una vez exista más de uno — coordinar con Slatex si toca `main_menu.gd`. | B |
| 89 | Librea/calcomanía simple como personalización visual (dirección ya fijada en `docs/direccion-visual.md` §7). | B |
| 90 | Decidir si las libreas son cosméticos desbloqueables (coordinar con Slatex) o variantes de color fijas. | A |
| 91 | Probar que el segundo vehículo respete todo lo ya construido (ruedas, sacudida por asiento, indicador de asiento ocupado) sin reimplementar nada. **Bloqueado, no pendiente por diseño**: no hay segundo vehículo todavía (#85 es arte/diseño, prioridad B) — nada que probar hasta que exista. | A |
| 92 | ~~Documentar "cómo agregar un vehículo nuevo" para no redescubrirlo cada vez.~~ **[x] Hecho** — `docs/agregar-vehiculo.md`. | A |

## Optimización / tooling de mundo (93-96)

| # | Tarea | Prio |
|---|---|---|
| 93 | ~~Medir el costo real de `RouteStreamer` en FPS con varios tramos activos a la vez.~~ **[x] Medido, con reserva honesta**: headless no renderiza nada, así que esto es costo de CPU/física real (`Performance.TIME_PHYSICS_PROCESS`), no FPS real con GPU — sigue faltando esa medición con ventana real. Manejando en `level_endless.tscn` con streaming activo (7 tramos activos en régimen estable): **0.56 ms promedio, 0.92 ms p95** de paso de física, contra un presupuesto de 16.67 ms a 60Hz. Margen amplio. | A |
| 94 | Evaluar si hace falta LOD para los props de banquina una vez que dejen de ser cajas grises. | B |
| 95 | ~~Revisar `far` clip (600 m) y `lookahead_distance`/`behind_keep_distance` juntos, para no generar ni de más ni de menos.~~ **[x] Revisado por cálculo**: con `fog_density = 0.013` (endless), la transmitancia (`exp(-density·distancia)`) cae a ~9.6% de claridad a los 180 m (el borde de `lookahead_distance`) y a ~5% a los 230 m — el borde del mundo generado ya queda bastante disuelto en niebla antes de acercarse al `far` de 600 m, sin superponerse de más con lo generado. `behind_keep_distance` (40 m, default) no tiene contraparte visual (no hay espejo retrovisor todavía, #35), así que no hay riesgo de pop-out visible por detrás. No hizo falta tocar ningún valor. | A |
| 96 | ~~Perfilar el costo de las partículas de polvo bajo las 4 ruedas simultáneas.~~ **[x] Medido**: comparé el mismo régimen estable manejando (polvo activo, ~0.56 ms/0.92 ms p95) contra la furgoneta detenida (polvo apagado, ~0.70 ms/2.53 ms p95 — el p95 más alto detenido es ruido de muestra por contactos de reposo resolviéndose, no una señal real). El polvo no aparece como costo medible aparte del resto de la física del vehículo. | A |

## QA y documentación de su dominio (97-100)

| # | Tarea | Prio |
|---|---|---|
| 97 | ~~Bug bash de física del vehículo: saltos, vuelcos, quedarse atascado, comportamiento en los bordes de la ruta.~~ **[x] Hecho, automatizado en vez de manual una sola vez** — `tests/test_vehicle_stress.gd`: 60s de aceleración a fondo con dirección oscilante (no recta, para chocar contra el chicane/obras/puente de verdad) a través de los 7 tipos de tramo, revisando posición/velocidad finitas (sin NaN/Inf) cada frame y que la red de seguridad de "fuera de la ruta" (`level_endless.gd`, y<-8/\|x\|>42) atrape una caída antes de que se vuelva una caída real a través del mundo. Este bug bash encontró **un bug real en el juego, no solo en el test**: manejar sin frenar contra `SpeedBumpSegment` repetidos a velocidad máxima sostenida puede lanzar la furgoneta lo bastante fuerte como para aterrizar encajada contra la geometría de la ruta — nunca vuelca (no dispara el chequeo de vuelco) y nunca sale de los límites (no dispara ese chequeo tampoco), simplemente se queda parada para siempre con `RunManager.is_running` todavía en `true`, sin forma de recuperarse. Corregido sumando detección genérica de "atascado" en `level_endless.gd` (6s de velocidad casi nula termina la run como pérdida, `"La camioneta quedó atascada..."`) — no existía ningún mecanismo así antes, en ningún modo. Nota para `docs/tareas-slatex.md` o revisión futura: el mismo hueco conceptual podría existir en `level_base.gd`, no tocado acá por ser zona compartida. | A |
| 98 | Playtesting de variedad de ruta: ¿los tramos curados se sienten repetitivos después de varias vueltas? | A |
| 99 | Verificar que `test_vehicle_presentation`, `test_vehicle_audio`, `test_route_streaming` y `check_driver_sightline` sigan pasando después de cada tarea grande. | A |
| 100 | Mantener actualizadas las filas de vehículo/ambientación en `docs/especificaciones-visuales.md` y `docs/direccion-visual.md` a medida que se completan tareas. | A |
