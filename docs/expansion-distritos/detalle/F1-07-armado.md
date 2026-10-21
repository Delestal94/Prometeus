# F1 · Grupo 07 — Armado de paquetes (detalle)

> Carril 3 de la rutina `desarrollador`. Solo las tareas que ya se construyeron o se están construyendo;
> el resto sigue en la tabla de [07-armado-de-paquetes.md](../07-armado-de-paquetes.md) y se detalla
> cuando le toque a un carril. Números de [supuestos.md](supuestos.md).

### D-0701 · Estación de armado — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — lógica de la mesa: `PackingStation` (`scripts/gameplay/business/packing_station.gd`); `test_packing_station`. Quedan abiertas la mesa visible y la captura (ver `revisar/D-0701.md`).
**Depende de:** D-0212 (`PackedBox`), D-0904 (la mesa `assembly_table`)
**Qué:** `class_name PackingStation`, `RefCounted` sin nodos (como `Shelf`). Una mesa tiene un hueco para
**una** caja abierta (`box: PackedBox`) y hasta `STAGING_SLOTS = 4` productos esperando al lado
(`staged`, ids; Decisión: no son stock del `Inventory`, el que arma los saca de la mano o del estante).
- `start_box(size)`: abre una caja vacía si el hueco está libre y el tamaño existe. El costo de la caja y
  el dispensador son D-0702.
- `stage_product(id)` / `unstage_product(id)`: deja o devuelve un producto a la mesa.
- `put_in_box(product, origin)`: pasa un producto de la mesa a la grilla de la caja (`PackedBox.place`);
  si no hay caja, no está en la mesa o no entra, no cambia nada.
- `take_box()`: saca la caja de la mesa (para cerrarla o despacharla).
- `to_dict` / `from_dict`: ida y vuelta por JSON (red y guardado).
**Test** `test_packing_station`: una caja a la vez y tamaños inválidos, tope de productos en la mesa,
`put_in_box` con sus tres negativas sin cambios, `take_box` y JSON.
**Hecho cuando:** el test pasa. La escena de la mesa (placeholder gris sobre la huella 2×1 de
`assembly_table`) y su captura quedan para la subtarea D-0701.b.

### D-0702 · Dispensador de cajas — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-04, PR pendiente)** — lógica: `BoxDispenser` (`scripts/gameplay/business/box_dispenser.gd`); `test_box_dispenser`. El objeto del dispensador y su menú de tamaños quedan para D-0702.b (ver `revisar/D-0702.md`).
**Depende de:** D-0701 (`PackingStation`), D-0501 (billetera de `CompanyState`)
**Qué:** `class_name BoxDispenser`, `RefCounted` con funciones estáticas. `dispense(station, size, wallet)`
abre una caja vacía del tamaño elegido (S, M, L, XL) en el hueco de la mesa y cobra `CompanyTuning.BOX_COST`
con el motivo `&"boxes"`. Rechaza sin cambiar nada: tamaño desconocido, mesa que ya tiene caja, billetera
que no alcanza, mesa o billetera nulas. `can_dispense` es la misma comprobación sin efectos (para el menú).
**Test** `test_box_dispenser`: caja abierta del tamaño pedido en la mesa, cobro y libro mayor, y las cuatro
negativas sin cambios.
**Hecho cuando:** el test pasa (caja aparece abierta en la mesa).

### D-0703 · Meter productos en la caja — A · Sonnet 5.5 · xhigh · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `PackedBox.first_fit()` + `NO_SPOT`; `test_packing_station` ampliado con tres productos.
**Depende de:** D-0701 (`PackingStation.put_in_box`), D-0212 (`PackedBox`)
**Qué:** Decisión: encastre en grilla (D-0704, decidido), no físico. `put_in_box` ya movía un producto de la
mesa a la grilla; falta que el jugador (o el bot) no tenga que adivinar la celda: `PackedBox.first_fit(product)`
devuelve la primera esquina baja libre (orden z, y, x) donde el producto entra, o `NO_SPOT` (-1,-1,-1) si no
entra. Sin rotación en F1.
**Test** `test_packing_station`: tres productos (1×1×2, 2×2×1, 2×1×1) en una caja M por `first_fit`, la caja
conoce los tres, 8 celdas ocupadas sin solaparse, y `NO_SPOT` para un producto grande, nulo o caja llena.
**Hecho cuando:** el test pasa. La interacción visible (apuntar a una celda, vista previa) queda para la mesa D-0701.b.

