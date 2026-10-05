# `main_menu.gd` y `company_root.gd` usan tipos (N-224.4)

**Fecha:** 2026-10-05 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento:

- `scripts/ui/main_menu.gd`: los cuatro paneles (`_progress`, `_tutorial`, `_cosmetics`, `_leaderboard`) como
  `ProgressPanel`, `TutorialPanel`, `CosmeticsPanel` y `LeaderboardPanel`; `open()` directo (`.call` 4 → 0).
- `scripts/gameplay/company_root.gd`: `CompanyState` por la constante `COMPANY_STATE` (preload del script, el
  autoload no tiene `class_name`); `to_dict`, `is_active`, `new_company`, `stock`, `reset` y `from_dict` directos
  (`.call` 7 → 0).

`tests/test_dynamic_dispatch_budget.gd` suma los dos a `BUDGETS`.

## Qué tiene que hacer Slatex

Nada. Si se renombra algo de lo que leen estos archivos, ahora falla al compilar en vez de en el juego.
