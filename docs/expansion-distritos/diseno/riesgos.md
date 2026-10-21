# Riesgos técnicos de la expansión (D-0120)

> Qué puede romper el modo Empresa en lo técnico: severidad, evidencia en el repo, mitigación y la tarea `D-`
> que la hace. Parte de [reutilizacion.md](reutilizacion.md) (D-0119) y del código al 2026-10-21
> (`origin/main` 7a246ea). Las rutas de código son relativas a `do-not-drop/` y las líneas son de esa fecha.
> **Cómo se mantiene:** se revisa al cerrar cada fase, en la auditoría integral de D-2039 (que absorbió
> D-0249). En esa revisión cada riesgo queda mitigado (se tacha y se cita el PR que lo cerró) o sube o baja
> de severidad. Uno nuevo toma el próximo `R-`. Un P0 o P1 no se tacha sin la medición o el test que pide
> su mitigación.

**Severidad.** P0: pierde progreso o bloquea el corte vertical de F1. P1: rompe su fase si no se mitiga
(desincronía, tirones, presupuesto de red o de FPS pasado). P2: costo o fricción que crece con cada tarea.
P3: vigilar.

## Resumen

| ID | Riesgo | Sev. | Mitigación en | Fase |
|---|---|---|---|---|
| R-01 | Ancho de banda del galpón con empleados, cintas y cuerpos sincronizados | P1 | D-2002, D-1012, D-1115 | F1-F2 |
| R-02 | Join tardío: partes del snapshot que faltan y cajas vivas | P1 | D-0715.b, D-2017 | F1 |
| R-03 | Guardado: el cierre no guarda, un corte pierde todo, el día cortado se rehace mal | P0 | D-0236, D-0320 | F1 |
| R-04 | Save en versión 1, sin migraciones y con lectura tolerante | P2 | D-2026, D-1016, D-1116 | F2 |
| R-05 | Empleados: camino en grilla sin evitación y costo por empleado | P1 | D-1011, D-1020, D-0232 | F2 |
| R-06 | Cintas: 300 ítems, dibujado y cajas que caen con física | P1 | D-1101, D-1102, D-1120 | F2 |
| R-07 | N-917 otra vez: terreno de celdas en paralelo deja a Jolt sin hilos | P1 | D-0315, D-2011 | F1 |
| R-08 | Jolt con muchos cuerpos y cajas apiladas | P2 | D-2012, D-0318, D-0947 | F1-F2 |
| R-09 | Streaming medido con celdas vacías; tirones de primer uso sin pantalla de carga | P1 | D-2011, D-0315, D-0314 | F1 |
| R-10 | El host simula todo y cada peer tiene 31 celdas fijas: CPU y memoria | P1 | D-2002, D-2023, D-0947 | F1-F2 |
| R-11 | Agua: ola del shader contra flotación en CPU, fase distinta en cada peer | P1 | D-1301, D-1304 | F3 |
| R-12 | Vuelo: 44 m/s contra streaming, red y terreno lejano | P1 | D-1411, D-1404, D-1446 | F4 |
| R-13 | `--script` que pierde autoloads al nombrar clases nuevas (N-919) | P2 | D-0243 | F0-F5 |
| R-14 | Determinismo: pedidos por semilla y tripulación, tránsito por reloj | P2 | D-0246, D-0807, D-1504 | F1-F2 |
| R-15 | Regresiones en Entrega y Endless por archivos compartidos | P2 | D-0315, D-2039 | todas |
| R-16 | `CompanyNet` en 992 de las 1000 líneas del lint | P2 | D-2041 | F1-F2 |

## R-01 · Ancho de banda del galpón — P1 · F1-F2

- **Qué puede salir mal:** con 8 jugadores el galpón ya usa 19,8 de los 24 KB/s por cliente (modelo).
  Todo lo que el host replique de más sale de los 4,2 KB/s que quedan: empleados que caminan, cajas armadas
  y palets como cuerpos sincronizados, ítems en cinta, un vehículo afuera. Pasado el presupuesto, en Steam
  suben la latencia y las pérdidas para todos, y el galpón lleno con 8 es justo el caso que se promete.
