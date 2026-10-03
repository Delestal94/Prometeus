# Ciudad procedural — seis distritos construidos del spike

Decisiones del equipo, 2026-10-02: una ciudad continua con seis distritos;
contorno asimétrico que varía por semilla, calles diagonales y manzanas de
tamaños distintos. Plazas, parques, jardines y monumentos forman parte del
trazado. Una campaña conservará su mundo al continuar; una campaña nueva
tendrá otra semilla. El guardado y la campaña todavía no están conectados.

## Distritos

1. Barrio del depósito: inicio, viviendas bajas, taller, plaza y parque.
2. Centro: comercios, plazas y calles más ajustadas.
3. Industrial: fábricas y cargas pesadas.
4. Campo: caminos rurales y barro.
5. Puerto: muelles y costa.
6. Sierra: pendientes, bosque y nieve.

Conexiones previstas: 1–2, 1–4, 2–3, 3–5, 5–4, 4–6, 6–3.
La prueba por pasos conserva Barrio y Centro abiertos. Las nuevas escenas
`town_city.tscn` y `town_city_delivery.tscn` construyen los seis distritos y
abren los siete conectores para inspección/exploración offline. La campaña
aún no aplica progresión/capacidad del vehículo a estos accesos.
El trazado completo se genera antes de abrir distritos: desbloquear una zona
no debe cambiar las calles ni mover las casas existentes.

## Implementado en esta rama

`modules/town_gen/town_plan.gd` devuelve datos, sin escenas ni autoloads:

- Semilla y `generator_version = 2` por defecto; versión 1 reproducible.
- Seis distritos de contorno irregular, con escala, orientación y vértices
  variados por semilla. Las conexiones funcionales son estables.
- Grafo de cruces y calles de 12 m: circuitos locales, diagonales y conexiones
  entre distritos. Las calles que se cruzan comparten un nodo del grafo.
- Lotes con frente a una calle, posición, tamaño, orientación y dirección.
- Plaza y parque reservados antes de colocar edificios. Lotes y vegetación
  respetan el espacio de circulación.
- Un depósito, tres casas de clientes y un taller en el distrito inicial.

Flujos RNG separados para forma, áreas verdes y lotes; no usa el RNG global
ni el roster de jugadores. Mismo generador y semilla producen el mismo plano.

`scenes/gameplay/town/town_prototype.tscn` construye **solo el primer barrio**:
calles, patios, edificios con colisión, árboles agrupados en MultiMesh,
bancos, farolas y una plaza con monumento de paquetes. Por defecto las salidas
a Centro y Campo tienen barreras. `built_districts` permite construir más zonas
del mismo plano; el adaptador jugable usa `[0, 1]`, abre el corredor al Centro
y mantiene cerradas Campo e Industrial. `town_art.gd` viste los lotes con el arte existente:

- Las cinco viviendas originales, elegidas por semilla y espacio disponible,
  orientadas hacia su calle y conservando la escala del modelo. Una vivienda
  grande que no cabe se sustituye por la cottage.
- Tres casas de entrega distintas (cottage, cabin y bungalow), cuya variante
  se mantiene entre la escena de inspección y la escena jugable.
- Depósito y taller compactos con materiales de `DepotKit`, marcos/piezas
  de portón originales, pallets, jaulas de carga y herramientas. Se adapta
  el conjunto al lote; no se reduce el edificio completo del depósito original.
- Estante de carga con los modelos originales de marcos y bandejas: seis
  pedidos separados en dos niveles, códigos A–F y sus colisiones. Las cajas
  inferiores quedan adelantadas dentro de la bandeja para que el borde del
  nivel superior no bloquee la interacción desde delante.
- Robles, abedules y arces originales agrupados por `DressingBatcher`, con
  colisión de troncos; bancos y farolas originales apoyados sobre el terreno.

