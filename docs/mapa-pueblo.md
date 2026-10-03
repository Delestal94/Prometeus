# Ciudad procedural — barrio y Centro jugables del spike

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
En la prueba offline están abiertos Barrio y Centro. Los accesos restantes
se abrirán por progresión/capacidad del vehículo en un paso posterior.
El trazado completo se genera antes de abrir distritos: desbloquear una zona
no debe cambiar las calles ni mover las casas existentes.

## Implementado en esta rama

`modules/town_gen/town_plan.gd` devuelve datos, sin escenas ni autoloads:

- Semilla y `generator_version = 1`.
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
- Estante de carga con los modelos originales de marcos y bandejas, tres
  pedidos separados y sus colisiones.
- Robles, abedules y arces originales agrupados por `DressingBatcher`, con
  colisión de troncos; bancos y farolas originales apoyados sobre el terreno.

Esta integración conserva los assets originales. El monumento, pavimentos
y suelo amplio siguen siendo geometría del prototipo; faltan terreno, aceras,
ambientación de los cuatro distritos restantes y medición del presupuesto de render.

### Abrir y recorrer

Abrir la escena en Godot y pulsar **F6**. Cámara libre: WASD mueve, Q/E cambia
altura, botón derecho permite mirar y Shift acelera. La escena acepta
`--town-seed=4242` después de `--` para repetir un mundo. También puede
fijarse `world_seed` en el inspector. Con valor cero toma la semilla de la
sesión si existe y genera una nueva en una prueba independiente.

La escena de inspección conserva la cámara libre. Para jugar, abrir
`scenes/gameplay/town/town_delivery.tscn` y pulsar **F6**, sin sesión online:

1. Tomar los paquetes A/B/C del estante frente al depósito y cargarlos en
   los soportes del camión usando **E**. El cartel y el prompt muestran su código.
2. Subir al asiento del conductor con **E**: empieza el reparto. **WASD**
   mueve al jugador o conduce; los controles habituales del camión siguen activos.
3. **F1/F2/F3** eligen cualquiera de las casas pendientes. El GPS de la cabina
   indica distancia por calles y el siguiente cruce, además de casa/código.
4. **F4** dirige el GPS al Centro, a un punto de calle junto a su plaza.
   Recorrerlo es opcional: conserva los tres pedidos. **F1/F2/F3** vuelven a
   la navegación del cliente. El Centro tiene comercios con toldos, predominio
   de viviendas de dos plantas, plaza/monumento, parque y mobiliario original.
5. Bajar con **E**, sacar el paquete y tocar el timbre de la casa correcta.
   Una caja equivocada deja el pedido pendiente; el estado de la caja afecta
   la entrega como en el juego. Los pedidos pueden resolverse en cualquier orden.
6. Tras cerrar los tres pedidos, volver al depósito y detener el camión.
   El regreso al depósito tiene prioridad sobre la exploración del Centro.
   **Esc** libera o vuelve a capturar el mouse.

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

- `modules/town_gen/tests/test_town_plan.gd`: 100 semillas, conectividad de
  los seis distritos, variación, determinismo, roles iniciales, parques y
  lotes fuera de las calles y cruces unidos en el grafo. Portable.
- `tests/test_town_prototype.gd`: escena real, edificios con colisión,
  barreras, plaza/monumento, modelos existentes, viviendas que caben en su lote,
  tres especies de árboles agrupadas y centros de calle despejados. Abrir el
  Centro conserva el plano y verifica sus edificios a escala nativa, áreas
  verdes, barreras restantes y soporte de asfalto a lo largo del corredor.
- `tests/render_town_prototype.gd`: dos semillas desde arriba y plaza a
  altura de calle para revisión visual, además de vistas de los dos distritos
  conectados y del Centro con sus comercios.
- `modules/town_gen/tests/test_town_navigation.gd`: tramos parciales,
  desvíos entre calles paralelas, rutas inaccesibles y 300 recorridos de
  clientes y 100 rutas al Centro sobre 100 semillas. Comprueba conectores
  divididos y accesos cerrados. También corre en un proyecto vacío.
- `tests/test_town_delivery.gd`: carga real, conducción sobre asfalto,
  selección/GPS, rechazo de una caja equivocada, entregas en orden 3/1/2,
  posibilidad de volver al asiento y final al regresar al depósito; clientes
  con tres modelos distintos y estante de carga original. La exploración del
  Centro cambia solo la guía GPS y permite volver a los pedidos pendientes.
- `tests/render_town_delivery.gd`: depósito/camión, cabina/GPS, casa de cliente y GPS dirigido al Centro.

## Siguientes pasos del spike N-950

Medir duración, esfuerzo de carga, visibilidad de las casas y presupuesto de
render. Luego conectar campaña/guardado con semilla y versión del generador,
accesos desbloqueables y ambientación específica de los demás distritos.
El arroyo/corredor de ribera del diseño visual requiere terreno y geometría
adicional; todavía no está construido en la escena.
