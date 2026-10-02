# Votación de la estación de servicio: arreglos de la auditoría de red (N-110)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex (y zona compartida)

## Qué cambió

- `modules/coop_vote/coop_vote.gd` (compartida): función pública nueva `send_state_to(peer_id)`, que le manda a un
  peer la votación tal como está, sin tocar votos ni reloj. No cambia ninguna firma existente ni ningún RPC.
- `scripts/core/shop_vote_manager.gd` (compartida): `use_priority()` y `use_discount()` sobre una oferta con
  `venue` (la de una estación) cierran la votación con `close_on()` en vez de comprar: la paga la estación una sola
  vez. Las ofertas del depósito siguen igual.
- `scripts/core/event_bus.gd` (compartida): señal local nueva `care_supplies_changed`, que emite
  `RunManager` cuando cambia el kit (en el host y al sincronizar en un cliente).
- `scripts/ui/depot_panel.gd` (tu dominio): la cara `service` toma lo que no se puede comprar del kit local
  (`shop.unavailable()`), se redibuja con `care_supplies_changed` y se cierra sola si tu jugador se aleja más de
  `Interactable.REMOTE_REACH * 3` del mostrador.
- `scripts/ui/hud/hud_pause.gd` (tu dominio): cuando Endless borra la estación, su panel se cierra
  (`shop.tree_exiting`).
- Sin cambio de `PROTOCOL_VERSION`: no cambian RPCs ni lo que se replica.

## Qué tiene que hacer Slatex

`git pull` antes de tocar `depot_panel.gd` o `hud_pause.gd`.
