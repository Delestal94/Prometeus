# Mapa de pueblo dinámico por partida — diseño inicial

> Estado: **borrador** (2026-10-02). Nada construido. El equipo aprobó en la conversación D1-D5 y
> pidió sumar desbloqueo de zonas y biomas (sección 4.7). Las preguntas de la sección 7 siguen abiertas.
> Origen: relevamiento de código del 2026-10-02 (rutas y archivos abajo) + idea del equipo de pasar
> de una ruta aleatoria a un pueblo generado por partida.

## 1. Qué se quiere

Un modo donde cada partida genera **un pueblo distinto** (calles, lotes, ubicación del depósito y de
cada cliente) a partir de la semilla compartida. Los jugadores manejan el camión **por calles**, buscan
la casa de cada pedido con un GPS que guía y entregan en el orden que quieran.

Lo que queda igual: caos coop con el camión, paquetes con trampas, clientes con manía (`narrativa.md`),
progresión, tienda, tono.

## 2. Decisiones de partida (propuesta, a confirmar)

| # | Tema | Propuesta | Por qué |
|---|---|---|---|
| D1 | Relación con la ruta | **Modo nuevo** "Pueblo"; Reparto y Endless siguen como están | El test dorado (`test_route_golden`) y ~10 tests de ruta atan el layout actual. No se rompe nada que funciona |
| D2 | Tamaño | Pueblo chico: 4×4 a 6×6 manzanas, 6-10 casas | Un generador chico se puede curar; uno grande sale vacío |
| D3 | Qué es aleatorio | Trazado de calles, qué lotes son casa, dónde cae el depósito, la base y cada cliente | Lo memorable (depósito, casas de clientes) son piezas hechas a mano colocadas por semilla |
| D4 | Orden de entrega | Libre (el GPS sugiere la más cercana) | Hoy es fijo 0,1,2… y los plazos asumen eso; en un pueblo el orden libre es el gancho |
| D6 | Desbloqueo (decidido por el equipo) | Por **hito de campaña**; el vehículo desbloqueado define hasta dónde se puede llegar | Se siente como progreso real: un camión nuevo abre mapa nuevo |
| D7 | Forma del mundo (decidido por el equipo) | **Un mundo gigante que se expande**, con barreras cerradas entre zonas, no mapas separados | Ver sección 4.7 |
| D5 | Estilo de generación | **Piezas curadas + reglas** ("procgen liviano", ya anotado en `mecanicas-candidatas.md`), no ruido libre | Mejor legibilidad y barrio con identidad |

## 3. Lo que hoy impide hacerlo (del relevamiento)

El mundo actual es **una cinta lineal** de segmentos con un cursor que avanza por -Z. Casi todo se mide
como "metros a lo largo del camino". No existe grafo de calles, grilla de lotes, pathfinding, minimapa
ni generación de edificios por semilla (las casas son 5 GLB fijos).

Puntos de acople que hay que reemplazar o adaptar:

1. **Planificador y construcción**: `RoutePlanner.plan_spine()` + `Route._build_leg()`
   (`scripts/gameplay/route/route_planner.gd`, `route.gd:362`). Es la unidad de generación y es lineal.
2. **Medición de progreso**: `_path_points`, `_progress_samples`, `PathLookup`
   (`route_path.gd`) alimentan `get_progress`, `road_distance`, `stop_road_distance`,
   `distance_from_path`. Con calles paralelas y cruces esa medición es ambigua.
3. **Reglas de nivel**: `level_base.gd:206-240` (progreso, "fuera del camino" a 42 m, plazos
   `_house_distances`, exención de atasco).
4. **GPS**: `dashboard_gps.gd` apunta en línea recta a la casa. Con calles engaña.
5. **Casas**: `RouteHouses.build_house()` las pone como desvío lateral del cursor; la dirección es
   solo `house_index` ("CASA N").
