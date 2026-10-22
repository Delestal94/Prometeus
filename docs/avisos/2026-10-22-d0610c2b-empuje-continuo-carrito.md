# Aviso 2026-10-22 · empuje continuo del carrito (D-0610.c2.b)

Dominio de Slatex tocado: `do-not-drop/scripts/gameplay/interaction/picking_cart_point.gd` (una acción nueva,
`ACTION_GRIP`, y su clave de texto; `ACTION_PUSH` sigue igual). No cambia ninguna firma existente ni
`Interactable`, `Player` o el sondeo de interacción.

- Nuevo `scripts/gameplay/picking_cart_grip.gd` (`PickingCartGrip`): quién tiene agarrada la manija de qué carrito
  (solo el host) y los pasos cortos que lo hacen acompañar al jugador. Usa el mismo pedido `cart_push` y el mismo
  evento `cart_moved`; sin RPC nuevo ni `PROTOCOL_VERSION` nuevo (el pedido acepta una clave opcional `step`, que un
  host viejo ignora y que ningún cliente manda).
- Zona compartida / Nacho: `company_carts.gd` (`push_ask` lleva `step`), `company_tuning.gd` (`CART_GRIP_*`),
  `company_root.gd` (cuelga el `PickingCartGrip` y le pasa los usos del carrito), `picking_cart_view.gd` (la manija es
  el agarre; `place_at` desliza desde lo que se ve). Textos: `WORLD_SHED_GRIP_CART` y `WORLD_SHED_PUSH_BLOCKED`.

Para Slatex: nada que hacer.
