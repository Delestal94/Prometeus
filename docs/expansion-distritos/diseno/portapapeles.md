# El portapapeles de gestión (D-0131)

> Cómo se lleva la gestión del galpón **en la mano y no en un menú**: qué es, cuándo se puede sacar, qué hojas
> tiene, cómo se navega y qué va a la red. Lo construye D-1902 (el objeto y sus hojas) y lo usan D-1004
> (asignar empleados) y D-1038 (plantilla). Fuentes: [referencia-schedule-1.md](referencia-schedule-1.md) §2,
> [vision.md](vision.md) §9, [roles-tripulacion.md](roles-tripulacion.md) §1, [onboarding.md](onboarding.md),
> [red-autoridad.md](red-autoridad.md). Revisado por `critico-diseno`. Los números viven en `company_tuning.gd`.

## 1. Reglas

1. **Es un objeto, no una pantalla.** Se saca con una tecla, se ve en la mano del que lo lleva (los demás lo ven
   leyendo) y **ocupa las manos**: con el portapapeles afuera no se levanta una caja ni se empuja un carrito, y
   levantar una caja lo guarda solo. Así nunca compite con la regla de los 2 min (roles-tripulacion §1): leer
   es un rato corto entre dos cajas.
2. **Está desde el día 1** (cambia lo que decía referencia-schedule-1 §2: "aparece con el primer empleado"). Las
   hojas de stock (D-0612) y del proveedor (D-0603) son de F1 y ya existen; esperar al hito 8 las dejaría sin
   lugar. Lo que abre el hito `first_employee` es **la hoja de empleados**, no el objeto.
3. **No inventa pantallas: junta las que hay.** Cada hoja es un panel que ya existe o que ya tiene tarea
   (`StockPanel`, `SupplierOrderPanel`, `OrderBoardPanel`…) dibujado sobre el marco del portapapeles. D-1902
   construye el marco, el cambio de hoja y el sacar y guardar; las hojas siguen siendo de sus tareas.
4. **Leer es local, decidir va al host.** Abrir, cambiar de hoja y mirar no mandan nada: cada máquina dibuja su
   copia (`CompanyNet`), como hoy `StockBoard`. Lo que cambia la empresa (pedir al proveedor, asignar, marcar
   prioridad) sale por la petición que esa tarea ya tiene, con su rechazo.
5. **Los tableros del galpón se quedan.** El tablero de pedidos es lo que la tripulación mira en común y no se
   saca. El del proveedor queda como **atajo**: usarlo saca el portapapeles en la hoja del proveedor. Nada del
   juego exige el portapapeles: todo lo que hay en él también se puede hacer en su estación.

## 2. Las dos posiciones

| Posición | Cómo se ve | El jugador | Qué se hace |
|---|---|---|---|
| **Bajado** (al sacarlo) | En la mano derecha, a la altura del pecho; abajo a la derecha una tira con el título de la hoja y su **línea clave** (§3) | Camina a paso normal, sin correr ni saltar; la cámara es libre | Mirar: apuntar a algo del galpón muestra su línea (estante: qué tiene; estación: quién la atiende). Con empleados, es el modo de asignar (D-1004, §5) |
| **Levantado** (mantener o tocar `interact` con él bajado) | La hoja ocupa los dos tercios de abajo de la pantalla, con el galpón atrás | Quieto; el ratón se suelta y el input del jugador se corta, como los paneles de hoy | Leer la hoja entera y usar sus botones |

Bajar la hoja (`ui_cancel` o la misma tecla) vuelve a **bajado**; la tecla del portapapeles con él bajado lo
guarda. Recibir un golpe, subirse a manejar, que el día pase a `SUMMARY` o abrir la pausa lo guarda solo.

```
 Bajado                                     Levantado
 ┌──────────────────────────────────┐       ┌──────────────────────────────────┐
 │        (galpón, cámara libre)    │       │        (galpón, quieto)          │
 │                                  │       │ ┌──────────────────────────────┐ │
 │             · Estante 3          │       │ │ [Pedidos] Stock  Prov.  Día  │ │
 │               Leche 4 · Pan 0    │       │ │──────────────────────────────│ │
 │                                  │       │ │ #12 Belgrano 340   vence 11:40│ │
 │                      ┌─────────┐ │       │ │   2× Leche  1× Yerba    ⚑    │ │
 │                      │ Pedidos │ │       │ │ #13 Alsina 77      vence 12:15│ │
 │                      │ 3 abier.│ │       │ │   1× Pan  (falta)            │ │
 │                      │ #12 vence│ │       │ │──────────────────────────────│ │
 │                      │ 11:40   │ │       │ │ LB/RB hoja · A marcar · B bajar│
 │                      └─────────┘ │       │ └──────────────────────────────┘ │
 └──────────────────────────────────┘       └──────────────────────────────────┘
```

## 3. Las hojas

Como mucho **5 hojas**, siempre en este orden; una hoja que todavía no se abrió no aparece (no hay pestañas
grises). La línea clave es lo que se ve con el portapapeles bajado.