6. **Decorado**: `RouteDresser` (zona por distancia a casas + ruido 1D), `TownSign`, `RoadsideStory`.
7. **Terreno**: `TerrainField` sirve (flat zones, platforms, spans) pero asume un único camino.
8. **Depósito y base**: depósito fijo en (0,0,8) con puerta a -Z; `RouteGoalLot` orientada por el cursor.
9. **Fauna y eventos**: cuelgan de `StraightSegment`/`route_distance`; `RailCrossingSegment` usa RPC
   por path de nodo.
10. **Red**: mundo 100 % derivado de `world_seed`; el handshake lleva la semilla y `world_house_count`.
11. **Tests dorados**: cualquier cambio a la generación actual obliga a regenerar firmas.

Lo reutilizable: semilla compartida, `TerrainField`, `RoutePlacement` (rejilla de ocupación),
`DressingBatcher` (MultiMesh por celda), `FrameSlicer` (construcción por tajadas), `WorldMood`,
`RoadsideStory` (props), nombres de pueblo, clientes y tono.

## 4. Arquitectura propuesta

### 4.1 Generador puro (módulo portable)

`modules/town_gen/` (según `docs/modulos.md`: nada del juego adentro, con `module.cfg` y tests propios).

- `TownPlan.generate(seed, params) -> TownPlan`: **pura y determinista**, sin nodos.
  - Entrada: `seed`, `blocks_x`, `blocks_y`, `lots_per_block`, reglas.
  - Salida: grafo de calles (nodos = cruces, aristas = tramos con largo y ancho), manzanas, lotes
    (rect + frente + calle + número), y un `address` por lote (calle + número).
- Asignación de roles de lote (depósito, base, casa, estación de servicio, plaza) la hace una función
  aparte con otra sub-semilla (`hash([seed, &"lots"])`), para que cambiar una no mueva la otra.
- **Regla de oro**: depende solo de `seed` + `params` que viajan en el handshake. **Nunca** del roster
  local (precedente: el reparto de 3+ jugadores divergía por eso).

### 4.2 Adaptador en el juego

- `scripts/gameplay/town/` arma los nodos desde el `TownPlan`: calles (reusando `TerrainField.spans`),
  manzanas y lotes (`flat_zones`/`platforms`), edificios (piezas curadas), depósito y base como lotes.
- Construcción bajo `FrameSlicer` y pantalla de carga, como `route.gd`.
- Edificios en MultiMesh por modelo + `visibility_range` (nunca "colocar menos" según calidad: rompería
  la igualdad entre peers).

### 4.3 Navegación

- Grafo de calles ⇒ `TownNav`: distancia por camino más corto (A*/Dijkstra) y próxima maniobra.
- GPS (`dashboard_gps.gd`) deja la flecha recta y muestra distancia por calles + giro siguiente.
- Pantalla de mapa (minimapa o tablet en el camión): propuesta para una fase posterior.

### 4.4 Reglas de partida

- Progreso: distancia acumulada recorrida, no proyección sobre una polilínea.
- "Fuera de camino": se reemplaza por límite del mapa (borde del pueblo), no por distancia a un eje.
- Plazos: por distancia de grafo desde la posición al destino, con orden libre.
- Atascado/estacionado: exenciones por lote de depósito y de cada casa, no por radio a un punto lineal.

### 4.5 Fauna, eventos y clima

- `WorldMood` funciona tal cual (semilla por corrida).
- Perro, ovejas, ciervos: se reubican como eventos de calle/plaza; los de campo abierto no aplican.
- Estación de servicio y cruce de tren: pasan a ser lotes o cruces del pueblo, o se dejan fuera de la v1.

### 4.7 Progresión: zonas desbloqueables y biomas (pedido del equipo, estilo Schedule I)

Idea: el mapa crece con la progresión. Se empieza en un barrio chico y, con misiones y mejoras, se
abren distritos y, más adelante, otras ciudades con biomas distintos (nieve, etc.).

**Decisión de arquitectura (hay que tomarla antes de F0):** el generador recibe un `tier` además de la
semilla.

- `TownPlan.generate(seed, params)` con `params.tier` (cuántos distritos están abiertos) y
  `params.theme` (bioma). Misma semilla + mismo tier ⇒ mismo pueblo.