### D-0705 · Relleno — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-12, ya en main)** — se construyó con D-0212 y D-0504: `PackedBox.fill_free_cells` / `free_ratio` / `fill_ratio` y `PackagingSupplies.pad` (cobra 1 por celda); `test_packed_box`, `test_packaging_supplies`. Decisión: un solo tipo de relleno en F1 (supuestos: "1 por celda"); papel/burbuja/espuma quedan para la Ampliación.
**Depende de:** D-0212, D-0504

### D-0706 · Cerrar con cinta — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `PackingStation.seal(wallet)`, `is_sealed()` y `dispatch()`; `test_packing_station` ampliado. El gesto de pasar el dispensador queda para la mesa visible (D-0701.b).
**Depende de:** D-0701 (`PackingStation`), D-0504 (`PackagingSupplies.tape`)
**Qué:** `seal` pone la cinta de la caja de la mesa y cobra `TAPE_COST` una vez. `dispatch()` saca la caja de la mesa solo si está sellada; abierta devuelve null y la deja donde está.
**Test** `test_packing_station`: sin caja, caja abierta que no se despacha, sellado con un solo cobro, despacho de la caja sellada.
**Hecho cuando:** el test pasa (caja sin cinta no se puede despachar).

### D-0707 · Etiqueta de envío con el pedido — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `OrderLabel` (`scripts/gameplay/business/order_label.gd`) y `PackingStation.label_for(order, wallet)`; `test_packing_station` ampliado. La hoja impresa y su dibujo (reusar `package_shipping_label.gd`) quedan para la mesa visible (D-0701.b).
**Depende de:** D-0802 (`Order`), D-0504 (`PackagingSupplies.label`), D-0701
**Qué:** `OrderLabel.address(order)` devuelve `{order, customer, street_key, number}` desde `house_id`
(`<zona>_house_<n>`); vacío si el pedido no tiene id o casa. `PackingStation.label_for` pega la etiqueta del
pedido en la caja de la mesa y la cobra con `PackagingSupplies.label` (gratis hoy, `LABEL_COST = 0`; repetir el
mismo pedido no cobra). Sin caja o con pedido sin casa no cambia nada.
Decisión: la calle es una clave de traducción (`WORLD_STREET_<ZONA>`, una por zona, con `WORLD_STREET_MAIN` de
reserva) y el número es el de la casa, hasta que D-0312 dé nombre a cada calle. Las tres claves están en
`strings_world.csv` (Calle Central, Camino Rural, Calle Principal); D-0312 las reemplaza por calles reales.
**Test** `test_packing_station`: calle y número del pedido, zona desconocida, pedido sin casa o sin id, caja
sin etiquetar tras un rechazo, cobro, el mismo pedido gratis, y reetiquetar para otro.
**Hecho cuando:** el test pasa (la etiqueta muestra calle y número del pedido).