- **Evidencia:**
  - `docs/rendimiento-pc.md` §"Ancho de banda del modo Empresa (D-2002)": con poses a 15/s, el galpón usa
    8,7 KB/s con 4 jugadores y 19,8 con 8. "Una salida afuera" (≤ 40) y "2 vehículos lejos" (≤ 64) siguen
    pendientes de D-2002.2.
  - Hoy el galpón no tiene sincronizadores propios: los bultos del piso son estáticos (`red-autoridad.md`
    §1, regla 10). La caja armada es un `DeliveryPackage` con sincronizador a 30/s
    (`scenes/gameplay/package/package.tscn:98-99`), que `NetRestThrottle` frena en reposo.
  - Estimación con el mismo modelo, no medida: un empleado replicado como un jugador a 15/s cuesta unos
    2,4 KB/s por cliente, lo que hoy cuesta la pose del jugador del host. Con 8 jugadores entran 1 o 2
    empleados. 20 empleados con 4 jugadores (el caso de D-1047) serían unos 57 KB/s.
  - El interest management (D-2022) quedó pospuesto a condición de que esta medición pase
    (`critica-alcance.md` §5.4, punto 4).
- **Mitigación:**
  1. Los empleados viajan en un RPC por lote del host (pose comprimida, 5-10 por segundo, `NetPoseSmoother`
     del lado que recibe), no con un sincronizador cada uno. Lo mide `test_company_bandwidth_budget` con 20.
  2. Cintas como grafo: viajan la entrada y la salida de cada ítem, y el avance lo calcula cada peer con el
     reloj del día (D-1115). Nunca viaja la posición de cada ítem.
  3. D-2002.2 mide una salida y 2 vehículos lejos apenas el mundo de la empresa tenga vehículo.
  4. Si D-1047 o D-1148 pasan el presupuesto, se reabre D-2022 en vez de bajar más el ritmo de las poses.
- **Tareas:** D-2002 (D-2002.2), D-1012, D-1115, D-1047, D-1148.

## R-02 · Join tardío con partes que faltan — P1 · F1

- **Qué puede salir mal:** el que entra tarde recibe stock, empresa, reloj, fase, mesas y piso, pero no el
  libro de pedidos, los palets con su estado ni las cajas armadas vivas. Además, si el sincronizador de un
  `DeliveryPackage` llega antes que el evento que lo crea, el cliente no resuelve el camino y esa caja no se
  mueve más en su pantalla.
- **Evidencia:**
  - `red-autoridad.md` §6, "Partes que faltan": `OrderBook` (D-0803/D-0807), palets (D-0605/D-0607) y cajas
    vivas (D-0709/D-0711).
  - Regla 10 (`red-autoridad.md:61-68`) y el caso real que la originó
    (`scripts/gameplay/package/package.gd:185-189`).
  - D-0715 figura ✅ en la tabla, pero su detalle deja abierta D-0715.b: crear el paquete en cada peer y
    mandar las cajas vivas en el snapshot (`detalle/F1-07-armado.md:143`).
  - El tamaño no es el problema: 300 unidades con el libro de caja lleno pesan 2 KB comprimidas, un solo
    trozo (`scripts/core/company/company_net.gd:104-113`).
- **Mitigación:** cada parte que se suma al snapshot trae su caso en `test_company_late_join`. D-0715.b usa
  el filtro de visibilidad de la regla 10 y llama a `update_visibility` después del último trozo. QA de red
  par y trío entrando a mitad de día (D-2017). Fuzz de agarrar y soltar a la vez (D-2027).
- **Tareas:** D-0715 (subtarea abierta D-0715.b), D-0807, D-2017, D-2027.

## R-03 · Guardado del día — P0 · F1

- **Qué puede salir mal:**
  1. Nada guarda al cerrar el día. El único guardado es el del día interrumpido, en el `_exit_tree` de
     `CompanyRoot`.
  2. Si el proceso muere (crash, matarlo, corte de luz), `_exit_tree` no corre y se pierde todo desde la
     última salida limpia al menú, que puede ser la partida entera.
  3. El día interrumpido carga plata, stock y libro de caja tal como estaban en el último evento, pero el
     reloj vuelve a las 08:00 y no hay pedidos, mesas ni salidas, porque no están en el save. Quedan
     unidades en `box:<id>` sin mesa e ids de caja que se pueden repetir. Por lo que se lee del código,
     salir en SUMMARY guarda el día ya cobrado como interrumpido, y al cargarlo se juega de nuevo con el
     alquiler ya pagado. Hay que confirmarlo con un test.
