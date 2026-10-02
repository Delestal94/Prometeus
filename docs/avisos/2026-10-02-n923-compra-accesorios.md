# N-923.3 / N-923.4: compra de accesorios con la plata del equipo

Se pueden comprar accesorios (gorra, chaleco, casco, mochila) con la plata compartida, en el
depósito y en las paradas de servicio. Es solo lógica de host; N-923.5 (red) la envuelve en RPCs
más adelante y no se tocó `network_manager.gd`.

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

Nadie más que el host cambia plata ni inventario. Sin RPCs nuevos, sin cambio de `PROTOCOL_VERSION`.
Hacer pull antes de tocar la tienda: las ofertas de la votación ahora pueden traer una clave `accessory`.
