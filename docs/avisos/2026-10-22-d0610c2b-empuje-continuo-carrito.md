# Aviso 2026-10-22 · empuje continuo del carrito (D-0610.c2.b)

Dominio de Slatex tocado: `do-not-drop/scripts/gameplay/interaction/picking_cart_point.gd` (una acción nueva,
`ACTION_GRIP`, y su clave de texto; `ACTION_PUSH` sigue igual). No cambia ninguna firma existente ni
`Interactable`, `Player` o el sondeo de interacción.

- Nuevo `scripts/gameplay/picking_cart_grip.gd` (`PickingCartGrip`): quién tiene agarrada la manija de qué carrito
  (solo el host) y los pasos que lo hacen ir delante del jugador, con adelanto según su paso y su ida y vuelta
  (`NetStats.round_trip_seconds`). Usa el mismo pedido `cart_push` y el mismo evento `cart_moved`; sin RPC nuevo ni
  `PROTOCOL_VERSION` nuevo (el pedido acepta una clave opcional `step`, que un host viejo ignora y que ningún cliente
  manda). Se conecta a `NetworkManager.peer_removed` / `peer_returned` y a `multiplayer.peer_disconnected` (solo
  escucha, como `CompanyNet`) para soltar el carrito de quien se va.
- **Ruta de nodo sin cambios:** el punto de la manija ahora agarra pero su nodo sigue llamándose `Use_<id>_push`
  (`PickingCartView.handle_point_name`), porque `request_interact` viaja por la ruta del nodo; un cliente y un host
  de antes y después de este cambio se siguen entendiendo (el viejo empuja un paso entero, el nuevo agarra).
  `test_company_picking_cart_world` fija los nombres de todos los puntos del carrito.
- Zona compartida / Nacho: `company_carts.gd` (`push_ask` lleva `step`), `company_tuning.gd` (`CART_GRIP_*`, con
  `CART_GRIP_LEAD_S` y `CART_GRIP_MAX_LEAD_M` nuevos), `company_root.gd` (cuelga el `PickingCartGrip` y le pasa los
  usos del carrito), `picking_cart_view.gd` (la manija es el agarre; `place_at` desliza desde lo que se ve),
  `stock_board.gd` (no redibuja la planilla con `cart_moved`). Textos: `WORLD_SHED_GRIP_CART` y
  `WORLD_SHED_PUSH_BLOCKED`.

Para Slatex: nada que hacer.
