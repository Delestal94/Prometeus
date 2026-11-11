# La primera semana del modo Empresa (D-0130)

> Qué aprende el jugador cada uno de los primeros 7 días y cómo se le enseña. Lo construyen D-1901 (el tutorial,
> un objetivo por vez) y D-0412 (los hitos 1 a 5 como repaso del bucle). Fuentes:
> [corte-vertical.md](corte-vertical.md), [hitos.md](hitos.md), [economia.md](economia.md),
> [roles-tripulacion.md](roles-tripulacion.md), [eventos-del-dia.md](eventos-del-dia.md),
> [narrativa-empresa.md](narrativa-empresa.md), [dificultad.md](dificultad.md). Revisado por `critico-diseno`.
> Los números viven en `company_tuning.gd`, no acá.

## 1. Reglas

1. **El día 1 es el bucle entero; del 2 al 7, una cosa nueva por día.** Nada que se pueda aprender después se
   enseña el día 1. No hay nivel de tutorial ni día de práctica: el día 1 cuenta para la empresa.
2. **Se enseña cuando pasa, no por calendario.** Cada fila tiene un **disparador** (lo primero que la hace
   necesaria) y un **día mínimo** (el de calendario, igual para cualquier tripulación). Si no pasa, no se enseña.
3. **Una línea guía en pantalla, nunca dos** (D-1901): arriba a la izquierda, con la acción por `ControlHints`.
   Hecho el objetivo, tilde y el siguiente. Sin pausar, sin menús que cerrar, sin bloquear nada: se puede
   hacer todo fuera de orden y la línea se adapta (sale del estado).
4. **Aprender no cuesta plata.** El día 1 no sale en rojo jugando torpe (economía §3) y no hay eventos del día
   hasta el 4 (eventos-del-dia, "Decisiones").
5. **Dos tipos de texto.** La **línea del objetivo** es UI, seca (`UI_ONBOARD_<ID>`). La **nota** es una voz (la
   Jefa o el Jefe del depósito) en el feed de avisos (`OrderNoticeFeed`), con el tono de
   [narrativa-empresa.md](narrativa-empresa.md) §3 (`WORLD_ONBOARD_<ID>_<n>`). Las filas sin objetivo son solo nota.
6. **El progreso es de cada jugador**, no de la empresa (§4): el veterano no ve la guía y el nuevo sí, aunque
   jueguen juntos. Lo del juego base (manejar, cuidar la caja, las trampas) usa las tarjetas de una vez que ya
   existen; D-1901 comprueba que también salgan en modo Empresa.

## 2. La tabla

| Día mín. | Qué aprende | Disparador | Objetivo (id) o nota | Hecho cuando | Tareas |
|---|---|---|---|---|---|
| 1 | **El bucle entero** (§3) | Abrir el día 1 | Los 6 objetivos de §3 | Día 1 cerrado | D-0720, D-0716, D-0717, D-0611 |
| 1 | **Pedido en espera** (falta stock: el palet regalado trae 1 por producto) | Primer pedido que no se puede armar con lo que hay | Nota del Jefe: "Eso no está en el estante. Lo sumo al pedido de mañana." | — | D-0612, D-0151.3 |
| 1 | **Reponer la mesa** (cinta, cajas, relleno) | Primer insumo de la mesa en cero | `restock` reponé la mesa | Insumo repuesto | `station_supplies.gd` |
| 1 | **El galpón se congela** cuando sale toda la tripulación | Primera salida con nadie en el galpón | Nota de la Jefa | — | S4, roles-tripulacion §4 |
| 1 | **El cierre** y el pedido sugerido para mañana | Primer `CLOSING` | Nota de la Jefa: "Primer día cerrado. Mañana a las 08:30 llega lo que pedí por ustedes." | — | D-0320, D-0151.3 |
| 2 | **El proveedor**: camión de las 08:30, zorra y remito | Llega el primer camión del proveedor | `unload` bajá el palet con la zorra | Camión vacío | D-0601, D-0605, D-0614 |
| 2 | **Cambiar el pedido al proveedor** | Primer cierre después del día 1 con faltantes | `order_more` sumá lo que faltó al pedido de mañana | Pedido de mañana con el faltante | D-0603, `supplier_order_cart.gd` |
| 2 | **La ventana de 4 h y el vencimiento** | Primer aviso de vencimiento | Nota del Jefe (ya existe) | — | `order_waiting.gd` |
| 2 | **Armar bien**: caja justa y relleno; la trampa la pone lo que va adentro | Primera caja rota o entregada con `Q` baja | `fill` llená el hueco con relleno antes de cerrar | Caja con `Q` de "bien armada"; con Armado asistido se saltea | D-0709, [armado-y-trampas.md](armado-y-trampas.md), D-1919 |
| 3 | **La reputación** | Primer cierre con cambio de reputación de ±2 o más | Nota de la Jefa en el cierre | — | D-0405 |
| 4 | **Pedidos de 3 productos** (fin de la rampa) | Primer pedido de 3 productos | Nota del Jefe | — | D-0812 |
| 4 | **Un evento del día** | Primer evento sorteado (positivo o mixto) | El anuncio del evento (sin línea propia) | — | D-0123, D-1905 |
| 7 | **Fin de la guía** | Día 7 cerrado | — | — | — |

