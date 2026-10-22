# Red del modo Empresa: quién manda en cada acción (D-2001)

> Baja a acciones concretas el principio de `docs/arquitectura.md` §10.2 (host dueño de todo el negocio,
> petición → validación → evento). Es el contrato que construyen D-2003 (`company_net.gd`), D-2004
> (snapshot), D-2006 (caída de un cliente) y cada tarea de F1 que agrega una acción. Una acción nueva que
> no está en esta tabla se suma acá en el mismo PR que la construye.

## 1. Reglas que valen para todas

1. **Un cliente nunca escribe estado de negocio.** Ni `Inventory`, ni `OrderBook`, ni `CompanyState`, ni
   la caja en armado. Tampoco "por adelantado" para que se vea más rápido: la única predicción del modo es
   la que ya existe para la caja en la mano (N-217). Si la petición se pierde o se rechaza, en el cliente
   no cambió nada y no hay nada que deshacer.
2. **Cuatro RPC, todos en `CompanyNet`** (dos de negocio, uno de snapshot y uno de aviso) (hijo de `CompanyWorld`, D-2003):

   | RPC | Modo | Guardas |
   |---|---|---|
   | `_request(kind: StringName, data: Dictionary)` | `@rpc("any_peer", "call_local", "reliable")`, cliente → host (`rpc_id(1, …)`); el host se llama a sí mismo por el mismo camino | descarta si no es el host; `RpcGuard.allow_request` (o `allow_critical_request` si la tabla dice **crítica**), `name_ok(kind)`, `dict_ok(data)`, `kind` dentro de la lista blanca de §2 |
   | `_apply_event(seq: int, kind: StringName, data: Dictionary)` | `@rpc("authority", "call_local", "reliable")`, host → cada peer con `is_peer_ready()` | `RpcGuard.from_host`; `seq` mayor que el último aplicado (si no, se ignora) |
   | `_snapshot(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray)` | `@rpc("authority", "call_remote", "reliable")`, host → un peer (D-2004) | `RpcGuard.from_host`; `0 ≤ chunk < total ≤ SNAPSHOT_MAX_CHUNKS`, `size ≤ SNAPSHOT_MAX_BYTES`, `bytes` ≤ 60 KB; ver §3 y §6 |
   | `_rejected(rid: int, reason: StringName)` | `@rpc("authority", "call_remote", "reliable")`, host → solo el que pidió | `RpcGuard.from_host`; solo dibuja un aviso, no toca estado |

   - El host difunde así: sube `seq`, **aplica llamando directo** a la función y después hace `rpc_id` a
     cada peer listo que no sea él. Nunca `.rpc()`: también le llega a los peers que todavía no están listos.
   - **Decisión:** `_rejected` existe para que el jugador sepa por qué no pasó nada ("no hay stock",
     "la mesa está ocupada"). Sin él, una petición rechazada es indistinguible de un lag. Lleva un `rid`
     (entero que pone el cliente en `data.rid`, leído solo después de `dict_ok`; si no es un `int`, la
     petición se descarta en silencio, sin `_rejected`). No gasta `seq`. Si el que pidió es el propio host,
     el aviso se llama directo a la UI (el RPC es `call_remote` y no le llegaría).
   - No hay otro `@rpc("any_peer")` de negocio: pedir un snapshot es un `kind` de `_request`
     (`snapshot_request`, §3). `CompanyFleet._have_fleet` (regla 10) no es de negocio: solo abre sincronizadores.
3. **El actor es `RpcGuard.sender(self)`, nunca un campo de `data`.** Toda ubicación `hands:<peer>` la arma
   el host con ese número. Un cliente que manda `peer: 3` en `data` se ignora.
4. **Alcance físico lo mide el host.** Toda acción en una estación (palet, estante, mesa, tablero,
   dispensador, bulto en el piso) lleva `station: StringName` (el id estable de la estación, no un
   `NodePath`); el host busca la estación en `CompanyWorld` y exige la misma distancia que
   `Interactable._within_reach` (`REMOTE_REACH` + `NetStats.reach_slack`), **medida hasta el hueco o la
   celda** y no hasta el centro del mueble (un estante largo dejaría huecos fuera de alcance): un helper
   estático compartido que reciben la posición. **Decisión:** id y no `NodePath` porque el id también es la
   clave en el layout guardado y en el `Inventory` (`shelf:<id>`, `table:<id>`); el host nunca resuelve un
   camino que mandó un cliente. Excepción heredada: `DeliveryPackage.request_transfer(recipient_path)` de
   hoy (`path_ok` y lo resuelve `PackageHandling`), que no se toca (S1).
5. **Datos planos y acotados.** `data` solo lleva `int`, `float` finitos, `bool`, `StringName` y `Vector3`
   finito (lo que acepta `RpcGuard.plain_value`; **no** `Vector2i`, así que una celda viaja como `cx`, `cy`
   enteros); cantidades `1..Pallet.MAX_UNITS`; ids que existen en el registro (`data/products/`, tamaños de
   caja, pedidos vivos). Lo que no cumple se rechaza con `_rejected(rid, &"bad_data")`.
6. **Un evento = un hecho ya validado.** Cada peer lo aplica con el mismo código (sin volver a validar
   reglas de juego, solo que los datos sean coherentes) y **después** emite su señal de `EventBus` (§10.3).
   El host aplica primero y difunde después, con el mismo `seq`.
7. **Nada de negocio en un `MultiplayerSynchronizer`.** Lo físico (cajas sueltas, palet en la zorra,
   vehículos, jugadores) sigue con sus sincronizadores de hoy; lo que cuenta plata o unidades viaja solo en
   eventos.
8. **Peticiones críticas**: soltar (unidades o una caja). Como no hay predicción, perder una no deja a nadie
   en desacuerdo, pero sí deja al jugador con las manos llenas sin poder vaciarlas mientras su presupuesto
   está gastado; por eso usan la reserva propia de `allow_critical_request`. Las demás son repetibles: si se
   pierde, el jugador vuelve a apretar.
9. **Lo que se ve antes de confirmar es local.** La vista previa de la grilla, la rotación de un producto
   antes de soltarlo y el resaltado de un hueco no viajan; solo la colocación confirmada es una petición.
   Así el armado entra holgado en el tope de `RpcGuard` (20 por segundo, ráfaga de 40, compartido con
   `request_interact` y las peticiones de la caja).
10. **Nodos sincronizados creados por evento.** Cuando un evento crea un nodo que tiene
    `MultiplayerSynchronizer` (la caja de `box_sealed`, el palet de `supply_arrived` si es un cuerpo
    sincronizado), el host lo crea con el sincronizador **invisible** para los peers a los que el host
    todavía no les mandó ese `seq` (filtro de visibilidad), manda el evento por el mismo canal reliable y recién
    después llama a `update_visibility(peer)`. Si el sincronizador llega antes que el nodo, el cliente no
    resuelve el camino y esa caja no se mueve más ahí (el mismo bug que documenta `package.gd:184`). Con el snapshot, `update_visibility` va después del
    último trozo. Así entran los vehículos de la flota (`CompanyFleet`, `World/Vehicles/<id>`, D-0302.2.b): cada
    peer los arma desde el snapshot (la flota de `CompanyState`) y avisa cuáles tiene con `_have_fleet` (un RPC del
    nodo `World/Vehicles`, que no tiene sincronizador y existe en cada peer desde el `_ready` del mundo;
    `RpcGuard.allow_critical_request`, hasta `MAX_VEHICLES` nombres de vehículos que existen); el host abre el
    sincronizador de cada uno a ese peer recién entonces y con su mundo arriba (`is_peer_ready()`). No alcanza con
    abrirlo después de mandar el snapshot: puede no salir (muy grande) o no aplicarse allá. Uno que el host arme
    después queda cerrado hasta que ese peer lo avise; al irse un peer (o volver a levantar su mundo) se cierra y el
    host lo saca del volante. Los bultos de unidades en el piso
    son nodos **estáticos** sin sincronizador: el evento trae su posición y no se mueven.
11. **Lo físico lejos no viaja (D-0316).** El sincronizador de un vehículo (`company_vehicle`) o una caja suelta
    (`company_loose_box`) lo maneja `CompanyInterest`: el host lo manda solo a los peers con su jugador a ≤ 2 celdas
    (lo deja pasado 3) y al conductor, y un cliente esconde su copia lejana (y la saca de la física). Sus
    `public_visibility` y `set_visibility_for` son de `CompanyInterest`; la regla 10 y cualquier otra condición van con
    `add_visibility_filter` (se suman). El host simula todo igual. **Un RPC llamado sobre ese cuerpo (la raíz del
    sincronizador) no llega a los peers que no lo ven, tampoco un broadcast**: un hecho único o una baja de ese cuerpo
    (una caja entregada, `_remote_consume` de `package_handling.gd`; un vehículo vendido) va como propiedad ON_CHANGE
    del sincronizador, como evento de `CompanyNet` (un nodo que no se sigue) o después de `untrack()`; si no, el peer
    lejano se queda con una copia vieja para siempre. Nada que cree un `MultiplayerSpawner` entra a esos grupos (no
    verlo lo despawnea). Decisión `docs/decisiones/2026-10-21-visibilidad-por-distancia.md`.
    **Soltar antes del broadcast (D-0316.3):** la caja de `box_sealed` entra a `company_loose_box` en cada peer
    (`CompanyInterest.add_loose_box()`) y, en el host, `consume()` emite `DeliveryPackage.consuming` antes de mandar
    `_remote_consume`: `WorldCellInterest.release()` la saca del seguimiento y de los grupos (pública otra vez, con
    los filtros de la regla 10) y la baja llega a todos. El ancla de cada jugador es su `reach_origin()` (sentado, el
    asiento), así quien viaja con la caja la sigue recibiendo.

## 2. Las 20 acciones del corte vertical (y las de construir el galpón, 21 a 24)

`kind` de petición → `kind` de evento. "Host" en la columna de quién inicia quiere decir que no hay
petición: el host lo detecta o lo decide solo y emite el evento.

