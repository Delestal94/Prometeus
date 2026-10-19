# Decisión 2026-10-18: en red, el galpón lo construye solo el host

Tomada por la rutina de la expansión al hacer D-0910
([red-autoridad.md](../expansion-distritos/diseno/red-autoridad.md) §2 filas 21 a 24 y §8).

**Decisión:**

1. **Solo el host coloca, mueve, gira o vende piezas del galpón.** Un cliente puede pedirlo por
   `CompanyNet` (los mismos `kind`), pero el host lo rechaza con `host_only` antes de mirar nada más, y el
   aviso le llega solo a él. El voto de la tripulación queda como subtarea D-0910.1.
2. **Construir no depende del día**: ni de la fase (apertura, operación, cierre, resumen) ni del galpón
   congelado (S4, D-0203). Un evento de layout no toca `DayCycle`.
3. **Las piezas se nombran por `uid`**, nunca por índice, y el host le da un `uid` nuevo (`<id>_<n>`) a cada
   pieza que se coloca.
4. **No se vende una pieza que tiene unidades** (`not_empty`).

**Por qué:**

1. Es lo más simple que cumple "solo host o voto" y no deja estados a medias: el host ya es el dueño de la
   plata y del layout (S8, regla 1), y es quien abre el día y lo pasa al siguiente. Que el cliente pueda
   pedir y oiga por qué no (en vez de no poder pedir) deja el camino armado para el voto: la comprobación
   está en un solo lugar (`CompanyLayoutNet.check()`, `by_host`).
2. Ni el contrato de red ni D-0203 lo piden. Si el jugador puede entrar al modo construcción lo decide el
   adaptador (`BuildMode.enter(can_build)`: en un vehículo, lejos del galpón, con una caja en la mano).
3. Con dos pedidos en vuelo un índice puede apuntar a otra pieza; el `uid` además es la clave del stock del
   estante (`shelf:<uid>_<hueco>`) y del estado de la mesa, así mover no pierde nada.
4. Vender un estante con unidades las dejaría en un lugar que ya no existe.

**Cambia:** D-0910 (`docs/expansion-distritos/detalle/F1-09-galpon.md`); si se elige el voto, D-0910.1 suma
"o el voto pasó" en `CompanyLayoutNet.check()` y su test.