### D-0708 · Sellos — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `BoxSeals` (`scripts/gameplay/business/box_seals.gd`) y `PackingStation.stamp(kind, wallet)`; `test_box_seals`. El sello dibujado en la caja y el gesto de estamparlo quedan para la mesa visible (D-0701.b).
**Depende de:** D-0701 (`PackingStation`), D-0504 (`PackagingSupplies.stamp`), D-0806 (`OrderRequirement.required_seals`)
**Qué:** `BoxSeals` es estático: `KINDS` (fragile, no_bend, cold, gift, heavy: los ids que piden los requisitos), `required(order)` (sellos que piden los requisitos del pedido, sin repetir, ignorando ids sin recurso), `missing(box, order)` e `is_valid(box, order)` (el chequeo de la puerta). `PackingStation.stamp` estampa un sello conocido en la caja de la mesa y lo cobra (`STAMP_COST`, 0 hoy); rechaza sin caja, tipo desconocido o repetido.
Decisión: el tipo de sello es el id que ya usa `required_seals` (FRÁGIL = `fragile`, ESTE LADO ARRIBA = `no_bend`, FRÍO = `cold`), para no mantener dos listas. La penalidad de sello faltante en la calidad es D-0709; el cobro/rechazo en la puerta, D-0712.
**Test** `test_box_seals`: requeridos del pedido, caja sin sellos falla la puerta, sellar uno a uno, rechazos sin cambios, JSON.
**Hecho cuando:** el test pasa (el sello queda en la caja y la puerta lo valida).

### D-0709 · Calidad del armado — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `AssemblyQuality` (`scripts/gameplay/business/assembly_quality.gd`) y los números en `CompanyTuning`; `test_assembly_quality`.
**Depende de:** D-0212 (`PackedBox`), D-0506 (`OrderPenalties.matches_order`), D-0708 (`BoxSeals.missing`)
**Qué:** `AssemblyQuality.score(box, order, products)` devuelve la calidad de 0 a 100 y `breakdown()` los puntos perdidos por motivo (`content`, `gaps`, `seals`, `closure`). Parte de 100 y resta, según [supuestos.md](supuestos.md):
- −40 si el contenido no coincide con el pedido;
- −30 × fracción de celdas de la caja vacías y sin relleno (`PackedBox.free_ratio()`), ×1,5 si algún producto es frágil;
- −15 por cada sello requerido que falte;
- −10 (una sola vez) si falta la cinta o la etiqueta.
Caja nula: 0. Nunca sale de 0-100. D-0710 usa este número para la intensidad de la trampa y D-0502 para el bono por condición.
Decisión: "sin cinta o sin etiqueta" resta una sola vez (la frase del supuesto es un "o"); `products` solo se lee para `fragile` y un id que no está cuenta como no frágil.
**Test** `test_assembly_quality`: 6 cajas de calidad conocida (perfecta 100, sin sello 85, frágil con hueco sin relleno 68,3, la misma rellena 100, sin cinta ni etiqueta 90, contenido equivocado 30), el desglose y la caja nula.
**Hecho cuando:** el test pasa con 6 cajas de calidad conocida.

### D-0710 · Calidad → trampa y su intensidad — A · Sonnet 5.5 · xhigh · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — `BoxTrap` (`scripts/gameplay/business/box_trap.gd`): intensidad = 1 − Q/100, nivel low/mid/high y Balance bajo (0,3) si la caja va floja; `BoxToPackage.build(box, products, order)` guarda el plan en `META_TRAP_PLAN`; `test_box_trap`.
**Depende de:** D-0709 (`AssemblyQuality`), D-0213 (`BoxToPackage`), D-0109
**Qué:** la trampa que viaja sigue siendo la del producto más difícil; el armado solo mueve la intensidad (`diseno/armado-y-trampas.md` §5). Números en `CompanyTuning` (`TRAP_INTENSITY_MID` 0,1, `TRAP_INTENSITY_HIGH` 0,25, `TRAP_LOOSE_BOX_INTENSITY` 0,3).
**Hecho cuando:** vidrio sin relleno da Frágil alto; con relleno, Frágil bajo.