- **Evidencia:**
  - `scripts/gameplay/company_root.gd:26-29`: todo día se guarda "en curso", también uno ya cerrado, y
    guardar el cerrado "es el gancho de D-0206". El guardado está en `:238-248` y se llama desde
    `_exit_tree` (`:284-286`).
  - `scripts/core/company/company_save.gd:20-25` y `:107-110` (reloj a la apertura).
  - `scripts/core/company/company_state.gd:65-82`: `to_dict()` no tiene pedidos, mesas ni salidas.
  - `red-autoridad.md:399` ("un día cargado trae unidades en `box:<id>` sin mesa") y
    `detalle/F1-07-armado.md:143` (`_serial` sin persistir).
  - D-0206 figura ✅, pero `revisar/D-0206.md` dice "El guardado no está enganchado todavía".
  - `bot_company_day` guarda y carga por su cuenta en `close_day` (`tests/bot_company_day.gd:595-600`,
    `revisar/D-2016.md`): el criterio del corte vertical pasa sin que el gancho exista.
- **Mitigación:**
  1. Pasar D-0236 al corte de F1, que ya pide guardar al cierre (ítem 14 de `corte-vertical.md`). Guarda al
     entrar en SUMMARY, con el día siguiente como próximo, y al salir.
  2. Un día interrumpido carga el último cierre, o se guarda completo (pedidos, mesas, `_serial`, salidas).
     Nunca a medias.
  3. Tests: matar el proceso a mitad de día y recuperar el último cierre (el "hecho cuando" de D-0236), y
     salir en SUMMARY y volver no cobra ni descuenta dos veces.
  4. `bot_company_day` deja de guardar por su cuenta cuando el gancho exista.
- **Tareas:** D-0236, D-0320, D-0715 (D-0715.b, `_serial`).

## R-04 · Esquema del save sin migraciones — P2 · F2

- **Qué puede salir mal:** F2 agrega empleados con estación (D-1016), máquinas con contenido (D-1116) y,
  por R-03, pedidos y mesas. Una clave nueva sin subir la versión deja que un save viejo cargue con valores
  por defecto en silencio: empleados sin estación, unidades en lugares que ya no existen. Con Steam
  Auto-Cloud (D-2010) el mismo save viaja entre builds.
- **Evidencia:** `scripts/core/company/company_save.gd:29-34` (`VERSION = 1`, `MIGRATIONS = {}`).
  `company_state.gd:85-89`: lo que falta toma su valor por defecto. Ya hubo un caso: `interrupted` se sumó
  sin subir la versión (`company_save.gd:24-25`).
- **Mitigación:** toda clave que cambia lo que significa otra sube `VERSION`, con su migración y un save de
  la versión anterior guardado como fixture en `tests/`. D-1016 y D-1116 traen su migración. D-2026 mide el
  tamaño y la carga de 50 días (< 2 s).
- **Tareas:** D-1016, D-1116, D-2026 (y "Sin tarea todavía", punto 3).

## R-05 · Empleados: camino y costo — P1 · F2

- **Qué puede salir mal:** 20 empleados y 8 jugadores en un galpón de hasta 32 × 20 m, con pasillos de una
  celda de 1 m. El camino es un A* en grilla de 4 vecinos, sin evitación: dos empleados de frente en un
  pasillo se clavan. Es la queja más repetida de *Schedule I*. Además, si cada empleado decide en
  `_physics_process`, 20 son 20 búsquedas y decisiones por tick, más su cuerpo y su animación.
- **Evidencia:**
  - `scripts/gameplay/business/walk_navigation.gd:9-10`: es "a grid A* and not an engine NavigationMesh on
    purpose".
  - `company_tuning.gd:99` (celda de 1 m), `:107-108` (hasta 32 × 20) y `:112` (hasta 100 piezas).
  - D-1011 pide "navmesh y evitación" y D-0908 (✅) dice "navmesh": el texto y el código no coinciden.
  - `referencia-schedule-1.md:95` ("IA que se traba").
- **Mitigación:**
  1. Las decisiones van en el tick de negocio de 4 Hz (D-0232), no por frame. El camino se recalcula solo
     cuando cambia `WalkNavigation.version`.
  2. Evitación en la misma grilla: cada empleado reserva su celda siguiente y, si está ocupada, espera o
     rodea. Ante un jugador espera con tiempo máximo. Se corrige el texto de D-1011.
  3. Medición: D-1011 (bot con 8 empleados un día entero sin trabarse), D-1020 (20 dentro del presupuesto),
     D-1040 (LOD) y D-1046 (no atraviesan paredes después de ampliar).
