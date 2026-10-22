# Roles de la tripulación de 1 a 8 (D-0110)

> Quién queda en el galpón, quién sale y qué hace el que se queda, según cuántos jugadores haya. Fuentes:
> [vision.md](vision.md) §8, [supuestos.md](../detalle/supuestos.md) (S3, S4, números del corte vertical) y
> el [mapa continuo](../../decisiones/2026-10-04-mapa-continuo.md) (máx. 2 vehículos lejos del galpón).
> Los números viven en `company_tuning.gd`; acá solo se razonan. Los roles no son clases fijas: cualquiera
> hace cualquier cosa y se reparten solos. La tabla dice **cómo debería repartirse** y es lo que mide el bot.

## 1. Regla de diseño

**Nunca un jugador más de 2 min (de reloj real) sin una caja en las manos o un vehículo que manejar.**
Una caja en las manos incluye: llevar un palet, un producto de estante a la mesa, una caja armada al
despacho o la caja que se cuida en el asiento. Esperar en la dársena que llegue el proveedor no cuenta;
si el diseño obliga a eso, hay que darle algo que hacer (armar la tanda siguiente). El bot de D-0111
(`bot_company_day`) registra el mayor tramo sin caja ni volante por jugador y falla el corte si pasa de 120 s.

Reglas comunes:

- **Pedidos por día:** `6 + 2 × jugadores`, tope 16 (1 → 8, 2 → 10, 3 → 12, 4 → 14, 5 o más → 16).
- **Salidas simultáneas:** como máximo 2 vehículos lejos del galpón a la vez.
- **Galpón congelado** (S4): si toda la tripulación sale y no hay empleados, el reloj del galpón (proveedor,
  vencimientos de armado) se pausa. El reloj de los pedidos **sigue**: la ventana de entrega es de 4 h de
  juego desde que entra el pedido, y se cumple en la ruta.
- **Una salida** = un vehículo con 1 conductor y 0 a 3 pasajeros (reparto sugerido; la camioneta tiene 8 asientos, [flota.md](flota.md)); cada
  pasajero cuida **una** caja (`PackageCare`), y el conductor lleva la suya solo si va solo.
- **Estaciones** (D-0904 y siguientes): **Dársena** (recibir palets), **Estantes** (guardar y sacar
  productos), **Heladera** (productos fríos, desde que haya fríos), **Mesa de armado** (caja, insumos,
  productos, cinta), **Tablero de pedidos** (D-0804) y **Despacho** (cajas listas por salida, carga del vehículo).

## 2. Tablas por cantidad de jugadores

### 2.1 Un jugador

| Momento | Qué hace | Estaciones |
|---|---|---|
| 08:00-08:30 | Espera al proveedor armando con el stock que quedó (si hay pedidos) | Tablero, Estantes, Mesa |
| 08:30 | Descarga el palet y guarda | Dársena, Estantes |
| Mañana | Arma de a una caja, en orden de vencimiento | Mesa, Despacho |
| Cuando hay 3-4 cajas listas o un pedido por vencer | **Sale solo** con la camioneta; las cajas van al asiento de al lado, se cuidan de a una | Despacho → ruta |
| Mientras sale | Galpón congelado | — |
| Cierre | Vuelve y cierra el día | Tablero |

Salidas por día: 2 a 3. Solo no hay tiempo muerto porque el galpón se pausa mientras maneja; el
costo es que la ruta no la puede cuidar nadie más: **el solitario sale con pocas cajas** (se prioriza
por vencimiento y no por rentabilidad).

### 2.2 Dos jugadores

| Rol | Se queda | Sale |
|---|---|---|
| A (galpón) | Descarga, estantes, arma, despacha | — |
| B (ruta) | — | Maneja con 1-2 cajas mientras A sigue armando |

- Una salida a la vez. Mientras B está afuera, A arma la tanda siguiente: **el galpón no se congela**, y A
  tiene siempre una caja en las manos.
- Cuando B vuelve se intercambian si quieren (el que armó sale, el que manejó arma): el reparto es
  voluntario, no obligado por el diseño.
- Si A también sale (tanda grande o pedido urgente), el galpón se congela y salen juntos: conductor y
  pasajero con su caja.
- Salidas por día: 3 a 4, en su mayoría 1 pasajero.

### 2.3 Tres y cuatro jugadores

| Rol | Se queda | Sale |
|---|---|---|
| Recepción y estantes (1) | Dársena, estantes, heladera, reposición de la mesa | — |
| Armado (1) | Mesa, tablero, etiquetas y sellos | — |
| Ruta (1-2) | — | Conductor y, con 4, un pasajero que cuida la caja |

- Con 3, el que queda en el galpón **alterna recepción y armado**: mientras no hay palet, arma. Con 4, la
  recepción se separa del armado y hay una segunda caja armándose en paralelo.