- Los distritos se generan **siempre completos pero con los cerrados bloqueados** (portón, obras,
  cinta) en lugar de no generarlos: así abrir un distrito no cambia las calles ya conocidas y la
  semilla sigue siendo estable. Propuesta; la alternativa (generar solo lo abierto) cambia el mapa al
  desbloquear.
- Cada distrito tiene tipo (residencial, comercial, rural, industrial) con su propio set de clientes,
  paquetes y trampas. Eso conecta con `narrativa.md`: cada cliente "vive" en su zona.

**Decidido por el equipo (2026-10-02):**
- Se desbloquea **por hito de campaña**, y el vehículo es la llave: un camión desbloqueado permite
  llegar más lejos (por ejemplo, uno todoterreno cruza el barro, uno con cadenas la nieve).
- El mundo es **uno solo, gigante, que se expande**. Las zonas nuevas están detrás de **barreras
  cerradas** (portón, puente cortado, nieve cerrada, obras) que se abren al cumplir el hito.

**Qué implica (propuesta de arquitectura):**
- **Mundo por campaña, no por partida.** Si el mundo se expande y el jugador recuerda dónde está cada
  cosa, el mapa tiene que ser el mismo entre partidas de una misma campaña. La semilla del mundo pasa a
  guardarse en la campaña (`modules/persistence`), y lo que varía por partida son los pedidos, el clima,
  los eventos y la hora. "Dinámico" queda como: cada campaña nueva genera un mundo distinto.
- **Streaming por chunks/distritos, no construcción de una vez.** Un mundo gigante no entra como hoy
  (`route.gd` construye todo bajo pantalla de carga). El precedente es `SegmentStreamer` de Endless
  (genera adelante, libera atrás). Hace falta un `DistrictStreamer`: el plan global (grafo y lotes) es
  liviano y se calcula entero; la geometría de cada distrito se instancia y libera según la cercanía.
- **Las barreras son datos del plan**, no geometría fija: cada arista del grafo tiene un
  `gate: requirement` (hito o capacidad de vehículo). El pathfinding del GPS ignora las aristas
  cerradas. Abrir una barrera cambia solo ese dato, no las calles.
- **El requisito de vehículo** se expresa como capacidad (`offroad`, `snow`, `high_clearance`...), no
  como nombre de camión, para que un vehículo nuevo se enchufe sin tocar el mapa. Ver
  `docs/agregar-vehiculo.md`.
- **Red:** el host manda semilla de campaña, `tier` y barreras abiertas en el handshake.
- **Guardado de la partida** (decidido): el archivo de guardado lleva `world_seed`, `params` del
  generador (tamaño, `theme`), `tier`, barreras abiertas, hitos cumplidos y vehículos desbloqueados.
  Todo lo demás se **regenera** desde la semilla al cargar, igual que hoy, así que el guardado es chico
  y no hace falta guardar geometría. Reglas:
  - Cargar la misma partida con la misma versión del generador debe dar el mismo mundo. Si el
    generador cambia entre versiones, el guardado necesita un `generator_version` y una migración o un
    aviso; es un riesgo que hoy el test dorado (`test_route_golden`) cubre para la ruta y habría que
    replicar para el pueblo.
  - Quien hostea carga la partida; los clientes reciben semilla y estado en el handshake. Un jugador que
    entra tarde reconstruye desde esos datos.
  - Usar `modules/persistence` y `modules/unlock_profile` en lugar de un guardado nuevo.

**Qué desbloquea cada cosa en detalle:** por decidir con `constructor-progresion` (economía, ver
`economia-y-contramedidas.md`; piezas existentes: `CrewProgression`, `UnlockManager`,
`modules/unlock_profile`).

**Biomas (`TownTheme`):** paleta y materiales, clima, reglas de agarre del camino y set de peligros.

| Bioma | Qué cambia | Qué ya existe para apoyarlo |
|---|---|---|
| Pueblo de campo (base) | Lo actual | `WorldMood` (verano/otoño), pueblo, fauna |
| Nieve | Hielo y poca tracción, nieve que tapa carteles y cunetas, noche temprana | `GripZones`, barro, `WorldMood`, `LowVisibilityEvent` |
| Otros (puerto, desierto) | Por decidir | — |

