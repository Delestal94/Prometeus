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
- **Una salida** = un vehículo con 1 conductor y 0 a 3 pasajeros (camioneta actual: 4 asientos); cada
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
