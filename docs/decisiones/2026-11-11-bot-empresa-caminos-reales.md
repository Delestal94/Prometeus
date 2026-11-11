# El bot del día de empresa juega por los caminos del juego (D-2016.4, primera parte)

**Decisión:** `tests/bot_company_day.gd` ya no toca los objetos del host para lo que el juego sabe hacer: usa las
peticiones de `CompanyNet` en las estaciones que resuelve el mundo, lleva las cajas en las manos, carga la van con el
tablero de despacho y deja que el juego guarde el día. Lo que el juego todavía no hace es un **atajo con nombre**
(`BOT_STUB`) que bloquea `BOT_OK`. Arma 6 cajas y mide ganancia, errores del motor y tiempo ocioso por jugador.

**Por qué:** el bot es el criterio de cierre de F1 (D-0111). Mientras jugaba por atajos, `BOT_OK` decía "el día
funciona" sin que el juego pudiera hacer ese día: un `BOT_OK` falso escondía justo lo que falta.

**Lo que se decidió en el camino:**

- **Cuatro atajos quedan, cada uno con la tarea que lo saca:** `pallet_unload` (abrir el palet y sacar sus unidades:
  D-0607.c), `table_use` (nada del juego manda los pedidos `box_*` al usar la mesa: D-0701.b), `order_claim` (nada ata
  un pedido a una mesa, el bot llena `CompanyTableNet.order_of`: fila 8 de `red-autoridad.md`, D-0804 / D-0807) y
  `door_settle` (cobrar en la puerta: D-0340 + D-0815.b). `table_use` y `order_claim` no estaban en el análisis de la
  tarea; salieron al armar por las peticiones y se nombran igual que los otros en vez de esconderlos.
- **Las mesas son estaciones del mundo:** `CompanyShed.station_for` no resolvía `table:<uid>`, así que las peticiones
  `box_*` de D-0715 no podían llegar a ninguna mesa del mundo de empresa (`no_station`). Se agregó: el punto es el hueco de
  la caja, `TABLE_BOX_LIFT` (0,45 m) sobre la tapa, para que el paquete en que se convierte la caja cerrada no nazca dentro
  de la mesa. Es un arreglo del juego, chico y cubierto por `test_company_bot_day`.
- **El segundo jugador es un actor local, no un peer ENet:** un `Player` más del equipo en el mundo del host
  (`Player_2`, autoridad 2). Sus pedidos entran por `CompanyNet._take_request` (el chequeo del host de un pedido de otro
  peer: alcance desde su nodo, sus manos, los mismos eventos) y se mueve escribiendo la pose que replicaría
  (`net_position`/`net_yaw`); soltar una caja es `PackageHandling.drop` con su id de peer. Solo falta el transporte; la
  pareja por ENet es D-2017. Con más de 2 jugadores el resto solo dimensiona los pedidos (atajo `crew_size`).
- **La pose del segundo jugador no pasa por el suavizador** (`NetPoseSmoother`): dos teletransportes en el mismo
  milisegundo se descartaban como repetidos y, separados por 1 ms, se extrapolaban a cientos de metros. Queda el par
  crudo, que es lo que el host usa antes del primer paquete de un peer.
- **Ocio:** se mide en tiempo real, de la primera etapa al `SUMMARY`: ocupado es tener unidades en las manos, una caja,
  un volante o el autoelevador. Como el bot se teletransporta, el número del jugador del host es chico (menos de 1 s);
  el que dice algo es el del segundo jugador mientras la van está afuera, que trabaja a ritmo de persona (6 s entre
  cosa y cosa, `STEP_SECONDS`).
- **El ocio del segundo jugador queda medido y en rojo:** con 2 jugadores el que se queda pasa 157 s sin trabajo
  mientras la van está afuera, casi siempre porque los estantes no tienen lo que piden los pedidos que entran. No se
  ablanda el límite de 120 s ni se le inventa trabajo en el bot: es un número del día (stock inicial, proveedor) que
  queda para decidir en [`revisar/D-2016.4.md`](../expansion-distritos/revisar/D-2016.4.md). Para explicarlo, el bot
  imprime `BOT_INFO stay_waits no_order=<n> no_stock=<n>`.
- **Ganancia:** plata del resumen al cerrar menos la plata cuando arrancó la primera etapa. Incluye el alquiler y el
  cobro del atajo `door_settle`; con la puerta real puede cambiar.
- **Errores del motor:** un `Logger` (como el de `net_pair_company.gd`) cuenta todo error que no sea aviso; cualquiera da
  `BOT_FAIL`.
- **Límite duro por defecto: 900 s** (antes 300). Con 6 cajas la van visita varias casas: la corrida con 1 jugador tardó
  unos 450 s (ida 75 s, entregas 257 s, vuelta 115 s). `test_company_bot_day` sigue manejando solo 20 m de calle y sin
  ir a las casas; su tope de tiempo pasó de 45 a 90 s por las 6 cajas.
- **`close_day` ya no guarda:** el juego guarda el día cerrado al llegar a `SUMMARY` (`CompanyRoot.save_closed_day`,
  la apertura del día siguiente); el bot solo lee ese archivo y comprueba día + 1, plata, libro y stock.
