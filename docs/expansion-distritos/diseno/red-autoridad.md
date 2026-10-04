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
2. **Dos RPC de negocio y uno de aviso**, todos en `CompanyNet` (hijo de `CompanyWorld`, D-2003):

   | RPC | Modo | Guardas |
   |---|---|---|
   | `_request(kind: StringName, data: Dictionary)` | `@rpc("any_peer", "call_local", "reliable")`, cliente → host (`rpc_id(1, …)`); el host se llama a sí mismo por el mismo camino | descarta si no es el host; `RpcGuard.allow_request` (o `allow_critical_request` si la tabla dice **crítica**), `name_ok(kind)`, `dict_ok(data)`, `kind` dentro de la lista blanca de §2 |
   | `_apply_event(seq: int, kind: StringName, data: Dictionary)` | `@rpc("authority", "call_local", "reliable")`, host → cada peer con `is_peer_ready()` | `RpcGuard.from_host`; `seq` mayor que el último aplicado (si no, se ignora) |
   | `_rejected(rid: int, reason: StringName)` | `@rpc("authority", "call_remote", "reliable")`, host → solo el que pidió | `RpcGuard.from_host`; solo dibuja un aviso, no toca estado |

   **Decisión:** el tercer RPC existe para que el jugador sepa por qué no pasó nada ("no hay stock",
   "la mesa está ocupada"). Sin él, una petición rechazada es indistinguible de un lag. Lleva un `rid`
   (entero que pone el cliente en `data.rid`) para que la UI sepa a qué intento responde. No gasta `seq`.
3. **El actor es `RpcGuard.sender(self)`, nunca un campo de `data`.** Toda ubicación `hands:<peer>` la arma
   el host con ese número. Un cliente que manda `peer: 3` en `data` se ignora.
4. **Alcance físico lo mide el host.** Toda acción en una estación (palet, estante, mesa, tablero,
   dispensador) lleva `station: StringName` (el id estable de la estación, no un `NodePath`); el host busca
   la estación en `CompanyWorld` y exige la misma distancia que `Interactable._within_reach`
   (`REMOTE_REACH` + `NetStats.reach_slack`). **Decisión:** id y no `NodePath` porque el id también es la
   clave en el layout guardado y en el `Inventory` (`shelf:<id>`, `table:<id>`); el host nunca resuelve un
   camino que mandó un cliente.
5. **Datos planos y acotados.** `data` solo lleva `int`, `float` finitos, `bool`, `StringName` y `Vector2i`
   (celdas de la grilla); cantidades `1..Pallet.MAX_UNITS`; ids que existen en el registro (`data/products/`,
   tamaños de caja, pedidos vivos). Lo que no cumple se rechaza con `_rejected(rid, &"bad_data")`.
6. **Un evento = un hecho ya validado.** Cada peer lo aplica con el mismo código (sin volver a validar
   reglas de juego, solo que los datos sean coherentes) y **después** emite su señal de `EventBus` (§10.3).
   El host aplica primero y difunde después, con el mismo `seq`.
7. **Nada de negocio en un `MultiplayerSynchronizer`.** Lo físico (cajas sueltas, palet en la zorra,
   vehículos, jugadores) sigue con sus sincronizadores de hoy; lo que cuenta plata o unidades viaja solo en
   eventos.
8. **Peticiones críticas** (las que, perdidas, dejan al host y al peer en desacuerdo para siempre): soltar y
   dejar en el piso. Las demás son repetibles: si se pierde, el jugador vuelve a apretar.

## 2. Las 20 acciones del corte vertical

`kind` de petición → `kind` de evento. "Host" en la columna de quién inicia quiere decir que no hay
petición: el host lo detecta o lo decide solo y emite el evento.

