# F2 · Grupo 06 — Mercadería y stock (detalle)

> Carril 2 de la rutina `desarrollador`. Tareas de F2 del grupo 06 que se construyen de a una; el resto sigue
> en la tabla de [06-mercaderia-y-stock.md](../06-mercaderia-y-stock.md). Números de [supuestos.md](supuestos.md).

### D-0616 · Productos fríos fuera de la heladera se echan a perder — A · Sonnet 5.5 · high · Aviso: no · F2
**[~] Parcial (2026-10-22, PR pendiente)** — la lógica (D-0616.a): `ColdChain` (`scripts/gameplay/business/cold_chain.gd`), `Inventory.discard`, `CompanyTuning.COLD_SPOIL_MINUTES` y `test_cold_chain`; conectada al mundo (D-0616.b, parcial): `ColdChainTick`, el evento `units_spoiled` (protocolo 51) y el guardado de los relojes. Falta D-0616.c (los movimientos de las mesas de empaque, el aviso en la etiqueta del hueco y lo demás de abajo).
**Depende de:** D-0211 (`Inventory`), D-0608 (`Shelf`), D-0204 (`temperature`), D-0904 (`PlaceableDefinition.cold`)
**Qué:** el campo `temperature` deja de ignorarse. Se cuenta, por producto frío y por lugar donde está guardado, cuántos minutos de juego pasó fuera de una heladera (un estante cuyo id está en `cold_shelves`).
- **D-0616.a (hecha) — la lógica.** `ColdChain` (`RefCounted`, sin nodos ni autoloads): `advance(inventory, products, cold_shelves, minutes)` envejece lo frío que no está en una heladera; pasados `COLD_SPOIL_MINUTES` (120 = 2 h) las unidades de ese lugar se pierden (`Inventory.discard`) y devuelve qué se pudrió y qué pedidos perdieron reserva. En la heladera el reloj **se frena pero no se reinicia**. `receive` y `move` hacen lo mismo que los de `Inventory` y además llevan el reloj: al juntarse unidades con otras, el reloj es el promedio ponderado por unidades. Lo que va en una caja en viaje es de `ColdPack`, no de acá.
- **`Inventory.discard(product, qty, location)`** saca unidades aunque estén reservadas: si los pedidos prometen más de lo que queda, recorta las reservas más nuevas hasta que entren y devuelve `{pedido -> unidades}` (esos pedidos quedan esperando stock, D-0811).
- **D-0616.b (hecha, parcial) — el mundo.**
  - `ColdChainTick` (`scripts/gameplay/business/cold_chain_tick.gd`, hijo de `CompanyRoot` solo en el host, un paso del
    `BusinessTick`): una vez por minuto de juego del galpón (`DayCycle.shed_minute()`, que no avanza con el reloj en
    pausa ni con el galpón congelado) y solo con el día abierto (OPENING y OPERATING, como los pedidos) llama a
    `ColdChain.age(...)` con `CompanyShed.cold_shelves()` (se lee cada vez: una heladera comprada a mitad del día
    cuenta). Un día nuevo, un día cerrado o un minuto que vuelve atrás solo mueven la marca: el tiempo entre días no cuenta.
  - **Red:** `ColdChain.age()` cuenta sin tocar el stock y devuelve lo vencido; el host publica un `units_spoiled`
    `{product, qty, location}` por producto y lugar (`CompanyColdNet`, `CompanyNet.publish`) y cada peer, el host también,
    lo aplica con `Inventory.discard`: el stock y las reservas recortadas quedan iguales en todos (`discard` recorta las
    mismas reservas porque todos las tienen). Cambia el protocolo: **`PROTOCOL_VERSION` 51** (§6 de convenciones-godot:
    sin PRs abiertos que toquen `network_manager.gd` ni ramas con más de 50; aviso en `docs/avisos/`).
  - El reloj viaja con las unidades: tras cada `units_moved` que el host aplicó (tomar, guardar, soltar), `ColdChain.note_moved`
    pasa el reloj del lugar de origen al de destino (promedio ponderado). Se engancha en el evento ya aplicado, no en cada
    llamada a `Inventory.move`: así no hay que tocar `CompanyAsk` ni las estaciones.
  - Qué envejece: lo que espera en estantes comunes, pallets, carritos y suelo (`ColdChain.ages_at`); **no** lo que está en
    una mano, una mesa de empaque, una caja abierta o un paquete (ahí manda `ColdPack`).
  - **Guardado:** `CompanyState.cold_clocks` (clave opcional, sin subir `CompanySave.VERSION`: un guardado viejo carga con
    relojes en cero y uno nuevo en una versión vieja ignora la clave); el host la escribe antes de cada guardado
    (`ColdChainTick.write_clocks`) y `CompanyNet.snapshot()` la saca de la parte `company` (el cliente no tiene relojes).
  - Test `test_company_cold_chain_world`.