Esta integración conserva los assets originales. El monumento, pavimentos
y aceras siguen siendo geometría del prototipo. El terreno ahora reutiliza
la base de carretera del juego; faltan manzanas cerradas, los biomas finales
de los distritos y medición del presupuesto de render.

### Aceras y accesos peatonales

`modules/town_gen/town_walkways.gd` deriva las superficies de los distritos
abiertos sin consumir RNG ni modificar calles, lotes o áreas verdes. Devuelve
polígonos con altura, accesos de lotes y recorridos de entrada a plazas/parques.
Las aceras de 2 m siguen también calles diagonales y se unen en los cruces;
se recortan contra el asfalto y tienen rampas exteriores hacia el terreno.

Cada lote recibe un acceso desde su frente de calle: 2 m para viviendas y
comercios, 5 m para depósito/taller. Los caminos verdes rodean los lotes que
interponen edificios y llegan al centro pavimentado. La escena reúne el
pavimento en una malla con colisión, añade suelo físico a césped/plazas y
rampas en su borde interior. Árboles y mobiliario dejan libres las entradas.
El jugador puede pasar del asfalto a la acera y al acceso sin saltar.

### Reutilización de la carretera existente

`town_environment.gd` conecta el grafo de ciudad con `route_terrain.gd`
(`TerrainField`), el mismo terreno continuo con colisión, relieve, shader y
cuatro mapas de detalle del juego. Reemplaza el cubo plano de 4000 m.
El perfil `town_terrain.gd` hereda ese sistema y mantiene el interior de los
contornos urbanos nivelado; mezcla el relieve original por fuera en 24 m,
evita montañas entre las casas y conserva un límite irregular.
Registra las calles abiertas y los extremos cerrados; plataformas nivelan
calles, lotes, zonas verdes y accesos para conservar sus alturas y el reparto.
Fuera de esas reservas reaparece el relieve original. Las calles usan además
el mapa de detalle de asfalto existente.

Cada tramo abierto utiliza `StraightSegment` en su orientación real. Su
modo `continuous_terrain` evita duplicar suelo/carretera y conserva la pintura
original; se retiran marcas que invadirían otra rama de un cruce. El grafo
urbano sigue determinando conexiones: no se vuelve al único recorrido
encadenado del generador anterior.

`town_dresser.gd` extiende `RouteDresser`: reutiliza su catálogo y
`RoutePlacement` (ocupación, pendientes, asentamiento y separación del camino)
para árboles, plantas, autos estacionados, mobiliario y paradas. El perfil
urbano reserva parcelas, plazas y caminos peatonales, y deja los objetos fuera
de las aceras/rampas. Dentro del contorno usa la zona urbana; fuera, bosque.
`DressingBatcher` agrupa estos modelos y las marcas de los tramos. No activa
los eventos, peligros ni la progresión del recorrido lineal.

La versión 2 completa los frentes libres de Barrio y Centro con parcelas
más cercanas a la acera, separadas al menos dos metros entre sí. Centro
agrega comercios y viviendas con los modelos originales. `town_infill.gd`
reserva primero los accesos a todas las direcciones existentes y las cuatro
áreas verdes: la densidad adicional no consume entradas, parques ni plazas.
Las calles, lotes originales y seis clientes conservan sus datos de versión 1.
`town_plan.generate(seed, 1)` reproduce el plano anterior; la versión 2 es
el valor por defecto. Una versión desconocida devuelve un diccionario vacío.
Sobre 100 semillas, Barrio pasa de 23,70 a 33,74 parcelas en promedio y
Centro de 23,77 a 33,84; la semilla 4242 pasa de 49 a 69 parcelas construidas.
Las pruebas de escena y reparto, portabilidad y capturas GPU verifican
modelos a escala nativa, circulación y conservación de los seis destinos.
Los perfiles de los cuatro distritos restantes se construyen en las escenas
completas. Las manzanas completamente cerradas y biomas específicos todavía
necesitan trabajo: sigue siendo una escena de prueba.
La escena completa rellena los huecos de suelo entre distritos. Desde arriba
se ve el borde exterior del terreno y el decorado se oculta por distancia;
la continuidad del horizonte y el presupuesto de render necesitan trabajo.