| # | Acción (tarea) | Inicia | Petición: `kind` y `data` | El host valida | Evento: `kind` y `data` | Cambia en cada peer |
|---|---|---|---|---|---|---|
| 1 | Pedir mercadería para mañana (D-0602, D-0503, D-0603.b.2, D-0621.b) | jugador, en el tablero del proveedor o el portapapeles | `supplier_order` `{supplier, <producto>: unidades…, rid}` (plano, hasta 14 productos; sin `supplier` = `distribuidora_central`) | sin alcance (se pide desde cualquier lado, [portapapeles](portapapeles.md) §3); día no cerrado (no `SUMMARY`); el proveedor existe y vende cada producto; 1..240 por línea; plata ≥ total a los precios de ese proveedor (`price_factor`); su camión del día ≤ 2400 por producto | `supplier_ordered` `{order_day, lines: [{product, qty}], peer, supplier}` | calendario (`SupplierSchedule`): el camión de ese proveedor del día siguiente; no se cobra al pedir (se cobra al recibir, D-0503) |
| 2 | Llega el camión del proveedor (D-0601) | host (08:30 de juego) | — | hay pedido de ayer | `supply_arrived` `{pallets: [{id, product, qty}]}` | `Inventory.receive` en `pallet:<id>` (una vez por palet); palets `sealed` |
| 3 | Bajar el palet a recepción (D-0605, zorra / autoelevador) | jugador, moviendo el cuerpo físico | — (es física: zorra o autoelevador, host como hoy) | el palet entró al área de recepción (señal del área en el host) | `pallet_placed` `{pallet, zone}` | el palet queda en `zone`; sus unidades no se mueven |
| 4 | Abrir el palet (D-0607) | jugador, en el palet | `pallet_open` `{station, rid}` | alcance; palet recibido, `sealed`, con unidades | `pallet_opened` `{pallet}` | `Pallet.open`: `sealed` → `open` |
| 5 | Tomar unidades de un palet, estante o bulto del piso (D-0609, D-0611) | jugador | `units_take` `{station, product, qty, rid}` | alcance; el origen (`pallet:`, `shelf:` o `floor:<n>`) tiene `qty` libres **o reservadas para el pedido de una mesa** (cualquiera puede tomar lo reservado para armarlo; la reserva solo impide que otro pedido lo use); manos libres o con el mismo producto; tope de la mano | `units_moved` `{product, qty, from, to: hands:<peer>}` | `Inventory.move` (la reserva es por producto y sigue en pie) |
| 6 | Guardar en un hueco del estante (D-0608) | jugador con unidades en la mano | `units_store` `{station, product, qty, rid}` | alcance; el hueco acepta ese producto y tiene lugar; la mano tiene `qty` | `units_moved` `{…, from: hands:<peer>, to: shelf:<id>}` | `Inventory.move` |
| 7 | Soltar unidades en el piso (D-2006) | jugador | `units_drop` `{product, qty, pos: Vector3, rid}` — **crítica** | `finite_vec3`; producto del catálogo y `qty` en rango; la mano tiene `qty` de ese producto; si `pos` está a más de 2 m del jugador según el host, suelta a sus pies (no rechaza: soltar siempre vacía la mano) | `units_moved` `{…, from: hands:<peer>, to: floor:<n>, pos}` (un bulto nuevo por soltada, §7) | `Inventory.move`; aparece el bulto estático en `pos` |
| 8 | Tomar un pedido del tablero (D-0807, D-0804) | jugador, en el tablero | `order_claim` `{station, order, table, rid}` | alcance; pedido vivo y sin mesa; mesa sin pedido; stock disponible para reservar | `order_claimed` `{order, table}` | `OrderBook`: pedido → mesa; `Inventory.reserve(order)`. **Decisión:** la mesa es **compartida**, sin dueño: cualquiera que llegue arma en ella (D-0715, uno pone productos y otro encinta); lo que la ata es el pedido, no un jugador |
| 9 | Sacar una caja del dispensador (D-0702, D-0718) | jugador, en la mesa | `box_start` `{station, size, rid}` | alcance; mesa sin caja (`has_box`); `size` ∈ S/M/L/XL; hay cajas de ese tamaño en la mesa (`no_supply`); plata (`no_money`) | `box_started` `{table, size, box, money, minute}` (D-0715: `box` = `box_<n>` del host; plata absoluta como D-0910) | caja vacía en la mesa (`CompanyNet.table`); caja de ese tamaño de la mesa `−1` (D-0718) y su costo (D-0504) |
| 10 | Poner un producto en la grilla (D-0703, D-0704) | jugador con la unidad en la mano | `box_place` `{station, product, cx: int, cy: int, cz: int, rot: 0, rid}` (D-0715: la grilla es 3D; F1 sin rotación, D-0703) | alcance; la unidad está en `hands:<peer>` (`not_enough`); caja sin cinta; la celda entra y está libre (`cell_taken`); si la mesa tiene pedido X, la unidad sale primero de la reserva de X y si no de lo libre; si solo queda reservada para otro pedido, `_rejected(rid, &"reserved_for_other")` (así una unidad de A no termina sellada en la caja de B; cuenta en §9) | `box_placed` `{table, product, cx, cy, cz, rot, from: hands:<peer>}` | `Inventory.move` mano → `box:<id>`; grilla ocupada |
| 11 | Sacar un producto de la caja abierta (D-0703) | jugador | `box_take_out` `{station, cx: int, cy: int, cz: int, rid}` (cualquier celda del producto) | alcance; caja sin cinta; celda con producto (`empty_cell`); mano vacía o con ese producto (`hands_busy`) y con lugar (`hands_full`) | `box_taken_out` `{table, cx, cy, cz, product, to: hands:<peer>}` | inverso del 10 (`PackedBox.take_out`) |
| 12 | Rellenar (D-0705) | jugador | `box_fill` `{station, cells: 1..64, rid}` (D-0715: un solo relleno en F1, D-0705, así que se pide cuántas celdas y no qué relleno) | alcance; caja sin cinta; celdas libres (`no_room`); relleno en la mesa (`no_supply`); plata | `box_filled` `{table, cells, money, minute}` (`cells`: lo menor entre lo pedido, el relleno de la mesa y lo libre) | celdas rellenadas; relleno de la mesa `−cells` y su costo |
| 13 | Etiquetar con el pedido (D-0707) | jugador | `box_label` `{station, rid}` | alcance; la mesa tiene pedido (#8; hasta que exista, `CompanyTableNet.order_of`) con casa (`no_order`); plata | `box_labeled` `{table, order, money, minute}` | etiqueta = pedido de la mesa |
| 14 | Poner un sello (D-0708) | jugador | `box_stamp` `{station, stamp, rid}` | alcance; caja sin cinta; `stamp` ∈ los del catálogo; no repetido (`already_stamped`); plata | `box_stamped` `{table, stamp, money, minute}` | sellos de la caja |
| 15 | Encintar y cerrar (D-0706, D-0709, D-0710, D-0711) | jugador | `box_tape` `{station, rid}` | alcance; caja con al menos un producto (`empty_box`); cinta en la mesa (`no_supply`); plata | `box_sealed` `{table, order, package_id, node_name, trap, trap_intensity, contents, absorption, quality, pos, basis, money, minute}` (D-0715: `package_id` = id de la caja) | la caja sale de la mesa; **cada peer crea el mismo `DeliveryPackage`** con esos datos (nombre de nodo estable, regla 10); `Inventory`: las unidades de `box:<id>` pasan a `package:<package_id>` y la reserva del pedido baja en lo que la caja lleva de cada producto (lo reservado ya no está libre: está en la caja); `OrderBook`: pedido → armado (`order_packed`) |
| 15a | Reponer un insumo de la mesa (D-0718, D-0715.c) | jugador, en la mesa | `box_restock` `{station, supply, rid}` (`supply`: `box_S`, `box_M`, `box_L`, `box_XL`, `tape` o `fill`) | alcance; `supply` de `StationSupplies` (`bad_data`); la mesa no lo tiene lleno (`supply_full`); el galpón no está corto de eso hoy (`CompanyTableNet.short_of`, `box_shortage`: `no_supply`). Con caja en la mesa o sin ella. Gratis (D-0718) | `box_restocked` `{table, supply, count}` (`count`: lo que tiene la mesa del host después, su capacidad) | `StationSupplies.restock(supply)`; nada de plata ni libro |
| 15b | Tirar la caja abierta (D-0719, D-0715.c) | jugador, en la mesa | `box_discard` `{station, rid}` | alcance; mesa con caja (`no_box`) sin cinta (`sealed`) | `box_discarded` `{table, box, contents, to, pos}` (`to`: `hands:<peer>` del que pide si entra todo, un producto hasta `HAND_MAX_UNITS`; si no, un bulto nuevo `floor:<n>` en el `spot` de la mesa, y solo entonces `pos`) | la caja sale de la mesa y se pierde con su relleno, etiqueta y sellos (nada se devuelve, D-0719); `Inventory.move` de `box:<id>` a `to` (la reserva del pedido sigue en pie); con `floor:<n>`, el bulto queda en `pos` (`FloorBundles`) |
| 16 | Llevar, pasar y soltar una caja armada (D-0711) | jugador | los de hoy: `Interactable.request_interact`, `submit_carry_transform` (unreliable), `request_transfer`, `request_drop` (**crítica**) | como hoy (`PackageHandling`) | — (lo lleva el sincronizador de `DeliveryPackage`) | nada de negocio |
| 17 | Dejar la caja en la zona de despacho (D-0716) | host (la caja quieta dentro del área) | — | caja sellada, en el área, en el piso o en un estante de despacho; no despachada antes | `box_dispatched` `{package_id, trip}` | `OrderBook`: pedido → salida `trip`. Si la caja sale del área antes de que arranque la salida, `box_undispatched` `{package_id}` la desata |
| 18 | Cargar la camioneta (D-0717) | jugador, en un punto de carga | los de hoy (`PackageMountPoint`) | como hoy | — | nada de negocio (el pedido ya va con la salida) |
| 19 | Salir por el portón y volver (D-0302, D-0307) | host (el vehículo cruza el portón, `CompanyTrips`) | — | vehículo con carga despachada (`stage_cargo`); con `VEHICLES_FAR_MAX` afuera sale negado | `trip_started` `{trip, vehicle, orders, boxes, minute}` / `trip_refused` `{vehicle, minute}` (salió negado: sin salida, cuenta como afuera) / `trip_closed` `{trip, vehicle, failed, minute}` (volvió; `trip` vacío y `failed` vacío si había salido negado). Hechos (D-0302.2.a) | `CompanyTripsView` (`TripsView` de cada peer): el vehículo queda afuera / adentro; `trip_closed` dice qué pedidos fallaron; el reloj sigue (D-0319). El snapshot lleva los que están afuera (parte `trips`) |
| 20 | Entregar en la casa (D-0340, D-0815, D-0502, D-0506) | jugador toca el timbre (`DoorbellPoint` → `DeliveryHouse` como hoy) | el de hoy (`Interactable.request_interact`) | como hoy, más: contenido contra el pedido, daño, plazo | `order_delivered` `{order, package_id, paid, tip, stars, penalties: {…}}` (`stars` 1-5 la calcula el host en `OrderSettlement.settle` y cada peer la pasa tal cual a `OrderBook.mark_delivered`, validada como en el snapshot, `CompanyOrdersNet._stars_ok`; no se recalcula, D-0816.b) | `OrderBook`: pedido entregado; `Inventory.consume` de todo lo que hay en `package:<package_id>` (y lo que quede reservado del pedido se libera); `money += paid + tip − penalties` |

### Fuera de las 20, sin petición de cliente

| Qué | Quién | Cómo viaja |
|---|---|---|
| Entra un pedido nuevo (D-0803, D-0813) | host, con el ritmo del día (`CompanyOrdersNet.poll`: el plan de `OrderGenerator` con la semilla del día) | evento `order_added` `{order}`: el pedido entero como lo escribe `Order.normalize()` (un pedido ya es un diccionario; no hay `Order.to_dict()`), estado `open`; cada peer lo suma a su `OrderBook` (§10) |
| Vence un pedido (D-0807, D-0813) | host (`CompanyOrdersNet.poll`, `OrderBook.overdue()`) | evento `order_expired` `{order, minute}`: el pedido pasa a LATE en cada peer (`OrderBook.expire_one()`, con `late_from`) y se sigue pudiendo entregar con −25 % (D-0807). **Decisión (D-0813):** sin `penalty` (vencer no cobra nada en el momento) y sin reserva que liberar (todavía nada reserva antes de `order_claim`, fila 8); `minute` deja el `now_min` del libro igual en todos. Lo que decía esta fila para un pedido que se pierde (se libera la reserva; la caja a medio armar queda en la mesa sin pedido; una caja sellada sigue siendo una caja sin pedido, D-0719) pasa al abandono (`abandon()`, FAILED y reputación), que es otro evento: D-0807.b |
| Un pedido termina sin entrega (D-0851, D-0807) | host (`CompanyOrdersNet.abandon()`, `close_day()`, `fail_returned()`) | evento `order_closed` `{order, state}` con `state` `failed` o `cancelled` (protocolo 57): cada peer mueve su libro con `OrderBook.mark_failed()` / `cancel()`; la reputación de un `failed` (`OrderPenalties.abandoned()`, −3) la escribe solo el host al publicar. Lo publican el cliente que se cansó (una ventana después de vencer, `OrderDayClose.abandoned()`), la salida que volvió sin entregarlo y el cierre del día en `CLOSING` (§14) |
| Fases del día (D-0203) | host (`DayCycle`) | evento `day_phase` `{day, phase, frozen, lag, frozen_at[, summary]}` (`phase` es OPENING, OPERATING, CLOSING o SUMMARY; `summary` solo en SUMMARY, `DaySummary.build()`); el mismo evento lleva el congelado del galpón (S4: `frozen`, `lag`, `frozen_at` en minutos). El cliente es pasivo: valida y aplica, y emite `company_day_*` en el EventBus local |
| Reloj (D-0219) | host | evento `clock_anchor` `{minute, speed, paused}` solo al cambiar (apertura, pausa, salida que cierra tarde); cada peer toma como origen **su propio** tick al recibirlo (o al aplicar el snapshot), menos medio RTT de `NetStats`, y calcula la hora local desde ahí (el tick del host no vale en otra máquina). **Decisión:** ancla y no envío cada 2 s (lo que decía D-0219): no gasta ancho de banda quieto y no hay que interpolar; D-0219 lo construye así |
| Cierre: cobro, alquiler, penalidades (D-0320, D-0509) | host | evento `day_closed` `{day, summary}`; después el host guarda (solo el host guarda) |
| Pasar al día siguiente | **solo el host** aprieta "seguir" en el resumen | evento `day_phase` `OPENING` del día siguiente (`DayCycle.next_day()`). **Decisión:** igual que el reinicio de la partida de hoy (`hud_pause.request_restart`): un cliente no puede adelantar el día de todos; si el host tarda, el resumen queda en pantalla |
| Se abre un bloqueo (D-0306) | host | evento `gate_opened` `{gate}`; no se vuelve a cerrar. En F1 Centro y Campo están abiertos desde el día 1 |
| Un peer se va (D-2006) | host, en `peer_removed` (o `peer_disconnected` si llega antes; el segundo encuentra las manos vacías) | eventos `units_moved` `hands:<peer>` → `floor:<n>` (uno por producto) con la última posición conocida del jugador: la del nodo del jugador si sigue en pie y, si no, la última que `CompanyNet` guardó en su `units_take` o `units_drop`. Las mesas no tienen dueño, así que no hay nada más que soltar |
| Entra un peer tarde (D-2004) | host, en el gancho de peer listo | snapshot con el `seq` actual (ver §3) |
| Se va el host (D-2005) | cada cliente, en `multiplayer.server_disconnected` | nada viaja: resumen local (`CompanyInterruptedDay`), empresa propia de vuelta, mundo congelado y menú con el resumen; el host guarda el día con `interrupted: true` al cerrar su mundo (`CompanyRoot._exit_tree()`) y al cargarlo arranca ese día desde la apertura |

### Construir el galpón (D-0910, fuera del corte)

Las cuatro las valida y aplica `CompanyLayoutNet` (`scripts/core/company/company_layout_net.gd`, §8). La pieza
se nombra por `uid` (`DefaultShed.piece_uid`), nunca por índice. **Solo el host construye:** la petición de
cualquier otro peer se rechaza con `host_only` antes de mirar nada más (el voto es D-0910.1).

| # | Acción (tarea) | Inicia | Petición: `kind` y `data` | El host valida | Evento: `kind` y `data` | Cambia en cada peer |
|---|---|---|---|---|---|---|
| 21 | Comprar y colocar una pieza (D-0902) | host, en el modo construcción | `layout_place` `{id, x: int, z: int, turns: 0..3, rid}` | que lo pida el host; `id` del catálogo `data/placeables/` (nombre exacto de archivo); celdas enteras en ±256; `BuildPlacement.preview` en la grilla de la etapa (dentro del piso, fuera de dársena y salida, sin choque, todo alcanzable) con la plata | `layout_placed` `{id, x, z, turns, uid, minute, money}` | `PlaceableShop.buy` desde el saldo del host antes de la compra (`money + price`), así la plata y el `balance` del libro quedan en `money`; libro `placeable_buy` con el `minute` del host; la pieza entra al `layout` con el `uid` nuevo (`<id>_<n>`, el `n` libre más bajo) |
| 22 | Mover una pieza (D-0903) | host | `layout_move` `{uid, x: int, z: int, rid}` | que lo pida el host; la pieza existe; `preview` ignorando la pieza | `layout_moved` `{uid, x, z, turns}` | la pieza cambia de celda; conserva `uid` (y con él su stock y su estación) |
| 23 | Girar una pieza (D-0903) | host | `layout_rotate` `{uid, turns: 1..3, rid}` (cuartos de vuelta a sumar) | como 22, alrededor de la celda esquina | `layout_moved` `{uid, x, z, turns}` (absolutos) | como 22 |
| 24 | Vender una pieza (D-0903, D-0920) | host | `layout_sell` `{uid, rid}` | que lo pida el host; la pieza existe; **no tiene unidades** (`shelf:<uid>_<hueco>`, `table:<uid>`): si no, `not_empty` | `layout_sold` `{uid, minute, money}` | `PlaceableShop.sell` desde `money − devolución` (libro `placeable_sell`, saldo final `money`); la pieza sale del `layout` |
| 25 | Movimiento de plata del host sin pedido propio (cobro al entregar, propina, alquiler, proveedor, tienda; D-0517) | solo el host (`CompanyNet.publish_wallet`) | — (no hay pedido: lo decide el host) | quien cobra comprueba `can_afford` antes; `amount` ≠ 0, `reason` id corto, `money` y `minute` en rango | `wallet_moved` `{amount, reason, money, minute}` (plata absoluta como D-0910) | cada peer parte de `money − amount` y hace un solo `earn` / `charge`; libro con el `minute` del host; deriva → `take_drift()` y snapshot |

### Comprar en la tienda (D-0518, fuera del corte)

La valida y aplica `CompanyShopNet` (`scripts/core/company/company_shop_net.gd`, §13) con `CompanyShop` (D-0511).
**Solo el host gasta:** la petición de cualquier otro peer se rechaza con `host_only` antes de mirar nada más (el
voto es D-0518.b).

| # | Acción (tarea) | Inicia | Petición: `kind` y `data` | El host valida | Evento: `kind` y `data` | Cambia en cada peer |
|---|---|---|---|---|---|---|
| 25 | Comprar una máquina, un vehículo o una ampliación (D-0511, D-0518) | host, en la tienda del cierre (D-0511.2) | `shop_buy` `{item, rid}` | que lo pida el host; `item` texto corto e id exacto de un ítem habilitado de `data/shop/` (si no, `bad_data`); `CompanyShop.check` (ya lo tiene, lo que requiere, la etapa siguiente, la plata): su clave `WORLD_SHOP_*` es el motivo | `shop_bought` `{item, money, minute}` | `CompanyShop.buy` desde el saldo del host antes de la compra (`money + price`), así la plata y el `balance` del libro quedan en `money`; libro `shop` con el `minute` del host; máquina → `equipment`, vehículo → `fleet`, ampliación → `warehouse_stage` |

## 3. Secuencia, huecos y snapshot

- El `seq` lo lleva el host, empieza en 0 al abrir `CompanyWorld` y sube 1 por evento. No se guarda: un día
  cargado abre desde la apertura y todo cliente que entra lo hace por snapshot ([guardado.md](guardado.md) §4).
- `reliable` no pierde mensajes, así que el único hueco real es **el evento que llega antes que el mundo**
  (el peer todavía no tiene `CompanyWorld`). Por eso el host manda eventos solo a peers con
  `is_peer_ready()` y, al quedar listo un peer, le manda el snapshot con el `seq` actual; el peer descarta
  todo evento con `seq` ≤ el del snapshot.
- Si un peer ve un salto (`seq` > último + 1), pide un snapshot con `_request(&"snapshot_request", {rid})` (como toda petición, lleva `rid`).
  Tope medido en el host: uno cada 5 s por peer (si no, un cliente roto pide un snapshot por evento).
- El snapshot (`var_to_bytes` + `compress`) viaja en trozos de hasta 64 KB por `_snapshot` (D-2004). El `seq`
  va adentro del snapshot; el RPC lleva el `id` del snapshot y su tamaño sin comprimir (§6).
  Mientras faltan trozos, el cliente **guarda** los eventos que llegan con `seq` mayor al del snapshot y
  los aplica en orden al terminar de armarlo.
- Aplicar el snapshot **no** emite las señales de hechos; emite una sola `company_state_restored` para que la
  UI se redibuje (§10.3).
- **Qué lleva**, todo lo que cambia un evento de §2:
  - `CompanyState.to_dict()` (plata, día, pedido al proveedor, bloqueos, salidas en curso);
  - la fase del día y el ancla del reloj (si no, el que entra tarde no tiene hora hasta el próximo cambio);
  - `Inventory` con reservas, y las unidades sueltas en el piso con su posición;
  - `OrderBook` (pedidos, mesa de cada uno, salida de cada uno);
  - cada palet con su estado (`sealed`/`open`) y su zona;
  - cada mesa en armado: tamaño, productos con celda y rotación, relleno, sellos y etiqueta;
  - las cajas vivas con todo lo de `box_sealed`, para crear cada `DeliveryPackage` igual (regla 10);
  - el layout del galpón.

## 4. Qué se mira al revisar un PR de la expansión

- Un `@rpc("any_peer")` nuevo fuera de `_request` necesita una línea acá que diga por qué (D-2007 lo
  detecta: todo RPC de `scripts/core/company/` y `scripts/gameplay/business/` pasa por `RpcGuard`).
- Un `kind` nuevo de petición: su fila en §2 con las validaciones; un `kind` nuevo de evento: qué cambia y
  qué señal emite.
- Ningún campo de `data` que diga quién es el actor; ningún `NodePath` que mande un cliente.
- Cambia `PROTOCOL_VERSION` (`docs/convenciones-godot.md` §6): el primero sube con D-2003 / D-2008.

## 5. Lo construido (D-2003)

- `scripts/core/company/company_net.gd` tiene `_request`, `_apply_event` y `_rejected` (protocolo 29) y los
  `kind` `units_take`, `units_store` (filas 5 y 6) y `snapshot_request`. Una tarea que suma una acción agrega
  su `kind` a `REQUEST_KINDS` (y a `CRITICAL_KINDS` si es crítica), lo valida en `_handle_request()` y aplica
  su evento en `_apply_state()`.
- **Quién pide:** el RPC `_request` atribuye al remitente (`RpcGuard.sender`); una petición del propio host
  (`request()`) es siempre del host, aunque la haga mientras atiende el RPC de otro peer.
- **Estaciones (regla 4):** `CompanyNet.stations` es un `Callable(id) -> {location, spot, accepts?, capacity?}`
  que pone el mundo que las coloca (D-0608, D-0609, D-0611); sin él toda estación es desconocida
  (`no_station`). El alcance se mide hasta `spot` con `CompanyNet.within_reach()`, desde la pose que replica el
  propio cliente (heredado, igual que `Interactable._within_reach`).
- **Motivos de `_rejected`:** `bad_data`, `no_station`, `out_of_reach`, `not_enough`, `hands_busy` (la mano
  tiene otro producto), `hands_full` (`CompanyTuning.HAND_MAX_UNITS`), `wrong_product` (el hueco es de otro
  producto), `no_room`. Un pedido de snapshot de más dentro de los 5 s se descarta sin `_rejected`.
- **Reglas del host que reaccionan a un hecho:** escuchan `CompanyNet.event_applied`, nunca
  `Inventory.stock_changed` (salta a mitad de aplicar un evento: una petición hecha ahí se rechaza).
- **Cliente que entra:** `CompanyRoot` no toca `CompanyState` en un cliente (regla 1): `CompanyNet` arranca con
  stock vacío y `wait_for_snapshot()` (guarda los eventos y pide el snapshot si no llega en 5 s; lo reintenta
  cada 5 s mientras espera). En el host (y solo) arranca la empresa y le pasa `CompanyState.stock()`.
- **Pendiente:**
  - ~~el snapshot y la llamada a `resume_after_snapshot()` del lado que lo recibe~~ (hecho en D-2004, §6);
    ~~guardar `seq` en el slot (D-0206)~~ (no hace falta: un mundo cargado arranca en `seq` 0 y todo cliente
    entra por snapshot, [guardado.md](guardado.md) §4);
  - el modo Empresa todavía no es una sesión: `company_root.tscn` no está en `NetworkManager.LEVEL_SCENES` y
    `company_root.gd` no llama a `NetworkManager.level_ready()`. Lo cablea la tarea que lo ponga en línea
    (la continuación de D-0214; D-2004 dejó el gancho listo, §6);
  - D-0206 escribe `CompanyNet.inventory` de vuelta en `CompanyState` **solo en el host** (en un cliente es un
    espejo y nunca se guarda);
  - ~~soltar lo de `hands:<peer>` al irse (D-2006, con `last_known_position()`)~~ (hecho en D-2006, §7).

## 6. Lo construido (D-2004)

- **`_snapshot(id, chunk, total, size, bytes)`** (protocolo 30), en el mismo canal confiable que
  `_apply_event`: llega después de todo evento mandado antes y antes de todo evento mandado después.
  **Decisión:** el RPC lleva `id` (el host numera cada snapshot que manda: un trozo de uno más viejo, o
  de uno ya armado, se descarta) y `size` (el tamaño sin comprimir, que `decompress()` necesita y que se
  acota a `SNAPSHOT_MAX_BYTES` = 4 MB); el `seq` va adentro del diccionario. Trozos de hasta
  `SNAPSHOT_CHUNK_BYTES` = 60 KB (el RPC entero queda bajo 64 KB), a lo sumo `SNAPSHOT_MAX_CHUNKS` = 8
  (480 KB en total: todos los trozos se encolan juntos y tienen que entrar en el búfer de envío de
  Steam, ~512 KB por defecto),
  `FileAccess.COMPRESSION_ZSTD`, `bytes_to_var` (nunca `_with_objects`) y el resultado tiene que ser un
  `Dictionary`.
- **Cuándo lo manda el host** (`send_snapshot(peer)`): cuando ese peer queda listo
  (`NetworkManager.peer_level_ready`, conectado por camino, sin nombrar el autoload), a cada peer que ya
  estaba listo cuando el `CompanyNet` del host entra al árbol (diferido, después de que el dueño le da el
  stock) y cuando lo pide (`grant_snapshot()`, el mismo tope de 5 s; un snapshot que no se pudo mandar no
  cuenta como concedido). Nunca mientras aplica un evento. Uno demasiado grande no se manda y da un solo
  error por peer.
- **Qué lleva hoy** (`CompanyNet.snapshot()`): `seq`; `inventory` (el stock vivo con reservas);
  `company` (`CompanyState.to_dict()` sin su stock guardado: plata, día y hora, reputación, bloqueos
  abiertos, flota, empleados, hitos, layout, libro de caja). Un galpón de 300 unidades en 150 lugares con
  el libro lleno pesa 34 KB y 2 KB comprimido: un solo trozo. Parte `clock` (D-0219, `GameClock.attach()`):
  el ancla `{minute, speed, paused}` movida al momento en que el host arma el snapshot; el que entra la
  toma con su propio tick menos medio RTT, como un `clock_anchor`.
- **Partes que faltan**: `add_snapshot_part(key, take, put)` suma una parte con su clave; cada peer suma
  las mismas antes de que su mundo esté listo. `take` (host) devuelve datos planos; `put` (cliente) los
  pone en su lugar sin señales de hechos, los valida (regla 5) y devuelve `false` si no sirven (el
  cliente espera otro snapshot). Las suman: ~~`OrderBook`~~ (hecho en D-0813: parte `orders`, §10),
  fase del día (D-0203), palets con estado y zona (D-0605 / D-0607), mesas de
  armado (D-0701 en adelante), vehículos afuera (~~D-0302.2.a~~: hecho, parte `trips` de `CompanyTripsView`:
  la lista de los que están afuera, cada uno con la forma de `trip_started`), cajas vivas con lo de `box_sealed` y `update_visibility` después del
  último trozo (regla 10, D-0709 / D-0711) y bultos en el piso con su posición (~~D-2006~~: hecho, clave
  propia `floor`, §7; dibujarlos es D-0611).
- **Del lado del cliente** (`apply_snapshot()`): valida el `seq` (entero, no menor al aplicado) y el stock
  (`stock_ok()`: solo `stock` y `reserved`, ids de texto, cantidades enteras positivas) antes de tocar
  nada; reemplaza el stock y carga `company` en su `CompanyState` (su única escritura ahí, regla 1, con el
  stock vivo en el espejo; `CompanyRoot._exit_tree()` le devuelve lo que tenía antes, o `reset()` si no
  tenía empresa, así jugar solo o guardar después nunca toma la del host), aplica las partes, emite **una** `company_state_restored(seq)` y después
  `resume_after_snapshot()`: descarta lo guardado con `seq` ≤ y aplica el resto en orden. El primer trozo
  de un snapshot nuevo ya empieza a guardar eventos; un snapshot que no se arma o no se aplica deja al
  cliente esperando y vuelve a pedir a los 5 s.

## 7. Lo construido (D-2006)

- **`units_drop`** (fila 7, protocolo 33), **crítica** (`CRITICAL_KINDS`): `{product, qty, pos: Vector3, rid}`,
  la arma `CompanyNet.drop(product, qty, pos)`. El host valida producto (del catálogo) y `qty` (entero,
  `1..PALLET_MAX_UNITS`) como en `units_take` (`CompanyAsk`, `scripts/core/company/company_ask.gd`: las
  validaciones de datos de las peticiones de unidades y el catálogo, separadas de `company_net.gd`); `pos`
  `Vector3` finito (un `NaN` o fuera del mundo no pasa `dict_ok` y se descarta en silencio; otro tipo es
  `bad_data`); que la mano tenga esa cantidad de ese producto (`not_enough`, también si tiene otro).
- **Los pies del jugador** (`_feet_of`): la posición del **cuerpo** (`global_position` del nodo del
  jugador, no su `reach_origin()`; con `player_origin` puesto, su valor) y, si el nodo ya no está, la última
  que se anotó en `_last_origin`. Solo si no hay ninguna de las dos se rechaza con `out_of_reach`. Si `pos`
  está a más de `DROP_REACH` = 2 m más `NetStats.reach_slack()` de los pies, suelta ahí: nunca rechaza por
  distancia. Anota los pies en `_last_origin`.
- **Bultos en el piso**: cada soltada es un bulto nuevo, `floor:<n>` con el `n` libre más bajo (sin unidades
  y sin posición: el `floor:0` que deja un guardado, `CompanyRoot.SAVED_HANDS_LOCATION`, no se pisa). El
  evento es `units_moved {product, qty, from: hands:<peer>, to: floor:<n>, pos}`; en cada peer
  `FloorBundles` (`scripts/core/company/floor_bundles.gd`, `CompanyNet.floor_bundles`) anota la posición al
  aplicarlo y, después de cada evento aplicado, olvida todo bulto que quedó vacío (`prune()`: también si en
  el futuro un evento consume unidades del piso, no queda un bulto fantasma). Un `units_moved` hacia
  `floor:` sin `pos` `Vector3` finito no se aplica. **Decisión:** no se suma a un bulto que ya está (cada soltada es uno nuevo), y las
  posiciones viven en una clase de datos aparte y no en `CompanyNet`, que quedó cerca del tope de 1000
  líneas de gdlint.
- **Tomar un bulto** (fila 5): la estación de `units_take` puede ser el propio `floor:<n>` si tiene
  posición; el alcance se mide hasta ahí. Guardar en un bulto con `units_store` se rechaza con
  `no_station` (soltar es `units_drop`).
- **Un peer se va**: el host, en `NetworkManager.peer_removed` (llega con el jugador todavía en pie y antes
  del `peer_disconnected` de un fantasma que suelta, N-221), en `multiplayer.peer_disconnected` (lo que
  llegue primero; el segundo encuentra las manos vacías) o en `NetworkManager.peer_returned(id, id)` (Steam
  le devuelve el mismo id al que vuelve y no hubo ni `peer_removed` ni desconexión), publica un
  `units_moved` por producto de `hands:<peer>` a un bulto nuevo, en sus pies (`_feet_of`) y si no en el
  origen; después olvida `_last_origin[peer]`. Solo en el host. Si llega mientras se aplica un evento, se
  difiere al frame siguiente (sin olvidar dónde estaba); si un evento no se puede publicar, `push_error`.
  El que vuelve recibe el snapshot de D-2004 con el piso así.
- **Snapshot**: clave propia `floor` (en `SNAPSHOT_KEYS`), `{floor:<n>: Vector3}`. El cliente la valida antes
  de tocar nada (`FloorBundles.positions_ok()`: diccionario de a lo sumo `MAX_BUNDLES` = 4096 entradas, ids
  de texto `floor:<n>` de hasta 32 caracteres con `n` entero ≥ 0, `Vector3` finitos) y reemplaza las suyas; un
  snapshot sin la clave deja el piso sin posiciones.
- Test: `test_company_rejoin` (y `test_company_late_join` usa otra clave para su parte de prueba).
- **Pendiente:**
  - dibujar los bultos (nodos estáticos, regla 10) leyendo `floor_bundles` en `event_applied` y
    `company_state_restored` (D-0611);
  - ~~guardar las posiciones con el día (D-0206)~~: no se guardan; al guardar, todo bulto del piso y las manos
    pasan al bulto de devolución `floor:0`, que sí lleva posición (D-0252, [guardado.md](guardado.md) §3);
  - `company_net.gd` quedó en 967 de las 1000 líneas que permite gdlint (ya salieron `FloorBundles` y
    `CompanyAsk`): la próxima acción grande tiene que sacar algo más a otra clase;
  - el margen de `reach_slack()` en `DROP_REACH` depende del RTT y no tiene test propio.

## 8. Lo construido (D-0910): el layout del galpón

- **Peticiones** `layout_place`, `layout_move`, `layout_rotate`, `layout_sell` y **eventos** `layout_placed`,
  `layout_moved`, `layout_sold` (filas 21 a 24, protocolo 34), por el `_request` / `_apply_event` de siempre: ningún
  RPC nuevo. `CompanyNet` solo los suma a `REQUEST_KINDS` / `EVENT_KINDS` y los pasa a `CompanyNet.build`
  (`CompanyLayoutNet`): `check()` en el host, `apply()` en cada peer (`_apply_state`). Ninguno es crítico.
- **Decisión: solo el host construye.** `check()` recibe si el que pidió es el host (`RpcGuard.sender` en
  `_request`, el host mismo en `request()`); cualquier otro oye `host_only` y nada cambia. Así el cliente que
  abre el modo construcción sabe por qué no pasó nada. El voto de la tripulación queda en D-0910.1.
- **Decisión: el día no lo frena.** Construir no depende de la fase ni del galpón congelado (D-0203): ni este
  contrato ni D-0203 lo piden, y un evento de layout no toca `DayCycle` (ni fase ni minuto del galpón). Si el
  jugador puede entrar al modo lo decide el adaptador (`BuildMode.enter(can_build)`, D-0917).
- **Mismas comprobaciones que el modo construcción**: `BuildPlacement.preview` con la grilla, dársena,
  salida y entradas de la etapa (`WarehouseStages.apply_to`, `CompanyLayoutNet.placement_for()`, que el
  adaptador usa también para el verde/rojo local, regla 9) y la plata. Motivos de `_rejected`: los de
  `BuildPlacement` (`out_of_bounds`, `fixed_area`, `overlap`, `blocks_path`, `no_definition`, `no_money`) más
  `host_only`, `no_piece` (no hay pieza con ese `uid`), `not_empty` y `bad_data`.
- **Eventos chicos y absolutos**: enteros y dos ids cortos (< 200 bytes); girar y mover mandan la pose final,
  no el delta. **La plata también va absoluta**: `money` es el saldo del host después del movimiento y cada
  peer arranca la compra o la venta desde el saldo del host antes de ella, así la plata y el `balance` de la
  entrada quedan iguales aunque al espejo le faltara un movimiento. Si el saldo del espejo no era ese, lo
  corrige, avisa (`push_warning`) y `CompanyNet` pide un snapshot para el resto del libro
  (`CompanyLayoutNet.take_drift()`, con el tope de 5 s por peer). `minute` es el `clock_minutes` del host y va
  **solo a la entrada del libro** que el evento escribió: el `clock_minutes` del cliente no se toca (lo escribe
  solo el reloj del host). Cada peer aplica con las mismas llamadas a `PlaceableShop` y solo comprueba los datos
  (regla 6), todas las comprobaciones antes del primer cambio: si su copia no lo toma, no cambia nada y espera
  un snapshot.
- **Una rama por evento** en `CompanyNet._apply_state()` (`CompanyLayoutNet.PLACED, MOVED, SOLD:`), sin `_:`:
  un `kind` nuevo que se olvide su rama no cae en la de otro (`test_company_layout_net` lo lee del código).
- **Nombres estables**: antes de aplicar cualquier evento de layout, toda pieza sin `uid` guardado recibe el
  que ya se deducía (`DefaultShed.piece_uid`, todos calculados antes de guardar ninguno), así vender una no
  renombra a otra y su stock sigue bajo su nombre. Si dos piezas comparten nombre (un `uid` guardado al lado
  de uno deducido, o un guardado editado a mano), la segunda recibe uno nuevo (`<id>_<n>`, el `n` libre más
  bajo), igual en todos los peers; el host nombra una pieza nueva después de ese renombre. `BuildLayoutSave.sanitize`
  no renombra (el primer evento de layout lo hace).
- **Join tardío**: el layout ya viaja en `company` (`CompanyState.to_dict()`); `CompanyState.from_dict` lo pasa
  por `BuildLayoutSave.sanitize`, que conserva un layout que el host validó pieza por pieza. `CompanyShed.follow(net)`
  redibuja el galpón en cada evento de layout y en `company_state_restored`, y las etiquetas en `units_moved`
  (`CompanyRoot` lo usa).
- Test: `test_company_layout_net` (solo, host + cliente ENet y un tercero que entra tarde).
- **Pendiente:**
  - el voto de la tripulación para que un cliente construya (D-0910.1);
  - ampliar la etapa por red (D-0910.2): `WarehouseStages.expand` hoy es local; quien lo cablee en el host
    sin un evento deja a los clientes con otra grilla hasta el próximo snapshot (la ampliación comprada en la
    tienda ya viaja como `shop_bought`, §13);
  - `CompanyLayoutNet.navigation` (D-0908) lo da el mundo cuando existan empleados (D-1011), y ese dueño
    llama a `rebake()` también en `company_state_restored`;
  - ~~`not_empty` mira `shelf:<uid>_<hueco>` y `table:<uid>`; cuando la caja en armado viaje por red
    (`box_started` / `box_place`, D-0702 / D-0703, unidades en `box:<id>`), vender una mesa también tiene
    que mirar su caja~~ (hecho en D-0715, §9: `CompanyNet._build` lo rechaza con `not_empty`);
  - `money_changed` de `CompanyState` sale en medio de aplicar el evento (como cualquier movimiento de plata
    hoy): es **solo para presentación**; quien lo escuche no puede pedir ni publicar nada ahí (una regla del
    host escucha `event_applied`);
  - `CompanyShed.follow` hace un `rebuild()` entero (piso y paredes incluidos) por cada evento de layout: los
    eventos son de a uno y a ritmo humano, pero si se nota un tirón, rehacer solo los muebles (`Furniture`) y
    los palets;
  - ~~`holds_units` mira solo `shelf:<uid>_<hueco>` y `table:<uid>` (ver arriba la caja en armado)~~ (D-0715).

## 9. Lo construido (D-0715, parte a): la mesa de armado compartida

- **Peticiones** `box_start`, `box_place`, `box_take_out`, `box_fill`, `box_label`, `box_stamp`, `box_tape` y
  **eventos** `box_started`, `box_placed`, `box_taken_out`, `box_filled`, `box_labeled`, `box_stamped`,
  `box_sealed` (filas 9 a 15, protocolo 37), por el `_request` / `_apply_event` de siempre: ningún RPC nuevo.
  `CompanyNet` los suma a `REQUEST_KINDS` / `EVENT_KINDS` y los pasa a `CompanyNet.table`
  (`CompanyTableNet`, `scripts/core/company/company_table_net.gd`): `check()` en el host, `apply()` en cada
  peer, con una rama de `_apply_state()` por grupo de eventos (sin `_:`). Ninguna es crítica (regla 8):
  ninguna suelta nada; si se pierde, el jugador vuelve a apretar.
- **La mesa no tiene dueño** (fila 8): cualquier peer hace cualquier paso sobre la misma caja (uno pone
  productos, otro rellena, sella y encinta). El host atiende las peticiones de a una, así que de dos que
  chocan (dos cajas en la misma mesa libre, dos productos en la misma celda) pasa la primera y la segunda
  oye el motivo (`has_box`, `cell_taken`). La del host se atiende al pedirla; la de un cliente, al llegar.
- **Estación (regla 4):** una mesa es una estación de `CompanyNet.stations` con `location` `table:<uid>` (el
  `uid` de la pieza del layout) y `spot` en el hueco de la caja; el alcance se mide como en las unidades
  (`_lookup_station` / `_station_problem`). Cualquier otra ubicación es `no_station`.
- **Estado:** un `PackingStation` por mesa tocada (caja, insumos de D-0718) y el id de su caja, en
  `CompanyNet.table` y no en `CompanyShed.stations` (que solo dibuja). Los ids de caja los da el host,
  `box_<n>` después del último, salteando los que todavía tienen unidades (`box:<id>` o `package:<id>`: un
  día cargado los trae). Las unidades de la caja abierta están en `box:<id>`; al encintar pasan a
  `package:<id>` (`package_id` = id de la caja) y la reserva del pedido de la etiqueta baja en lo que lleva
  (`Inventory.unreserve`). Los productos "en espera" de la mesa (`PackingStation.staged`) no viajan: por red
  la unidad va de la mano a la grilla.
- **Reserva (fila 10):** poner una unidad de P en la caja de la mesa con pedido X pasa si a X todavía le falta
  P en su caja (reserva de X mayor que lo de P en su caja); si no, pasa si queda una unidad libre: las de P
  fuera de cajas y paquetes, menos lo que cada pedido tiene reservado y todavía no está en su caja, tiene
  que dar al menos 1. Si no, `reserved_for_other`.
- **Pedido de la mesa:** hasta que exista `order_claim` (fila 8, D-0804 / D-0807), lo da
  `CompanyTableNet.order_of` (`Callable(table) -> Order`, en el host); sin él ninguna mesa tiene pedido:
  `box_label` es `no_order` y `box_place` solo toma unidades libres. Calidad y trampa de `box_sealed` se
  calculan en el host con la caja ya encintada y el pedido de su etiqueta (`AssemblyQuality`, `BoxTrap`,
  `BoxToPackage.absorption`).
- **Plata absoluta** (como D-0910): los pasos que se pagan llevan `money` (saldo del host después) y `minute`
  (minuto del host, solo para la entrada del libro). Cada peer arranca el paso desde el saldo del host antes;
  si el suyo era otro lo corrige, avisa y `CompanyNet` pide un snapshot (`CompanyTableNet.take_drift()`).
- **Join tardío:** las mesas viajan en el snapshot como la parte `packing` (`{serial, tables: {uid: {box_id,
  box, supplies}}}`), que `CompanyNet` suma sola en `_init()`. El cliente la valida antes de tocar nada
  (`CompanySnapshot.tables_from()`: a lo sumo 256 mesas, más que las 100 piezas del galpón más grande; ids
  de texto corto; cada caja abierta (sin cinta) tal como la escribe `PackedBox.to_dict()` y que vuelve igual
  de `from_dict()`, productos del catálogo con sus celdas del catálogo, cada sello una vez; un id por caja;
  insumos en su rango). Aplicarlo borra el aviso de plata desfasada (`take_drift()`): el snapshot ya trae la
  del host.
- **Layout:** vender una mesa con caja es `not_empty` (`CompanyNet._build`); `layout_sold` olvida el estado de
  la mesa vendida (una mesa nueva con el mismo `uid` arranca llena).
- **Motivos de `_rejected`:** los de `CompanyNet` (`bad_data`, `no_station`, `out_of_reach`, `not_enough`,
  `hands_busy`, `hands_full`, `no_room`) más `no_money`, `has_box`, `no_box`, `sealed`, `no_supply`,
  `cell_taken`, `empty_cell`, `reserved_for_other`, `no_order`, `already_stamped`, `empty_box`, `no_trap`
  (D-0715.b, §11) y `supply_full` (D-0715.c, §14). Una celda que llega como `Vector3i` no pasa `dict_ok` y se
  descarta sin aviso (regla 5).
- **Líneas:** el empaquetado del snapshot y los chequeos de lo que trae salieron a `CompanySnapshot`
  (`scripts/core/company/company_snapshot.gd`; `CompanyNet.pack_snapshot`, `unpack_snapshot` y `stock_ok`
  siguen con la misma firma). `company_net.gd` queda en 990 de las 1000 líneas de gdlint: la próxima acción
  tiene que sacar algo más (p. ej. el armado de trozos `_take_chunk`).
- Test: `test_company_shared_table` (y `test_company_layout_net` lee las ramas `CompanyTableNet.*`).
- **Pendiente:**
  - ~~**D-0715.b**: cada peer crea el mismo `DeliveryPackage` con lo de `box_sealed` (regla 10), validando
    antes `pos`, `basis`, `quality`, `trap` y `node_name`~~ (hecho, §11); de D-0715.b quedan las cajas vivas
    en el snapshot con `update_visibility` después del último trozo, `OrderBook` → armado (`order_packed`)
    ahora que el libro está en `CompanyNet.orders.book` (D-0813, §10) (`_serial` no se guarda: [guardado.md](guardado.md) §4);
  - ~~**D-0715.c** (bloquea D-0701.b): `box_restock` (reponer los insumos por red; D-0718 es local) y
    `box_discard` (desarmar o tirar la caja abierta): sin ellas una mesa sin cinta queda trabada con su caja~~
    (hecho, §14);
  - la mesa visible (D-0701.b) da `stations` para cada mesa y dibuja desde `net.table.station_of(uid)`;
  - `order_claim` (fila 8) llena `CompanyTableNet.order_of`;
  - ~~guardar las mesas con el día (D-0206)~~: no se guardan; lo de `box:<id>` va al bulto de devolución al
    guardar (D-0252, [guardado.md](guardado.md) §3).

## 10. Lo construido (D-0813): los pedidos del día

- **Un libro en cada peer:** `CompanyNet.orders` (`CompanyOrdersNet`, `scripts/core/company/company_orders_net.gd`)
  tiene el `OrderBook` que comparten todos (`orders.book`), igual en todos y escrito solo por eventos del host. Ningún
  `kind` de petición lo toca: un cliente no tiene cómo escribirlo (regla 1); `publish()` y `poll()` no hacen nada en
  un cliente.
- **Eventos** `order_added` y `order_expired` (fila "Fuera de las 20", protocolo 41), por `publish()`
  (`HOST_EVENT_KINDS`) y el `_apply_event` de siempre: ningún RPC nuevo. Cada peer, el host también, los aplica en
  `CompanyOrdersNet.apply()` (una rama de `_apply_state()`, sin `_:`) y solo comprueba datos (regla 6).
- **El host decide:** `plan_day(seed, day, players, zones, products, requirements, company)` arma el plan del día con
  `OrderGenerator.generate_day` (minutos de `OrderRhythm`, la semilla del día, menos pedidos en rojo, D-0510) y
  `poll(net, minuto)` publica un `order_added` por cada pedido planeado cuyo `created_min` ya llegó, del más viejo al
  más nuevo, y después un `order_expired` por cada pedido del libro que pasó su `due_min` (`OrderBook.overdue()`, en
  el orden del libro). Un pedido sale del plan recién cuando su evento salió: uno que nunca entraría (`order_ok()`
  lo rechaza o su id ya está en el libro) se descarta con un aviso; con el libro lleno, mientras se aplica un evento
  (`CompanyNet.is_applying()`), sin inventario o con `publish()` rechazado, `poll()` corta y el próximo reintenta. El
  plan (lo que falta llegar) no viaja ni va en el snapshot. **Decisión:** viaja el pedido
  entero (380 a 550 bytes, medido) y no la semilla: así ningún cliente necesita los mismos catálogos, zonas abiertas,
  tripulación y plata que el host para llegar al mismo pedido, y uno que entra tarde lo recibe igual en el snapshot.
- **Validación (regla 5)**, `CompanyOrdersNet.order_ok()`: exactamente las claves de `Order.normalize()` (más las que
  suma el libro al moverse, `box_id`, `trip_id`, `late_from`, `quality`, `paid`, `intact` y, en un pedido entregado, `stars` 1-5 (D-0816.b), solo en el snapshot), id y
  cliente de texto de hasta 64, una zona de `data/zones/` y una casa del mapa (`HouseAddresses`) o `<zona>_house_<n>`
  de esa zona con `n` de 1 a 12, de 1 a 3 productos del catálogo distintos con `qty` entera 1..24, requisitos de
  `data/order_requirements/` sin repetir, `created_min < due_min` enteros, paga entera 0..10⁹ y estado conocido (`open`
  en un evento). Un `order_added` de un id que el libro ya tiene, o con el libro lleno (`MAX_ORDERS` = 256 desde D-0813.1), no
  se aplica; un `order_expired` de un pedido desconocido, cerrado, ya atrasado o que a ese `minute` todavía no venció,
  tampoco. En el host `publish()` devuelve `false` sin gastar `seq` (y `push_error`); en un cliente el evento no se
  aplica y el peer pide snapshot (§3).
- **Join tardío y huecos:** parte `orders` del snapshot (`{orders, now_min}`, `OrderBook.to_dict()`), que `CompanyNet`
  suma sola en `_init()`. El cliente la valida entera antes de tocar su libro (`book_ok()`: a lo sumo `MAX_ORDERS`,
  cada pedido `order_ok()` con los campos del libro, sin ids repetidos, `now_min` entero) y la pone con
  `OrderBook.from_dict()`, que no emite señales.
- **Líneas:** `company_net.gd` queda en 996 de las 1000 de gdlint (el cuerpo de `_lookup_station` salió a
  `CompanyAsk.station_of()`): la próxima acción tiene que sacar algo antes de sumar (p. ej. el armado de trozos
  `_take_chunk`).
- Test: `test_company_orders_net` (solo, la parte del snapshot, y host + cliente + uno que entra tarde por ENet);
  `test_order_book` suma `overdue()` y `expire_one()`; `test_company_layout_net` ya lee las ramas nuevas de
  `_apply_state()`.
- **El mundo (D-0813.1):** el host planea cada día nuevo en el `OPENING` (`CompanyDayOrders.plan()` →
  `CompanyDayOrders.plan()`: `day_seed(CompanySeed.ORDERS)`, tripulación de la sesión, zonas sin portón o con todos los
  suyos abiertos, catálogos; una vez por día, así un `OPENING` repetido por congelar el galpón no replanea) y el
  `BusinessTick` suma el paso `orders` después de `day_cycle` (`CompanyDayOrders.poll()`: `poll(net,
  floor(shed_minute()))` solo en `OPENING` y `OPERATING`). Cada peer emite `EventBus.order_added` desde
  `event_applied` (nunca por un snapshot ni desde las señales del libro). **Poda:** el `day_phase` que abre un día nuevo
  (`DayCycle.apply_phase()`, `is_new`) llama `CompanyOrdersNet.prune_closed()` adentro del evento, en cada peer: el
  libro suelta los entregados, fallados y cancelados (todos de días anteriores) y se queda con los abiertos, armados,
  en camino y atrasados. Determinista porque fase, día y libro son los mismos en todos en cada `seq` (eventos y
  snapshot), sin `kind` nuevo ni cambio de protocolo. `MAX_ORDERS` baja a 256. `CompanyTrips` y `OrderBoxLink` siguen
  con su libro (el bot del día le copia los pedidos al de `CompanyTrips`); el tablero de stock lee el compartido, solo
  los pedidos del día (`only_today`, por el id `d<día>_`). Con el libro lleno `poll()` no trae pedidos pero sigue
  mandando los vencimientos. Test: `test_company_orders_world`.
- **Pendiente:**
  - lo que `CompanyTrips` hace directo sobre su libro (`mark_out` al salir, `close` al volver) y el armado
    (`order_packed`) pasan a eventos con las filas 15, 17, 19 y 20 (D-0715.b, D-0716, D-0302, D-0815): un cambio
    del libro compartido que no sea evento queda solo en el host hasta el próximo snapshot (hoy no pasa: ningún
    vehículo sale). `order_claim` (fila 8) llena `CompanyTableNet.order_of` desde este libro. **El PR que traiga
    esos eventos sube `PROTOCOL_VERSION`**: con pedidos que se cierran, la poda del `OPENING` cambia lo que hace un
    `day_phase` sobre el libro (D-0813.1 no lo subió porque hasta entonces no hay pedidos cerrados que podar);
  - ~~el abandono (`abandon()`: FAILED y reputación, D-0807) como evento propio~~: hecho en D-0851 (§14), `order_closed`; la
    reputación la escribe solo el host (no viaja absoluta como la plata);
 - ~~guardar el libro con el día (D-0206)~~: no se guarda, se vuelve a sortear en `OPENING` ([guardado.md](guardado.md) §4). Mientras nada cierre pedidos del libro compartido (las filas de arriba), la
    poda no suelta nada y el libro crece hasta 16 por día: lleno (256, unos 16 días de la tripulación más grande en una
    sola sesión) `poll()` espera y no entran pedidos nuevos (`revisar/D-0813.1.md`).

## 11. Lo construido (D-0715.b): el paquete de la caja encintada

- **Cada peer crea el mismo `DeliveryPackage`** al aplicar `box_sealed` (fila 15, protocolo 42; el evento no
  cambia): `CompanyPackages` (`scripts/core/company/company_packages.gd`, `CompanyTableNet.packages`) lo arma
  con `BoxToPackage.build` desde la caja encintada que tiene ese peer y le pone lo que dice el host: nombre
  `node_name`, `package_id`, trampa, absorción, la pose `pos`/`basis` (espacio del mundo) y calidad e
  intensidad en la meta `BoxToPackage.META_TRAP_PLAN`. Va bajo `parent`, el mismo camino en todos los peers
  (`CompanyRoot`: `World/Packages`); sin `parent` no se crea nada y el evento se aplica igual.
- **Validación (reglas 5 y 6), antes del primer cambio:** `node_name` = `Package_<package_id>`, nombre de
  nodo válido y libre bajo `parent`; `pos` `Vector3` finito y `basis` `Basis` que juntos pasan
  `RpcGuard.finite_transform`; `trap` el nombre exacto de un `.tres` de `data/traps/`; `quality` en
  0..`QUALITY_MAX`; `trap_intensity` y `absorption` en 0..1. El paquete se construye (fuera del árbol)
  antes de mover plata o unidades; si algo no encaja, no cambia nada y el peer espera un snapshot.
- **El host no encinta lo que no puede ser paquete:** `box_tape` de una caja cuyo producto principal no
  nombra una trampa de `data/traps/` (error de catálogo) se rechaza con `no_trap` (motivo nuevo de §9), en
  vez de fallar su propio `apply()`. Un id de caja cuyo `Package_<id>` sigue en el mundo no se reparte
  (`_new_box_id` lo saltea): un paquete que sobrevive no traba la mesa.
- **Regla 10 en el host, con acuse:** el sincronizador entra con un filtro (`add_visibility_filter`, se suma
  al de `package.gd`) que no deja pasar a nadie hasta que **ese peer** dice que tiene el nodo. El cliente,
  al crear el paquete, pide `package_ack` `{package, rid}` (un `kind` más de `_request`, ningún RPC nuevo;
  diferido, porque mientras se aplica un evento no se pide nada); el host comprueba que `package` sea un id
  cuyo `Package_<id>` es un nombre válido y un paquete suyo, y recién ahí abre el sincronizador a ese peer.
  Un acuse de algo que no hay no cambia nada y no se contesta (`bad_data` solo si no es un id). **Por qué
  acuse y no "abrir al mandar el evento"** (auditor-red, B1): un cliente que espera un snapshot guarda el
  `box_sealed` y lo aplica más tarde (o nunca, si el snapshot ya lo cubre o su copia no lo acepta); el camino
  del sincronizador que le llega antes que el nodo no se vuelve a mandar y esa copia queda quieta para
  siempre. Un peer que se va o cuyo mundo vuelve a levantar sale del filtro hasta que acuse de nuevo; el que
  entra tarde no tiene el nodo y nunca lo recibe (sin filtro: `Node not found:
  ".../Packages/Package_box_1/MultiplayerSynchronizer"`).
- **Física lejos (D-0318.1):** el host registra cada paquete en `CompanyRoot.cells` (`track_body`) y lo
  suelta al salir del árbol.
- Test: `test_company_sealed_package` (solo, campos malos, `no_trap`, id salteado, host + cliente ENet, el
  cliente que espera un snapshot mientras se encinta, y un tercero que entra tarde) y `test_company_root`
  (celdas).
- **Protocolo:** 42 (sobre el 41 de D-0813).
- **Pendiente:**
  - las cajas vivas en el snapshot (hasta entonces el que entra tarde, o un cliente cuyo snapshot cubrió el
    `box_sealed`, no ve las cajas ya encintadas; con el acuse no recibe errores, solo no las tiene);
  - **ancho de banda por paquete:** cada `DeliveryPackage` manda su pose a 30 Hz a cada peer que acusó,
    ~3 KB/s por peer aunque esté quieto; ~~entrar a `company_loose_box`~~ (hecho en D-0316.3, regla 11: solo
    a los peers cerca); queda bajar su frecuencia en reposo para los que están cerca;
  - **dónde aparece:** en el `spot` de la estación (el hueco de la caja) con base identidad; un cubo de
    0,65 m centrado ahí puede quedar metido en la tabla; revisarlo con `probador-qa` cuando exista la mesa
    visible (D-0701.b);
  - `order_packed`; `_serial` con el día (D-0206).

## 12. La semilla de la empresa (D-0246)

- **Una semilla por empresa**, `CompanyState.company_seed` (1 a 2³¹−1), sorteada en `new_company()` y guardada con la
  empresa. Viaja en la parte de `CompanyState` del snapshot como cualquier campo, pero **ningún cliente sortea con
  ella**: los pedidos salen enteros (`order_added`, §10). Que el cliente la tenga no le da nada que decidir.
- **La del día:** `CompanyState.day_seed(CompanySeed.ORDERS)` = `hash([company_seed, día, "orders"])`. Es la que el host
  le pasa a `CompanyOrdersNet.plan_day()` en el `OPENING` (D-0813.1). Una corriente por sistema (`ORDERS`, `SUPPLIERS`
  para el mercado de D-0133), así sumar un sorteo en uno no corre los del otro.
- **Regla para lo que venga:** todo sorteo del negocio sale de un `RandomNumberGenerator` con una semilla de
  `day_seed()` (o derivada de ella), y solo en el host. `test_company_seed` falla si aparece un `randi()`, `randf()`,
  `randomize()`, `shuffle()` o `pick_random()` global en `scripts/gameplay/business/` o `scripts/core/company/`.
- Guardado de antes de D-0246: semilla sacada del nombre (`CompanySeed.from_name`), estable entre cargas.
- "Mismo día" es con la misma semilla, día, tripulación y plata (`OrderRhythm`, `Bankruptcy`). `test_company_seed` fija
  `for_day(1234, 3, "orders")` = 550168617 (Godot 4.7.2): si un motor nuevo hashea distinto, el test avisa.

## 13. Lo construido (D-0518): la tienda, solo el host gasta

- **Petición** `shop_buy` y **evento** `shop_bought` (fila 25, protocolo 50), por el `_request` / `_apply_event` de
  siempre: ningún RPC nuevo. `CompanyNet` los suma a `REQUEST_KINDS` / `EVENT_KINDS` y los pasa a `CompanyNet.shop`
  (`CompanyShopNet`, `scripts/core/company/company_shop_net.gd`): `ask()` / `check()` en el host, `apply()` en cada
  peer (una rama de `_apply_state()`, sin `_:`). No es crítica (regla 8): si se pierde, el jugador vuelve a apretar.
- **Decisión: solo el host gasta** (D-0518 incluye D-0428, el voto de la tienda; "el host o un voto" se resuelve como
  "el host" en esta tarea). El que pide es `RpcGuard.sender` (regla 3): un `peer: 1` en `data` no cambia nada.
  Cualquier otro peer oye `host_only` antes de que se mire nada más, nada cambia y no se gasta `seq`; así la
  pantalla de la tienda del cliente (D-0511.2) puede decir por qué. Jugando solo, el host es el peer 1 y compra por
  el mismo camino. El voto de la tripulación queda en D-0518.b, en el mismo lugar que D-0910.1 (`check()` recibe
  `by_host`).
- **Motivos de `_rejected`:** `host_only`; `bad_data` (el ítem no es texto, es largo, no es el id exacto de un ítem
  habilitado del catálogo, o no hay empresa); y las claves de `CompanyShop.check` tal cual
  (`WORLD_SHOP_ALREADY_OWNED`, `WORLD_SHOP_NEEDS_ITEM`, `WORLD_SHOP_WRONG_STAGE`, `WORLD_SHOP_CANNOT_AFFORD`): son
  claves de traducción y la pantalla las muestra sin mapear. Un campo anidado en `data` no pasa `dict_ok` y se
  descarta sin aviso (regla 5).
- **Decisión: el día no lo frena**, como construir (§8): ni la fase ni el galpón congelado. La tienda es la
  pantalla del cierre (D-0511.2, `hitos.md`: "se compra en la tienda del cierre"), justo en SUMMARY, donde el pedido
  al proveedor sí se niega (`day_closed`: su calendario es el del día cerrado). Una compra hecha en SUMMARY queda
  en `CompanyState` del host y entra al guardado cuando el host sale del mundo (`save_closed_day()` desde
  `_exit_tree`) o en el guardado siguiente; si el juego se cae antes, se pierden juntas la compra y la plata.
- **Plata absoluta** (como D-0910 y D-0715): `money` es el saldo del host después de la compra y `minute` su
  `clock_minutes` (solo para la entrada del libro: el `clock_minutes` del cliente no se toca). Cada peer arranca
  desde `money + price` con el mismo `CompanyShop.buy`; si su saldo era otro lo corrige, avisa y `CompanyNet` pide
  un snapshot (`CompanyShopNet.take_drift()`, junto a las de `build` y `table` en `_receive`).
- **Validación del evento (regla 6), todo antes del primer cambio:** exactamente `item`, `money` y `minute`; un
  ítem habilitado del catálogo de ese peer; `money` entero 0..`MAX_MONEY`; `minute` entero del día; y que la copia
  lo pueda tomar (`CompanyShop.check` salvo la plata: no lo tiene, tiene lo que requiere, es la etapa siguiente).
  Si no, no cambia nada y el peer espera un snapshot (§3).
- **Join tardío:** sin parte propia del snapshot: plata, libro, `equipment`, `fleet` y `warehouse_stage` ya viajan
  en `company` (`CompanyState.to_dict()`).
- **Líneas:** para sumar la tienda, los chequeos de un trozo de snapshot y su unión salieron de
  `CompanyNet._take_chunk` a `CompanySnapshot.chunk_ok()` / `join()` (mismo comportamiento); `company_net.gd` queda
  en 996 de las 1000 de gdlint.
- Test: `test_company_shop_net` (el ayudante solo, solo con el catálogo real, y host + cliente ENet + uno que entra
  tarde, con un catálogo de test que habilita un vehículo).
- **Pendiente:**
  - D-0518.b: el voto de la tripulación para que un cliente compre (`modules/coop_vote`; `ShopVoteManager` es la
    votación de la tienda del depósito de Entrega, de Slatex, y no se usa acá);
  - la pantalla de la tienda (D-0511.2) pide con `CompanyNet.request(CompanyShopNet.BUY, {"item": id})` y muestra
    el motivo de `request_rejected` (`tr()` para las claves `WORLD_SHOP_*`, un texto propio para `host_only`);
  - una ampliación comprada cambia `warehouse_stage` en todos por evento (lo que D-0910.2 pedía para la grilla),
    pero `CompanyShed.follow` no redibuja con `shop_bought`: el galpón grande se dibuja con el próximo evento de
    layout o snapshot. Va con D-0910.2 o con D-0511.2;
  - un vehículo comprado entra a `fleet` como dato; que aparezca en el mundo es de cada vehículo (D-1207, D-1221…).

## 14. Lo construido (D-0616.b): la leche que se echa a perder

- **Evento** `units_spoiled` `{product, qty, location}` (protocolo 51): lo publica solo el host (`HOST_EVENT_KINDS`, ningún
  pedido lo origina) cuando `ColdChainTick` ve que las unidades de un producto frío llevan `COLD_SPOIL_MINUTES` fuera
  de una heladera; cada peer, el host también, lo aplica con `Inventory.discard` (`CompanyColdNet.apply`, una rama de
  `_apply_state()`). Es el stock del lugar entero. No dice qué pedidos pierden reserva: `discard` recorta las
  reservas más nuevas hasta que entren y todos los peers tienen las mismas reservas (viajan en el snapshot), así que
  todos recortan las mismas. Si el lugar no tiene esas unidades, el evento no entra y el cliente pide snapshot.
- **Los relojes son solo del host** (`ColdChain`): el cliente ve la pérdida como stock y nada más. Van a
  `CompanyState.cold_clocks` solo para el guardado (`ColdChainTick.write_clocks` antes de cada `CompanySave.save`) y
  `CompanyNet.snapshot()` los saca de la parte `company`. Un guardado viejo sin esa clave carga con relojes en cero
  (no hace falta subir `CompanySave.VERSION`).
- `company_net.gd` queda en 996 de las 1000 líneas de gdlint: lo que siga va en archivos nuevos.

## 15. Lo construido (D-0715.c): reponer la mesa y tirar la caja

- **Peticiones** `box_restock` y `box_discard`, **eventos** `box_restocked` y `box_discarded` (filas 15a y 15b,
  protocolo 52), por el `_request` / `_apply_event` de siempre: ningún RPC nuevo. Van con los otros pasos de la
  mesa en `CompanyTableNet` (`check()` en el host después del alcance de `CompanyNet._pack`, `apply()` en cada
  peer, una rama de `_apply_state()` sin `_:`). Ninguna es crítica (regla 8): si se pierde, el jugador vuelve a
  apretar. Sin ellas una mesa sin cinta quedaba trabada con su caja en una sesión.
- **Reponer** (`box_restock {station, supply}`): un insumo por petición, de vuelta a su capacidad
  (`StationSupplies.restock`), con caja en la mesa o sin ella. Motivos: `bad_data` (un `supply` que no es de
  `StationSupplies`), `supply_full` (motivo nuevo: ya está lleno) y `no_supply` si el galpón está corto de eso
  hoy (`CompanyTableNet.short_of`, `Callable(supply) -> bool` del host: el gancho para `box_shortage`,
  [eventos-del-dia.md](eventos-del-dia.md) #4; sin él, todo se repone). **Decisión:** gratis, como decidió D-0718
  (cuesta el tiempo del que se queda), así que `box_restocked` no lleva `money` ni `minute`; lleva `count`, lo que
  queda en la mesa del host, y cada peer solo lo acepta si es la capacidad de ese insumo (un peer con otra tabla de
  capacidades no lo aplica y pide snapshot).
- **Tirar** (`box_discard {station}`): la caja abierta sale de la mesa y se pierde. **Decisión:** se tira, no
  queda vacía en la mesa como en `PackingStation.disassemble()` (D-0719): una caja del tamaño equivocado seguiría
  trabando la mesa, y sacar productos para rearmar la misma caja ya es `box_take_out`. De D-0719 vale el resto:
  relleno, etiqueta y sellos se pierden, no se devuelve plata y la caja no vuelve a los insumos. `disassemble()`
  no se usa porque deja los productos en `PackingStation.staged`, que por red no viaja.
- **A dónde van las unidades:** a `hands:<peer>` del que pide si entran **todas** (un solo producto; mano vacía
  o con ese producto; hasta `HAND_MAX_UNITS`, la regla de `units_take`); si no, **todas** a un bulto nuevo
  `floor:<n>` (`FloorBundles.next_free`) en el `spot` de la mesa, donde estaba la caja, que se levanta con
  `units_take` en ese bulto. **Decisión:** el `spot` y no los pies del jugador: no depende de la pose que replica
  el cliente y es donde D-0719 deja los productos ("de vuelta en la mesa") y donde aparece el paquete de
  `box_sealed`. `CompanyTableNet.bundles` es el `CompanyNet.floor_bundles` de ese peer (lo pone `CompanyNet` en
  `_init()`). La reserva del pedido no cambia: por producto, sigue en pie como con `units_take`.
- **Validación del evento (regla 6), todo antes del primer cambio:** la mesa tiene la caja `box` del evento y el
  mismo `contents`; las unidades están en `box:<id>`; `to` es una mano (con a lo sumo un producto) o un bulto
  `floor:<n>` con `pos` finito (`FloorBundles.positions_ok`), con algo que guardar, vacío y sin posición en esa
  copia. `box_restocked`: `supply` conocido y `count` entero igual a la capacidad. Si no, no cambia nada y el peer
  espera un snapshot (§3).
- **Join tardío:** sin parte nueva del snapshot: los insumos van en `packing`, las unidades en `inventory` y la
  posición del bulto en `floor`.
- **Líneas:** `company_net.gd` queda en 999 de las 1000 de gdlint: la próxima acción tiene que sacar algo antes
  (p. ej. el armado de trozos `_take_chunk`).
- Test: `test_company_table_restock_discard` (solo con los rechazos y los destinos de las unidades, eventos que
  no encajan, y host + cliente ENet + uno que entra tarde).
- **Pendiente:**
  - el gesto de reponer y el cartel de "falta X" (`StationSupplies.low_kinds()`) en la mesa visible (D-0718.b,
    D-0701.b): pide `CompanyNet.request(CompanyTableNet.RESTOCK, {"station": id, "supply": kind})` por insumo;
  - `short_of` lo llena el evento `box_shortage` cuando exista (grupo 05);
  - dibujar el bulto que deja `box_discarded` (D-0611): está en el `spot` de la mesa, a la altura de la tabla, y
    puede quedar debajo de la caja nueva que se abra ahí;
  - textos de UI para `supply_full` (y los demás motivos de la mesa).

## 14. Lo construido (D-0851): el cierre del día para los pedidos

- **Evento** `order_closed {order, state}` (`CompanyOrdersNet.CLOSED`, `HOST_EVENT_KINDS`, protocolo 57): exactamente esas dos
  claves, el id de un pedido del libro y `state` `failed` o `cancelled`. Cada peer, el host también, lo aplica en
  `CompanyOrdersNet.apply()` con `OrderBook.mark_failed()` / `cancel()`: una transición que el libro no permite (cancelar un
  atrasado, cerrar uno ya cerrado) no se aplica, así que el host no lo publica y un cliente pide snapshot. Sin `minute`: no
  lo usa nadie.
- **La reputación es del host.** `_close()` publica y, solo si salió, suma `OrderPenalties.abandoned(order)` (−3, tope por pedido
  −10) a `net.company`; el aplicar del evento no toca `CompanyState`. Un cliente ve su reputación nueva con el próximo
  snapshot (no hay evento de reputación): lo mismo que antes con la reputación de cualquier otra fuente. **Decisión:** no se
  agregó la reputación absoluta al evento (como la plata de D-0517) porque el test de la tarea pide que solo cambie en el
  host; si el HUD del cliente la muestra, sale una tarea para replicarla.
- **Quién lo publica.** `CompanyOrdersNet.abandon(net, minuto, on_road)` (el cliente se cansó: tarde, fuera de la ruta, una
  ventana después de `due_min`) desde `CompanyDayOrders.poll()` en `OPENING`, `OPERATING` y `CLOSING`;
  `fail_returned(net, ids)` desde `CompanyRoot` cuando `CompanyTrips.trip_closed` trae pedidos sin entregar;
  `close_day(net, minuto, early)` desde `DayCycle.poll()` en `CLOSING` cuando `trips_out() == 0`, con el minuto del galpón y
  `early` si el día lo cerró `close_early()`. `OrderDayClose` (`scripts/gameplay/business/`) decide los ids sin tocar el libro
  (`OrderBook` está en el límite de métodos públicos de gdlint). `DayCycle` espera un `poll` más antes de `SUMMARY` solo si cerró
  algo; con el libro sin pedidos pasa directo.
- **Vehículo que sale de noche.** `CompanyTrips.day_open` (`DayCycle.is_day_closed()` negado): la salida se niega con
  `DAY_CLOSED` (`UI_COMPANY_GATE_DAY_CLOSED`) y el que cruza igual queda en `_night_out`: está afuera (no se le vuelve a
  negar, `refused_returned` al volver) pero no cuenta en `trips_out()`, así que no traba el resumen. La vista de salidas
  (`CompanyTripsView`) no cambia: ve un `trip_refused` y un `trip_closed` sin viaje como con el tope de vehículos.
- **Pendiente:** el libro compartido no se entera aún de que un pedido salió o se entregó (filas 15, 17, 19 y 20 de este
  documento, D-0815.b, D-0302): `abandon()` consulta a `CompanyTrips.carries()` para no abandonar lo que va en camino, y
  `fail_returned()` cubre el que vuelve sin entregar; **cuando la puerta entregue (D-0815.b) tiene que publicar la entrega
  como evento del libro compartido**, o el cierre del día lo va a dar por no entregado. Test: `test_company_day_close_orders`.
