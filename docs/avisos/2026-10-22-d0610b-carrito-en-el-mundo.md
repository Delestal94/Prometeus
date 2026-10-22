# Aviso 2026-10-22 · carrito de picking en el mundo (D-0610.b)

Dominio de Slatex tocado (`scripts/gameplay/interaction/`), solo un archivo nuevo; no cambia ninguna firma existente.

- `do-not-drop/scripts/gameplay/interaction/picking_cart_point.gd` (nuevo): `PickingCartPoint extends Interactable`, el
  punto de uso del carrito (plataforma: cargar o descargar; manija: empujar). Señal `used(cart_id, action, peer_id, from)`.
  Mismo patrón que `ShedPiecePoint`: `interact()` corre en el host y solo avisa quién lo usó.
- Zona compartida / Nacho: `company_net.gd` (pedido `cart_push`, evento `cart_moved`, parte `carts` del snapshot;
  `CompanyCarts` nuevo en `scripts/core/company/`), `company_shed.gd`, `company_root.gd`, `default_shed.gd` (+ `cart_spots`),
  `PROTOCOL_VERSION` 38 -> 39.
- Textos: `WORLD_SHED_USE_CART` y `WORLD_SHED_PUSH_CART` en `strings_world.csv`.

Para Slatex: nada que hacer. `Interactable`, `Player` y el sondeo de interacción no cambian.