- **Tareas:** D-1011, D-1020, D-0232, D-1040, D-1046.

## R-06 · Cintas y automatización — P1 · F2

- **Qué puede salir mal:** 300 ítems en cinta como nodos con `_process` o con física se comen el frame. Las
  cajas que se caen de la cinta "con física de verdad" (D-1137) o una caja explosiva que estalla en el
  galpón (D-1138) crean cuerpos de golpe. Antes del arreglo, cada caja arruinada costaba 40-110 ms en un
  tick, y todavía quedan picos de 26-42 ms por el polvo y la ragdoll que nacen al arruinarse.
- **Evidencia:** el encabezado de `11-automatizacion.md` ("se simulan como grafo (no física) y se dibujan
  con MultiMesh"). D-1101, que absorbió D-0226 con la meta de 1000 ítems por tick en < 1 ms.
  `docs/rendimiento-pc.md` §"Camión lleno y 5 jugadores".
- **Mitigación:** el grafo corre en el tick de negocio (D-0232) y se dibuja con un MultiMesh por tipo de
  caja (D-1102). Una caja es cuerpo solo mientras cae, con un tope de caídas a la vez (D-1137).
  `bench_conveyor` deja su número en `rendimiento-pc.md` (D-1120). D-1147 prueba ciclos en el grafo. La
  parte de red está en R-01.
- **Tareas:** D-1101, D-1102, D-1120, D-1137, D-1147.

## R-07 · N-917 otra vez: terreno y pool de hilos — P1 · F1

- **Qué puede salir mal:** en N-917, `TerrainField` ocupaba todo el `WorkerThreadPool`. Jolt corre sus jobs
  en ese mismo pool: se acumularon hasta los 2048 fijos y el paso de física esperó en el hilo principal,
  con cuadros de 0,4-1,8 s tapados por la pantalla de carga. El arreglo deja un hilo libre, pero solo
  cuando hay un grupo de tareas a la vez (`worker_tasks()` = núcleos − 1). En el mapa continuo, Campo usa el
  terreno de `route_gen` y las celdas cargan escenas en el mismo pool. Dos celdas que arman terreno a la
  vez piden 2 × (núcleos − 1) tareas, y ya no hay pantalla de carga que tape el tirón.
- **Evidencia:** N-917 en `docs/tareas-nacho-archivo.md`. `modules/route_gen/terrain_field.gd:452-463`,
  `:492-494` y `:801-803`. `scripts/gameplay/districts/road_graph.gd:66` (`register_terrain`).
  `modules/world_cells/cell_streamer.gd:6-7` (`load_threaded_request`).
- **Mitigación:** un solo grupo de terreno a la vez en todo el juego (una cola en `TerrainField` o en
  `CompanyCells`), o el terreno de Campo horneado en recursos por celda en vez de calcularse en vivo. Se
  extiende `test_jolt_job_budget` a dos celdas con terreno cargando juntas y un cuerpo despierto.
- **Tareas:** D-0315, D-2011 (D-2011.1).

## R-08 · Jolt con muchos cuerpos y cajas apiladas — P2 · F1-F2

- **Qué puede salir mal:** el presupuesto es de 400 cuerpos. El modo Empresa suma cajas armadas (16
  pedidos por día como tope en F1, más con empleados) apiladas en el despacho y en la carga, palets en la
  zorra y cajas que caen de la cinta. En Jolt, una pila alta tiembla o no se duerme, y una pila que cae
  despierta a todas. Además, Jolt no le informa a Godot cuántos cuerpos están activos: el bench cuenta
  nodos y no ve el costo real.
- **Evidencia:**
  - `corte-vertical.md` §4 (≤ 400 cuerpos, ≤ 6000 nodos).
  - `docs/rendimiento-pc.md` §"Camión lleno y 5 jugadores": 147 `RigidBody3D`, 12-14 despiertos, paso de
    Jolt ≤ 3 ms, y `PHYSICS_3D_ACTIVE_OBJECTS` siempre en 0.
  - `company_tuning.gd:167` (16 pedidos).
  - `revisar/D-0318.md`: D-0318.1 sigue abierta y nadie registra cajas sueltas con `track_body`, así que
    las de una celda descargada no se congelan.
- **Mitigación:** el despacho y la carga tienen huecos fijos, como los `package_mount` del camión, en vez
  de pilas libres. Las unidades en estantes siguen siendo datos, no cuerpos. D-0318.1 registra las cajas
  sueltas. `bench_company` cuenta `RigidBody3D` despiertos, como ya hace `bench_drive`. D-2012 fija el
  presupuesto y D-0947 lo mide con el galpón grande lleno.
- **Tareas:** D-2012, D-0318 (D-0318.1), D-0947, D-1137.

## R-09 · Streaming medido con celdas vacías — P1 · F1

- **Qué puede salir mal:** el criterio del corte ("ningún frame > 50 ms al manejar de Centro a Campo") hoy
  pasa con celdas vacías, en headless y sin shaders. Una celda con contenido se arma entera, con su
  `add_child`, en un solo paso: la tajada de 4 ms solo corta entre una celda y la siguiente. Además, la
  primera vez que aparece cada tipo de tramo cuesta 80-120 ms en frío (modelos, mallas y shaders de primer
  uso). Hoy eso lo tapa la pantalla de carga, pero en el mapa continuo no hay ninguna después de la
  inicial.
- **Evidencia:**
  - `tests/test_company_cells.gd:14`, `:52` y `:69` miden sobre `CompanyCells.new()` sin contenido;
    `scripts/gameplay/districts/company_cells.gd:9-11` dice "until then a cell is an empty `Node3D`".
    D-0313 se cerró con esa medición.
  - `modules/world_cells/cell_streamer.gd:185-202` (`_instance_ready`).
  - `docs/rendimiento-pc.md` §N-219 (último párrafo) y §"Carga y memoria" (frame de 380 ms en frío bajo
    la cubierta).
  - Punto 5 de `docs/decisiones/2026-10-04-mapa-continuo.md` (no hay pantallas de carga).
  - `bench_company` imprime `drive: not_available` (D-2011.1) y su paso de CI es informativo
    (`.github/workflows/tests.yml:221-230`, `|| true`).
- **Mitigación:** en la carga inicial se precalientan modelos y shaders de todo tipo de tramo y decorado
  del mapa, como hizo N-409 con la entrega. Una celda se arma por piezas a lo largo de varios frames.
  D-2011.1 mide con contenido real y en ventana (rutina `pc-build`). La medición de D-0313 se repite cuando
  estén D-0315 y D-0314. En CI se cuenta lo que no depende de la GPU ("Sin tarea todavía", punto 2).
- **Tareas:** D-2011 (D-2011.1), D-0315, D-0314, D-2012.

## R-10 · El host simula todo; celdas fijas y memoria — P1 · F1-F2

- **Qué puede salir mal:** el host simula todos los vehículos, así que tiene cargadas 5 × 5 celdas
  (1,6 km²) alrededor de cada ancla, más las fijas. Además corre empleados, cintas, pedidos y la física de
  cada caja, y encima juega con su propia GPU. Cada peer tiene siempre 31 celdas fijas (el galpón y las
  tres calles principales) que nunca se descargan y que van a crecer con su contenido. Como referencia,
  una partida de Reparto hoy llega a 479 MiB estáticos y 262 MiB de video.
- **Evidencia:** punto 6 de la decisión del mapa continuo (el host simula todo; máximo 2 vehículos lejos).
  `company_tuning.gd:42-47` (celdas de 256 m, radio 2, impostores a 5). `company_cells.gd:5-8` y `:13-17`:
  31 celdas fijas, contadas con la misma cuenta de `pin_fixed_cells()`. `docs/rendimiento-pc.md`
  §"Carga y memoria". D-2002.2 sigue pendiente.
- **Mitigación:** medir antes de abrir la segunda zona. D-2002 (con D-0317 adentro) decide si el tope de 2
  vehículos lejos se sostiene. D-2023 corre un bot de 8 jugadores en CI nocturno. Memoria con el galpón
  grande (D-0947), preset bajo (D-2038) y fugas en 10 días (D-2013). Las celdas fijas se cargan en versión
  liviana (calle e impostor), sin todo el decorado.
- **Tareas:** D-2002, D-2023, D-0947, D-2038, D-2013.

## R-11 · Agua y flotación — P1 · F3

- **Qué puede salir mal:** la lancha flota con la altura de ola que calcula la CPU del host y el agua se
  dibuja con un shader. Si las dos funciones no dan lo mismo (±5 cm), la lancha atraviesa o sobrevuela las
  olas. Si el shader usa su `TIME`, cada peer ve otra fase de ola, porque ese reloj arranca con su proceso:
  en los clientes, la lancha del host flota sobre olas que no están. Además, la caja que cae al agua
  (D-1308) suma cuerpos que flotan y hay que replicar.
- **Evidencia:** en `13-lancha-e-islas.md`, D-1301 es xhigh y pide "la altura de la ola en CPU coincide con
  el shader ±5 cm". `critica-alcance.md:59` califica el riesgo de "muy alto" (agua en GL Compatibility,
  física y red). El día ya tiene un reloj común por ancla (`docs/decisiones/2026-10-04-reloj-por-ancla.md`,
  `GameClock`).
