# Autoload `CompanyState` y `company_tuning.gd` (D-0202)

**Fecha:** 2026-10-04 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- `project.godot`: nuevo autoload `CompanyState` (`scripts/core/company/company_state.gd`) registrado
  justo después de `UnlockManager`. Es el estado persistente del modo Empresa; arranca **inactivo**
  (`is_active()` falso) y solo `new_company()` o `from_dict()` lo activan, así que Entrega y Endless no
  cambian. No nombra ningún otro autoload ni clase de UI (lección N-919).
- `scripts/core/company/company_tuning.gd` (`class_name CompanyTuning`): todos los números de
  `docs/expansion-distritos/detalle/supuestos.md` como `const`. `Order`, `Pallet` y `ProductDefinition`
  los leen de ahí (mismos valores; `Order.WINDOW_MIN` y compañía siguen existiendo como alias).
- Tests: `test_company_state` (nuevo) y `test_hud_script_loads` (ahora también nombra `CompanyState`).

## Qué tenés que hacer

Nada. Si agregás un autoload nuevo, ponelo después de `CompanyState`; si tu código necesita saber si hay
una empresa en curso, usá `CompanyState.is_active()`.
