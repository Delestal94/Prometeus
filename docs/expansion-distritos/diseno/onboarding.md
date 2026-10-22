# La primera semana del modo Empresa (D-0130)

> Qué aprende el jugador cada uno de los primeros 7 días y cómo se le enseña. Lo construyen D-1901 (el tutorial,
> un objetivo por vez) y D-0412 (los hitos 1 a 5 como consejo del bucle). Fuentes:
> [corte-vertical.md](corte-vertical.md), [hitos.md](hitos.md), [economia.md](economia.md),
> [roles-tripulacion.md](roles-tripulacion.md) §6, [eventos-del-dia.md](eventos-del-dia.md),
> [narrativa-empresa.md](narrativa-empresa.md), [dificultad.md](dificultad.md),
> [referencia-schedule-1.md](referencia-schedule-1.md). Los números viven en `company_tuning.gd`, no acá.

## 1. Reglas

1. **Una cosa nueva por día, y el día 1 es el bucle entero.** El día 1 enseña el bucle de punta a punta con
   lo mínimo (la caja más simple, una salida); del 2 al 7 se suma **una** cosa por día. Nada que se pueda
   aprender después se enseña el día 1.
2. **Se enseña cuando pasa, no por calendario.** Cada fila de la tabla tiene un **disparador** (lo primero que
   lo hace necesario). El "día" de la tabla es cuándo se espera que pase con 1 jugador; si pasa antes (4
   jugadores, un hito temprano) se enseña antes, y si no pasa, no se enseña. Así una tripulación grande no
   espera al calendario y una chica no recibe consejos de cosas que todavía no tiene.
3. **Un objetivo por vez en pantalla** (D-1901): una línea arriba a la izquierda, con la acción del mando o
   del teclado (`ControlHints`). Hecho el objetivo, tilde y el siguiente. Nunca un muro de texto, nunca una
   pausa del juego, nunca un menú que haya que cerrar. El reloj del galpón corre igual.
4. **Aprender no cuesta plata.** El día 1 no puede salir en rojo jugando torpe (economía §3: palet regalado,
   ~+100 neto con 1 jugador) y no hay eventos del día hasta el 4 ni negativos hasta el 8 (eventos-del-dia, "Decisiones").
5. **La voz es la de la Jefa**, por radio o nota, con el tono de [narrativa-empresa.md](narrativa-empresa.md)
   §3: dos frases, un chiste como mucho, el dato aparte. La línea del objetivo es seca (es UI); el comentario
   de la Jefa, cuando lo hay, va en el feed de avisos (`OrderNoticeFeed`).
6. **Nada se repite al jugador que ya lo sabe.** Lo que es del juego base (manejar, cargar en brazos,
   las trampas) usa los consejos de una vez de `UnlockManager.seen_tips` (por jugador, como hoy). Lo que es
   del modo Empresa se marca **por empresa** (§4): una empresa nueva vuelve a guiar, pero se puede apagar.

## 2. La tabla de los 7 días

`Día` = día esperado con 1 / 2 / 4 jugadores. `Objetivo` es la línea que se ve; `Hecho` es lo que la tilda
(lo comprueba el host con estado que ya existe).

