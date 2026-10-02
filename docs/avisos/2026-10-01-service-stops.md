# Estaciones de servicio en la ruta (N-110): panel del depósito, HUD, kit y protocolo 22

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex (y zona compartida)

## Qué cambió

- `scripts/ui/depot_panel.gd` (tu dominio): una sexta cara, `&"service"`, que abre el mostrador de una
  estación de servicio con su `ServiceStopShop` como `depot`. `_build_shop()` se partió: las filas de
  ofertas (botón de compra o voto, detalle, votantes, descuento) salen de `_offer_rows()`, que usan las
  dos caras. `_on_shop_resolved()` ya no compra en el depósito una oferta con `venue == &"service_stop"`
  (la compra la hace la estación). Las señales que redibujaban solo con `station == &"shop"` ahora usan
  `_selling()` (shop o service). La cara `service` se cierra sola en `run_ended`.
- `scripts/ui/hud/hud_pause.gd` (tu dominio): escucha `EventBus.service_counter_opened(shop)` y abre el
  panel en la cara `service`, solo con `overlay_mode == "run"` y la corrida en marcha.
- `scripts/core/event_bus.gd` (compartida): señal local nueva `service_counter_opened(shop: Node)`.
- `scripts/core/run_manager.gd` (compartida): `consume_care_supply(tool, amount = 1)`: el segundo
  argumento es nuevo y opcional; negativo devuelve unidades al kit (la estación lo repone). Los llamados
  existentes no cambian.
- `scripts/core/network_manager.gd` (compartida): `PROTOCOL_VERSION` 21 → 22 (RPCs del mostrador y de
  la tienda de la estación). Host y cliente tienen que estar en la misma versión.
- `scripts/gameplay/level_base.gd` (compartida): un camión parado en la dársena de la estación no
  cuenta como trabado.
- `translations/strings_ui.csv` y `strings_world.csv`: claves `UI_SERVICE_*` y `WORLD_SERVICE_*`.

## Qué tiene que hacer Slatex

`git pull` antes de tocar `depot_panel.gd` o `hud_pause.gd`. Si agregás una cara nueva que venda, sumala
a `_selling()` y usá `_offer_rows()` en vez de copiar las filas.