- **Mitigación:** la fase de la ola sale del reloj del día, con un uniform global que cada peer fija desde
  `GameClock` (nunca `TIME`). Una sola función de ola, con su copia en GLSL y un test que compara las dos.
  La flotación la calcula el host y los clientes solo dibujan (D-1304). Preset para GPU baja (D-1346) y
  auditoría de red (D-1348).
- **Tareas:** D-1301, D-1302, D-1304, D-1346, D-1348.

## R-12 · Vuelo y mapa visto desde lejos — P1 · F4

- **Qué puede salir mal:**
  - A 160 km/h (44 m/s), la avioneta cruza una celda de 256 m en menos de 6 s. El radio de carga
    (2 celdas, 512 m) le da unos 11 s de margen, y una pista de montaña puede no estar cargada en el
    cliente al aterrizar.
  - Desde el aire se ve el mapa entero, con zonas a hasta 3,7 km del origen. Más allá del radio de
    impostores (5 celdas, 1,28 km) no hay nada, y el impostor por defecto es un bloque plano.
  - En red, a 30 poses por segundo hay 1,5 m entre poses, y `NetPoseSmoother` dibuja 2 intervalos atrás:
    los demás ven la avioneta unos 3 m detrás de donde está, con la carga y los pasajeros adentro.
  - Precisión: sin origen flotante (punto 2 de la decisión del mapa continuo), a 3,7 km el `float` tiene
    pasos de 0,24 mm y alcanza. Pero el tope de 6 × 6 km que la decisión ubica "en `world_tuning.gd`"
    no existe en el código: nada impide que el mapa crezca. Las zonas de hoy ocupan x −1280..3072 y
    z −3072..2048.