### D-0711 · Caja armada sigue siendo `DeliveryPackage` — A · Sonnet 5.5 · xhigh · Aviso: no · F1
**[x] Hecho (2026-10-12, PR pendiente)** — sin código nuevo: `test_box_package_flow` prueba levantar, asentar, asiento, cuidado igual al de un paquete común y entrega en la puerta con una caja armada.
**Depende de:** D-0213 (`BoxToPackage`), D-0710
**Qué:** el paquete que sale de `BoxToPackage.build()` no es un tipo nuevo: se levanta, se asienta en el camión, se cuida y se entrega con el mismo código de hoy (`package.gd`, `PackageHandling`, `PackageCare`). Decisión: no se agrega ninguna clase; se prueba el flujo completo con una caja armada y se deja la garantía en un test.
**Test** `test_box_package_flow`: una caja armada pasa por levantar, asentar en el camión, cuidado y entrega en la puerta; sus metadatos (`META_PACKED_BOX`, `META_ORDER_ID`) sobreviven.
**Hecho cuando:** `test_box_package_flow` pasa y los tests de paquete actuales siguen verdes.

### D-0712 · Error de contenido — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-18, PR pendiente)** — `BoxContentCheck` (`scripts/gameplay/business/box_content_check.gd`): `diff` (qué falta y qué sobra, con unidades), `is_correct` y `door_accepts`; `PackingStation.content_errors(order)` para la mesa; `test_box_content_check`.
**Depende de:** D-0709 (`OrderPenalties.matches_order`), D-0701 (`PackingStation`)
**Qué:** dos momentos detectan el error. En la mesa, antes de la cinta, `content_errors` avisa qué falta o sobra (solo aviso: se puede sellar igual). En la puerta, `door_accepts` da el veredicto con el mismo criterio que `OrderPenalties.matches_order` (que ya paga 0) y suma el motivo.
Decisión: el aviso de la mesa no bloquea el cierre, porque el pedido decide el pago y el jugador puede querer despachar igual; la UI que lo muestra es D-0714/D-0744.
**Test** `test_box_content_check`: caja exacta, falta una unidad, falta un producto, sobra una unidad o un producto, sin caja; los dos momentos con la misma caja.
**Hecho cuando:** el test pasa para la mesa y para la puerta.

### D-0713 · Balanza de control — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `BoxScale` (`scripts/gameplay/business/box_scale.gd`): `expected_kg`, `real_kg` y `weigh`; `CompanyTuning.SCALE_TOLERANCE_KG`; `test_box_scale`. El objeto de la balanza en la mesa queda para D-0713.b (ver `revisar/D-0713.md`).
**Depende de:** D-0712 (`BoxContentCheck`), D-0116 (`ProductDefinition.weight_kg`)
**Qué:** `class_name BoxScale`, `RefCounted` estático. `weigh(order, box, products)` devuelve `{expected, real, delta, ok}`: el peso esperado suma los productos del pedido por cantidad; el real, lo que contiene la caja; `ok` si `|delta| <= SCALE_TOLERANCE_KG` (0,05 kg).
Decisión: solo pesan los productos (relleno y caja pesan 0) y es solo un aviso, como D-0712. No dice qué falta: un cambio por otro producto del mismo peso pasa (límite documentado y a propósito, para que la balanza sea una pista y no reemplace a `BoxContentCheck`).
**Test** `test_box_scale`: caja exacta, falta una unidad (delta negativo), sobra una (positivo), cambio de igual peso, tolerancia, sin caja y producto desconocido.
**Hecho cuando:** el test pasa.