| Hoja | Desde | Qué muestra levantado | Botones | Línea clave (bajado) | Tarea |
|---|---|---|---|---|---|
| **Pedidos** | Día 1 | Los pedidos abiertos del día: dirección, productos, vencimiento, qué falta (`StockAlert`) | Marcar prioridad (⚑) | Abiertos y el que vence primero | D-0804, D-0838 |
| **Stock** | Día 1 | La lista de stock por producto, con lo que falta y lo que viene en camino | — (solo lectura) | Productos en cero | D-0612 (`StockPanel`) |
| **Proveedor** | Día 1 | El carrito del pedido de mañana, precargado con el sugerido | ± unidades, Pedir | Lo pedido para mañana y su total | D-0603 (`SupplierOrderPanel`), D-0151.3 |
| **Día** | Día 1 | Plata, cobrado y gastado hoy, alquiler, cajas entregadas y rotas, reputación | — | Plata y hora | D-1903 (los mismos datos del HUD del día) |
| **Empleados** | Hito 8 `first_employee` | La plantilla: nombre, rol, estación (con número, "Mesa 2"), sueldo, cansancio | Contratar (si la agencia tiene candidatos), despedir | Empleados y estaciones sin nadie | D-1003, D-1004, D-1038 |

**Flota** (D-1902 la nombraba) no es una hoja: con 2 vehículos como mucho lejos del galpón, la flota se ve en el
mundo (dársena y GPS). Si con la avioneta (F4) hace falta, entra como sexta hoja quitando otra. **Plata** es
la hoja **Día**: el libro contable de 7 días (D-0531) está pospuesto.

## 4. Controles

| Acción | Teclado y ratón | Mando |
|---|---|---|
| Sacar / guardar | `I` (la de la lista de stock hoy, `company_stock`) | Cruceta derecha |
| Levantar / bajar | `E` (`interact`) con él bajado, sin nada apuntado que se use; `Esc` baja | A / B |
| Cambiar de hoja | `Q` / `E` levantado, o clic en la pestaña | LB / RB |
| Moverse en la hoja | Ratón, flechas | Stick izquierdo / cruceta |

La cruceta derecha es también `care_tool_next`, pero cuidar una caja ocupa las manos y el portapapeles no se
puede sacar: no chocan. `F` (celular) y el portapapeles se excluyen: sacar uno guarda el otro.

## 5. Asignar apuntando (con empleados, D-1004)

Bajado, mirar a un empleado y apretar `interact` lo **toma**; mirar una estación y apretar otra vez lo
**asigna**, y queda una línea resaltada entre los dos por 3 s. Mirar otro empleado cambia la selección; `Esc`
la suelta. La hoja Empleados muestra el resultado y sirve para lo mismo sin caminar (elegir empleado → elegir
estación de la lista). La asignación es una petición al host (D-1004) y un empleado ya asignado a otro jugador
no se bloquea: gana la última que llega al host, como cualquier petición de la empresa.

## 6. Red, guardado y presentación

- **Sin RPC nuevo para el objeto.** Tenerlo afuera y su posición son un estado del jugador que ya replica su
  pose: un `int` más en lo que el jugador manda al host para la animación (`0` guardado, `1` bajado, `2`
  levantado), para que los demás lo vean leyendo. No va al snapshot de la empresa ni al save.
- **La hoja que estaba abierta** se recuerda por jugador (local, `GameSettings`), no por empresa.
- **Jugador sin empresa** (Entrega o Endless): la tecla no hace nada; el portapapeles es del modo Empresa.
- **Arte:** un portapapeles low-poly de madera con una hoja y un broche (`arte-pendiente/D-1902.md`). Mientras
  tanto, un `BoxMesh` marrón de 0,23 × 0,32 × 0,01 m en la mano y el marco 2D con borde de madera.
- **Sonido** (D-1913): papel al cambiar de hoja, broche al sacar y guardar.

## 7. Qué construye cada tarea

| Tarea | Qué toma de acá |
|---|---|
| D-1902 | El objeto (§1-2), las dos posiciones, el marco con pestañas, controles (§4), la exclusión con celular y cajas, el estado de pose (§6) y el test de navegación con mando y teclado; las hojas de §3 que ya existen se enchufan tal cual |
| D-0612 / D-0603 | Sus paneles pasan a ser hojas: `StockBoard` y `SupplierBoard` abren el portapapeles en su hoja en vez de su panel suelto |
| D-0838 | El botón ⚑ de la hoja Pedidos |
| D-1004 / D-1038 | §5 y la hoja Empleados |
| D-1901 | Ningún objetivo nuevo: el tutorial no enseña el portapapeles (onboarding §6); su primera salida la cuenta una nota de la Jefa el día 2 |

## 8. Qué NO

- Rutas a mano "desde → hasta" como en *Schedule I* (referencia-schedule-1, decisión 3): el flujo es implícito.
- Un portapapeles por empresa que se pasa de mano en mano: cada jugador tiene el suyo.
- Pedir al proveedor o asignar sin el host, o abrir con un RPC (se abre en la máquina de cada uno).
- Mapa, GPS o despacho en el portapapeles: el mapa es del celular y el despacho, de su tablero (D-0303).
- Hojas que solo son números sin un objeto del galpón detrás (vision §9): cada hoja tiene su estación.