Lo que habría que construir para nieve: materiales y shaders de nieve (`artista-shaders`), partículas
(`artista-vfx`), una zona de agarre de hielo en el vehículo (`constructor-camion`), y nuevas trampas o
contenidos (un paquete que se congela, por ejemplo; `constructor-trampas`).

**Estado persistente:** qué está desbloqueado es perfil, no semilla. Preguntas de red: ¿cuenta el perfil
del host o el de cada jugador? Propuesta: el host manda el `tier` y el bioma en el handshake, y cada
jugador acumula sus propios logros. Revisión de `auditor-red`.

**Orden de construcción:** primero un solo pueblo con un solo bioma, pero con `tier` y `theme` ya en la
firma del generador. Zonas bloqueadas y biomas se agregan sobre eso, no se rehacen.

### 4.6 Red

- El host decide `seed` y `town_params` una vez y viajan en `_session_state` del handshake.
- Subir `PROTOCOL_VERSION` (hoy 27) según `docs/convenciones-godot.md` §6 y revisión de `auditor-red`.
- `restart_delivery` debe poder sortear un pueblo nuevo.
- Late join: reconstruir desde semilla, como hoy.

## 5. Fases

Cada fase termina con algo que se puede jugar o medir, y ninguna rompe el modo actual.

| Fase | Entrega | Agente | Hecho cuando |
|---|---|---|---|
| F0 | Spike: grilla de calles + terreno plano + camión conducible, sin red ni casas | `constructor-mundo` | Se maneja por un pueblo generado y se ve en una captura (`revisor-visual`) |
| F1 | `modules/town_gen` con tests: determinismo, conectividad, lotes sin solaparse, sin depender del roster | `escritor-tests` + `constructor-mundo` | Misma semilla ⇒ mismo plan en 100 semillas; `check_modules` verde |
| F2 | Lotes con roles: depósito, base y casas; direcciones calle+número | `constructor-mundo` | Se entrega un paquete en un lote de casa |
| F3 | `TownNav` + GPS por calles | `constructor-camion` / `constructor-ui` | El GPS no engaña en una calle sin salida; test de caminos |
| F4 | Reglas de partida (progreso, límites, plazos, orden libre) | `constructor-progresion` | Una entrega completa con puntaje y plazos |
| F5 | Red: semilla y parámetros en el handshake | `constructor-red` + `auditor-red` | Par y trío ven el mismo pueblo, join tardío incluido |
| F6 | Decorado, fauna, clima, farolas, personalidad de barrios | `constructor-mundo`, `artista-vfx`, `disenador-audio` | Captura de prensa del pueblo |
| F7 | Rendimiento | `perfilador-rendimiento` | Presupuesto de draw calls y FPS dentro del actual |

| F7b | `DistrictStreamer`: plan global liviano + instanciar y liberar distritos por cercanía, bajo `FrameSlicer` | `constructor-mundo` + `perfilador-rendimiento` | Recorrer el mundo entero sin picos de frame ni leaks de nodos |
| F8 | Barreras (`gate`) en el grafo, GPS que las ignora, desbloqueo por hito de campaña y capacidad de vehículo | `constructor-progresion` + `constructor-mundo` | Abrir un distrito no cambia las calles ya conocidas |
| F9 | Primer bioma nuevo (nieve): materiales, clima, hielo en el camión, 1-2 trampas | `artista-shaders`, `artista-vfx`, `constructor-camion`, `constructor-trampas` | Una partida completa en nieve, con captura |

F8 y F9 van después de que el pueblo base se sienta bien (F0-F7).

F0 es el punto de control: si el pueblo generado no se siente bien al manejar, se decide ahí si seguir.

## 6. Riesgos

- **Pueblos aleatorios que se sienten vacíos o repetidos.** Mitigación: piezas curadas, puntos de
  interés fijos con identidad (cliente, depósito), F0 como prueba temprana.