- Una o dos salidas simultáneas; la segunda solo con 4 y con pedidos de zonas distintas.
- El que maneja puede ser el que armó la caja: cuidarla en el viaje es parte de la gracia
  ("lo que armaste es lo que vas a sufrir").
- Salidas por día: 4 a 6.

### 2.4 Cinco a ocho jugadores

| Rol | Cantidad | Se queda | Sale |
|---|---|---|---|
| Recepción y estantes | 1 | Dársena, estantes, heladera | — |
| Armado | 2-3 (mesa propia cada uno; la 2ª mesa es D-0715/D-0904) | Mesa, tablero | — |
| Despacho y carga | 1 | Despacho, carga del vehículo, tablero | — |
| Ruta A | 1-2 | — | Vehículo 1 |
| Ruta B | 1-2 | — | Vehículo 2 |

- Con 5 el despacho lo hace uno de los armadores; con 8 hay un especialista por estación.
- Siempre alguien en el galpón: no se congela salvo que **todos** decidan salir a la vez.
- Dos salidas simultáneas (el máximo del mapa); una tercera espera a que vuelva una.
- Con 6 o más puede haber **dos personas en la misma mesa** (uno pone productos, otro la cinta, D-0715).
- Salidas por día: 6 a 8, con pedidos de varias zonas.

## 3. Qué hace el que se queda mientras los otros manejan

El tiempo de espera es el riesgo de aburrir. En orden de prioridad:

1. **Armar la próxima tanda** con los pedidos de menor vencimiento.
2. **Recibir** el palet si llegó (08:30) y **guardar** (estantes).
3. **Reponer insumos** de la mesa (cinta, cajas, relleno) hasta el nivel mínimo.
4. **Despachar y cargar** lo que ya está listo, para que el que vuelve se lleve la camioneta cargada.
5. **Atender el tablero**: priorizar pedidos (D-0838) y mirar el celular de la tripulación (D-0814).

Si no hay pedidos que armar ni nada que guardar, el diseño tiene un hueco: la regla de los 2 min lo detecta
y se corrige subiendo los pedidos por jugador o agregando una tarea en la estación.

## 4. Escalado y bordes

- **Entra o sale alguien a mitad de partida:** los roles no se reasignan solos; la tabla de su cantidad se
  usa como sugerencia en el tutorial. El tope de pedidos del día se fija al abrir el día.
- **Solo uno vuelve de la ruta en un grupo grande:** el galpón sigue (con alguien adentro); no hay congelado.
- **El host sale** (en modo Empresa el host simula el mundo): sigue la regla de red vigente; si queda
  la sesión sin host, termina el día como hoy el juego actual.
- **Sin empleados (F1)** el galpón no avanza solo. Desde F2 los empleados toman las estaciones vacías
  (recepción, armado básico), y las tablas de arriba se corren una fila hacia "menos jugadores en el galpón".

## 5. Cómo se mide

| Qué | Cómo | Umbral |
|---|---|---|
| Tiempo sin caja ni volante por jugador | `bot_company_day` con 1, 2 y 4 bots | máx. 120 s |
| Pedidos completados por jugador y día | `sim_economy` (D-0540) | 1 jugador no pierde más de la mitad por vencimiento |
| Salidas por día | contador del bot | dentro de los rangos de las tablas |

## 6. Modo solo (D-0126)

Qué automatiza el juego para que **una persona sola** lleve la empresa sin aburrirse ni quebrar. Lo verifica
el bot de D-2024 (`bot_company_solo`, 20 días) y lo construye D-0151. Decisión:
[2026-10-22-modo-solo.md](../../decisiones/2026-10-22-modo-solo.md).

### 6.1 Regla

- **No es un modo aparte ni un interruptor.** El juego cuenta la tripulación al abrir el día
  (`crew_size`: jugadores conectados, host incluido; los empleados no cuentan) y, si es **1**, prende las
  ayudas de solitario de §6.2 hasta el cierre. Igual que el tope de pedidos (§4): si entra alguien a mitad
  del día, las ayudas siguen hasta el cierre y el día siguiente se recalculan.
- **Se automatiza lo que en coop hace "el que se queda"** (§3: reponer, pedir, ordenar), nunca el núcleo:
  armar, manejar y cuidar la caja siguen siendo del jugador.
- Cada ayuda es una regla chica del host con su constante en `CompanyTuning`, no un sistema nuevo. Ninguna
  agrega RPC: cambian datos que ya se replican (stock de la mesa, pedido al proveedor, reloj).

### 6.2 Ayudas

