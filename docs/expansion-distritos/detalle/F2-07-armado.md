# F2 · Grupo 07 — Armado de paquetes (detalle)

> Carril 3 de la rutina `desarrollador`. Ampliación del grupo 07 que se construye de a una; el resto sigue en
> la tabla de [07-armado-de-paquetes.md](../07-armado-de-paquetes.md). Números de [supuestos.md](supuestos.md).

### D-0721 · Conservadora con hielo para productos fríos — B · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `ColdPack` (`scripts/gameplay/business/cold_pack.gd`) + `PackedBox.ice_packs`; `test_cold_pack`. Meter el hielo desde la mesa visible, cobrar `ICE_PACK_COST` y leer la duración en la puerta quedan para D-0721.b (ver `revisar/D-0721.md`).
**Depende de:** D-0703 (`PackedBox`), D-0708 (`BoxSeals`, sello de frío)
**Qué:** `class_name ColdPack`, estático. Una caja con un producto frío (`temperature == &"cold"`) aguanta `COLD_BASE_MINUTES` (15) sola y `COLD_PER_ICE_MINUTES` (25) más por cada paquete de hielo (`PackedBox.ice_packs`, máximo `ICE_PACKS_MAX` = 2). `add_ice`, `cold_minutes`, `holds(box, minutos_de_viaje)` y `ice_needed(minutos)`. El hielo viaja en `to_dict`/`from_dict` de la caja.
Decisión: el hielo es un contador de la caja, no un insumo de la mesa: `SUPPLY_CAPACITY` viaja en el snapshot de red y tocarlo cambiaría el protocolo por algo que todavía no se dibuja. Decisión: `ICE_PACK_COST` (2) lo cobra quien llama, como el resto de `PackagingSupplies`.
**Test** `test_cold_pack`: solo una caja con producto frío cuenta; el hielo se detiene en el máximo; el mismo viaje arruina la caja sin hielo y la salva con hielo; una caja sin frío siempre aguanta; `ice_needed`; ida y vuelta por JSON con el conteo limitado.
**Hecho cuando:** el frío dura N min en la ruta (el test pasa).

### D-0723 · Envoltorio de regalo (pedido de regalo paga más) — B · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `GiftWrap` (`scripts/gameplay/business/gift_wrap.gd`) + `PackedBox.gift_wrapped`; `test_gift_wrap`. Envolver desde la mesa visible, cobrar `GIFT_WRAP_COST` y sumar el bono al liquidar el pedido quedan para D-0723.b (ver `revisar/D-0723.md`).
**Depende de:** D-0703 (`PackedBox`), D-0706 (cinta), D-0806 (requisito `gift`)
**Qué:** `class_name GiftWrap`, estático. Solo una caja con cinta se envuelve, una vez (`wrap`). Un pedido con requisito `gift` entregado en una caja envuelta paga `GIFT_WRAP_BONUS` (15 %) de su pago además del bono del requisito (`bonus(pay, box, order)`); envolver para otro pedido no da nada. El papel viaja en `to_dict`/`from_dict` de la caja.
Decisión: el bono es aparte del sello `gift` (que la puerta ya valida): el sello es obligatorio, el papel es opcional y premia el esmero. Decisión: `GIFT_WRAP_COST` (3) lo cobra quien llama, como el hielo.
**Test** `test_gift_wrap`: caja abierta o nula no se envuelve; no hay doble capa; bono solo en pedido de regalo con caja envuelta; ida y vuelta por JSON y cajas viejas sin papel.
**Hecho cuando:** un pedido de regalo paga más con envoltorio (el test pasa).

### D-0726 · Productos que no se pueden juntar — B · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `ProductCompatibility` (`scripts/gameplay/business/product_compatibility.gd`) + `CompanyTuning.INCOMPATIBLE_QUALITY_PENALTY`; `test_product_compatibility`. Avisar en la mesa y restar el castigo en `AssemblyQuality` quedan para D-0726.b (ver `revisar/D-0726.md`).
**Depende de:** D-0703 (`PackedBox`), D-0116 (catálogo)
**Qué:** `class_name ProductCompatibility`, estático. Tres grupos por id de producto (peligroso: petardos; comida: leche, masa madre, torta; vivo: gallina, cachorro, mapache) y dos reglas: peligroso con comida y peligroso con vivo. Lo demás (vidrio, lámpara) se mezcla con todo. `clash(a, b)`, `conflicts(caja)` (pares de grupos en choque, una vez cada uno), `is_safe`, `penalty` (30 puntos por par).
Decisión: la tabla vive en el script y no en un campo nuevo de los `.tres`: son 7 ids y así no se toca el recurso de Slatex/trampas ni el protocolo; al crecer el catálogo pasa a `ProductDefinition.group`. Decisión: no hay químicos en el catálogo, así que "químicos con comida" se lee como los petardos (lo único peligroso de hoy).
**Test** `test_product_compatibility`: choques en ambos órdenes, grupos que se mezclan, ids sin grupo, cajas reales con uno y dos pares, castigo, caja nula y que todo id agrupado exista en el catálogo.
**Hecho cuando:** la regla tiene su test (pasa).