- **D-0616.c (abierta) — lo que falta.**
  - Los movimientos de las mesas de empaque (`box_*`, `table:`) no llevan el reloj: la leche que sale de una caja
    (`box_take_out`) empieza de cero. Hay que sumar el reloj a esos eventos o a la caja.
  - El aviso en la etiqueta del hueco ("se echa a perder en 40 min") con `ColdChain.minutes_left`: hoy los relojes son
    solo del host; para mostrarlo en los clientes hay que replicar los minutos restantes (no hace falta para el stock).
  - Avisar a los jugadores que algo se echó a perder (cartel/sonido, `event_applied` con `units_spoiled`) y a los pedidos
    que perdieron reserva (D-0811, "quedan esperando stock"): el evento no lleva los pedidos, cada peer los recorta.
  - Una caja ya armada con frío dentro no envejece acá (es de `ColdPack`); falta decidir si el paquete en un pallet de
    salida o en un vehículo parado también.
  - Los relojes por lugar siguen sin viajar con un pallet entero que cambia de lugar (`jack_*` no cambia su `location`,
    así que no hace falta hoy; sí si algún día un pallet pasa a otra ubicación).
Decisión: el reloj es por lugar, no por unidad (`Inventory` no sigue unidades): es lo más simple que no deja engañar al sistema sacando y devolviendo leche de la heladera. Decisión: la pérdida es de todo el lugar a la vez, no unidad por unidad.
**Test** `test_cold_chain`: la leche en un estante común se pudre a las 2 h y sale del stock; en la heladera nunca; lo ambiente nunca; el reloj se frena y no se reinicia; mover lleva el reloj y juntar promedia; la pérdida recorta las reservas más nuevas y lo informa; ida y vuelta por JSON; `discard` rechaza de más.
**Test** `test_company_cold_chain_world` (D-0616.b): el reloj del día hace que la leche de un estante común se eche a perder a las 2 h y baje el stock en el host y en un cliente (y en uno que entra tarde); en la heladera no; las unidades de una mano no envejecen; nada avanza en pausa ni de noche; los pedidos reservados más nuevos quedan esperando stock; el reloj viaja con un `units_moved`; los relojes salen y vuelven por el guardado; en el `CompanyRoot` real la leche de los primeros pallets se pierde a las 2 h y el guardado lleva el reloj.
**Hecho cuando:** producto frío fuera de heladera 2 h de juego → vencido en todos los peers (D-0616.a + D-0616.b); el aviso y las mesas son D-0616.c.

### D-0617 · Heladera como estantería especial — A · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `Shelf.cold` (la heladera del `.tres` hace un estante frío), `Shelf.set_label` con la temperatura del producto (la heladera solo rotula frío; los demás estantes, solo lo que no es frío), `CompanyShed.cold_shelves()` (el `cold_shelves` de `ColdChain.advance`) y el galpón por defecto con la heladera `cold_1` en lugar del estante `shelf_3` (leche y torta). `DefaultShed.problems()` marca un producto frío en un estante común. `test_cold_shelf`.
**Depende de:** D-0608 (`Shelf`), D-0904 (`PlaceableDefinition.cold`), D-0616.a
**Qué:** que el estante de frío exista de verdad y solo él guarde frío, antes de conectar el reloj al mundo (D-0616.b).
Decisión: el uid de la heladera por defecto es `cold_1` y no `fridge_1`, para no chocar con el nombre que recibe la primera heladera que se compra. Decisión: el control es al rotular (un hueco), no al depositar: lo que no se puede rotular no tiene dónde entrar. Decisión: la heladera por defecto es gratis y sale de la lista de "no propio al inicio" solo en el layout, no en `fridge.tres` (comprar otra sigue costando 200).
**Test** `test_cold_shelf`. **Hecho cuando:** el test pasa; `test_company_default_layout` y `test_company_layout_net` siguen verdes.