### Ciudad completa para inspección y conducción

Abrir `scenes/gameplay/town/town_city.tscn` y pulsar **F6** para inspeccionar
los seis distritos con cámara libre. `town_city_delivery.tscn` permite recorrer
la misma ciudad con el jugador, camión y los seis pedidos existentes. Ambos
usan la misma semilla/plano de las escenas anteriores; no aparecen barreras
entre distritos. La semilla 4242 construye 163 parcelas, y 90210 construye 164:
61 segmentos de calle y doce entradas a plazas/parques en ambas.

Industrial y Puerto tienen almacenes con las piezas/materiales del depósito,
con paletas diferenciadas. Campo favorece las farmhouses originales y suma
el molino existente; Sierra favorece cabañas, pinos y el perfil de bosque.
El decorador original aplica reglas rurales de fardos/cajones y tractores
en Campo. Industrial reutiliza la torre de agua. Los landmarks se colocan
solo en huecos que no invaden calles, lotes, verdes ni accesos, a escala nativa,
y quedan reservados antes de la ambientación de carretera.

`town_delivery.built_districts` configura tanto la construcción como el GPS:
la escena de dos distritos mantiene su selección `[0, 1]`, mientras la completa
selecciona los seis. Conducir a otras zonas conserva destinos/pedidos A–F.
Abrirlas en esta prueba no simula desbloqueos ni agrega clientes de campaña.

El suelo cubre la envolvente irregular completa y su margen exterior, sin
crear carreteras ficticias para rellenar huecos. `TownTerrain.index_profile()`
indexa las plataformas antes del build; solo lee las candidatas de cada tesela,
conservando orden y banda de mezcla. Los cinco distritos llanos retornan altura cero antes
de calcular un paisaje que luego se descartaría. Sierra conserva el perfil
natural original, con plataformas niveladas en calles, lotes y accesos. Pruebas comparan el índice
contra muestras exhaustivas, con rotación, solapamiento y coordenadas negativas.
La prueba de ciudad pasó de 63 s a 43 s al evitar el cálculo descartado y
a 9 s con el índice, incluso cubriendo ahora toda la envolvente de suelo.
Son tiempos locales de construcción/prueba, no una medición de FPS.

Puerto tiene una bahía tallada en el mismo terreno físico, orientada hacia
el exterior según la ciudad generada. Su orilla queda más allá de todos
los lotes, calles y parques. Un camino calculado con el grafo de visibilidad
existente esquiva parcelas y verdes hasta un muelle de madera con colisión,
pilotes, barandas, cajones y bolardos originales. El agua se recorta contra
el lecho real y tiene ondas de color; no agrega carreteras al GPS. La
ambientación reserva el acceso y descarta posiciones sumergidas.

Sierra conserva colinas entre parcelas, cabañas y pinos. La nieve del shader
se limita al polígono irregular de Sierra y a terreno alto con poca pendiente.
Calles, lotes y accesos verdes mantienen altura cero. Este relieve no convierte
las calles en carreteras de montaña ni implementa clima/estaciones de campaña.
El horizonte lejano y el presupuesto de render siguen pendientes.

### Abrir y recorrer

Abrir la escena en Godot y pulsar **F6**. Cámara libre: WASD mueve, Q/E cambia
altura, botón derecho permite mirar y Shift acelera. La escena acepta
`--town-seed=4242` después de `--` para repetir un mundo. También puede
fijarse `world_seed` en el inspector. `generator_version` permite comparar
las versiones 1 y 2 en la escena de inspección. Con valor cero toma la semilla de la
sesión si existe y genera una nueva en una prueba independiente.

