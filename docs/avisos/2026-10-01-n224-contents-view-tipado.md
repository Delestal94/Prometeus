# `package_contents_view.gd` usa tipos para la caja y su contenido (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/package/package_contents_view.gd` (solapas y contenido de la caja), sin cambio de comportamiento:

- `_package` es un `DeliveryPackage` (`package_id`, `trap_state`, `contents_spilled`, `is_open` y
  `content_definition()` directos). `package.gd` no carga esta vista, así que no hay ciclo de compilación.
- El contenido se lee como `PackageContent` (`localized_name`, `condition_text`, `pick_note`, `model`, `box_size`).
- Sigue por nombre el `connect` al `EventBus` (un test puede reemplazarlo por un `Node`), como en `package_feedback.gd`.

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` (root 1, el resto 0).

## Qué tiene que hacer Slatex

Nada. Si la vista se agrega a un nodo que no es `DeliveryPackage`, ya no funciona (antes tampoco: leía `package_id`).