| # | Acción (tarea) | Inicia | Petición: `kind` y `data` | El host valida | Evento: `kind` y `data` | Cambia en cada peer |
|---|---|---|---|---|---|---|
| 1 | Pedir mercadería para mañana (D-0602, D-0503) | jugador, en el tablero del proveedor | `supplier_order` `{station, product, qty, rid}` | alcance; fase `OPERATING`; producto del catálogo; `qty` en rango; plata ≥ costo | `supplier_ordered` `{product, qty, cost}` | `CompanyState`: pedido al proveedor de mañana y `money −= cost`; señal `money_changed` |
| 2 | Llega el camión del proveedor (D-0601) | host (08:30 de juego) | — | hay pedido de ayer | `supply_arrived` `{pallets: [{id, product, qty}]}` | `Inventory.receive` en `pallet:<id>` (una vez por palet); palets `sealed` |
| 3 | Bajar el palet a recepción (D-0605, zorra / autoelevador) | jugador, moviendo el cuerpo físico | — (es física: zorra o autoelevador, host como hoy) | el palet entró al área de recepción (señal del área en el host) | `pallet_placed` `{pallet, zone}` | el palet queda en `zone`; sus unidades no se mueven |
| 4 | Abrir el palet (D-0607) | jugador, en el palet | `pallet_open` `{station, rid}` | alcance; palet recibido, `sealed`, con unidades | `pallet_opened` `{pallet}` | `Pallet.open`: `sealed` → `open` |
| 5 | Tomar unidades de un palet o estante (D-0609, D-0611) | jugador | `units_take` `{station, product, qty, rid}` | alcance; origen con `qty` libres; manos libres o con el mismo producto; tope de la mano | `units_moved` `{product, qty, from, to: hands:<peer>}` | `Inventory.move` |
| 6 | Guardar en un hueco del estante (D-0608) | jugador con unidades en la mano | `units_store` `{station, product, qty, rid}` | alcance; el hueco acepta ese producto y tiene lugar; la mano tiene `qty` | `units_moved` `{…, from: hands:<peer>, to: shelf:<id>}` | `Inventory.move` |
| 7 | Soltar unidades en el piso (D-2006) | jugador | `units_drop` `{product, qty, pos: Vector3, rid}` — **crítica** | `finite_vec3`; `pos` a ≤ 2 m del jugador según el host | `units_moved` `{…, to: floor:<n>, pos}` | `Inventory.move`; aparece el bulto en `pos` |
| 8 | Tomar un pedido del tablero (D-0807, D-0804) | jugador, en el tablero | `order_claim` `{station, order, table, rid}` | alcance; pedido vivo y sin mesa; mesa libre; stock disponible para reservar | `order_claimed` `{order, table}` | `OrderBook`: pedido → mesa; `Inventory.reserve(order)` |
| 9 | Sacar una caja del dispensador (D-0702, D-0718) | jugador, en la mesa | `box_start` `{station, size, rid}` | alcance; mesa sin caja; `size` ∈ S/M/L/XL; hay insumo | `box_started` `{table, size, box}` | caja vacía en `table:<id>`; insumo `−1` (D-0504) |
| 10 | Poner un producto en la grilla (D-0703, D-0704) | jugador con la unidad en la mano | `box_place` `{station, product, cell: Vector2i, rot: int, rid}` | alcance; la unidad está en `hands:<peer>`; la celda entra y está libre | `box_placed` `{table, product, cell, rot}` | `Inventory.move` mano → `box:<id>`; grilla ocupada |
| 11 | Sacar un producto de la caja abierta (D-0703) | jugador | `box_take_out` `{station, cell, rid}` | alcance; caja sin cinta; celda ocupada; mano con lugar | `box_taken_out` `{table, cell}` | inverso del 10 |
| 12 | Rellenar (D-0705) | jugador | `box_fill` `{station, fill, rid}` | alcance; caja sin cinta; `fill` ∈ papel/burbuja/espuma; hay insumo | `box_filled` `{table, fill}` | relleno de la caja; insumo `−1` |
| 13 | Etiquetar con el pedido (D-0707) | jugador | `box_label` `{station, rid}` | alcance; la mesa tiene pedido (#8) | `box_labeled` `{table, order}` | etiqueta = pedido de la mesa |
| 14 | Poner un sello (D-0708) | jugador | `box_stamp` `{station, stamp, rid}` | alcance; caja sin cinta; `stamp` ∈ los del catálogo; no repetido | `box_stamped` `{table, stamp}` | sellos de la caja |
| 15 | Encintar y cerrar (D-0706, D-0709, D-0710, D-0711) | jugador | `box_tape` `{station, rid}` | alcance; caja con al menos un producto; insumo de cinta | `box_sealed` `{table, order, package_id, node_name, trap, trap_intensity, contents, absorption, quality, pos, basis}` | la caja sale de la mesa; **cada peer crea el mismo `DeliveryPackage`** con esos datos (nombre de nodo estable); `Inventory`: `box:<id>` pasa a pertenecer a `package:<package_id>`; `OrderBook`: pedido → armado (`order_packed`) |
| 16 | Llevar, pasar y soltar una caja armada (D-0711) | jugador | los de hoy: `Interactable.request_interact`, `submit_carry_transform` (unreliable), `request_transfer`, `request_drop` (**crítica**) | como hoy (`PackageHandling`) | — (lo lleva el sincronizador de `DeliveryPackage`) | nada de negocio |
| 17 | Dejar la caja en la zona de despacho (D-0716) | host (la caja quieta dentro del área) | — | caja sellada, en el área, en el piso o en un estante de despacho | `box_dispatched` `{package_id, trip}` | `OrderBook`: pedido → salida `trip` |
| 18 | Cargar la camioneta (D-0717) | jugador, en un punto de carga | los de hoy (`PackageMountPoint`) | como hoy | — | nada de negocio (el pedido ya va con la salida) |
| 19 | Salir por el portón y volver (D-0302, D-0307) | host (el vehículo cruza el portón) | — | vehículo con al menos una caja de la salida | `trip_started` `{trip, vehicle, packages}` / `trip_returned` `{trip}` | `CompanyState`: salida en curso / cerrada; el reloj sigue (D-0319) |
| 20 | Entregar en la casa (D-0340, D-0815, D-0502, D-0506) | jugador toca el timbre (`DeliveryHouse` como hoy) | el de hoy (`Interactable.request_interact`) | como hoy, más: contenido contra el pedido, daño, plazo | `order_delivered` `{order, package_id, paid, tip, penalties: {…}}` | `OrderBook`: pedido entregado; `Inventory.consume(order)`; `money += paid + tip − penalties` |

### Fuera de las 20, sin petición de cliente

| Qué | Quién | Cómo viaja |
|---|---|---|
| Entra un pedido nuevo (D-0803) | host, con el ritmo del día | evento `order_added` `{order: Order.to_dict()}` |
| Vence un pedido (D-0804) | host | evento `order_expired` `{order, penalty}` |
| Fases del día (D-0203) | host (`DayCycle`) | eventos `day_phase` `{day, phase}`; el cliente es pasivo |
| Reloj (D-0219) | host | evento `clock_anchor` `{minute, at_tick, speed, paused}` solo al cambiar (apertura, pausa, salida que cierra tarde); cada peer calcula la hora local. **Decisión:** ancla y no envío cada 2 s (lo que decía D-0219): no gasta ancho de banda quieto y no hay que interpolar; D-0219 lo construye así |
| Cierre: cobro, alquiler, penalidades (D-0320, D-0509) | host | evento `day_closed` `{day, summary}`; después el host guarda (solo el host guarda) |
| Pasar al día siguiente | **solo el host** aprieta "seguir" en el resumen | evento `day_phase` `OPENING`. **Decisión:** igual que el reinicio de la partida de hoy (`hud_pause.request_restart`): un cliente no puede adelantar el día de todos; si el host tarda, el resumen queda en pantalla |
| Se abre un bloqueo (D-0306) | host | evento `gate_opened` `{gate}`; no se vuelve a cerrar. En F1 Centro y Campo están abiertos desde el día 1 |
| Un peer se va (D-2006) | host, en `peer_removed` | eventos `units_moved` `hands:<peer>` → `floor:<n>` (una por producto) y `table_released` `{table}` si tenía la mesa a medias (la caja queda en la mesa, sin dueño); se liberan sus reservas de pedido solo si el pedido no tiene caja |
| Entra un peer tarde (D-2004) | host, en el gancho de peer listo | snapshot con el `seq` actual (ver §3) |

## 3. Secuencia, huecos y snapshot

- El `seq` lo lleva el host, empieza en 0 al abrir `CompanyWorld` y sube 1 por evento. Se guarda en el slot
  para que un día cargado siga numerando.
- `reliable` no pierde mensajes, así que el único hueco real es **el evento que llega antes que el mundo**
  (el peer todavía no tiene `CompanyWorld`). Por eso el host manda eventos solo a peers con
  `is_peer_ready()` y, al quedar listo un peer, le manda el snapshot con el `seq` actual; el peer descarta
  todo evento con `seq` ≤ el del snapshot.
- Si un peer ve un salto (`seq` > último + 1), pide un snapshot. Tope: uno cada 5 s por peer (si no, un
  cliente roto pide un snapshot por evento).
- Aplicar el snapshot **no** emite las señales de hechos; emite una sola `company_state_restored` para que la
  UI se redibuje (§10.3).
- El snapshot lleva también las cajas vivas con todo lo de `box_sealed` (para crear cada `DeliveryPackage`
  igual) y las unidades sueltas en el piso con su posición.

## 4. Qué se mira al revisar un PR de la expansión

- Un `@rpc("any_peer")` nuevo fuera de `_request` necesita una línea acá que diga por qué (D-2007 lo
  detecta: todo RPC de `scripts/core/company/` y `scripts/gameplay/business/` pasa por `RpcGuard`).
- Un `kind` nuevo de petición: su fila en §2 con las validaciones; un `kind` nuevo de evento: qué cambia y
  qué señal emite.
- Ningún campo de `data` que diga quién es el actor; ningún `NodePath` que mande un cliente.
- Cambia `PROTOCOL_VERSION` (`docs/convenciones-godot.md` §6): el primero sube con D-2003 / D-2008.