### D-0714 · Hoja de pedido visible en la mesa — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `OrderSheet` (`scripts/gameplay/business/order_sheet.gd`) arma la hoja y `OrderSheetPanel` (`scripts/ui/order_sheet_panel.gd`) la dibuja; `PackingStation.sheet_for`; `test_company_order_sheet`. Ponerla en pantalla junto a la mesa visible queda para D-0701.b (ver `revisar/D-0714.md`).
**Depende de:** D-0701 (`PackingStation`), D-0802 (`Order`), D-0707 (`OrderLabel`)
**Qué:** `OrderSheet.build(order, box, now_min, products)` devuelve un diccionario sin nodos: cliente, dirección (la de la etiqueta), una línea por producto con lo que ya tiene la caja, productos de más, sellos de los requisitos (hecho / pendiente), cinta, etiqueta de este pedido, minutos que quedan (negativos si se pasó), paga y `ready` (contenido justo, todos los sellos, cinta y etiqueta). `OrderSheetPanel` lo dibuja con una marca por línea (✓ hecho, ○ pendiente, ✗ mal), así se lee sin color, y "Sin pedido en la mesa" si no hay.
Decisión: la hoja es un panel de solo lectura (sin foco ni input); abrirlo y cerrarlo, y dónde se ancla, lo decide la mesa visible. Decisión: sin hora de reloj, solo "quedan N min" / "atrasado N min" (los minutos del pedido son del día y el reloj lo muestra el HUD). Decisión: los nombres de requisitos son `WORLD_REQ_<ID>` (las seis filas se suman acá, como pedía D-0806); el nombre de un sello es el de su requisito (mismo id).
**Test** `test_company_order_sheet`: contenido (falta, sobra, de más), sellos y `ready`, tiempo y bordes (sin pedido, sin caja), `sheet_for` de la mesa, y el panel con sus marcas, el atraso en rojo, el vacío y el idioma.
**Hecho cuando:** el test pasa y la hoja se lee con la caja a medio armar.