| # | Ayuda | Qué hace con 1 jugador | Con 2 o más | Por qué | Estado |
|---|---|---|---|---|---|
| 1 | **Galpón congelado** (S4) | Mientras maneja, el reloj del galpón (proveedor en la dársena, vencimientos de armado) está quieto | Solo si salen todos | Sin esto el camión del proveedor se va mientras reparte | ya (`DayCycle._poll_shed`, D-0316) |
| 2 | **Pausa de verdad** | La pausa del menú para el reloj del día (`GameClock.pause()`): pedidos, galpón y ruta quietos | No hay pausa: el mundo sigue (como hoy en coop) | Una persona sola tiene que poder atender la puerta sin perder un pedido; mira el número **en vivo** (solo sin otro peer conectado), no el del día | D-0151 |
| 3 | **Pedido al proveedor sugerido** | El carrito del proveedor se abre precargado con lo que falta (§6.3). Si a las `SOLO_AUTO_ORDER_MIN` (19:00) no mandó nada para mañana, se manda el sugerido solo y lo avisa el celular | Precargado igual (sirve a todos), nunca se manda solo | Olvidarse el pedido de la tarde, cuando el solitario está en la ruta, deja el día siguiente sin stock: es la espiral de quiebra más corta | D-0151 |
| 4 | **Mesa llena al abrir** | Al abrir el día, cada mesa arranca con `SUPPLY_CAPACITY` completo (gratis, como reponer: decisión del 2026-10-19). A media jornada repone él | Reponer es la tarea del que se queda | En solo no hay "el que se queda" a la mañana; una reposición por día alcanza para 8 pedidos | D-0151 |
| 5 | **Asistente de estante en la ruta** | Las cajas que nadie cuida se estabilizan solas y las trampas complejas se pausan estacionado (`package_rescue.gd`, `solo_assist`) | No: cada pasajero cuida una caja | Es lo que el juego base ya hace con 1 jugador; la caja en la mano sigue siendo suya | ya (juego base) |
| 6 | **Un evento por día** | Máximo 1 evento del día, sin los que piden 3 o más | Escala con la tripulación | Carga mental | ya ([eventos-del-dia.md](eventos-del-dia.md)) |
| 7 | **Pedidos a su medida** | 8 por día (`6 + 2 × 1`), ventana de 4 h, de 1 a 2 productos los primeros 3 días | Escala | Ya balanceado en [economia.md](economia.md) (+380/día) | ya |
| 8 | **El cierre espera** | Si a las 20:00 está en la ruta, el cierre espera a que vuelva (S3) | Igual | No se corta una salida | ya (D-0203) |

### 6.3 Pedido sugerido (ayuda 3)

Por producto del catálogo del proveedor: `max(0, unidades en pedidos abiertos − stock + demanda media diaria
de los últimos SOLO_ORDER_LOOKBACK_DAYS (3) días)`, redondeado hacia arriba a múltiplos de 4 (una mano), sin
pasar el total de plata menos `SOLO_ORDER_CASH_RESERVE` (100, la misma reserva de la curva de economía).
El día 1 no hay historia: se usa la demanda esperada de `CompanyDayOrders` para mañana. Se ve como un pedido
normal en el tablero y el portapapeles; el jugador lo cambia o lo borra. El pedido automático de las 19:00 se
cobra como cualquier otro (al recibir cada palet, D-0503): si nadie lo descarga, no cuesta nada.

### 6.4 Lo que no se automatiza

- **Armar, manejar, cuidar en la mano, descargar el palet, elegir qué cajas salen.** Son el juego.
- **No hay compañero IA** ni repartidor NPC en F1: el camino para crecer solo son los empleados de F2
  (§4), sin descuento de sueldo para el solitario (el novato ya se paga con 1 pedido más por día,
  [economia.md](economia.md)).
- **No se alarga la ventana de entrega**: el solitario sale con pocas cajas y prioriza por vencimiento
  (§2.1). Si el bot entrega menos del 70 %, es un hallazgo de balance para `pulidor-jugabilidad`, no una ayuda nueva.

### 6.5 Con empleados (F2)

Un empleado repositor asignado a una mesa apaga la ayuda 4 en esa mesa (él la repone); uno en la dársena no
cambia la 3 (pedir sigue siendo del jugador). La ayuda 1 ya pasa a "el galpón sigue si hay empleados" (S4).
El resto no cambia.

### 6.6 Cómo se mide

| Qué | Cómo | Umbral |
|---|---|---|
| Día 1 con ganancia | `bot_company_day` con 1 bot (D-2016) | ganancia > 0 |
| 20 días seguidos | `bot_company_solo` (D-2024) con la política de §2.1 | sin quiebra, ninguna etapa trabada, ≥ 70 % de pedidos entregados |
| Pedido sugerido | el bot de D-2024 no pide nunca a mano: vive solo del sugerido y del automático | ningún día con un pedido abierto sin stock por falta de pedido |
| Regla de 2 min | `bot_company_day` con 1 bot | máx. 120 s sin caja ni volante (el tiempo en pausa no cuenta) |