- **Divergencia en red.** Mitigación: todo desde seed + params, test de igualdad entre dos peers.
- **Rendimiento.** Ya hay 2.256 draw calls en Reparto; una ciudad sin instancias compartidas no entra.
- **Alcance.** Es un modo entero. Mitigación: modo aparte, F0 antes que nada, sin tocar Reparto.
- **Choque con Slatex.** Si se tocan personajes o cuerpos (S-311), avisar según `docs/colaboracion-equipo.md`.

## 7. Preguntas abiertas

1. ¿El pueblo reemplaza algún día a Reparto o convive para siempre?
2. ¿Orden de entrega libre del todo o con plazos que empujan un orden?
3. ¿Hay endless en el pueblo (entregas infinitas) o solo reparto con fin?
4. ¿Cuánto del imperio (flota, empleados, zonas) entra en la v1? Propuesta: nada; primero el mapa, con
   `tier` y `theme` ya en la firma del generador (sección 4.7).
4b. ~~¿Cómo se desbloquea un distrito?~~ **Decidido:** hito de campaña, con el vehículo como llave.
4c. ~~¿Mapa aparte o mundo que se expande?~~ **Decidido:** un mundo gigante con barreras.
4d. ¿El perfil de desbloqueos es del host o de cada jugador? (con mundo por campaña, probablemente
    la campaña la guarda quien hostea; por confirmar)
4e. ~~¿El mapa es el mismo en todas las partidas de una campaña?~~ **Decidido (2026-10-02):** el mundo se
    genera al crear la partida; después se guarda y se continúa con la misma semilla. Una partida nueva
    genera un mundo distinto.
4f. ~~¿Qué tan grande es "gigante"?~~ **Decidido (provisorio, 2026-10-02):** referencia Schedule I
    (una ciudad chica con 6 distritos que se abren por rango, sin pantallas de carga). Meta: unos 6
    distritos de 4×4 manzanas (~100 manzanas, cifra de Claude, no de Schedule I). Se mide el costo de
    un distrito en F0 antes de comprometer el total; si es chico, F7b puede cargar por distrito entero
    en lugar de chunks finos.
4g. ¿Se puede volver atrás (re-cerrar), o lo abierto queda abierto para siempre?
5. ¿Edificios curados a mano (cuántos modelos) o ensamblados por módulos?
6. ¿Qué pasa con el depósito actual? Hoy es una escena fija con puerta a -Z.

## 8. Decisión del equipo y ajustes tras la crítica (2026-10-02)

`critico-diseno` recomendó postergar hasta después del Early Access (contenido cerrado 2026-10-30, EA
2027-01-22, 37 tareas N- abiertas) y recortar D6/D7. **El equipo decidió seguir con la visión completa**:
hay juegos competidores por salir y se apuesta a más grande, más contenido y más personalidad. Riesgo
aceptado a conciencia: choca con el calendario del EA y con el congelado de `vehicle.gd`.

Lo que se adopta de la crítica porque mejora el diseño sin contradecir la decisión:

- **Plazos fijados una sola vez al salir del depósito**, por distancia de grafo depósito→casa. Calcularlos
  "desde la posición" (4.4) se reinicia dando vueltas: es un exploit. Sin bono por ruta óptima.
- **El GPS muestra la casa del paquete que peor está**, no la más cercana, así "¿a quién entregamos
  primero?" es comunicación entre conductor y cargadores. Rol posible: el pasajero que navega.
- **Cantidad de casas por entrega** sigue la regla actual (`crew_house_count`), no 6-10: mantiene
  entregas de 2-5 min. Esas casas se sortean dentro de un mundo mayor.
- **Contradicción resuelta:** D2 (barrio de 4×4 a 6×6 manzanas) es el tamaño de **un distrito**; los
  ~6 distritos de 4f son el mundo completo.
- **`generator_version` en el guardado y test dorado del pueblo** desde F1, porque el generador va a
  seguir cambiando durante el EA.
- **El host carga la colisión de todo distrito con un jugador o paquete.** Medir en F0 y F7b; la niebla
  rinde menos en una grilla urbana, así que se prevé un presupuesto de visibilidad propio.