### D-0715 · Varias personas en la misma mesa (uno pone productos, otro la cinta) — A · Sonnet 5.5 · xhigh · Aviso: sí (`network_manager.gd`) · F1
**[x] Hecho (2026-10-19, PR pendiente)** — partial: `CompanyTableNet` (`scripts/core/company/company_table_net.gd`, `CompanyNet.table`) valida en el host y aplica en cada peer los siete pasos de la mesa (filas 9 a 15 del contrato), las mesas viajan en el snapshot (parte `packing`), `PROTOCOL_VERSION` 37; `test_company_shared_table`. Queda D-0715.b (crear y validar el `DeliveryPackage` en cada peer al encintar, persistir los ids de caja) y D-0715.c (`box_restock` y `box_discard`; bloquea D-0701.b).
**Depende de:** D-2001 (contrato), D-2003 / D-2004 (`CompanyNet`, snapshot), D-0701, D-0702, D-0703, D-0706, D-0707, D-0708, D-0718 (`PackingStation`, `BoxDispenser`, `PackedBox`, `PackagingSupplies`, `StationSupplies`), D-0709 / D-0710 (calidad y trampa), D-0910 (plata absoluta en los eventos)
**Qué:**
- **Peticiones y eventos** (contrato `diseno/red-autoridad.md` §2 filas 9 a 15 y §9), por el `_request` / `_apply_event` de siempre (ningún RPC nuevo): `box_start {station, size}` → `box_started {table, size, box, money, minute}`; `box_place {station, product, cx, cy, cz, rot: 0}` → `box_placed {…, from: hands:<peer>}`; `box_take_out {station, cx, cy, cz}` → `box_taken_out {…, product, to}`; `box_fill {station, cells}` → `box_filled {table, cells, money, minute}`; `box_label {station}` → `box_labeled {table, order, money, minute}`; `box_stamp {station, stamp}` → `box_stamped {…}`; `box_tape {station}` → `box_sealed {table, order, package_id, node_name, trap, trap_intensity, contents, absorption, quality, pos, basis, money, minute}`. Celdas como tres enteros, nunca `Vector3i`.
- **El host valida** con las mismas reglas que la mesa local: alcance hasta el hueco de la caja (`stations`, ubicación `table:<uid>`), mesa con o sin caja, tamaño, insumos de la mesa (D-0718), plata, celda que entra y está libre (`PackedBox.place` sobre una copia), unidad en `hands:<peer>`, mano con lugar al sacar, sello no repetido, caja con producto al encintar y la reserva del pedido (`reserved_for_other`). Los motivos están en el contrato §9.
- **La mesa no tiene dueño:** cualquiera hace cualquier paso sobre la misma caja; el host atiende de a una petición y la segunda de dos que chocan oye el motivo (`has_box`, `cell_taken`).
- **Cada peer aplica** con las mismas llamadas (`BoxDispenser.dispense`, `PackedBox.place` / `take_out`, `PackingStation.pad` / `stamp` / `seal`, `PackagingSupplies.label`) y solo comprueba datos y su copia (regla 6), todo antes del primer cambio. Plata absoluta como D-0910: si el espejo estaba desfasado se corrige y pide snapshot.
- **`box_sealed`** saca la caja de la mesa en todos los peers: las unidades pasan de `box:<id>` a `package:<id>` y la reserva del pedido de la etiqueta baja en lo que lleva (`Inventory.unreserve`, nuevo). Crear el paquete es D-0715.b.
- **Join tardío:** las mesas (caja, insumos, id) son la parte `packing` del snapshot; el cliente la valida antes de tocar nada (`CompanySnapshot.tables_from`).
- **Layout:** no se vende una mesa con caja (`not_empty`); al venderla se olvida su estado.
- `company_net.gd` estaba al borde de las 1000 líneas de gdlint: el empaquetado del snapshot y el chequeo del stock salieron a `CompanySnapshot` (mismas firmas en `CompanyNet`).
- **D-0715.b (abierta, `constructor-red` + `constructor-trampas`)** Con `box_sealed`, cada peer crea el mismo `DeliveryPackage` (`node_name`, `pos`, `basis`, trampa, intensidad, absorción, calidad; `BoxToPackage` con la caja que cada peer todavía tiene) con el sincronizador invisible hasta mandar el `seq` (regla 10); el `apply()` de cada peer **valida** `pos` y `basis` (finitos, `RpcGuard.finite_vec3` / `finite_transform`), `quality` (0..100), `trap` (id de trampa conocido) y `node_name` (texto corto, `Package_<id>`) antes de crear nada (hoy `box_sealed` no los lee); las cajas vivas viajan en el snapshot con `update_visibility` después del último trozo; `OrderBook` → armado (`order_packed`) cuando el libro esté en `CompanyNet`; y `CompanyTableNet._serial` se **persiste** con el día (D-0206) para que un día cargado no reparta ids ya usados por paquetes vivos.
- **D-0715.c (abierta, `constructor-red`; bloquea D-0701.b)** Dos peticiones nuevas de la mesa: `box_restock` (reponer los insumos por red: hoy `StationSupplies.restock` es local) y `box_discard` (desarmar o tirar la caja abierta: sus unidades vuelven a la mano o al piso). Sin ellas una mesa sin cinta queda **trabada** en una sesión (la caja no se puede encintar ni sacar), así que la mesa visible (D-0701.b) no se cierra antes que esto.
**Decisión:** la caja en armado vive en `CompanyNet.table` y no en `CompanyShed.stations`; la celda lleva `cz` (la grilla es 3D) y `rot` solo 0; `box_fill` pide `cells` y no un tipo de relleno (uno solo en F1); los pasos que cuestan llevan `money` y `minute`; las cajas son `box_<n>` del host y su paquete usa el mismo id; el pedido de la mesa lo da `order_of` hasta que exista `order_claim`. `docs/decisiones/2026-10-19-mesa-compartida-red.md`.
**Test** `test_company_shared_table`: solo, los siete pasos con sus cobros, insumos e inventario (dos gallinas a la caja, una sale y vuelve, relleno, sello, etiqueta, cinta: `box_sealed` con todos sus campos y la calidad de la caja encintada, unidades en `package:box_1`, reserva en 0); cada rechazo sin cambios ni `seq` (19 casos más mano ocupada y llena, `Vector3i` descartado en silencio); reserva de otro pedido y la propia; sin insumo, sin plata, caja llena; no se vende una mesa con caja y sí después; eventos que no encajan no se aplican; la parte del snapshot ida y vuelta y siete partes malas; con host + cliente ENet, el cliente abre y pone gallina y cachorro, el host sella, rellena, etiqueta y encinta, iguales tras cada paso (mesas, inventario, empresa y minuto del host en el libro); dos pedidos a la vez (caja y celda): pasa el del host y el cliente oye `has_box` / `cell_taken`; un tercero que entra tarde recibe la mesa a medio armar por snapshot, pone una gallina y el cliente la encinta; `seq` sin huecos.
**Hecho cuando:** test de red con 2 peers armando la misma caja (pasa). Nota: el ✅ de la tabla del grupo es parcial: D-0715.b y D-0715.c quedan abiertas.

