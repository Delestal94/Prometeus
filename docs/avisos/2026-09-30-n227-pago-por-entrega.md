# Aviso: N-227.2, el pago por entrega y el fin del bono de tiempo

Toca `run_manager.gd` (zona compartida) y `scripts/ui/hud/hud_results.gd` (UI de Slatex).

- **Pago**: `CrewProgression.award_delivery()` paga `delivery_points + cargo_points` (sin el multiplicador
  de caos, que sigue solo en el puntaje). Endless no trae ninguno de los dos: no paga dinero. El
  diccionario de resultados suma `payout`, y la pantalla de resultados muestra una línea nueva
  (`HUD_RESULT_PAYOUT`, "Pago del equipo") antes del saldo.
- **Se borra el bono de tiempo**: `PAR_SECONDS`, `time_bonus`, `lost_time_bonus` y la clave
  `HUD_SCORE_SPEED` ya no existen. `HUD_RESULT_STATS` (la pantalla sin desglose) perdió la columna "Rapidez".
  El puntaje es `(cargo_points + delivery_points) x multiplicador`.
- **Cliente impaciente** ya no toca nada del puntaje: si falla, acorta un 15 % el plazo de la casa siguiente
  con plazo abierto (si no queda ninguna posterior, el próximo plazo abierto que haya) (`RunManager.shorten_next_deadline`, lógica pura en `scripts/core/deadline_cut.gd`).
- **Reclamo abollado determinista**: toda caja entregada abollada genera reclamo (se acabó el 50 %).
- **Precios de la tienda x4** (160 / 140 / 120 / 100) y seguro 50 por caja arruinada (reembolso + pago de arruinada < pago de abollada). La billetera sigue
  arrancando con 100, así que no alcanza para el acolchado hasta la primera entrega.
- Tests tocados: los que usaban `time_bonus` o precios fijos (`test_crew_progression`, `test_route_events`,
  `test_supply_vote`, `test_depot`, `test_cards`, `test_run_relay`, etc.) y uno nuevo, `test_dented_complaint`.
