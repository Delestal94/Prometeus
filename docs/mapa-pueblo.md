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

**Qué desbloquea cada cosa:** la progresión ya existe (`CrewProgression`, `UnlockManager`,
`ShopVoteManager`, campaña, `modules/unlock_profile`). Propuesta: distritos por hitos de campaña o por
compra en la tienda de votación; ciudades nuevas por un hito mayor. Por decidir con
`constructor-progresion` (la economía, ver `economia-y-contramedidas.md`).

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

| F8 | Distritos desbloqueables (`tier`), zonas bloqueadas visibles y su desbloqueo por progresión | `constructor-progresion` + `constructor-mundo` | Abrir un distrito no cambia las calles ya conocidas |
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
4b. ¿Cómo se desbloquea un distrito: hito de campaña, compra en la tienda o ambos?
4c. ¿Una ciudad nueva es un mapa aparte que se elige al empezar, o el mismo mundo que se expande?
4d. ¿El perfil de desbloqueos es del host o de cada jugador?
5. ¿Edificios curados a mano (cuántos modelos) o ensamblados por módulos?
6. ¿Qué pasa con el depósito actual? Hoy es una escena fija con puerta a -Z.

## 8. Próximos pasos

1. Confirmar D1-D5 y responder las preguntas abiertas.
2. Pasar este documento por `critico-diseno`.
3. `planificador-tareas` convierte las fases en tareas N-xxx en `docs/tareas-nacho.md`.
4. Reclamar F0 como pide `CLAUDE.md` (rama `nacho/<ID>-<tema>`) antes de tocar código.