### D-0716 · Despacho: la caja armada en la zona de salida se asocia a la salida — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `DispatchZone` (`scripts/gameplay/business/dispatch_zone.gd`): el área, `update_box`, `load_into`; `test_dispatch_zone`. Poner el área en el mundo y llamarla desde el host queda para D-0716.b (ver `revisar/D-0716.md`).
**Depende de:** D-0711 (caja sellada = `DeliveryPackage`), D-0302.1 (`CompanyTrips.stage_cargo`), D-0801 (`OrderBook`)
**Qué:** `class_name DispatchZone`, `RefCounted` sobre un `AABB` del piso. `update_box(box, order, pos, sealed, at_rest, book)` la llama el host cada tanto con la posición de cada caja: una caja sellada, quieta y dentro del área, cuyo pedido está `PACKED` con esa caja en el `OrderBook`, queda **despachada** (`box_dispatched`); si sale del área o la levantan antes de que arranque la salida, se **desata** (`box_undispatched`). `load_into(trips, vehicle)` le pasa a `CompanyTrips.stage_cargo` las cajas y pedidos que esperan y vacía la zona.
Decisión: la zona no cambia el estado del pedido (sigue `PACKED`); pasa a `OUT` solo cuando el vehículo cruza el portón (`Trip.start`), como ya hace `CompanyTrips`. Así una caja que se saca a tiempo no deja un pedido trabado en `OUT`.
**Test** `test_dispatch_zone`: caja abierta, llevada, fuera del área, de otro pedido o de un pedido no armado no se despachan; sellada y quieta dentro, sí; al salir se desata y puede volver; `load_into` carga las 2 cajas y la camioneta sale con sus 2 pedidos `OUT` y el tercero sigue `PACKED`; ida y vuelta por JSON.
**Hecho cuando:** el test pasa.

### D-0717 · Cargar el vehículo desde despacho — A · Sonnet 5.5 · high · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `DispatchLoading` (`scripts/gameplay/business/dispatch_loading.gd`) + `DispatchZone.load_boxes`; `test_dispatch_loading`. Llevar las cajas cargadas a los puntos de montaje de la camioneta queda para D-0717.b (ver `revisar/D-0717.md`).
**Depende de:** D-0716 (`DispatchZone`), D-0309 (`DispatchRules`), D-0207 (`VehicleDefinition`)
**Qué:** `class_name DispatchLoading`, estático. `plan(zone, book, vehicle, box_kg, zones, gates, owned, opened)` recorre las cajas de la zona, la más vieja primero, y deja en `load` las que entran: pasan `DispatchRules.check_order` para la zona de su pedido, hay `cargo_slots` libres y el peso acumulado no pasa `cargo_kg`. Las que no entran van en `left` con `box`, `order`, `key` y `args` (clave de traducción: las de `DispatchRules`, `WORLD_LOAD_NO_SLOTS`, `WORLD_LOAD_NO_WEIGHT`). `load_vehicle(...)` hace el plan y le pasa solo las que entran a `DispatchZone.load_boxes` → `CompanyTrips.stage_cargo`; el resto sigue esperando en la zona para el próximo vehículo.
Decisión: una caja que no entra por peso no corta la carga; se salta y una más liviana detrás sí puede ir (el jugador ve el motivo de cada una que quedó). Decisión: el peso de cada caja lo da quien llama (`BoxScale.real_kg`), no se guarda en la zona.
**Test** `test_dispatch_loading`: con 2 casilleros, de 3 cajas salen las 2 más viejas y la camioneta sale con esos pedidos `OUT` (la tercera sigue `PACKED` y espera); el siguiente vehículo la toma; por peso se salta la pesada y entra la liviana; una caja de Islas queda con el motivo de `DispatchRules`; las dos claves nuevas tienen traducción.
**Hecho cuando:** camioneta cargada con cajas armadas sale (el test pasa).