La escena de inspección conserva la cámara libre. Para jugar, abrir
`scenes/gameplay/town/town_delivery.tscn` y pulsar **F6**, sin sesión online:

1. Tomar los seis paquetes A–F del estante frente al depósito y cargarlos en
   los soportes del camión usando **E**. El cartel y el prompt muestran su código.
2. Subir al asiento del conductor con **E**: empieza el reparto. **WASD**
   mueve al jugador o conduce; los controles habituales del camión siguen activos.
3. **F1–F3** eligen clientes del barrio (A–C), **F4–F6** clientes del Centro
   (D–F). El GPS de la cabina indica distancia por calles y el siguiente cruce,
   además de casa/código. Tras resolver un pedido, elige el siguiente pendiente.
4. **F7** dirige el GPS a un punto de calle junto a la plaza del Centro.
   Esa visita es opcional y conserva los seis pedidos; **F1–F6** vuelven a
   la navegación del cliente. El Centro tiene comercios con toldos, predominio
   de viviendas de dos plantas, plaza/monumento, parque y mobiliario original.
5. Bajar con **E**, sacar el paquete y tocar el timbre de la casa correcta.
   Una caja equivocada deja el pedido pendiente; el estado de la caja afecta
   la entrega como en el juego. Los pedidos pueden resolverse en cualquier orden.
6. Tras cerrar los seis pedidos de ambos distritos, volver al depósito y
   detener el camión. Regresar con pedidos pendientes no termina el reparto.
   El regreso al depósito tiene prioridad sobre la exploración del Centro.
   **Esc** libera o vuelve a capturar el mouse.

Las tres direcciones iniciales se conservan. `town_delivery.delivery_lots`
selecciona las primeras tres viviendas residenciales del Centro por dirección,
independientemente del orden de construcción. Cada semilla fija seis destinos
y códigos; convertirlos en clientes no mueve el plano ni elimina los comercios.
Las casas del Centro conservan su modelo ya elegido y reciben timbre/marcador.

Este adaptador usa el jugador, camión, paquetes, casas y timbres reales.
Asfalto y cruces tienen colisión. Los edificios y muebles del barrio usan
los modelos/piezas descritos arriba; plaza, parque y salidas cerradas permanecen.

`modules/town_gen/town_navigation.gd` calcula caminos mínimos con proyecciones
sobre segmentos: incluye el tramo de calle desde la posición actual, sin
obligar a pasar por el cruce más cercano. El filtro de distritos excluye
calles cerradas. `accessible_edges(plan, districts)` es el filtro común de
geometría y navegación: un conector requiere ambos distritos abiertos.
Cada segmento conserva `district_pair`, incluso tras dividirse en un cruce.
La prueba navega por los distritos 0 y 1 y su corredor, con colisión de asfalto
y cruces. No cambia los lotes, calles ni áreas verdes al abrir el Centro.
`DashboardGps.guidance_provider` conecta el adaptador al GPS existente.

No está todavía en el menú ni sustituye Reparto/Endless. La prueba es offline
y conserva los resultados en memoria: no guarda campaña, no paga recompensas
ni sincroniza el nuevo barrio en cooperativo. Al salir limpia su estado temporal.

## Validación

- `tests/test_town_city.gd`: construcción de los seis distritos, todas las
  direcciones, siete conectores abiertos, doce entradas verdes, modelos a
  escala nativa, perfiles de almacenes/farmhouses/cabañas/pinos y dos landmarks.
  Asfalto físico en cada segmento y GPS desde todas las zonas a los pedidos.
  Bahía con lecho sumergido, muelle físico, plataformas niveladas y nieve local.
- `tests/test_town_terrain.gd` y `modules/route_gen/tests/test_terrain_platforms.gd`:
  alturas de plataformas indexadas iguales a la búsqueda exhaustiva, incluyendo
  solapamientos, rotaciones, bordes de tesela y coordenadas negativas. Cobertura
  entre distritos sin carreteras inventadas. El hook mantiene el resultado original.
  Veinte semillas de biomas conservan plano, acceso al muelle y distancias seguras
  de costa; Sierra conserva relieve entre plataformas.