- **Evidencia:** `flota.md:25` (160 km/h). `company_tuning.gd:44-47`. `cell_streamer.gd:12-13` (impostor
  por defecto). `data/zones/islas.tres` y `volcan.tres` (`bounds`). `docs/rendimiento-pc.md`, "Cómo está
  hecho D-2002.3". `critica-alcance.md:60` (riesgo "muy alto").
- **Mitigación:** un radio de carga que crece con la velocidad del ancla (más celdas adelante que atrás) y
  las pistas como celdas fijas (D-1411, D-1406). Impostores de todo el mapa (D-1411) con la distancia de
  dibujo medida (D-1446). Predicción para la avioneta (D-1404) y auditoría de red (D-1448). El tope del
  mapa como constante con su chequeo ("Sin tarea todavía", punto 4).
- **Tareas:** D-1401, D-1404, D-1406, D-1411, D-1446, D-1448.

## R-13 · `--script` que pierde autoloads (N-919) — P2 · F0-F5

- **Qué puede salir mal:** un `--script` (tests, `bench_*`, `render_*`) compila el árbol de clases antes
  que los autoloads. Una clase nueva que nombra un autoload, o que arrastra a otra que lo nombra, deja un
  nodo sin script y no avisa. Pasó con el #208: `bench_drive` midió sin HUD hasta el arreglo de N-919.
- **Evidencia:**
  - El caso original está en `docs/tareas/N-919.md`.
  - Hoy está cubierto: `tests/test_hud_script_loads.gd:20-26` y `:82-91` llegan a `CompanyState`
    (D-0202.3), y CI corre con `STRICT_SCRIPT_ERRORS: 1` (`.github/workflows/tests.yml:95`). El código
    nuevo llega a los autoloads por ruta (`company_net.gd:216`, `day_cycle.gd:496`, `company_state.gd:231`).
  - Lo que queda abierto: es una convención escrita en comentarios, sin un chequeo que la haga cumplir en
    `scripts/core/company/` ni en `scripts/gameplay/business/`. Y `bench_company` corre con `|| true`: si
    pierde un autoload, sus números cambian sin que nada falle, igual que en N-919.