### D-0718 · Insumos que se gastan y se reponen — B · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-19, PR pendiente)** — `StationSupplies` (`scripts/gameplay/business/station_supplies.gd`): cajas por tamaño, cinta y relleno por mesa; `PackingStation.supplies`, `seal()` y `pad()` los gastan, `BoxDispenser` se queda sin cajas; `test_station_supplies`. El gesto de reponer y el cartel de "falta cinta" quedan para la mesa visible (D-0701.b, ver `revisar/D-0718.md`).
**Depende de:** D-0701 (`PackingStation`), D-0702 (`BoxDispenser`), D-0504 (`PackagingSupplies`)
**Qué:** `class_name StationSupplies`, `RefCounted` con un contador por tipo: `box_S/M/L/XL`, `tape` (1 por caja) y `fill` (1 por celda). Capacidades en `CompanyTuning.SUPPLY_CAPACITY` (6/6/4/3 cajas, 10 cintas, 30 de relleno). Cada mesa arranca llena y cada paso gasta una unidad **después** de que la billetera lo pagó: un paso rechazado (sin plata, sin stock) no gasta nada. `restock(kind)` / `restock_all()` rellenan a capacidad; `low_kinds()` dice qué está en `SUPPLY_LOW_RATIO` (25 %) o menos, para el cartel o el HUD.
Decisión: reponer **no cuesta plata**, cuesta el tiempo de quien se queda en la mesa; lo que cuesta plata es usar el insumo (D-0504, se cobra al usarlo). Así no se cobra dos veces y la reposición es la tarea que pide `diseno/referencias-logistica.md` ("tarea del que se queda"). Decisión: el stock vive en la mesa (`PackingStation.supplies`), no en el `Inventory`, porque no son productos de pedidos ni se reservan; `to_dict` lo guarda y un guardado sin él vuelve lleno. Decisión: el relleno es un solo contador (sin papel/burbuja/espuma, igual que D-0705).
**Test** `test_station_supplies`: arranca lleno; `take` rechazado no cambia nada; el dispensador se queda sin cajas de un tamaño y otro tamaño sigue; sin cinta no se sella y la caja queda abierta; el relleno se limita a lo que queda; una billetera sin plata no gasta stock; `low_kinds`; reponer no mueve plata; ida y vuelta por JSON y guardado viejo sin `supplies`.
**Hecho cuando:** el test pasa.

### D-0719 · Desarmar una caja mal armada — A · Sonnet 5.5 · medium · Aviso: no · F1
**[x] Hecho (2026-10-21, PR pendiente)** — `PackingStation.disassemble()`; `test_box_disassemble`. El gesto, el evento de red y desarmar una caja ya despachada quedan para D-0719.b (ver `revisar/D-0719.md`).
**Depende de:** D-0701 (`PackingStation`), D-0212 (`PackedBox.items`)
**Qué:** `disassemble()` devuelve los productos de la caja de la mesa: vuelven a la mesa (`staged`) hasta `STAGING_SLOTS`, en el orden en que se armaron; lo que no entra va en `overflow` (para las manos o el estante), nada se pierde. Devuelve `{staged, overflow}`; `{}` y sin cambios si no hay caja.
Decisión: la caja vacía queda abierta en la mesa (se puede rearmar enseguida, sin pagar otra). Decisión: relleno, cinta, etiqueta y sellos **se pierden** y no se reembolsan (ya se pagaron al usarlos, D-0504): equivocarse cuesta un poco y desarmar siempre es posible, también con la caja encintada.
**Test** `test_box_disassemble`: sin caja no hace nada; los productos vuelven en orden y la caja queda vacía, abierta, sin etiqueta ni sellos; una caja encintada se abre y ya no se despacha; con 6 unidades solo 4 vuelven a la mesa y 2 van a `overflow`; los mismos productos entran de nuevo.
**Hecho cuando:** el test pasa.