Con hitos (F2) se suma la nota `teaches_key` de los hitos 1 a 5 al cumplirlos (§5): es **repaso** de algo que
la tabla ya enseñó, nunca primera enseñanza. Lo que abre un hito (tienda de mejoras, contratar, barrio nuevo,
bici) se enseña cuando se compra o se usa por primera vez, con D-1926, como empleados, máquinas, construcción,
flota y heladera.

**F1 sin hitos** (corte-vertical §3): la tabla entera funciona igual; ninguna fila depende de un hito.

## 3. El día 1, paso por paso

El día 1 abre con **un pedido de 1 producto y 1 unidad, sin sellos, a las 08:00** (`DAY_START_MIN`), de lo que
trae el palet regalado; el resto del ritmo (`OrderRhythm`, rampa de D-0812) no cambia. Así el primer armado
nunca espera a un pedido.

| # | id | Línea (es) | Hecho cuando (para ese jugador) |
|---|---|---|---|
| 1 | `stock_pallet` | Guardá la mercadería del palet en el estante | Dejó una unidad del palet en un hueco |
| 2 | `pick` | Buscá en el estante lo que pide el tablero | Tiene en la mano o en el carrito una unidad de un pedido abierto |
| 3 | `pack` | (la línea es el paso de `PackingTutorial`, hasta el despacho) | `PackingTutorial.step(...).done` |
| 4 | `drive` | Cargá la camioneta y seguí el GPS | Va manejando con una caja cargada |
| 5 | `deliver` | Entregá la caja en la puerta | Primera entrega que pagó |
| 6 | `return` | Volvé al galpón | Camioneta adentro del portón |

**Qué ve cada uno.** La línea mira primero al jugador: si tiene algo en la mano o maneja, ve el paso de eso; si
no, el primero pendiente **suyo**. Con 2 jugadores, mientras uno arma (`pack`) el otro que ya guardó el palet
ve `pick` o `drive`: nadie mira sin hacer nada (regla de los 2 min, roles-tripulacion §1). Un paso que hizo
otro no se tilda para mí: cada uno aprende el bucle con sus manos, pero no se traba (un paso que ya no se puede
hacer, como `stock_pallet` con el palet vacío, se tilda solo).

## 4. Estado, red y guardado (para D-1901)

- **Función pura** `CompanyOnboarding.current(player_ctx, company_ctx, seen) -> {id, key, action}`: recorre las
  tablas en orden y devuelve la primera fila cuyo disparador pasó y que el jugador no hizo. `player_ctx` es lo
  que tiene en la mano y si maneja; `company_ctx`, lo que ya replica `CompanyNet` (día, pedidos, stock,
  insumos). Corre en cada máquina sobre su copia: **sin RPC nuevo**.
- **Lo hecho se guarda en el perfil del jugador** con `UnlockManager.mark_tip_seen("company_onboard_<id>")`
  (local, como las tarjetas de trampas y `care_practice.gd`): sin campo nuevo en `CompanyState`, sin snapshot
  y sin opción del host. Quien ya hizo el día 1 en otra empresa no lo repite. No hay "reiniciar consejos" en el
  juego base y no se agrega ahora.
- **Claves:** `UI_ONBOARD_<ID>` y `WORLD_ONBOARD_<ID>_<n>`, es y en, con [glosario.md](glosario.md).
- **Medición sin gente** (playtesting al final): `bot_company_day` con 1 jugador (D-2016) tilda los 6 objetivos
  de §3 antes de las 20:00 del día 1; con 2 jugadores, ninguno pasa 120 s sin línea guía ni caja.

## 5. Qué construye cada tarea

| Tarea | Qué toma de acá |
|---|---|
| D-1901 | `CompanyOnboarding` (función pura con §2 y §3), la línea en pantalla, `seen_tips`, las notas, el test `test_company_onboarding` (orden, disparadores, un jugador con caja ve su paso, dos jugadores ven pasos distintos, Armado asistido saltea `fill`, perfil que ya la vio) |
| D-0412 | `teaches_key` de los hitos 1 a 5 como repaso: 1 → el bucle, 2 → varias paradas, 3 → el cierre, 4 → armar bien, 5 → la reputación |
| D-0801 / D-0812 | El pedido del día 1 a las 08:00 de §3 |
| D-1926 | Todo lo que se enseña al comprarlo o usarlo por primera vez |

## 6. Qué NO

- Columnas por cantidad de jugadores: con disparadores, el día lo pone el juego.
- Objetivos de "mirá tal pantalla" (tablero, tienda, resumen): son ventanas del cliente que el estado no ve y
  no enseñan nada que la nota no diga.
- Flechas en el piso, cámara que se mueve sola, acciones bloqueadas hasta hacer el paso.
- Subir el palet regalado para evitar el pedido en espera: la nota del Jefe lo enseña y el pedido sugerido lo
  resuelve al día siguiente; la economía no se toca.