| Día | Qué aprende | Disparador | Objetivos en orden (id) | Hecho cuando | Tareas |
|---|---|---|---|---|---|
| 1 / 1 / 1 | **El bucle entero.** Del palet al cierre, con un pedido de 1 producto primero | Abrir el día 1 de una empresa nueva | `stock_pallet` guardá el palet en el estante · `read_board` mirá el tablero de pedidos · `pick` sacá el producto del estante · `pack` armá la caja (los 7 pasos de `PackingTutorial`) · `dispatch` dejala en la salida y cargala · `drive` seguí el GPS a la casa · `deliver` entregala · `return` volvé al galpón | `first_delivery` (hito 1) y el día cerrado | D-0720, D-0716, D-0717, D-0611, GPS |
| 1 / 1 / 1 (cierre) | **El cierre** y que mañana llega lo pedido | Primer `CLOSING` | `close_day` mirá el resumen | Resumen cerrado | D-0320, D-0151.3 |
| 2 / 1 / 1 | **El proveedor**: el camión de las 08:30, el remito y descargar con la zorra | Llega el primer camión del proveedor (no el palet regalado) | `unload` bajá el palet con la zorra · `check_note` revisá el remito | Palet en la dársena vacío | D-0601, D-0605, D-0614 |
| 2 / 1 / 1 | **La tienda de mejoras** (premio del hito 1) | `first_delivery` cumplido | `upgrades` mirá la tienda de mejoras | Tienda abierta una vez | D-0403, `company_shop.gd` |
| 2 / 2 / 1 | **La ventana de 4 h y el vencimiento** | Primer aviso de vencimiento del Jefe | (sin objetivo: solo la nota) | — | `order_waiting.gd`, `OrderNoticeFeed` |
| 3 / 2 / 2 | **Varias paradas en una salida** (hito 2) | Salida con 2 o más cajas cargadas | `route` entregá dos casas en la misma salida | Dos entregas en una salida | D-0306, D-0312 |
| 3 / 3 / 3 | **Armar bien**: caja justa y relleno; la trampa la pone lo que va adentro | Primer producto frágil del lote Centro o primera caja rota | `fill` llená el hueco con relleno antes de cerrar | Caja con `Q` ≥ umbral de "bien armada" | D-0709, [armado-y-trampas.md](armado-y-trampas.md) |
| 3 / 2 / 2 | **La reputación** (hito 5) | Primer cambio de reputación de ±2 o más en un cierre | (sin objetivo: la Jefa lo explica en el cierre) | — | D-0405 |
| 4 / 3 / 2 | **Pedidos de 3 productos y quedarse sin stock** | Fin de la rampa (día 4) o primer faltante en `StockAlert` | `stock_view` mirá qué falta · `order_more` sumá al pedido del proveedor | Pedido de mañana con el faltante | D-0812, D-0612, `supplier_order_cart.gd` |
| 4 / 3 / 2 | **Un evento del día** | Primer evento sorteado (positivo hasta el día 8) | (sin objetivo: el aviso de la víspera ya lo cuenta) | — | D-0123 (el marco es tarea nueva del grupo 05), D-1905 |
| 5 / 4 / 3 | **Elegir qué pedido primero** (los que pagan más, los que vencen antes) | Primer día con más pedidos abiertos que cajas armables | `priority` marcá un pedido urgente en el tablero | Un pedido priorizado | D-0838, `order_board.gd` |
| 6 / 4 / 3 | **Un barrio nuevo** (hito 7: Suburbio y su permiso, o Campo con el 6) | Hito de distrito cumplido | `new_district` comprá el permiso o salí al barrio nuevo | Primera entrega en el distrito nuevo | D-0403, hitos 6 y 7 |
| 6 / 4 / 3 | **Contratar** (hito 8, solo F2) | `first_employee` cumplido | `hire` mirá la agencia | Agencia abierta una vez | D-0413; tutorial propio en D-1926 |
| 7 / 5 / 4 | **Cierre de la guía.** La Jefa deja de guiar; queda el consejo por sistema nuevo (D-1926) | Día 7 cerrado o los objetivos 1-5 hechos | — | — | — |

Lo que **no** se enseña en la primera semana (va a D-1926, con su propio disparador): empleados por
dentro, máquinas, construcción del galpón, flota nueva (bici, carrito), heladera y temperatura, licencias.
Cada uno, cuando el jugador lo compra.

**Sin hitos (F1).** En F1 no hay hitos (corte-vertical §3): las filas que se disparan con un hito no aparecen,
y Centro y Campo están abiertos desde el día 1. El día 1 y las filas con disparador de estado (proveedor,
vencimiento, varias paradas, armar bien, faltantes) ya funcionan en F1: es lo que necesita el corte.

## 3. El día 1, paso por paso (lo más caro de equivocar)

El día 1 abre con **un solo pedido de 1 producto** del palet regalado a las 08:00 y el resto del ritmo normal
(`OrderRhythm`, rampa de D-0812) desde las 09:00, así el primer armado no compite con nada. Con 2 o más
jugadores los objetivos son **de la empresa, no de cada uno**: el primero que guarda el palet tilda
`stock_pallet` para todos y, mientras uno arma, otro ve `drive` cuando hay caja cargada. Así nadie mira sin
hacer nada (regla de los 2 min de roles-tripulacion §2).

