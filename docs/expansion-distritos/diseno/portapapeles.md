# El portapapeles de gestión (D-0131)

> Cómo se lleva la gestión del galpón **en la mano y no en un menú**: qué es, cuándo se puede sacar, qué hojas
> tiene, cómo se navega y qué va a la red. Lo construye D-1902 (el objeto y sus hojas) y lo amplía D-1004
> (apuntar para asignar). Fuentes: [referencia-schedule-1.md](referencia-schedule-1.md) §2,
> [vision.md](vision.md) §9, [roles-tripulacion.md](roles-tripulacion.md) §1, [onboarding.md](onboarding.md),
> [red-autoridad.md](red-autoridad.md). Revisado por `critico-diseno`. Los números viven en `company_tuning.gd`.

## 1. Reglas

1. **Es un objeto, no una pantalla.** Se saca con una tecla, los demás lo ven en la mano del que lo lleva y
   **ocupa las manos**: no se saca si el jugador tiene las manos ocupadas (§4) y usar algo del mundo
   (`interact` sobre un `Interactable`) lo guarda en el momento y la acción sigue como siempre. El host nunca
   mira el portapapeles: no entra en ninguna validación.
2. **Está desde el día 1** (cambia la fila 116 de referencia-schedule-1: "aparece con el primer empleado"). Las
   hojas de stock (D-0612) y del proveedor (D-0603) son de F1 y ya existen sin lugar donde vivir; lo que abre el
   hito 8 `first_employee` es **la hoja Empleados**, no el objeto.
3. **Junta paneles que ya existen.** Cada hoja es un panel con tarea propia dibujado dentro del marco. Para eso
   el panel suma un modo `embedded`: sin fondo oscuro, sin botón Cerrar, sin manejar `ui_cancel` / `ui_pause` y
   sin sonido de abrir y cerrar; el foco lo pide el marco. D-1902 lo agrega a `StockPanel` y
   `SupplierOrderPanel`, con test.
4. **Leer es local, decidir va al host.** Sacarlo, cambiar de hoja y mirar no mandan nada: cada máquina dibuja su
   copia (`CompanyNet`), como hoy `StockBoard`. Lo que cambia la empresa (pedir al proveedor, asignar, despedir)
   sale por la petición que esa tarea ya tiene, con su rechazo.
5. **Los tableros del galpón se quedan.** El tablero de pedidos es lo que la tripulación mira en común: no tiene
   hoja y la prioridad (⚑, D-0838) se marca ahí. El del proveedor es un **atajo**: usarlo saca el portapapeles en
   la hoja Proveedor. No se construyen estaciones nuevas para lo que solo vive en el portapapeles.
6. **No pausa nada y no es descanso.** Para `bot_company_day` el tiempo con el portapapeles cuenta como "sin
   caja" (regla de los 2 min, roles-tripulacion §1).

## 2. Posiciones

**F1 (D-1902): guardado ↔ levantado**, con una tecla. Levantado, la hoja ocupa los dos tercios de abajo de la
pantalla con el galpón atrás; el jugador queda quieto, el ratón se suelta y su input se corta, como los paneles
de hoy. **F2 (D-1004): bajado**, en la mano con la cámara libre y caminando a paso normal, para apuntar y
asignar (§5); se construye junto con la asignación, porque antes no tiene para qué.

Se guarda solo al: usar algo del mundo, subirse a un asiento, entrar en ragdoll (`player_gel_ragdoll`), pasar
el día a `SUMMARY`, abrir la pausa o arrancar el modo construcción. El modo construcción no arranca con el
portapapeles afuera ni al revés (el mismo `busy` que hoy conecta `CompanyRoot` entre `ShedBuilder` y
`SupplierBoard`).

