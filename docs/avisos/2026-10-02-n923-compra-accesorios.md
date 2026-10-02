# N-923.3 / N-923.4 / N-923.5: compra de accesorios con la plata del equipo, y su red

Se pueden comprar accesorios (gorra, chaleco, casco, mochila) con la plata compartida, en el
depósito y en las paradas de servicio, y ponérselos, soltarlos y recogerlos en red con el host
como autoridad.

## N-923.3 / N-923.4 (compra, solo host)

Zona compartida y archivos del otro integrante que cambian:
- `scripts/core/crew_progression.gd`: `buy_accessory(buyer_color, id, price_multiplier, discount_peer)`.
  Valida antes de gastar: solo cobra si el otorgamiento va a salir.
- `scripts/core/shop_vote_manager.gd`: `_default_offers()` suma el estante de accesorios por jugador
  conectado; la oferta de accesorio la liquida el host al cerrar el voto (`settle_accessory_offer`)
  y `buy` / `use_priority` / `use_discount` ya no la cobran por su cuenta.
- `scripts/ui/depot_panel.gd` (Slatex): sección "Accesorios" en las caras `shop` y `service`;
  `_offer_rows` gana dos parámetros opcionales (`controls`, `blocked_keys`) sin cambiar su uso actual;
  `_on_shop_resolved` ya no manda a comprar una oferta de accesorio al depósito.
- `scripts/gameplay/route/service_stop_shop.gd`: ofertas de accesorios con el recargo de 1,4.
- Textos nuevos en `strings_ui.csv` (`UI_ACCESSORY_NOTICE_*`, `_ROW_*`, `_SECTION*`) y
  `strings_world.csv` (`WORLD_SERVICE_NOTICE_ACCESSORY`).

## N-923.5 (red) — **cambia el protocolo**

- `scripts/core/network_manager.gd`: `PROTOCOL_VERSION` **27 → 28** (línea 28 en el historial). Un
  cliente viejo con un host nuevo no se entiende (el nodo de los RPCs nuevos no existe en el viejo):
  el handshake los rechaza con "otra versión". Al mezclar `main`: si otra rama ya usó el 28, subir al
  siguiente libre y corregir la línea del historial (`docs/convenciones-godot.md` §6).
- Nodo nuevo `CrewProgression/AccessoryNet` (`scripts/core/accessory_net.gd`), creado en
  `CrewProgression._ready()`; `CrewProgression.accessory_net` lo apunta (null en una instancia fuera
  del árbol). RPCs nuevos:
  - `request_equip_accessory(slot: StringName, accessory: StringName)`: `any_peer`, `call_remote`,
    `reliable`. `accessory` vacío quita lo del slot.
  - `request_drop_accessory(accessory: StringName)`: `any_peer`, `call_remote`, `reliable`.
  - `request_pickup_accessory(pickup_id: int)`: `any_peer`, `call_remote`, `reliable`.
  - `_receive_accessories(owned: Dictionary, pickups: Array)`: `authority`, `call_remote`,
    `reliable`, canal 0 (el de `_receive_campaign`): inventario entero (`AccessoryInventory.to_dict()`)
    y suelo (`AccessoryGround.to_array()`), después de cada cambio y en cada cambio del roster.
  Todos los `any_peer` pasan por `RpcGuard` (`allow_request`, `name_ok`) y por el roster; el host
  atribuye la acción al color de quien la pidió.
- Para la UI (N-923.7) y el objeto del suelo (N-923.6), en `CrewProgression.accessory_net`:
  `equip(slot, id)`, `drop(id)`, `pick_up(pickup_id)` del jugador local; del lado host
  `equip_as` / `drop_as` / `pick_up_as(peer, ...)` devuelven `&""` o el motivo (`not_owner`,
  `on_ground`, `too_many`, `no_player`, `far`, `gone`, `unknown`). El suelo es igual en todos:
  `accessory_net.ground` con `pickup_added` / `pickup_removed`.
- No hay RPC de compra directa: online se compra votando la oferta propia (`request_vote`, ya
  existente). `scripts/core/shop_vote_manager.gd`: el accesorio se liquida **antes** de emitir
  `EventBus.shop_resolved` (antes iba después y el panel del host se reconstruía sin verlo).
- Lo soltado sigue en el inventario de su dueño hasta que otro lo recoge: quien lea
  `AccessoryInventory.owner_of()` ve al dueño también con el accesorio en el suelo; para saber si
  está tirado, `accessory_net.ground.pickup_of(id)`.

Nadie más que el host cambia plata ni inventario. Hacer pull antes de tocar la tienda: las ofertas de
la votación pueden traer una clave `accessory`.