- `tests/render_town_city.gd`: dos semillas, mapa completo y frentes/vistas
  de Industrial, Campo, Puerto y Sierra para revisar escala, apoyo y circulación.
  Añade vistas de bahía y muelle, nieve y las orillas de ambas semillas.

- `modules/town_gen/tests/test_town_plan.gd`: 100 semillas, conectividad de
  los seis distritos, variación, determinismo, roles iniciales, parques y
  lotes fuera de las calles y cruces unidos en el grafo. Compara las dos
  versiones, conserva todas las direcciones originales y comprueba parcelas
  compactas, separación entre patios, aceras y espacios verdes. Portable.
- `tests/test_town_prototype.gd`: escena real, edificios con colisión,
  barreras, plaza/monumento, modelos existentes, viviendas que caben en su lote,
  tres especies de árboles agrupadas y centros de calle despejados. Abrir el
  Centro conserva el plano y verifica sus edificios a escala nativa, áreas
  verdes, barreras restantes y soporte de asfalto a lo largo del corredor.
  Comprueba colisión continua de las entradas verdes y árboles alejados de ellas.
  Verifica reutilización del campo de terreno, alturas de calles estables,
  relieve exterior, tramos originales y ambientación agrupada del catálogo.
- `tests/render_town_prototype.gd`: dos semillas desde arriba y plaza a
  altura de calle para revisión visual, además de vistas de los dos distritos
  conectados y del Centro con sus comercios, aceras y entrada a la plaza.
- `modules/town_gen/tests/test_town_navigation.gd`: tramos parciales,
  desvíos entre calles paralelas, rutas inaccesibles y 300 recorridos de
  clientes y 100 rutas al Centro sobre 100 semillas. Comprueba conectores
  divididos y accesos cerrados. También corre en un proyecto vacío.
- `modules/town_gen/tests/test_town_walkways.gd`: cinco semillas, repetición
  exacta, plano sin mutaciones, superficies triangulables fuera del asfalto,
  alturas de rampas y entrada a las cuatro áreas verdes. Incluye un desvío
  alrededor de un lote rotado y selección vacía de distritos. Portable.
- `tests/test_town_delivery.gd`: carga real, conducción sobre asfalto,
  seis pedidos/cajas, selección/GPS, rechazo de una caja equivocada, entregas
  de ambos distritos en orden 3/1/2/6/4/5,
  posibilidad de volver al asiento y final al regresar al depósito; clientes
  con tres modelos distintos y estante de carga original. La exploración del
  Centro cambia solo la guía GPS y permite volver a los pedidos pendientes.
  Verifica cajas sin interpenetración y seleccionables apuntando en ambos
  niveles del estante, marcha real desde asfalto por acera/acceso sin saltar,
  F4/F7, seis registros únicos y regreso prematuro sin
  finalizar. Sobre 100 semillas comprueba seis destinos únicos, orden estable
  al invertir los lotes y 300 recorridos específicos a los clientes del Centro.
- `tests/render_town_delivery.gd`: depósito/camión, estante con seis cajas, cabina/GPS, casa de cliente,
  cliente del Centro y su ruta GPS. Algunas capturas GPU conservan una omisión
  intermitente de letras en el título; destinos, distancias y controles completos.

## Siguientes pasos del spike N-950

Medir duración, esfuerzo de carga, visibilidad de las casas y presupuesto de
render. Luego conectar campaña/guardado con semilla y versión del generador,
accesos desbloqueables y completar las manzanas interiores. Refinar el litoral
y el relieve con la medición del presupuesto de render.
El arroyo/corredor de ribera del diseño visual requiere registrar cauces y
construir sus pasos con los tramos existentes; todavía no está construido en la escena.
