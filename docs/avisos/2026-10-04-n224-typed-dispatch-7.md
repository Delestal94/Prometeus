# Menos despacho por nombre en `package_salvage.gd`, `care_practice.gd` y `hud_cargo_panel.gd` (N-224.4)

**Fecha:** 2026-10-04 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento en el juego:

- **`scripts/gameplay/package/package_salvage.gd`** (tuyo): el paquete como `DeliveryPackage`
  (`get_half_extents()`, `_find_vehicle()`, `content_definition()`) y `RunManager` por `PackageAutoloads`.
- **`scripts/ui/hud/care_practice.gd`** (tuyo): el perfil como `UnlockProfile` (`seen_tips`, `mark_tip_seen()`);
  el jugador y las cajas siguen siendo `Node` (los falsos de `test_care_prompt_view.gd`), leídos por propiedad.
- **`scripts/ui/hud/hud_cargo_panel.gd`** (tuyo): el disfraz de la caja mimética como `TrapDefinition`
  (`localized_name()`) y la velocidad máxima del camión por propiedad.
- `scripts/core/run_scoring.gd` (de nadie): las claves de las líneas de resultados pasan a constantes.

`tests/test_dynamic_dispatch_budget.gd` suma los cuatro archivos a `BUDGETS`.

## Qué tiene que hacer Slatex

Nada.