```
 Levantado (F1)
 ┌──────────────────────────────────────────────┐
 │              (galpón, quieto)                │
 │  ┌────────────────────────────────────────┐  │
 │  │  [ Stock ]   Proveedor                 │  │
 │  │────────────────────────────────────────│  │
 │  │  Leche      4   falta 2   viene 6      │  │
 │  │  Pan        0   falta 3   —            │  │
 │  │  Yerba     11   —         —            │  │
 │  │────────────────────────────────────────│  │
 │  │  (ControlHints) hoja · bajar           │  │
 │  └────────────────────────────────────────┘  │
 └──────────────────────────────────────────────┘
 Proveedor: ya pedido para mañana: 12 u · $ 340
            Leche  [-] 6 [+]   Pan  [-] 3 [+]   …   Total $ 210   [ Pedir ]
```

El pie con las teclas sale de `ControlHints` (teclado o mando), nunca fijo.

## 3. Las hojas

Como mucho **3**, en este orden; una hoja que todavía no se abrió no aparece (no hay pestañas grises).

| Hoja | Desde | Qué muestra | Botones | Tarea |
|---|---|---|---|---|
| **Stock** | Día 1 | La lista por producto, con lo que falta para los pedidos de hoy y lo que viene en camino | — (solo lectura) | D-0612 (`StockPanel`) |
| **Proveedor** | Día 1 | El carrito del pedido de mañana, precargado con el sugerido **menos lo ya pedido para mañana**, y arriba "ya pedido: X" | ± unidades, Pedir | D-0603 (`SupplierOrderPanel`), D-0151.3b |
| **Empleados** | Hito 8 | La plantilla: nombre, estación ("Mesa 2"; el rol sale de la estación), sueldo, estado (D-1001) | Despedir | D-1038, D-1010 |

- **Pedidos** no es hoja: es el tablero de la pared (regla 5). **Plata** no es hoja: es el HUD del día (D-1903)
  y el cierre. **Flota** no es hoja: con 2 vehículos lejos como mucho se ve en la dársena y el GPS. Contratar es
  del tablero de contratación del galpón (D-1003, fila 110 de referencia-schedule-1).
- Se pide al proveedor **a pie desde cualquier lado**, también en la calle (`supplier_order` no tiene chequeo de
  alcance; jugando solo, pedir desde la puerta de un cliente es lo que lo ayuda). Sentado, nunca.

## 4. Controles y manos ocupadas

| Acción | Teclado y ratón | Mando |
|---|---|---|
| Sacar / guardar | `I` (acción nueva `company_clipboard`) | Cruceta derecha (solo para sacar) |
| Cambiar de hoja | `Q` / `E`, o clic en la pestaña | LB / RB |
| Moverse en la hoja | Ratón, flechas | Stick izquierdo / cruceta |
| Guardar desde levantado | `Esc` o `I` | B (`ui_cancel`) |

- `company_clipboard` la registra el portapapeles en código, como hoy `StockBoard.ensure_action` registra
  `company_stock`; `StockBoard` deja de escuchar su tecla y queda como fuente de datos de la hoja. No se
  reasigna hasta D-1938.
- **Levantado, el portapapeles consume en `_input`**: LB/RB (también son `phone_toggle`, `phone_shutter` y los
  cambios de marcha), `Esc` (es `ui_cancel` y `ui_pause`: baja y no abre la pausa) y la cruceta derecha (es
  `company_clipboard` y `care_tool_next`: con el mando se sale con B, así navegar los ± no lo guarda).
- **Manos ocupadas** (no se saca): `carried_package` o `tended_package` válidos, unidades en
  `CompanyNet.hands_location(peer)`, un carrito agarrado (`picking_cart_grip`), `seat_node_path` no vacío
  (manejar o de pasajero), modo construcción, o un `PhoneCamera.is_open` en el árbol. Con esto el choque con
  `care_tool_next` (que `player_cargo_care` lee con `is_action_just_pressed`) no pasa: cuidar una caja es tener
  las manos ocupadas.
- **Celular:** en el mundo Empresa hoy no hay. Cuando llegue (D-1923), los dos entran al grupo `&"hand_tool"`
  (`is_open()` / `stow()`) y sacar uno guarda el otro, sin que ninguno nombre al otro.

## 5. Bajado y asignar apuntando (F2, D-1004)