- **Mitigación:** se reescribe D-0243, porque su "hecho cuando" (`test_hud_script_loads` con
  `CompanyState`) ya lo cumplió D-0202.3. Que el test llegue también a `CompanyRoot` y `CompanyNet`, y que
  el paso de `bench_company` falle si el log trae `SCRIPT ERROR`.
- **Tarea:** D-0243.

## R-14 · Determinismo: semilla de pedidos y reloj del tránsito — P2 · F1-F2

- **Qué puede salir mal:**
  - Pedidos: `OrderGenerator.generate_day()` y `OrderRhythm` dependen del tamaño de la tripulación. El
    detalle de D-0803 dice "mismos minutos en todos los peers", como si cada peer los calculara, pero el
    contrato de red dice que decide el host. Si algún peer los genera, alguien que entra o se va a mitad de
    día, o un día interrumpido que se rehace con otra tripulación (R-03), produce pedidos distintos de los
    que ya están reservados.
  - Tránsito y peatones: la crítica los pasó a rieles calculados con el reloj del host, sin replicar
    (D-1504, D-1505). El reloj se toma una vez por ancla, menos medio RTT, y su test admite ±1 min de juego
    (1,5 s reales). Esa tolerancia, en un auto a 12 m/s, son 18 m. Y el choque lo decide el host.
- **Evidencia:** `scripts/gameplay/business/order_generator.gd:32-47` y `order_rhythm.gd:26`.
  `detalle/F1-08-pedidos.md:49-52`. `red-autoridad.md` §1, regla 1. `critica-alcance.md:90-94`. La
  decisión del reloj por ancla. `detalle/F0-02-arquitectura.md:268`.
- **Mitigación:** los pedidos se generan solo en el host al abrir el día y quedan fijos en el `OrderBook`,
  que viaja en el snapshot y se guarda (D-0807, D-0236). D-0246 audita que nadie más los genere. Para el
  tránsito, el desfase del reloj se mide en red real y tiene que quedar por debajo del largo de un auto
  (D-1504), con auditoría de red (D-0349).
- **Tareas:** D-0246, D-0807, D-1504, D-1505, D-0349.

## R-15 · Regresiones en Entrega y Endless — P2 · todas

