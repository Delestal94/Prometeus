# Aviso 2026-10-22 · zorra de palets en el mundo (D-0605.b)

Dominio de Slatex tocado (`scripts/gameplay/interaction/`), solo un archivo nuevo; no cambia ninguna firma existente.

- `do-not-drop/scripts/gameplay/interaction/pallet_jack_point.gd` (nuevo): `PalletJackPoint extends Interactable`, el punto de uso de
  la zorra (horquillas: subir o apoyar un palet; manija: empujar). Señal `used(action, peer_id, from)`. Mismo patrón que
  `PickingCartPoint` y `ShedPiecePoint`: `interact()` corre en el host y solo avisa quién lo usó.
- Zona compartida / Nacho: `company_net.gd` (pedidos `jack_pick`, `jack_put`, `jack_push`; eventos `jack_picked`, `jack_placed`,
  `jack_moved`, `jack_loaded`; parte `pallets` del snapshot; `CompanyPallets` nuevo en `scripts/core/company/`; el pedido de objetos del
  mundo del carrito y el de la zorra comparten `_on_object`), `company_shed.gd`, `company_root.gd`, `supplier_truck_view.gd` (la caja
  queda abierta atrás y dibuja los palets), `company_tuning.gd` (+ `JACK_PUSH_STEP_M`), `pallet_jack.gd` (+ `can_pick_up`,
  `can_put_down`; cada lugar del libro lleva `received` (bool) en `places`, `to_dict`/`from_dict` y la parte `pallets` del snapshot:
  un palet se recibe en el `Inventory` solo la primera vez que se apoya, aunque después se vacíe), `PROTOCOL_VERSION` 42 -> 43.
- Textos: `WORLD_SHED_USE_JACK` y `WORLD_SHED_PUSH_JACK` en `strings_world.csv`.

Para Slatex: nada que hacer. `Interactable`, `Player` y el sondeo de interacción no cambian.
