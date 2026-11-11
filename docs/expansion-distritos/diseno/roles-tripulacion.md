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
  vencimientos de armado) se pausa. Los pedidos **entran y vencen con la hora del galpón** (así quedó en
  D-0813.1, `CompanyDayOrders.poll`): mientras está congelado no entra ninguno y la ventana de 4 h no corre;
  los que no llegaron a entrar antes del cierre se pierden ese día (ver §6.2, ayuda 3).
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
[2026-10-22-modo-solo.md](../../decisiones/2026-10-22-modo-solo.md). Revisado por `critico-diseno`.

### 6.1 Regla

- **No es un modo aparte ni un interruptor.** El juego mira la tripulación (`crew_size`: jugadores
  conectados, host incluido; los empleados no cuentan). Las reglas que dependen del día (los pedidos) la
  fijan al abrir el día, como el tope de pedidos (§4). Las que dependen del momento (la pausa, el asistente de
  estante) la miran **en vivo**.
- **Se automatiza lo que en coop hace "el que se queda"** (§3) cuando el solitario no puede hacerlo porque está
  en la ruta, nunca el núcleo: armar, manejar, cuidar y reponer la mesa siguen siendo del jugador.
- Cada ayuda es una regla chica del host con su constante en `CompanyTuning`. Ninguna agrega RPC: cambian
  datos que ya se replican (pedidos del día, pedido al proveedor, reloj).

### 6.2 Lo que construye D-0151

| # | Ayuda | Qué hace | A quién | Por qué |
|---|---|---|---|---|
| 1 | **Pausa de verdad** | La pausa del menú para el árbol **y** el reloj (`get_tree().paused` + `GameClock.pause()`, porque la hora es un ancla sobre el reloj del sistema y el árbol pausado no la frena). Al despausar solo se reanuda el reloj si lo pausó el menú (el resumen del día también lo pausa, `DayCycle._transition`). Si entra un peer con la pausa puesta, el host despausa antes de mandarle el snapshot | Host **sin ningún peer conectado** (sin red o con la sala abierta y vacía). Con alguien más, la pausa de hoy del coop (el mundo sigue) | Una persona sola tiene que poder atender la puerta sin perder un pedido |
| 2 | **Pedidos que alcanzan a entrar** | Con 1 jugador, el último pedido del día entra a las `SOLO_ORDER_LAST_ARRIVAL_MIN` (15:00 del galpón) en vez de las 19:00 (`ORDER_LAST_ARRIVAL_MIN`): las horas de llegada se comprimen, la cantidad (8) no cambia | Día abierto con `crew_size` 1 | El galpón congelado atrasa 40 min de juego por cada minuto real de ruta: con 3 salidas de ~3 min, a las 20:00 del mundo el galpón marca ~14:00 y los pedidos de la tarde nunca entran. La curva de [economia.md](economia.md) (+380/día) supone los 8 |
| 3 | **Pedido al proveedor automático** | Al pasar a CLOSING, si nadie mandó el pedido de mañana, el host manda el **sugerido** (§6.3) con una regla del cierre como el alquiler (`FixedCosts.settle`) y lo avisa el resumen del día. El carrito del proveedor se abre siempre precargado con el sugerido | **Todas** las tripulaciones | Olvidarse el pedido deja el día siguiente sin stock: la espiral de quiebra más corta, y en coop pasa igual. Una sola regla para todos es más barata que distinguir |

### 6.3 Pedido sugerido

Por producto: `max(0, unidades pedidas hoy − stock)`, sin redondeo. Si la suma pasa de
`plata − RENT_PER_DAY − SOLO_ORDER_CASH_RESERVE` (100, la reserva de la curva de economía), se recorta
empezando por los productos con menos unidades pedidas. No guarda nada nuevo: "hoy" son los pedidos del día que
termina (los abiertos al cierre ya están perdidos, no se compra para ellos aparte). Se cobra como cualquier
pedido, al recibir cada palet (D-0503): si nadie lo descarga, no cuesta nada. Un palet por producto
(`SupplierOrderCart`) sigue igual: sin redondeo a la mano, no se pide más de lo que se vendió.

### 6.4 Lo que ya existe (no es trabajo de D-0151)

| Ayuda | Qué hace con 1 jugador | Dónde |
|---|---|---|
| Galpón congelado (S4) | Mientras maneja, el reloj del galpón (proveedor, vencimientos, pedidos) está quieto | `DayCycle._poll_shed`, D-0316 |
| Asistente de estante | Las cajas que nadie cuida se estabilizan solas y las trampas complejas se pausan estacionado | juego base, `package_rescue.gd` (`solo_assist`, cuenta jugadores en vivo) |
| Un evento por día | Máximo 1, sin los que piden 3 o más | [eventos-del-dia.md](eventos-del-dia.md) |
| Pedidos a su medida | 8 por día, de 1 a 2 productos los primeros 3 días | `OrderGenerator`, [economia.md](economia.md) |
| El cierre espera | Si a las 20:00 está en la ruta, el cierre espera a que vuelva (S3) | D-0203 |

### 6.5 Lo que no se automatiza

- **Armar, manejar, cuidar en la mano, descargar el palet, elegir qué cajas salen, reponer la mesa.** Reponer
  la mesa es justo lo que llena la espera del proveedor de 08:00 a 08:30 (§2.1): la mesa llena al abrir le
  sacaba la única tarea de ese rato (descartada).
- **No hay compañero IA** ni repartidor NPC: el camino para crecer solo son los empleados de F2 (§4), sin
  descuento de sueldo (el novato ya se paga con 1 pedido más por día, [economia.md](economia.md)).
- **No se alarga la ventana de entrega** (con el galpón congelado ya no corre en la ruta). Si el bot entrega
  menos del 70 %, es un hallazgo de balance para `pulidor-jugabilidad`, no una ayuda nueva.

### 6.6 Con empleados (F2)

Con un empleado en el galpón no hay congelado (S4): la ayuda 2 deja de hacer falta y se apaga si hay un empleado
contratado ese día. La 1 y la 3 no cambian.

### 6.7 Cómo se mide

| Qué | Cómo | Umbral |
|---|---|---|
| Día 1 con ganancia | `bot_company_day` con 1 bot (D-2016) | ganancia > 0 |
| 20 días seguidos | `bot_company_solo` (D-2024), sin comprar a mano: vive del pedido automático | sin quiebra, ninguna etapa trabada, ≥ 70 % de pedidos entregados |
| Pedidos que entran | contador del bot | los 8 del día entran antes del cierre con 3 salidas |
| Regla de 2 min | `bot_company_day` con 1 bot | máx. 120 s sin caja ni volante (el tiempo en pausa no cuenta) |