- **Estresores en las calles** (cordones, lomos de burro, baches): una grilla plana a baja velocidad le
  quita a la carga lo que la hace sufrir.
- **Kit de edificios por módulos** (base + techo + puerta + color), con los 5 GLB actuales como casas de
  clientes con identidad. Pendiente de modelar en la PC (no hay Blender en la nube).
- **Perfil de desbloqueos del host**; cosméticos personales.

### F0 reformulado como control con criterios objetivos

Spike de 4-5 días (se descarta si se pasa) con F0 + F2 + F3 mínimos: depósito, 3 casas como cajas, A* y
orden libre. Se mide con `bench_drive`, `sim_trap_balance` y el bot de caos:

1. Una entrega de 3 casas dura 2 a 5 minutos.
2. El daño a la carga por minuto es al menos el 70 % del de la ruta con las mismas trampas.
3. El GPS no se equivoca en 100 semillas, incluidas calles sin salida.
4. La casa destino se reconoce desde la cabina a 40 m o más (captura de `revisor-visual`).
5. El costo de un distrito en draw calls y tiempo de construcción entra en el presupuesto actual.

Si falla el 2 o el 5, se ajusta el diseño antes de seguir; no se sigue a ciegas.

## 8b. Ideas de expansión (propuestas del equipo, sin comprometer, 2026-10-02)

Regiones lejanas del mundo, cada una con su bioma y su forma de llegar. Entran después de F8 (barreras
e hitos) y comparten el mismo mecanismo: la barrera pide un **medio de transporte**.

| Región | Cómo se llega | Qué cambia en el juego | Qué hay que construir (resumen) |
|---|---|---|---|
| Montaña | Avioneta | Altura, viento, frío, caminos de montaña | Un vehículo aéreo o un viaje en avioneta; arte y clima de montaña |
| Volcán | Por tierra o aire, con hito | Calor, ceniza, suelo que se rompe, trampas térmicas (paquete que se derrite) | Shaders y VFX de lava y ceniza; nuevas trampas |
| Isla | Barco o ferry | Agua, muelles, oleaje | Transporte marítimo; arte de costa |

**Decisión de alcance pendiente (importa mucho):** ¿el medio de transporte se **maneja** o es un **viaje**?
- *Manejable* (avioneta, barco): es un vehículo nuevo entero, con física, controles, cámara, arte,
  sonido, red y balance. Es del tamaño de otro juego dentro del juego. Hoy hay un solo camión y
  `vehicle.gd` está congelado.
- *Viaje* (el paquete cruza en avioneta o ferry como un tramo de la entrega): el pasaje se juega como un
  tramo corto donde el paquete sufre (turbulencia, oleaje) y el equipo cuida la carga, sin que nadie
  pilote. Mucho más barato y mantiene el pilar de cuidar el paquete.
- Propuesta: empezar por *viaje* para abrir las regiones, y dejar vehículos manejables para más
  adelante si el modo funciona.

Cada región es un distrito grande con sus propias reglas de generación (`theme`), así que el diseño de
`tier` y `theme` de la sección 4.7 ya la cubre; lo nuevo es el tipo de barrera (transporte) y el arte.

## 8c. Cambio de alcance del depósito: el equipo empaqueta (decisión del equipo, 2026-10-02)

Hoy el depósito entrega cajas ya armadas: `Depot.post_orders()` genera pedidos con `package_id`, trampa y
contenido, y las cajas salen listas para cargar. **Nuevo:** las cajas ya no vienen empaquetadas; el
equipo recibe el pedido, elige y prepara el contenido, arma la caja y la deja lista para cargar.

**Qué significa para el diseño (a decidir, nada construido):**

- **El empaquetado pasa a ser un tramo del juego, antes de manejar.** Bucle completo: recibir pedido →
  armar la caja → cargar → manejar por el pueblo → entregar. El pilar sigue siendo cuidar el paquete,
  pero ahora el cuidado empieza en el depósito.
