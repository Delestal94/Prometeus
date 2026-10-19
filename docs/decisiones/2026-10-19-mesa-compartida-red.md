# Decisión 2026-10-19: la mesa de armado compartida por red

Tomada por la rutina de la expansión al hacer D-0715 (parte a)
([red-autoridad.md](../expansion-distritos/diseno/red-autoridad.md) §2 filas 9 a 15 y §9).

**Decisión:**

1. **La caja en armado vive en `CompanyNet.table`** (`CompanyTableNet`, un `PackingStation` por mesa con su
   caja, sus insumos y el id de la caja), no en `CompanyShed.stations`, que solo dibuja. Viaja en el
   snapshot como la parte `packing`.
2. **La celda viaja como `cx`, `cy`, `cz`** (la grilla de `PackedBox` es 3D; el contrato decía `cx`, `cy`) y
   **`rot` solo vale 0** (F1 sin rotación, D-0703).
3. **`box_fill` pide `cells`** (cuántas celdas rellenar) en vez de `fill` (papel / burbuja / espuma): F1 tiene
   un solo relleno (D-0705, D-0718). El evento lleva las que se rellenaron de verdad.
4. **Los pasos que cuestan llevan `money` y `minute`** (saldo del host después y su minuto para el libro),
   como el layout (D-0910). `box_placed` y `box_taken_out` llevan además la mano (`from` / `to`, que arma el
   host) y `box_taken_out` el producto, para que cada peer compruebe su copia.
5. **Los ids de caja son `box_<n>` del host** (después del último, salteando los que todavía tienen
   unidades); el paquete que sale de la caja usa el mismo id (`package_id`, `package:<id>`).
6. **Regla de la reserva** (fila 10): una unidad entra en la caja del pedido X si a X le falta ese producto en
   su caja; si no, si queda una libre: las de afuera de cajas y paquetes menos lo que cada pedido tiene
   reservado y todavía no está en su caja.
7. **El pedido de la mesa lo da `CompanyTableNet.order_of`** hasta que exista `order_claim` (fila 8).
8. **No se vende una mesa con caja** (`not_empty`), y venderla olvida su estado.
9. **Los productos "en espera" de la mesa no viajan**: por red la unidad va de la mano a la grilla.
10. **Ninguna petición de la mesa es crítica** (regla 8): ninguna suelta nada.

**Por qué:**

1. El estado de negocio no puede vivir en un nodo de presentación: `CompanyShed` se redibuja y no está en
   todos los mundos (tests, servidor sin pantalla). `CompanyNet` ya es dueño del stock y del snapshot.
2. Un `Vector3i` no pasa `RpcGuard.dict_ok` (regla 5); sin `cz` no se puede apilar.
3. Mandar un tipo que no existe obligaría a validar un dato sin efecto.
4. Sin esto el libro de un cliente queda con su propio minuto (el reloj solo lo escribe el host) y un
   espejo desfasado nunca se corrige.
5. Un número del host evita choques entre peers; saltear los ocupados evita pisar una caja de un día cargado.
6. Es lo que pide el contrato ("primero de la reserva de X y si no de lo libre") contado con lo que ya hay
   en cajas, para que una unidad de A no termine en la caja de B.
7. Deja la regla de reserva y la etiqueta listas y probadas sin esperar el tablero de pedidos.
8. Las unidades de una caja están en `box:<id>`, no en `table:<uid>`: vender la mesa las dejaría sin lugar.
9. Son un apoyo visual de la mesa local; por red serían otro lugar de unidades sin `Inventory`.
10. Si se pierde, el jugador vuelve a apretar; nadie queda con las manos llenas.

**Cambia:** D-0715 (`docs/expansion-distritos/detalle/F1-07-armado.md`), el contrato (filas 9 a 15, §8 y §9);
si vuelven los tres rellenos, `box_fill` suma `fill`; si se permite girar (D-0727), `rot` toma 0..3.