| # | id | Línea (es) | Hecho cuando |
|---|---|---|---|
| 1 | `stock_pallet` | Guardá la mercadería del palet en el estante | Una unidad del palet en un hueco de estante |
| 2 | `read_board` | Mirá el pedido en el tablero | Alguien abrió el tablero |
| 3 | `pick` | Buscá el producto en el estante | Unidad del pedido en la mano o en el carrito |
| 4 | `pack` | Armá la caja en la mesa | `PackingTutorial.step(...).done` |
| 5 | `dispatch` | Dejá la caja en la salida y cargala | Pedido en `OUT` |
| 6 | `drive` / `deliver` | Seguí el GPS y entregá | `first_delivery` (sin hitos: el primer pedido entregado) |
| 7 | `return` | Volvé al galpón | Camioneta adentro del portón |
| 8 | `close_day` | Mirá el resumen del día | Cierre del día 1 terminado |

La Jefa, en el cierre del día 1 (dos frases, [narrativa-empresa.md](narrativa-empresa.md) §3): "Primer día
cerrado. Mañana a las 08:30 llega lo que pedí por ustedes." Lo pide la ayuda de pedido sugerido (D-0151.3,
para todos el día 1), y el día 2 se enseña a cambiarlo.

## 4. Estado, red y guardado (para D-1901)

- **Sin estado propio para el paso** (como `PackingTutorial`): el objetivo de ahora sale de una función pura
  `CompanyOnboarding.current(state, day_flags) -> {id, key, action}`: recorre la tabla en orden y devuelve el
  primero cuyo disparador ya pasó y cuyo "hecho" todavía no. Lo mismo en host y clientes, sin RPC.
- **Lo único guardado** es `CompanyState.onboarding_seen: Array[StringName]` (filas ya mostradas y cumplidas),
  para que el día 12 no vuelva a aparecer un objetivo del 2. Viaja en el snapshot de `CompanyNet` como el resto
  del estado; lo escribe solo el host. Un save sin el campo carga con la lista vacía y la guía apagada si
  `day` > 7 (la empresa vieja ya sabe).
- **Apagar la guía**: opción del host al crear la empresa, "Guía de la primera semana" (prendida por defecto),
  en `CompanyState.options` como los modificadores de [dificultad.md](dificultad.md) (`onboarding: bool`). No
  cambia la economía ni los hitos.
- **Pocas claves nuevas:** `UI_ONBOARD_<ID>` (línea del objetivo) y `WORLD_ONBOARD_<ID>_<n>` (comentario de la
  Jefa), es y en, con el glosario de [glosario.md](glosario.md).
- **Medición sin gente** (playtesting al final): `bot_company_day` con 1 jugador (D-2016) recorre el día 1 con la guía
  prendida y debe tildar los 8 objetivos de §3 antes de las 20:00; el bot de D-0412 cumple los hitos 1-5
  antes del día 5.

## 5. Qué construye cada tarea

| Tarea | Qué toma de acá |
|---|---|
| D-1901 | `CompanyOnboarding` (función pura, tabla de §2 y §3), la línea en pantalla, `onboarding_seen` en el save y el snapshot, la opción del host, el test `test_company_onboarding` (orden, disparadores, F1 sin hitos, 2 jugadores tildan juntos, save viejo) |
| D-0412 | El texto de `teaches_key` de los hitos 1 a 5 es el comentario de la Jefa de la fila de ese hito (hito 1 → bucle, 2 → varias paradas, 3 → cierre, 4 → armar bien, 5 → reputación) |
| D-0812 / D-0801 | Primer pedido del día 1: 1 producto, a las 08:00, del palet regalado |
| D-1926 | Todo lo de "no se enseña en la primera semana" |

## 6. Qué NO

- Un nivel de tutorial aparte o un día de práctica: el día 1 **es** el tutorial y cuenta para la empresa.
- Flechas en el piso, cámara que se mueve sola, bloquear acciones hasta hacer el paso: se puede hacer todo
  fuera de orden y el objetivo se adapta (sale del estado).
- Textos con más de una cosa por línea, o que nombran un botón sin `ControlHints`.
