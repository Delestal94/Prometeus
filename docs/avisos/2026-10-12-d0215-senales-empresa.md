# D-0215 — señales de negocio en `EventBus` (zona compartida)

Lo hizo Nacho (rutina desarrollador, carril 1). **Solo agrega**: ninguna señal existente cambia de
lugar ni de firma.

- `scripts/core/event_bus.gd`: 11 señales nuevas **al final** (después de `low_visibility_changed`):
  `company_day_started(day)`, `company_day_closing(day)`, `company_day_summary(day, summary)`,
  `order_added(order_id)`, `order_packed(order_id)`, `order_delivered(order_id)`,
  `supply_arrived(supplier_id)`, `box_sealed(station_id, order_id)`, `gate_opened(gate_id)`,
  `milestone_reached(milestone_id)` y `money_changed(amount, reason)`. Son hechos del modo Empresa y
  **no se relayan**: cada peer las emite al aplicar el evento de `CompanyNet` (`docs/arquitectura.md` §10.3).
- `scripts/core/company/company_state.gd`: `earn`/`spend`/`charge` emiten `money_changed` (monto con
  signo y el mismo motivo del libro) y `open_gate` emite `gate_opened`, por `/root/EventBus` (por ruta, no
  por nombre). `from_dict()` no emite nada.
- Test: `tests/test_event_bus_company.gd`.

Para Slatex: si la UI o el audio quieren reaccionar al negocio, escuchen estas señales; no hace falta
tocar nada de lo que ya existe.