Bajado, el portapapeles hace un raycast local desde la cámara contra empleados y estaciones. Mirar a un empleado
y apretar `interact` lo **toma**; mirar una estación y apretar otra vez lo **asigna** (petición al host), y queda
una línea resaltada entre los dos por 3 s, que ve solo quien asigna. Con un empleado tomado o a la vista, el
portapapeles consume `interact` en `_unhandled_input` antes que `player_input.gd`. `Esc` suelta la selección.
Sin listas de nombres (fila 117): la hoja Empleados es para leer y despedir. Si dos jugadores asignan al mismo,
gana la última petición que llega al host.

## 6. Red, guardado y presentación

- **Sin RPC.** Lo que ven los demás es una propiedad del jugador, `held_tool: StringName` (`&""`,
  `&"clipboard"`, `&"clipboard_up"`), escrita solo por el dueño y sumada a `Repl_player` de `player.tscn` con
  `spawn = true` y `replication_mode = 2` (solo al cambiar; el que entra tarde la recibe). Sube
  `PROTOCOL_VERSION` (convenciones-godot §6); `test_company_bandwidth_budget` sigue verde. `player.gd` y
  `player.tscn` son de Slatex: aviso en `docs/avisos/` en el PR de D-1902. No se reusa `anim_state`
  (`PlayerAnimator` lo pisa cada cuadro).
- **Nada al save ni al snapshot.** La hoja abierta se recuerda en memoria mientras dura el mundo.
- Fuera del modo Empresa (Entrega, Endless) la tecla no hace nada.
- **Presentación.** Los demás ven un `BoxMesh` marrón de 0,23 × 0,32 × 0,01 m en un `BoneAttachment3D` de
  `hand.R` con la pose de siempre; el jugador local no ve nada en 3D (su cuerpo está en
  `RenderLayers.LOCAL_BODY` y no hay manos de primera persona): para él es el marco 2D con borde de madera. El
  modelo es D-1816 y el clip de sostenerlo, D-1840. Sonido (D-1913): broche al sacar y guardar, papel al cambiar
  de hoja.

## 7. Qué construye cada tarea

| Tarea | Qué toma de acá |
|---|---|
| D-1902 | §1-4 y §6: guardado ↔ levantado, el marco con pestañas, el modo `embedded` de `StockPanel` y `SupplierOrderPanel`, `company_clipboard`, manos ocupadas, `held_tool`. Test de navegación con mando y teclado que incluye el borde derecho de la cruceta en los ± y `Esc` contra la pausa |
| D-0151.3b | El sugerido menos lo ya pedido para mañana (`SupplierSchedule`) y la línea "ya pedido" |
| D-0838 | ⚑ en el tablero de pedidos de la pared, compartido, con su petición al host |
| D-1004 | §5: la posición bajado y asignar apuntando |
| D-1038 / D-1010 | La hoja Empleados (leer y despedir) |
| D-1901 | Nada nuevo: la línea de `order_more` (onboarding §2, día 2) muestra con `ControlHints` la tecla del portapapeles o el tablero del proveedor; con eso se enseña |

## 8. Otros docs que cambian

- D-1902 (`19-ui-audio-vfx.md`): las hojas son stock, proveedor y empleados.
- D-1240 (`12-flota-bici-carrito.md`), "Pantalla de flota en el portapapeles": recortada; la flota se ve en el mundo.
- Fila 116 de referencia-schedule-1: desde el día 1, sin libro contable.
- Fila 1 de red-autoridad §2: `supplier_order` sin chequeo de alcance.

## 9. Qué NO

- Rutas a mano "desde → hasta" como en *Schedule I* (referencia-schedule-1, decisión 3): el flujo es implícito.
- Un portapapeles por empresa que se pasa de mano en mano: cada jugador tiene el suyo.
- Hojas de pedidos, plata, flota o mapa: viven en el tablero, el HUD, la dársena y el celular.
- Caminar más lento o no poder saltar con el portapapeles: castiga sin dar una decisión.
- Hojas que solo son números sin un objeto del galpón detrás (vision §9).
