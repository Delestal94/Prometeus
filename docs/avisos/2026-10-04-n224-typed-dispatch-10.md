# Menos despacho por nombre en `cosmetics_panel.gd` (N-224.4)

**Fecha:** 2026-10-04 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento en el juego:

- **`scripts/ui/cosmetics_panel.gd`** (tuyo): la vista del personaje como `CharacterPreview` (`bounce()`,
  `show_look()`, `set_framing()`), en vez de `.call(&"…")`.
- `scripts/gameplay/route/service_counter.gd` (de Nacho): la tienda como `ServiceStopShop` (`open_for_crew()`).

`tests/test_dynamic_dispatch_budget.gd` suma los dos archivos a `BUDGETS`.

## Qué tiene que hacer Slatex

Nada.