### D-0727 · Productos con orientación (líquidos de pie) — B · Sonnet 5.5 · medium · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `ProductOrientation` (`scripts/gameplay/business/product_orientation.gd`) + `PackedBox.on_side` + `CompanyTuning.TIPPED_QUALITY_PENALTY`; `test_product_orientation`. Acostar la caja desde la mesa, avisar y restar el castigo en `AssemblyQuality` quedan para D-0727.b (ver `revisar/D-0727.md`).
**Depende de:** D-0703 (`PackedBox`), D-0116 (catálogo)
**Qué:** `class_name ProductOrientation`, estático. Productos que van de pie: `milk_canister` (el único líquido del catálogo) y `wedding_cake`. Una caja acostada (`PackedBox.on_side`) con alguno de ellos los lista en `tipped(box)` (una vez cada uno); `is_safe` y `penalty` (25 puntos por producto). La caja de pie nunca falla. `on_side` viaja en `to_dict`/`from_dict` (los snapshots viejos quedan de pie).
Decisión: la orientación es de la caja entera y no de cada producto, porque en F1 los productos no rotan en la grilla (`PackedBox`). Decisión: la lista va por id en el script, como `ProductCompatibility`, para no tocar los `.tres` del catálogo.
**Test** `test_product_orientation`: qué ids piden estar de pie y existen en el catálogo; caja de pie segura; caja acostada con leche la lista una vez y cobra el castigo; el vidrio acostado no falla; caja nula; ida y vuelta por JSON y snapshot viejo.
**Hecho cuando:** la regla tiene su test (pasa).

### D-0729 · Pedidos multi-caja (un pedido en 2-3 cajas) — B · Sonnet 5.5 · high · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `OrderParts` (`scripts/gameplay/business/order_parts.gd`) + `CompanyTuning.ORDER_BOXES_MAX` y `MULTI_BOX_FILL`; `test_order_parts`. Que el generador pida pedidos grandes, el vínculo de varias cajas en `OrderBoxLink`, la hoja con "caja 1/2" y cobrar al entregar todas quedan para D-0729.b (ver `revisar/D-0729.md`).
**Depende de:** D-0703 (`PackedBox`), D-0712 (`BoxContentCheck`), D-0808 (`OrderBoxLink`)
**Qué:** `class_name OrderParts`, estático. Un pedido que ocupa más de `MULTI_BOX_FILL` (75 %) de una caja XL se parte con `split(order, products)` en 1 a `ORDER_BOXES_MAX` (3) partes, una por caja: unidades de mayor a menor volumen, cada una en la primera parte con lugar (empates por id de producto). Cada parte es un pedido (`id` `<pedido>#<n>`) que `BoxContentCheck` ya entiende. `match(order, products, boxes)` empareja las cajas entregadas con las partes en cualquier orden y dice `missing` (partes sin caja) y `extra` (cajas sobrantes); `door_accepts` exige las dos listas vacías.
Decisión: la partición se calcula de los ítems del pedido, no se guarda: todos los peers obtienen lo mismo y no cambia `Order`, `OrderBook` ni el protocolo. Decisión: pasado el tope de cajas, la unidad va a la parte con más lugar (el pedido sigue entrando en 3); el generador no debería pedir tanto y D-0729.b lo limita.
**Test** `test_order_parts`: 6 unidades son una parte (el pedido mismo); 7 son dos y 14 tres; las partes suman lo pedido y la partición es repetible; el tope no pierde unidades; emparejado en cualquier orden, caja faltante, caja equivocada y caja de más.
**Hecho cuando:** un pedido grande se parte en cajas y la puerta solo lo acepta con todas (el test pasa).

### D-0731 · Mensaje escrito a mano del cliente — B · Sonnet 5.5 · low · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `CustomerNote` (`scripts/gameplay/business/customer_note.gd`) + `PackedBox.note_key` + 6 claves `UI_COMPANY_NOTE*` en `strings_ui.csv`; `test_customer_note`. Dibujar la nota en la cara de la caja con el marcador de `PackageScribble` y mostrarla en la hoja quedan para D-0731.b (ver `revisar/D-0731.md`).
**Depende de:** D-0703 (`PackedBox`), D-0723 (`GiftWrap.is_gift`)
**Qué:** `class_name CustomerNote`, estático. Cada pedido lleva una nota corta elegida por su id de una lista fija (4 comunes, 2 de regalo para pedidos `gift`): `key_for(order)`, `attach(box, order)` (la escribe una sola vez en `PackedBox.note_key`) y `text(box)` (traducida). `note_key` viaja en `to_dict`/`from_dict`; una clave desconocida se descarta.
Decisión: la nota sale del id del pedido (`String.hash`), no de un azar: todos los peers obtienen la misma sin red y no cambia `Order` ni el protocolo. Decisión: son claves de `strings_ui.csv` y no texto libre del cliente, para que se traduzca; la lista crece con D-0822 (60 textos).
**Test** `test_customer_note`: nota repetible, pedido sin id sin nota, pool de regalo vs. común, las 4 comunes se usan, todas las claves están en el CSV, se escribe una vez, ida y vuelta por JSON, clave falsa y snapshot viejo.
**Hecho cuando:** la caja lleva la nota de su pedido (el test pasa).