- **La trampa nace en el empaquetado.** Hoy la trampa (frágil, explosiva, ruidosa...) la define el pedido.
  Con empaquetado, la calidad de lo que se arma puede decidir cuánto resiste la caja en el camino:
  una caja mal armada se rompe antes. Esto conecta el depósito con el manejo.
- **Roles nuevos:** quien arma, quien carga, quien maneja. Más comunicación, que es el gancho coop.
- **Presupuesto de tiempo:** una entrega dura hoy 2-5 min. Si empaquetar suma minutos, hay que decidir si
  el empaquetado cuenta dentro de ese tiempo, o si es una fase aparte con su propio ritmo. Riesgo de
  que el depósito se vuelva un minijuego largo antes de la acción.
- **Cercanía a otro juego:** Packing Shift! (el informe que pasaste) tiene empaquetado como núcleo, así que
  conviene que acá sea una *fase corta y con consecuencias en la ruta*, no el juego entero.
- **Piezas del depósito que ya existen** y habría que reutilizar (según el relevamiento): estantes,
  pizarra de pedidos (`DepotOrderBoard`), taller, jaula de suministros, cinta, autoelevador. Las cajas
  y `DeliveryPackage`/`PackageCare` están en el dominio de `constructor-jugador`.

**Respuestas del equipo (2026-10-02):**
1. **Tiempo:** generoso pero no infinito. Hay un límite de tiempo para empaquetar; no se puede quedar
   toda la tarde. Cifra concreta por definir con `pulidor-jugabilidad`.
2. **Qué se decide:** todo (contenido, tamaño de caja, relleno, sellado y lo que haga falta). Es un
   sistema profundo, no un paso simple.
3. **Salir a medio armar:** se puede. Las cajas incompletas se pagan en el camino (se rompen antes,
   peor puntaje, reclamo del cliente).
4. **Reparto de roles:** lo deciden los jugadores entre ellos; no hay roles fijos. **Se puede jugar solo**,
   así que una sola persona tiene que poder empaquetar, cargar y manejar dentro del tiempo.

**Consecuencias de diseño que salen de esas respuestas (propuestas, a validar):**
- **El tiempo límite tiene que escalar con el equipo.** Con "se decide todo" y juego en solitario, el
  mismo límite no sirve para 1 y para 6 jugadores. Propuesta: el tiempo del depósito se calcula con la
  cantidad de cajas y de jugadores, como hoy `crew_house_count` y `RunDeadlines` calculan casas y plazos.
- **Dar valor a salir apurado:** como se puede salir con cajas a medio armar, el límite de tiempo tiene
  que pesar. Cada caja puede tener un nivel de armado visible, y el cliente reclama según ese nivel.
- **Profundidad sin abrumar:** "se decide todo" es mucho para aprender. Conviene que haya un camino rápido
  (opciones recomendadas por el contenido del pedido) y un camino experto (decidir cada cosa), con el
  tutorial (`constructor-ui`) enseñando de a poco. Es una decisión de UX, no de reglas.
- **En solitario**, el cargador, el empaquetador y el conductor son la misma persona; el
  tiempo generoso es lo que hace jugable ese caso.

**Preguntas que quedan abiertas:**
- Cifra del límite (segundos por caja y por entrega) y cómo escala con jugadores.
- Lista concreta de decisiones al empaquetar (la lista de "todo") y cuántas por caja.
- Cómo se cobra una caja a medio armar (puntaje, rotura, plata).

**Plan:** no se toca el spike N-950. Se agrega una tarea nueva de diseño del empaquetado en M10
(`critico-diseno` + `pulidor-jugabilidad`), antes de construirlo; el depósito actual se rediseña en
una tarea propia. Hasta decidirlo, el pueblo asume el depósito actual.

## 9. Próximos pasos

1. Confirmar D1-D5 y responder las preguntas abiertas.
2. Pasar este documento por `critico-diseno`.
3. `planificador-tareas` convierte las fases en tareas N-xxx en `docs/tareas-nacho.md`.
4. Reclamar F0 como pide `CLAUDE.md` (rama `nacho/<ID>-<tema>`) antes de tocar código.