- **Qué puede salir mal:** S1 dice que Entrega y Endless no cambian, pero la expansión ya tocó archivos
  del juego base: `vehicle.gd` (D-0208 en el #525, D-0209 en el #543), `package_rescue.gd` (#543),
  `delivery_house.gd` (D-0312, #552) y el ritmo de poses del jugador según el modo (D-2002.3). Un cambio
  en el manejo, el cuidado de la caja o la puerta no siempre rompe un test, y `bench_drive` mide en CI
  pero no falla por sus números.
- **Evidencia:** `reutilizacion.md` §1 y el `git log` de esos archivos desde el 2026-10-04. Los tests que
  protegen son `test_reference_truck`, `test_reference_truck_golden` y `test_route_golden`.
  `.github/workflows/tests.yml:200-207`.
- **Mitigación:** un PR de la expansión que toca `scripts/gameplay/vehicle/`, `package/`, `route/` o
  `player/` corre además los filtros `truck`, `route` y `package`, y deja su aviso. D-0315 exige los tests
  de ruta actuales en verde dentro del modo Empresa. D-2039 compara la serie de `bench_drive` de la PC
  antes y después de cada fase.
- **Tareas:** D-0315, D-2039.

## R-16 · `CompanyNet` contra el tope de líneas — P2 · F1-F2

- **Qué puede salir mal:** `CompanyNet` maneja peticiones, eventos, snapshot, stock y piso, y cada acción
  nueva le suma un `kind`. Está en 992 líneas con un tope de 1000 en el lint, así que la próxima acción no
  entra, y F2 trae empleados, cintas, palets y vehículos. Partirlo apurado dentro del PR de una feature de
  red es una manera conocida de meter un bug de autoridad.
- **Evidencia:** `scripts/core/company/company_net.gd` (992 líneas). `gdlintrc:21` (`max-file-lines:
  1000`). `red-autoridad.md:386` ("la próxima acción tiene que sacar algo más"). Ya hay piezas separadas
  que sirven de modelo: `CompanyTableNet`, `CompanyLayoutNet` y `CompanySnapshot`.
- **Mitigación:** antes de F2 se separan el armado de trozos del snapshot y el despacho de peticiones por
  dominio (como `CompanyTableNet`), con los tests `company` en verde y sin cambiar el protocolo.
- **Tareas:** D-2041 (no alcanza sola) y "Sin tarea todavía", punto 1.

## Sin tarea todavía

1. **Partir `CompanyNet` (R-16).** Propuesta para el grupo 02: `constructor-red`, esfuerzo medium. Hecho
   cuando `company_net.gd` baja de 800 líneas, `PROTOCOL_VERSION` no cambia y `tools/run-tests.sh company`
   sigue en verde.
2. **Compuerta de conteos en CI (R-08, R-09).** `bench_company` imprime `nodes`, `objects`, `draw_calls` y
   `physics_bodies`, que no dependen de la velocidad de la GPU. Propuesta: sumarlo a D-2012, y que el paso
   falle si se pasan los topes de `corte-vertical.md` §4 (≤ 900 draw calls, ≤ 400 cuerpos, ≤ 6000 nodos).
   Los FPS siguen siendo informativos.
3. **Regla de versión del save (R-04).** Propuesta: un test que guarde la lista de claves de
   `CompanyState.to_dict()` por versión y falle si cambian sin que suba `CompanySave.VERSION`.
4. **Tope del mapa en código (R-12).** La decisión del mapa continuo lo pone en `world_tuning.gd`, que no
   existe. Propuesta: una constante en `company_tuning.gd` (±3072 m cubre las zonas de hoy) y que D-0245
   falle si algún `ZoneDefinition.bounds` se sale de ahí.

## Fuentes

- `docs/expansion-distritos/README.md`, `detalle/supuestos.md`, `detalle/F0-01-diseno.md`,
  `detalle/F0-02-arquitectura.md`, `detalle/F0-20-red-y-ci.md`, `detalle/F1-03-distritos.md`,
  `detalle/F1-07-armado.md` y `detalle/F1-08-pedidos.md`.
- `diseno/`: `reutilizacion.md`, `corte-vertical.md`, `critica-alcance.md`, `red-autoridad.md`,
  `flota.md`, `referencia-schedule-1.md` y `mapa.md`.
- Tablas de grupo: `02`, `03`, `09`, `10`, `11`, `13`, `14`, `15` y `20`.
- `docs/decisiones/`: `2026-10-04-mapa-continuo.md`, `2026-10-04-reloj-por-ancla.md`,
  `2026-10-19-pose-galpon-15hz.md`, `2026-10-19-mesa-compartida-red.md` y `2026-10-12-modulos-expansion.md`.
- `docs/rendimiento-pc.md`: N-219, N-220, "Camión lleno y 5 jugadores", "Carga y memoria" y "Ancho de
  banda del modo Empresa (D-2002)".
- `docs/arquitectura.md` §10.
- N-917 en `docs/tareas-nacho-archivo.md` y `docs/tareas/N-919.md`.
- `revisar/D-0206.md`, `revisar/D-0203.md`, `revisar/D-0318.md` y `revisar/D-2016.md`.
- Código: `scripts/core/company/` (`company_net.gd`, `company_save.gd`, `company_state.gd`,
  `company_tuning.gd`, `game_clock.gd`, `day_cycle.gd`) y `scripts/gameplay/company_root.gd`.
- Código: `scripts/gameplay/business/walk_navigation.gd`, `order_generator.gd` y `order_rhythm.gd`.
- Código: `scripts/gameplay/districts/company_cells.gd` y `road_graph.gd`.
- Código: `modules/world_cells/cell_streamer.gd` y `modules/route_gen/terrain_field.gd`.
- Código: `scenes/gameplay/package/package.tscn`, `scripts/gameplay/package/package.gd` y
  `data/zones/*.tres`.
- Tests y CI: `tests/test_company_cells.gd`, `tests/test_hud_script_loads.gd`, `tests/bot_company_day.gd`,
  `tests/bench_company.gd`, `.github/workflows/tests.yml` y `gdlintrc`.
